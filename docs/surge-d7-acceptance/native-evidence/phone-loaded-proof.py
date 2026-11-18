# -*- coding: utf-8 -*-
"""
F2. 手机已加载订阅证明 (phone-loaded-proof.py)

任务 F 第二步: phone_loaded_sha 验证机制。

背景 (第一轮遗留阻塞):
  * phone_loaded_sha 是 UNKNOWN —— 手机实际加载的订阅无法独立验证。
  * 配置文件内容 / 资源 ready 状态 / updatedAt / 源端 SHA,
    均不自动等于实际已加载订阅 SHA, 不得互相推断。

证明等级 (proof_level, 强到弱, fail-closed):
  * "BYTE_PROOF"        字节级证明: 手机端独立上报的已加载订阅 SHA-256
                        与冻结候选 payload_sha256 逐字节一致。
                        唯一能把 phone_loaded_sha 从 "UNKNOWN" 改为
                        真实 SHA 的等级。
  * "MEMBERS_VERIFIED"  弱证明: 手机端可读的已加载成员名集合
                        (如 /v1/policies 或 /v1/policy_groups 返回的
                        成员名) 与冻结候选成员集合逐名一致。
                        只能证明“成员名集合一致”, 不能证明字节一致
                        (同一成员名可对应不同 URI / 密码 / 参数)。
                        phone_loaded_sha 仍保持 "UNKNOWN",
                        production_admission 恒为 "PENDING_REVIEW",
                        生产准入资格须单独审查, 永远不能由弱证明
                        自动升级为 BYTE_PROOF。
  * "UNVERIFIED"        无证明: 无字节 SHA、无完整成员集合、
                        或任一比对不一致。phone_loaded_sha 为 "UNKNOWN"。

硬规则:
  * 任何情况下不得伪造 phone_loaded_sha: 只有 BYTE_PROOF 能填入
    64 位 SHA-256, 其他等级一律 "UNKNOWN"。
  * 弱证明绝不参与 evidence-validator 的 eligible_for_removal 判定:
    validator 仍只认 phone_loaded_sha 为 hex 的证据。
    本模块提供 attach_loaded_proof() 把证明附加到证据记录上,
    但它永不改写 verdict, 也不把 phone_loaded_sha 写成已验证。
  * 成员集合比对是“集合相等” (排序去重后逐名相等), 不是“包含”:
    多一个 / 少一个 / 改名, 一律不通过。
  * 配置文件内容、external_resources 的 ready 状态、updatedAt、
    源端 SHA, 一律不作为已加载证明: classify_loaded_proof()
    会把这些输入显式标记为 insufficient, 并给出理由。

只用 Python 3 标准库, 不联网, 不读 / 不写生产路径。
测试夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123)。
"""

from __future__ import annotations

import hashlib
import re

PROOF_LEVELS = ("BYTE_PROOF", "MEMBERS_VERIFIED", "UNVERIFIED")

# production_admission 取值:
#   "GRANTED"        仅 BYTE_PROOF 且与冻结候选一致时 (本模块只出证明,
#                    真正的生产准入仍由 evidence-validator 另行判定)。
#   "PENDING_REVIEW" 弱证明 (MEMBERS_VERIFIED) 的固定值: 须单独审查。
#   "DENIED"         无证明 / 比对不一致。
ADMISSIONS = ("GRANTED", "PENDING_REVIEW", "DENIED")

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _is_sha256(value) -> bool:
    return isinstance(value, str) and bool(_SHA256_RE.match(value))


def _member_names(value) -> list:
    """归一化成员名列表: 去空白、去空串、去重、排序。非字符串元素直接丢弃
    (不静默改写, 调用方另行记录)。返回排序后的名字列表。"""
    if not isinstance(value, (list, tuple, set)):
        return []
    names = set()
    for item in value:
        if isinstance(item, str) and item.strip():
            names.add(item.strip())
    return sorted(names)


