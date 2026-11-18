# -*- coding: utf-8 -*-
"""
B3. 证据校验器 + 影子审计接入 (evidence-validator.py)

职责:
  * validate_evidence(record, candidate_record):
    校验 schema 完整性、字段类型、候选绑定、时效、
    phone_loaded_sha 限制与钉选保护, 产出 verdict 与是否可用于生产下架。
  * audit_shadow(candidate_nodes, evidence_records, pinned_names, stop_status):
    只写隔离证据目录, 输出 B6 要求的十项计数, 判定 removal_candidates 与
    decision (NO_SAFE_REMOVAL 或候选数)。
  * run_example(output_dir): 可运行的示例入口, 用冻结的 TEST-NET 测试候选
    生成一条完整可复核的同候选证据链示例, 输出到隔离证据目录并打印十项计数。

硬规则 (fail-closed):
  * 候选绑定不一致 (payload_sha / member_set_sha / candidate_id) -> UNVERIFIED。
  * 时效 TTL 24h, 过期 -> UNVERIFIED。
  * phone_loaded_sha 为 "UNKNOWN" 时, 该证据禁止用于生产下架。
  * 21 条钉选即使测速失败也不能由清理器删除。
  * 只有“有可信失败证据的非钉选”才计入 removal_candidates:
    可信 = 绑定一致 + 未过期 + measurement_verified=True +
    phone_loaded_sha 已验证 + 失败信号真实
    (latency_ms >= 300, 或 latency_ms 为 null 且 raw_result 有明确失败信号)。
  * STOP 状态下 removal_candidates 强制为 0, decision 为 NO_SAFE_REMOVAL。
  * 影子审计只写调用方传入的隔离输出目录, 永不写生产路径
    (/opt/surge-bridge、/opt/free-node-program、pool-new.txt 等一律拒绝)。

只用 Python 3 标准库。测试夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123)。
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

_HERE = Path(__file__).resolve().parent


def _load_sibling(module_name: str, filename: str):
    """加载同目录下带连字符的文件名模块 (candidate-freeze.py 等无法直接 import)。"""
    path = _HERE / filename
    spec = importlib.util.spec_from_file_location(module_name, str(path))
    if spec is None or spec.loader is None:
        raise ImportError("无法加载 {}".format(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


freeze_mod = _load_sibling("candidate_freeze_mod", "candidate-freeze.py")
collector_mod = _load_sibling("native_collector_mod", "native-collector.py")

POLICY_IDENTIFIER = collector_mod.POLICY_IDENTIFIER
LATENCY_THRESHOLD_MS = collector_mod.LATENCY_THRESHOLD_MS
EVIDENCE_TTL_SECONDS = collector_mod.EVIDENCE_TTL_SECONDS

# 钉选期望数量 (任务背景: 21 条钉选)。
PINNED_EXPECTED = 21

# 影子审计禁止写入的生产路径片段 (任一命中即拒绝写入)。
FORBIDDEN_OUTPUT_FRAGMENTS = (
    "/opt/surge-bridge",
    "/opt/free-node-program",
    "pool-new.txt",
    "/opt/surge",
)


def _node_name_of(record: dict):
    """从证据记录取被测节点名 (仅用于钉选匹配与覆盖统计)。

    证据 schema 本身不含节点名; 名字只从 raw_result 的
    node_name / name / identifier 字段取, 取不到则为 None
    (覆盖统计改按 uri_fingerprint 匹配, 见 audit_shadow)。
    """
    raw = record.get("raw_result") if isinstance(record, dict) else None
    if isinstance(raw, dict):
        for key in ("node_name", "name", "identifier"):
            value = raw.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return None


def _candidate_name_set(candidate_nodes) -> set:
    """candidate_nodes 归一化为名字集合。

    接受 list[str] 或 list[dict] (dict 取 name / node_name / identifier,
    无名字则取 uri_fingerprint)。
    """
    names = set()
    for item in candidate_nodes or []:
        if isinstance(item, str):
            names.add(item.strip())
        elif isinstance(item, dict):
            for key in ("name", "node_name", "identifier"):
                if isinstance(item.get(key), str) and item[key].strip():
                    names.add(item[key].strip())
                    break
            else:
                fp = item.get("uri_fingerprint")
                if isinstance(fp, str) and fp:
                    names.add(fp)
    names.discard("")
    return names


def _candidate_fingerprint_map(candidate_nodes) -> dict:
    """uri_fingerprint -> 节点名 (candidate_nodes 为 dict 列表时可用)。"""
    mapping = {}
    for item in candidate_nodes or []:
        if isinstance(item, dict):
            fp = item.get("uri_fingerprint")
            name = item.get("name") or item.get("node_name") or item.get("identifier")
            if isinstance(fp, str) and isinstance(name, str):
                mapping[fp] = name.strip()
    return mapping


def validate_evidence(record: dict, candidate_record: dict, pinned_names=None, node_name=None) -> dict:
    """校验一条证据记录。

    参数:
        record: 证据记录 dict (native-collector.build_evidence_chain 产出)。
        candidate_record: 冻结候选记录 dict (candidate-freeze.freeze_candidate 产出)。
            为 None 时候选绑定校验失败 (fail-closed): 没有冻结候选就
            没有可绑定的池状态, 证据不可判 valid, 永不可计入删除资格。
        pinned_names: 钉选名列表 (可选); 命中则 is_pinned=True, 永不允许删除。
        node_name: 被测节点名 (可选); 不传则从 raw_result 取。

    返回:
        {"valid": bool,              # schema+绑定+时效是否通过
         "verdict": str,             # judge 结果, 绑定/时效失败时强制 UNVERIFIED
         "reasons": [str, ...],      # 全部判定理由
         "eligible_for_removal": bool,  # 是否可用于生产下架 (极严)
         "is_pinned": bool,
         "checks": {...}}
    """
    reasons = []
    checks = {
        "schema_ok": False,
        "candidate_binding_ok": False,
        "not_expired": False,
        "phone_verified": False,
        "measurement_verified": False,
        # F2/F3: 可选附加字段 (loaded_proof_level 等) 的一致性。
        # 不出现 = 通过; 出现但类型/取值/一致性错误 = 不通过。
        "loaded_proof_ok": False,
    }

    if not isinstance(record, dict):
        return {
            "valid": False,
            "verdict": "UNVERIFIED",
            "reasons": ["证据记录不是 dict"],
            "eligible_for_removal": False,
            "is_pinned": False,
            "checks": checks,
        }

    schema_errors = collector_mod.validate_evidence_schema(record)
    if schema_errors:
        reasons.extend(schema_errors)
    else:
        checks["schema_ok"] = True

    # F2/F3 可选附加字段一致性 (不降低第一轮 fail-closed 语义:
    # 弱证明绝不能冒充字节证明, 校准未通过绝不能置 measurement_verified)。
    proof_errors = collector_mod.validate_loaded_proof_fields(record)
    if proof_errors:
        reasons.extend(proof_errors)
    else:
        checks["loaded_proof_ok"] = True
    if record.get("loaded_proof_level") == "MEMBERS_VERIFIED":
        reasons.append(
            "弱证明: 成员集合一致仅为弱证明, phone_loaded_sha 仍为 UNKNOWN, "
            "生产准入待单独审查, 不可据此下架"
        )

    # 候选绑定: payload_sha / member_set_sha / candidate_id 三者一致。
    # Fail-closed: candidate_record 为 None (冻结候选缺失) 时绑定校验
    # 失败, 不得跳过。没有冻结候选就没有可绑定的池状态, 证据不可判
    # valid, 永不可计入 removal_candidates, 否则一次缺失冻结就会把
    # 未绑定证据误算成删除资格。
    if candidate_record is None:
        checks["candidate_binding_ok"] = False
        reasons.append("无冻结候选记录, 候选绑定校验失败, 禁止用于生产下架")
    elif not isinstance(candidate_record, dict):
        reasons.append("candidate_record 不是 dict, 候选绑定校验失败")
    else:
        binding_ok = True
        if record.get("payload_sha") != candidate_record.get("payload_sha256"):
            binding_ok = False
            reasons.append("候选绑定不一致: payload_sha 与冻结候选不符")
        if record.get("member_set_sha") != candidate_record.get("member_set_sha256"):
            binding_ok = False
            reasons.append("候选绑定不一致: member_set_sha 与冻结候选不符")
        if record.get("candidate_id") != candidate_record.get("candidate_id"):
            binding_ok = False
            reasons.append("候选绑定不一致: candidate_id 与冻结候选不符")
        if candidate_record.get("policy_fingerprint") != freeze_mod.POLICY_FINGERPRINT:
            binding_ok = False
            reasons.append("候选绑定不一致: 冻结记录的 policy_fingerprint 与当前策略不符")
        checks["candidate_binding_ok"] = binding_ok

    # 时效 TTL 24h。
    if collector_mod.is_expired(record):
        reasons.append("证据已过期 (TTL 24h), 判 UNVERIFIED")
    else:
        checks["not_expired"] = True

    # Actual byte-level binding: a plausible nonempty hex is not proof.
    # Source identity must equal the exact frozen payload SHA; members-only
    # matches or self-asserted SHA without independent proof never authorize
    # production removal.
    phone_sha = record.get("phone_loaded_sha")
    if phone_sha == "UNKNOWN":
        reasons.append('phone_loaded_sha 为 UNKNOWN (手机实际加载未独立验证), 禁止用于生产下架')
    elif (isinstance(candidate_record, dict)
          and isinstance(phone_sha, str)
          and collector_mod._SHA256_RE.fullmatch(phone_sha)
          and phone_sha == candidate_record.get("payload_sha256")
          and record.get("loaded_proof_level") == "BYTE_PROOF"
          and record.get("production_admission") == "GRANTED"):
        checks["phone_verified"] = True
    else:
        reasons.append("手机字节级 SHA 未通过冻结候选一致性/独立证明校验，禁止下架")

    if record.get("measurement_verified") is True:
        checks["measurement_verified"] = True

    # 钉选保护。
    pinned = set(pinned_names or [])
    resolved_name = node_name or _node_name_of(record)
    is_pinned = bool(resolved_name and resolved_name in pinned)
    if is_pinned:
        reasons.append("钉选保护: {} 为钉选成员, 即使失败也不得删除".format(resolved_name))

    valid = bool(
        checks["schema_ok"]
        and checks["candidate_binding_ok"]
        and checks["not_expired"]
        and checks["loaded_proof_ok"]
    )

    # verdict: 绑定/时效/schema 任一失败 -> 强制 UNVERIFIED; 否则取 judge 结果。
    if not valid:
        verdict = "UNVERIFIED"
    else:
        verdict = collector_mod.judge_evidence(record)

    # Single measurements never authorize irreversible deletion.
    # High latency is NOT a connectivity failure, and a single timeout can
    # recover. A later temporal stability gate must aggregate independent
    # verified failures across different times and reject recovered nodes.
    latency = record.get("latency_ms")
    has_failure_signal = (
        latency is None
        and collector_mod._raw_indicates_failure(record.get("raw_result") or {})
    )
    qualified_failure_sample = bool(
        valid
        and verdict == "FAIL"
        and has_failure_signal
        and checks["phone_verified"]
        and checks["measurement_verified"]
        and record.get("calibration_verdict") == "CALIBRATED"
        and record.get("network_bearer") in ("wifi", "cellular")
        and not is_pinned
    )
    eligible = False  # no deletion from a single timestamp
    if isinstance(latency, (int, float)) and not isinstance(latency, bool):
        if latency >= LATENCY_THRESHOLD_MS:
            reasons.append("测速>=300ms仅表示未达优选目标，连通则保留，不可下架")
    if qualified_failure_sample:
        reasons.append("独立连接失败样本待跨时段累计；单次失败仍不得下架")
    elif verdict in ("FAIL", "FAIL_LATENCY"):
        reasons.append("证据不足或不构成持久连接故障，禁止自动下架")

    return {
        "valid": valid,
        "verdict": verdict,
        "reasons": reasons,
        "eligible_for_removal": eligible,
        "qualified_failure_sample": qualified_failure_sample,
        "is_pinned": is_pinned,
        "checks": checks,
    }


def _is_stop(stop_status) -> bool:
    """STOP 状态判定: 字符串 STOP/STOPPED/HALT, 或布尔 True。"""
    if stop_status is True:
        return True
    if isinstance(stop_status, str):
        return stop_status.strip().upper() in ("STOP", "STOPPED", "HALT", "HALTED")
    return False


def _check_output_dir(output_dir) -> Path:
    """校验隔离输出目录: 拒绝生产路径, 拒绝根目录。返回 Path。"""
    if output_dir is None:
        return None
    path = Path(str(output_dir)).expanduser()
    text = str(path)
    for fragment in FORBIDDEN_OUTPUT_FRAGMENTS:
        if fragment in text:
            raise ValueError("拒绝写入生产路径: {} 命中禁写片段 {!r}".format(text, fragment))
    if str(path.resolve()) in ("/", str(Path.home().resolve())):
        raise ValueError("拒绝写入根目录或 home 根目录: {}".format(text))
    return path


def audit_shadow(
    candidate_nodes,
    evidence_records,
    pinned_names,
    stop_status,
    output_dir=None,
    candidate_record=None,
):
    """影子审计: 只读统计 + 只写隔离证据目录, 绝不改生产。

    参数:
        candidate_nodes: 当前候选节点, list[str] 或 list[dict]。
        evidence_records: 原生证据记录列表。
        pinned_names: 21 条钉选名列表。
        stop_status: STOP 状态 ("STOP" / "RUNNING" / True / False 等)。
        output_dir: 隔离输出目录 (可选); 为 None 时不写文件只返回计数。
            传入生产路径会直接抛 ValueError。
        candidate_record: 冻结候选记录 (可选); 传入则做候选绑定校验。

    返回十项计数 + 判定:
        candidate_count / evidence_coverage / valid_test_count /
        lt_300_count / gte_300_count / failed_count / unknown_count /
        safe_removal_eligible_count (= removal_candidates) /
        pinned_integrity ("21/21") / stop_status,
        另含 pinned_intact / removal_candidate_names / decision。
    decision: removal_candidates==0 时为 "NO_SAFE_REMOVAL",
        否则为 "REMOVAL_CANDIDATES:<n>"。
    """
    out_path = _check_output_dir(output_dir)
    candidates = list(candidate_nodes or [])
    evidences = list(evidence_records or [])
    pinned = list(pinned_names or [])
    stopped = _is_stop(stop_status)

    candidate_names = _candidate_name_set(candidates)
    fp_map = _candidate_fingerprint_map(candidates)
    pinned_set = {str(p).strip() for p in pinned if str(p).strip()}
    pinned_present = len(pinned_set & candidate_names)
    pinned_intact = bool(pinned_present == PINNED_EXPECTED and pinned_set <= candidate_names)

    covered_names = set()
    valid_test_count = 0
    lt_300_count = 0
    gte_300_count = 0
    failed_count = 0
    unknown_count = 0
    removal_names = set()

    for record in evidences:
        if not isinstance(record, dict):
            unknown_count += 1
            continue
        # 覆盖统计: 先按节点名匹配, 再按 uri_fingerprint 匹配。
        name = _node_name_of(record)
        if name and name in candidate_names:
            covered_names.add(name)
        elif record.get("uri_fingerprint") in fp_map:
            covered_names.add(fp_map[record["uri_fingerprint"]])

        validation = validate_evidence(
            record, candidate_record, pinned_names=pinned, node_name=name
        )
        latency = record.get("latency_ms")
        if validation["valid"] and isinstance(latency, (int, float)) and not isinstance(latency, bool):
            valid_test_count += 1
        if isinstance(latency, (int, float)) and not isinstance(latency, bool):
            if latency < LATENCY_THRESHOLD_MS:
                lt_300_count += 1
            else:
                gte_300_count += 1
        elif latency is None:
            if collector_mod._raw_indicates_failure(record.get("raw_result") or {}):
                failed_count += 1
            else:
                unknown_count += 1
        else:
            unknown_count += 1

        if validation["eligible_for_removal"] and name:
            removal_names.add(name)

    # Global safety interlock. Missing one of the 21 protected members,
    # a missing frozen candidate, or STOP all prohibit deletion regardless
    # of any individual probe verdict.
    if stopped or not pinned_intact or candidate_record is None:
        removal_names = set()
    removal_candidates = len(removal_names)
    decision = "NO_SAFE_REMOVAL" if removal_candidates == 0 else "REMOVAL_CANDIDATES:{}".format(
        removal_candidates
    )

    audit = {
        "candidate_count": len(candidates),
        "evidence_coverage": len(covered_names),
        "evidence_coverage_total": len(candidates),
        "valid_test_count": valid_test_count,
        "lt_300_count": lt_300_count,
        "gte_300_count": gte_300_count,
        "failed_count": failed_count,
        "unknown_count": unknown_count,
        "safe_removal_eligible_count": removal_candidates,
        "removal_candidates": removal_candidates,
        "removal_candidate_names": sorted(removal_names),
        "pinned_present": pinned_present,
        "pinned_expected": PINNED_EXPECTED,
        "pinned_integrity": "{}/{}".format(pinned_present, PINNED_EXPECTED),
        "pinned_intact": pinned_intact,
        "stop_status": "STOP" if stopped else str(stop_status),
        "decision": decision,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    audit["summary_10"] = [
        "1. 当前候选节点数: {}".format(audit["candidate_count"]),
        "2. 原生证据覆盖数: {}/{}".format(
            audit["evidence_coverage"], audit["evidence_coverage_total"]
        ),
        "3. 有效测试数: {}".format(audit["valid_test_count"]),
        "4. 小于 300ms 数量: {}".format(audit["lt_300_count"]),
        "5. 大于等于 300ms 数量: {}".format(audit["gte_300_count"]),
        "6. 明确失败数量: {}".format(audit["failed_count"]),
        "7. UNKNOWN 数量: {}".format(audit["unknown_count"]),
        "8. 具有安全删除资格的非钉选数量: {}".format(audit["safe_removal_eligible_count"]),
        "9. 21 条钉选完整性: {} (intact={})".format(
            audit["pinned_integrity"], audit["pinned_intact"]
        ),
        "10. STOP 状态: {}".format(audit["stop_status"]),
    ]

    if out_path is not None:
        out_path.mkdir(parents=True, exist_ok=True)
        target = out_path / "shadow-audit.json"
        target.write_text(
            json.dumps(audit, ensure_ascii=False, sort_keys=True, indent=2),
            encoding="utf-8",
        )
        audit["audit_file"] = str(target)
    return audit


def _test_fixture_subscription():
    """TEST-NET 测试候选订阅 (30 行: 21 钉选 + 9 轮换, 全部假值)。

    密码一律 test123, 地址一律 192.0.2.0/24, 与真实节点无关。
    """
    lines = []
    for i in range(1, 22):
        lines.append(
            "trojan://test123@192.0.2.{}:443#TEST-PINNED-{:02d}".format(i, i)
        )
    for j in range(1, 10):
        lines.append(
            "trojan://test123@192.0.2.{}:443#TEST-ROTATION-{:02d}".format(100 + j, j)
        )
    return "\n".join(lines) + "\n"


def run_example(output_dir=None):
    """可运行的示例入口。

    用冻结的 TEST-NET 测试候选生成一条完整可复核的同候选证据链示例:
      冻结候选 -> 采集一条证据 (phone_loaded_sha 诚实记 UNKNOWN,
      latency 取 raw_result 显式值 131ms, 语义未校准故
      measurement_verified=False) -> 校验 -> 影子审计。
    同时审计“生产当前态” (30 候选、0 证据) 以复核 0/30 的正确结论。

    输出写到隔离证据目录 (默认 native-evidence/isolated-evidence-example),
    打印两组十项计数并返回结果 dict。
    """
    if output_dir is None:
        output_dir = _HERE / "isolated-evidence-example"
    out_path = _check_output_dir(output_dir)
    out_path.mkdir(parents=True, exist_ok=True)

    subscription = _test_fixture_subscription()
    subscription_bytes = subscription.encode("utf-8")
    candidate = freeze_mod.freeze_candidate(subscription_bytes, source_revision="test-revision-001")
    verify = freeze_mod.verify_candidate(candidate, subscription_bytes)
    assert verify["valid"], "示例候选冻结后自校验应通过: {}".format(verify["reason"])

    pinned_names = ["TEST-PINNED-{:02d}".format(i) for i in range(1, 22)]
    rotation_names = ["TEST-ROTATION-{:02d}".format(j) for j in range(1, 10)]
    candidate_nodes = pinned_names + rotation_names

    # 一条完整可复核的同候选证据链示例。
    # 注意诚实点: 沙盒内无真机, phone_loaded_sha 只能是 UNKNOWN;
    # measurement_verified 保持 False (语义未校准)。
    uri_fp = collector_mod.fingerprint_uri("trojan://test123@192.0.2.101:443#TEST-ROTATION-01")
    raw_result = {
        "node_name": "TEST-ROTATION-01",
        "latency_ms": 131,
        "round_one_total_ms": 1315,
        "available_ms": 387,
        "note": "TEST-NET 示例: latency_ms 为显式测速值; "
        "round_one_total_ms 仅作原始字段保留, 不等于组内显示分。",
    }
    evidence = collector_mod.build_evidence_chain(
        candidate_record=candidate,
        phone_loaded_sha="UNKNOWN",
        uri_fingerprint=uri_fp,
        policy_identifier=collector_mod.POLICY_IDENTIFIER,
        raw_result=raw_result,
        test_url="https://example.invalid/generate_204",
        network_bearer="UNKNOWN",
        tested_at=collector_mod.now_iso8601(),
        measurement_verified=False,
    )
    judged = collector_mod.annotate_verdict(evidence)
    validation = validate_evidence(judged, candidate, pinned_names=pinned_names)

    chain_file = out_path / "example-evidence-chain.json"
    chain_file.write_text(
        json.dumps(
            {
                "candidate": candidate,
                "candidate_verify": verify,
                "evidence": judged,
                "validation": validation,
                "phone_loaded_sha_honest": judged["phone_loaded_sha"],
            },
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        ),
        encoding="utf-8",
    )

    # 示例审计: 30 候选 + 1 条示例证据。
    example_audit = audit_shadow(
        candidate_nodes,
        [judged],
        pinned_names,
        stop_status="RUNNING",
        output_dir=None,
        candidate_record=candidate,
    )
    (out_path / "shadow-audit-example.json").write_text(
        json.dumps(example_audit, ensure_ascii=False, sort_keys=True, indent=2),
        encoding="utf-8",
    )

    # 生产当前态复核: 30 候选 + 0 证据 -> 覆盖 0/30, removal 0, NO_SAFE_REMOVAL。
    production_audit = audit_shadow(
        candidate_nodes,
        [],
        pinned_names,
        stop_status="RUNNING",
        output_dir=None,
        candidate_record=candidate,
    )
    (out_path / "shadow-audit-production-state-0-30.json").write_text(
        json.dumps(production_audit, ensure_ascii=False, sort_keys=True, indent=2),
        encoding="utf-8",
    )

    return {
        "output_dir": str(out_path),
        "chain_file": str(chain_file),
        "candidate_id": candidate["candidate_id"],
        "phone_loaded_sha": judged["phone_loaded_sha"],
        "evidence_verdict": judged["verdict"],
        "validation": validation,
        "example_audit": example_audit,
        "production_state_audit": production_audit,
    }


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="证据校验器 + 影子审计示例入口")
    parser.add_argument(
        "--output-dir",
        default=None,
        help="隔离证据输出目录 (默认 native-evidence/isolated-evidence-example, 永不写生产路径)",
    )
    args = parser.parse_args(argv)
    result = run_example(output_dir=args.output_dir)
    print("示例证据链已产出: {}".format(result["chain_file"]))
    print("candidate_id: {}".format(result["candidate_id"]))
    print("phone_loaded_sha (诚实结论): {}".format(result["phone_loaded_sha"]))
    print("示例证据 verdict: {}".format(result["evidence_verdict"]))
    print("eligible_for_removal: {}".format(result["validation"]["eligible_for_removal"]))
    print("")
    print("== 示例审计十项计数 (30 候选 + 1 条 TEST-NET 示例证据) ==")
    for line in result["example_audit"]["summary_10"]:
        print(line)
    print("decision: {}".format(result["example_audit"]["decision"]))
    print("")
    print("== 生产当前态复核十项计数 (30 候选 + 0 证据) ==")
    for line in result["production_state_audit"]["summary_10"]:
        print(line)
    print("decision: {}".format(result["production_state_audit"]["decision"]))
    print("removal_candidates: {}".format(result["production_state_audit"]["removal_candidates"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