def _frozen_member_names(candidate_record: dict) -> list:
    """从冻结候选记录取成员名集合。

    优先用 candidate_record["member_names"] (冻结时若已记录);
    否则从 "member_lines" 逐行取 '#' 后的名字 (订阅行形如
    trojan://...#NAME); 两者都没有时返回 [] (无法比对 -> UNVERIFIED)。
    """
    if not isinstance(candidate_record, dict):
        return []
    names = candidate_record.get("member_names")
    if isinstance(names, (list, tuple, set)) and names:
        return _member_names(names)
    lines = candidate_record.get("member_lines")
    if isinstance(lines, (list, tuple)):
        parsed = []
        for line in lines:
            if isinstance(line, str) and "#" in line:
                parsed.append(line.rsplit("#", 1)[-1].strip())
        return _member_names(parsed)
    return []


def verify_byte_level(phone_reported_sha, candidate_record: dict) -> dict:
    """字节级证明校验。

    phone_reported_sha: 手机端独立上报的已加载订阅 SHA-256,
    或 "UNKNOWN" / None (表示手机端未提供)。
    candidate_record: freeze_candidate() 产出的冻结记录。

    返回 {"proof_level", "phone_loaded_sha", "production_admission",
          "match", "reasons": [...]}。
    只有上报 SHA 为合法 hex 且与冻结 payload_sha256 相等时才为 BYTE_PROOF。
    """
    reasons = []
    frozen_sha = (candidate_record or {}).get("payload_sha256")
    if not _is_sha256(frozen_sha):
        return {
            "proof_level": "UNVERIFIED",
            "phone_loaded_sha": "UNKNOWN",
            "production_admission": "DENIED",
            "match": False,
            "reasons": ["冻结候选缺少合法 payload_sha256, 无法做字节级比对"],
        }
    if phone_reported_sha in (None, "UNKNOWN", ""):
        return {
            "proof_level": "UNVERIFIED",
            "phone_loaded_sha": "UNKNOWN",
            "production_admission": "DENIED",
            "match": False,
            "reasons": ["手机端未提供已加载订阅 SHA (UNKNOWN), 无字节级证明"],
        }
    if not _is_sha256(phone_reported_sha):
        return {
            "proof_level": "UNVERIFIED",
            "phone_loaded_sha": "UNKNOWN",
            "production_admission": "DENIED",
            "match": False,
            "reasons": ["手机端上报的 SHA 不是合法 SHA-256 hex, 拒绝采信"],
        }
    if phone_reported_sha == frozen_sha:
        return {
            "proof_level": "BYTE_PROOF",
            "phone_loaded_sha": phone_reported_sha,
            "production_admission": "GRANTED",
            "match": True,
            "reasons": ["手机端上报的已加载订阅 SHA 与冻结候选 payload_sha256 一致"],
        }
    return {
        "proof_level": "UNVERIFIED",
        "phone_loaded_sha": "UNKNOWN",
        "production_admission": "DENIED",
        "match": False,
        "reasons": [
            "手机端上报的已加载订阅 SHA 与冻结候选 payload_sha256 不一致: "
            "手机加载的不是本轮冻结候选"
        ],
    }


def verify_loaded_members(phone_member_names, candidate_record: dict) -> dict:
    """弱证明校验: 已加载成员名集合比对。

    phone_member_names: 手机端可读的已加载成员名列表
    (如 /v1/policies 或 /v1/policy_groups 返回的成员名)。
    candidate_record: 冻结候选记录 (须含 member_names 或 member_lines)。

    返回 {"proof_level", "phone_loaded_sha", "production_admission",
          "loaded_members_verified", "matched_count", "expected_count",
          "missing", "extra", "reasons": [...]}。
    集合完全相等时 proof_level 为 "MEMBERS_VERIFIED",
    但 phone_loaded_sha 仍为 "UNKNOWN",
    production_admission 恒为 "PENDING_REVIEW"。
    """
    reasons = []
    phone_names = _member_names(phone_member_names)
    frozen_names = _frozen_member_names(candidate_record)
    base = {
        "phone_loaded_sha": "UNKNOWN",  # 弱证明永不填入真实 SHA
        "production_admission": "PENDING_REVIEW",
        "loaded_members_verified": False,
        "matched_count": 0,
        "expected_count": len(frozen_names),
        "missing": [],
        "extra": [],
    }
    if not frozen_names:
        base.update(
            {
                "proof_level": "UNVERIFIED",
                "production_admission": "DENIED",
                "reasons": ["冻结候选未记录成员名集合, 无法做成员集合比对"],
            }
        )
        return base
    if not phone_names:
        base.update(
            {
                "proof_level": "UNVERIFIED",
                "production_admission": "DENIED",
                "reasons": ["手机端未返回可读的已加载成员名集合, 无弱证明"],
            }
        )
        return base
    phone_set = set(phone_names)
    frozen_set = set(frozen_names)
    missing = sorted(frozen_set - phone_set)
    extra = sorted(phone_set - frozen_set)
    matched = len(frozen_set & phone_set)
    base.update(
        {
            "matched_count": matched,
            "missing": missing,
            "extra": extra,
        }
    )
    if not missing and not extra:
        base.update(
            {
                "proof_level": "MEMBERS_VERIFIED",
                "loaded_members_verified": True,
                "reasons": [
                    "手机端已加载成员名集合与冻结候选成员集合逐名一致 "
                    "({}/{}); 仅证明成员名一致, 不证明字节一致, "
                    "生产准入待单独审查".format(matched, len(frozen_names))
                ],
            }
        )
        return base
    if missing:
        reasons.append("手机端缺失冻结候选成员: {}".format(", ".join(missing)))
    if extra:
        reasons.append("手机端多出冻结候选外成员: {}".format(", ".join(extra)))
    reasons.append(
        "成员集合不一致 ({}/{} 匹配), 弱证明不成立".format(matched, len(frozen_names))
    )
    base.update(
        {
            "proof_level": "UNVERIFIED",
            "production_admission": "DENIED",
            "reasons": reasons,
        }
    )
    return base


def classify_loaded_proof(api_responses: dict, candidate_record: dict,
                          group_name: str = None) -> dict:
    """从一组只读 API 原始响应判定手机已加载证明的上限。

    api_responses: 各只读端点的原始 JSON 响应 dict, 键为端点路径, 如:
        {"/v1/profiles/current": {...},
         "/v1/external_resources": {...},
         "/v1/policy_groups": {...},
         "/v1/policies": {...}}
    group_name: 要比对的策略组名 (如 "免费节点池")。给出时,
        /v1/policy_groups 的成员取该规则下的条目名
        (isGroup=false 的代理条目); 不给时回退为全部规则条目名
        的并集 (更弱, 仅作参考, 须在 reasons 中注明)。
    只读响应里**没有**已加载订阅字节 SHA 时, 本函数绝不推断 BYTE_PROOF。
    配置文件内容 / ready 状态 / updatedAt / 源端 SHA 一律记为
    insufficient, 并在 reasons 中逐项说明为什么不算证明。

    返回 {"proof_level", "phone_loaded_sha", "production_admission",
          "loaded_members_verified", "available_sources": [...],
          "insufficient_sources": [...], "reasons": [...]}。
    """
    available = []
    insufficient = []
    reasons = []

    # 端点键归一化: 去掉 query 部分
    # (如 "/v1/profiles/current?sensitive=0" -> "/v1/profiles/current")。
    responses = {}
    if isinstance(api_responses, dict):
        for key, value in api_responses.items():
            if isinstance(key, str):
                responses[key.split("?", 1)[0]] = value
                responses.setdefault(key, value)
            else:
                responses[key] = value

    profiles = responses.get("/v1/profiles/current")
    if isinstance(profiles, dict) and profiles:
        available.append("/v1/profiles/current")
        # profiles/current 只给配置元数据, 不给已加载订阅字节 SHA。
        insufficient.append(
            "/v1/profiles/current: 仅含配置元数据 (名称/updatedAt 等), "
            "不含已加载订阅字节 SHA, 不能作为 phone_loaded_sha 证明"
        )
    resources = responses.get("/v1/external_resources")
    if isinstance(resources, dict) and resources:
        available.append("/v1/external_resources")
        insufficient.append(
            "/v1/external_resources: ready 状态只说明资源可加载, "
            "不等于实际已加载订阅字节 SHA"
        )
    groups = responses.get("/v1/policy_groups")
    if isinstance(groups, dict) and groups:
        available.append("/v1/policy_groups")
    policies = responses.get("/v1/policies")
    if isinstance(policies, dict) and policies:
        available.append("/v1/policies")

    # 字节级证明: 只有响应中出现手机端独立上报的已加载 SHA 才认。
    reported_sha = None
    if isinstance(responses, dict):
        for key in ("phone_loaded_sha", "loaded_sha", "loaded_subscription_sha"):
            value = responses.get(key)
            if _is_sha256(value):
                reported_sha = value
                break
    if reported_sha is not None:
        byte_result = verify_byte_level(reported_sha, candidate_record)
        if byte_result["proof_level"] == "BYTE_PROOF":
            byte_result.update(
                {
                    "loaded_members_verified": False,
                    "available_sources": available,
                    "insufficient_sources": insufficient,
                    "reasons": byte_result["reasons"]
                    + ["字节级证明来自手机端独立上报的已加载订阅 SHA"],
                }
            )
            return byte_result
        reasons.extend(byte_result["reasons"])

    # 弱证明: 从 /v1/policies 或 /v1/policy_groups 取成员名集合。
    phone_names = []
    for endpoint in ("/v1/policies", "/v1/policy_groups"):
        payload = responses.get(endpoint)
        phone_names.extend(_extract_member_names_from_api(payload, group_name))
    if group_name is None:
        reasons.append(
            "未指定策略组名, /v1/policy_groups 成员取全部规则条目名的并集, "
            "弱证明口径更宽, 仅作参考"
        )
    members_result = verify_loaded_members(phone_names, candidate_record)
    if members_result["proof_level"] == "MEMBERS_VERIFIED":
        extra_reasons = ["成员名集合取自 {}".format(", ".join(available) or "无")]
        if group_name is None:
            extra_reasons.append(
                "未指定策略组名, 成员取全部规则条目名的并集, 弱证明口径更宽, 仅作参考"
            )
        members_result.update(
            {
                "available_sources": available,
                "insufficient_sources": insufficient,
                "reasons": members_result["reasons"] + extra_reasons,
            }
        )
        return members_result

    reasons.extend(members_result["reasons"])
    reasons.extend(insufficient)
    return {
        "proof_level": "UNVERIFIED",
        "phone_loaded_sha": "UNKNOWN",
        "production_admission": "DENIED",
        "loaded_members_verified": False,
        "available_sources": available,
        "insufficient_sources": insufficient,
        "reasons": reasons or ["无任何可用的已加载证明来源"],
    }


def _extract_member_names_from_api(payload, group_name=None) -> list:
    """从 /v1/policies 或 /v1/policy_groups 原始响应中提取成员名。

    接受的形态 (只读、容错、绝不猜测):
      * {"policies": ["NAME", ...]} / {"policies": [{"name": ...}, ...]}
      * {"groups": {"GROUP": {"members": ["NAME", ...], ...}}}
      * {"members": ["NAME", ...]}
      * 顶层 list。
      * 规则 -> 条目列表 (真实 /v1/policy_groups 形态):
        {"RULE": [{"name": "NAME", "isGroup": bool, ...}, ...]}。
        group_name 给出时只取该规则下 isGroup=false 的代理条目名;
        不给时取全部规则条目名的并集。
    取不到名字时返回 [], 由上层判 UNVERIFIED。
    """
    names = []
    if isinstance(payload, list):
        for item in payload:
            if isinstance(item, str):
                names.append(item)
            elif isinstance(item, dict) and isinstance(item.get("name"), str):
                names.append(item["name"])
        return names
    if not isinstance(payload, dict):
        return names
    for key in ("policies", "members"):
        value = payload.get(key)
        if isinstance(value, list):
            for item in value:
                if isinstance(item, str):
                    names.append(item)
                elif isinstance(item, dict) and isinstance(item.get("name"), str):
                    names.append(item["name"])
    groups = payload.get("groups")
    if isinstance(groups, dict):
        for group in groups.values():
            if isinstance(group, dict):
                members = group.get("members")
                if isinstance(members, list):
                    for item in members:
                        if isinstance(item, str):
                            names.append(item)
                        elif isinstance(item, dict) and isinstance(item.get("name"), str):
                            names.append(item["name"])
    # 真实 /v1/policy_groups 形态: 规则名 -> 条目列表。
    rule_lists = {
        key: value
        for key, value in payload.items()
        if isinstance(value, list)
        and value
        and all(isinstance(item, dict) and "name" in item for item in value)
    }
    if rule_lists:
        if group_name is not None and group_name in rule_lists:
            for item in rule_lists[group_name]:
                # 只取代理条目 (isGroup=false); 策略组条目不是成员。
                if item.get("isGroup") is False and isinstance(item.get("name"), str):
                    names.append(item["name"])
        elif group_name is None:
            for entries in rule_lists.values():
                for item in entries:
                    if item.get("isGroup") is False and isinstance(item.get("name"), str):
                        names.append(item["name"])
    return names


def attach_loaded_proof(evidence_record: dict, proof: dict) -> dict:
    """把已加载证明附加到证据记录副本上 (不修改输入, 不改写 verdict)。

    附加字段:
      * loaded_proof_level: "BYTE_PROOF" / "MEMBERS_VERIFIED" / "UNVERIFIED"
      * loaded_members_verified: bool
      * production_admission: "GRANTED" / "PENDING_REVIEW" / "DENIED"
    只有 proof_level 为 BYTE_PROOF 时才把 phone_loaded_sha 写成真实 SHA;
    其他等级下 phone_loaded_sha 保持原值 (一般为 "UNKNOWN")。
    verdict 永不由本函数改写: 语义校准与否仍由 judge_evidence() 判定。
    """
    if not isinstance(evidence_record, dict):
        raise TypeError("evidence_record 必须是 dict")
    if not isinstance(proof, dict):
        raise TypeError("proof 必须是 dict")
    level = proof.get("proof_level")
    if level not in PROOF_LEVELS:
        raise ValueError("proof_level 非法: {!r}".format(level))
    admission = proof.get("production_admission")
    if admission not in ADMISSIONS:
        raise ValueError("production_admission 非法: {!r}".format(admission))
    record = dict(evidence_record)
    record["loaded_proof_level"] = level
    record["loaded_members_verified"] = bool(proof.get("loaded_members_verified"))
    record["production_admission"] = admission
    if level == "BYTE_PROOF":
        sha = proof.get("phone_loaded_sha")
        if not _is_sha256(sha):
            raise ValueError("BYTE_PROOF 必须携带合法 SHA-256 phone_loaded_sha")
        record["phone_loaded_sha"] = sha
    return record


def member_set_sha_of_names(names) -> str:
    """成员名集合 SHA: 排序去重后的名字以 "\\n" 连接后取 SHA-256。

    供调用方把手机端成员名集合与冻结候选的 member_set_sha256
    做集合级比对时使用。注意: 名字集合 SHA 与订阅字节的
    member_set_sha256 口径不同 (后者以订阅行原文为准),
    两者相等不能互相替代, 仅作辅助核对。
    """
    joined = "\n".join(_member_names(names))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


if __name__ == "__main__":
    print("phone-loaded-proof.py: 手机已加载订阅证明机制, 无独立 CLI。")
    print("证明等级: BYTE_PROOF > MEMBERS_VERIFIED(弱证明, 准入待审查) > UNVERIFIED。")
    print("只有 BYTE_PROOF 能填入真实 phone_loaded_sha; 其他等级一律 UNKNOWN。")
