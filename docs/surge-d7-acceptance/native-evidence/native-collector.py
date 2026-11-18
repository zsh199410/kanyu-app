# -*- coding: utf-8 -*-
"""
B2. 原生测速采集器 (native-collector.py)

采集手机 Surge 原生测速证据, 证据记录 schema 字段名与类型严格一致。

三者必须区分, 缺一不可 (不得互相推断):
  (1) VPS 已生成的订阅: 冻结候选的 payload_sha256 (见 candidate-freeze.py)。
  (2) HTTP 实际返回的订阅: 下发时实测到的响应字节 SHA (应与 (1) 比对,
      不一致即说明下发链路有问题, 证据记 UNVERIFIED)。
  (3) 手机 Surge 实际加载的订阅: phone_loaded_sha。
      只有手机端独立上报 / 独立读取到的已加载订阅 SHA 才能作为此值。
      不能因 (1) 与 (2) 的 SHA 相同就推断手机加载成功。
      无法独立验证时 phone_loaded_sha 记 "UNKNOWN", 且该证据
      禁止用于生产下架 (由 evidence-validator.py 强制执行)。

硬规则:
  * 采集时保留原始字段和数据类型, 禁止为适配字段编造延迟。
    latency_ms 只取 raw_result 中显式的数值型 latency_ms,
    没有就不填 (null), 绝不拿 round-one-total / available / tcp /
    receive 等其他数字冒充。
  * latency_ms 为 null 时 verdict 不得为合格 (PASS)。
  * 网络类型只认 wifi / cellular / UNKNOWN; 无法确定时记 UNKNOWN,
    不得伪装成蜂窝结果。
  * measurement_verified 在原生语义未校准前保持 False。
    Surge API 测试值与手机界面显示值的语义对照见 README.md:
    round-one-total / available / tcp / receive 均不等于
    Smart 组内显示分 (组报第二轮分数), 语义未校准前
    measurement_verified 必须为 False, judge_evidence() 据此判 UNVERIFIED。
  * 真机 POST 部分只写接口与约束, 不实际发送。
    沙盒内无真机, 本模块不含任何 socket / HTTP 发送代码;
    post_test_to_phone() 只返回“未发送”的明确结果。

只用 Python 3 标准库, 不联网, 不读 / 不写生产路径。
测试夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123)。
"""

from __future__ import annotations

import hashlib
import re
from datetime import datetime, timezone

POLICY_IDENTIFIER = "native-evidence-policy-v1"

# 合格阈值: 严格小于 300ms 才可作为合格候选条件之一。
LATENCY_THRESHOLD_MS = 300

# 证据时效: 24 小时, 过期判 UNVERIFIED (校验器执行, 此处供判定共用)。
EVIDENCE_TTL_SECONDS = 24 * 3600

VALID_BEARERS = ("wifi", "cellular", "UNKNOWN")

# 批次执行范围约束。
MAX_BATCH_SIZE = 10
MIN_BATCH_INTERVAL_SECONDS = 3600

# verdict 取值 (judge_evidence 产出):
#   PASS         严格 <300ms, 且语义已校准、手机加载已验证、未过期
#   ABOVE_TARGET 延迟 >=300ms 但仍连通（保留；不是连接失败）
#   FAIL         超时或失败 (latency_ms 为 null, 原始失败证据保留)
#   UNKNOWN      未测试 (latency_ms 为 null, 且无失败信号)
#   UNVERIFIED   默认 / 版本不一致 / 已过期 / 语义未校准 / 手机加载未验证
VERDICTS = ("PASS", "ABOVE_TARGET", "FAIL_LATENCY", "FAIL", "UNKNOWN", "UNVERIFIED")

# 证据记录 schema: 字段名 -> 允许的类型 (tuple)。
# latency_ms 允许 int/float 或 None; bool 不是合法延迟 (Python bool 是 int 子类, 须排除)。
EVIDENCE_SCHEMA = {
    "candidate_id": (str,),
    "payload_sha": (str,),
    "member_set_sha": (str,),
    "phone_loaded_sha": (str,),
    "policy_identifier": (str,),
    "uri_fingerprint": (str,),
    "test_url": (str,),
    "network_bearer": (str,),
    "latency_ms": (int, float, type(None)),
    "raw_result": (dict,),
    "tested_at": (str,),
    "measurement_verified": (bool,),
    "verdict": (str,),
}

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def fingerprint_uri(uri: str) -> str:
    """节点 URI 的指纹 (SHA-256 hex)。证据只存指纹, 不存原始 URI。

    原始 URI / 密码绝不写入证据记录、日志或代码。
    """
    if not isinstance(uri, str) or not uri:
        raise ValueError("uri 必须是非空字符串")
    return hashlib.sha256(uri.encode("utf-8")).hexdigest()


def normalize_network_bearer(value) -> str:
    """规范化网络类型, 只认 wifi / cellular / UNKNOWN。

    None / 空串 / 空白 -> "UNKNOWN" (无法确定, 不得伪装成蜂窝结果)。
    大小写不敏感 ("WiFi" -> "wifi")。
    其他值 -> ValueError, 拒绝写入, 防止伪造网络类型。
    """
    if value is None:
        return "UNKNOWN"
    if isinstance(value, str):
        v = value.strip().lower()
        if v == "":
            return "UNKNOWN"
        if v in ("wifi", "wi-fi"):
            return "wifi"
        if v in ("cellular", "cell", "mobile", "4g", "5g"):
            return "cellular"
        if v == "unknown":
            return "UNKNOWN"
        raise ValueError("无法识别的 network_bearer: {!r}, 只允许 wifi/cellular/UNKNOWN".format(value))
    raise ValueError("network_bearer 必须是字符串, 得到 {!r}".format(type(value).__name__))


def validate_phone_loaded_sha(value) -> str:
    """校验 phone_loaded_sha: 64 位小写 hex, 或 "UNKNOWN"。

    "UNKNOWN" 表示手机实际加载的订阅无法独立验证,
    该证据禁止用于生产下架。其他任何值都拒绝, 防止伪造“已验证”。
    """
    if value == "UNKNOWN":
        return "UNKNOWN"
    if isinstance(value, str) and _SHA256_RE.match(value):
        return value
    raise ValueError(
        'phone_loaded_sha 必须是 64 位 SHA-256 hex 或 "UNKNOWN", 得到 {!r}'.format(value)
    )


def validate_evidence_schema(record: dict) -> list:
    """校验证据记录的 schema 完整性与字段类型, 返回错误列表 (空表 = 通过)。

    补充检查:
      * latency_ms 为 bool 时拒绝 (bool 是 int 子类, 但不是合法延迟)。
      * network_bearer 不在 wifi/cellular/UNKNOWN 时拒绝。
      * phone_loaded_sha 不是 SHA-256 或 "UNKNOWN" 时拒绝。
      * tested_at 无法解析为 ISO8601 时拒绝。
      * verdict 不在取值范围时拒绝。
    """
    errors = []
    if not isinstance(record, dict):
        return ["证据记录不是 dict"]
    for field, types in EVIDENCE_SCHEMA.items():
        if field not in record:
            errors.append("缺字段: {}".format(field))
            continue
        value = record[field]
        if field == "latency_ms":
            if isinstance(value, bool) or not isinstance(value, types):
                errors.append("字段类型错误: latency_ms 必须是 number 或 null")
            elif isinstance(value, (int, float)) and value < 0:
                errors.append("字段值错误: latency_ms 不得为负数")
            continue
        if not isinstance(value, types):
            errors.append(
                "字段类型错误: {} 应为 {}, 得到 {}".format(
                    field, "/".join(t.__name__ for t in types), type(value).__name__
                )
            )
    if isinstance(record.get("network_bearer"), str) and record["network_bearer"] not in VALID_BEARERS:
        errors.append("字段值错误: network_bearer 只允许 wifi/cellular/UNKNOWN")
    if isinstance(record.get("phone_loaded_sha"), str):
        if record["phone_loaded_sha"] != "UNKNOWN" and not _SHA256_RE.match(record["phone_loaded_sha"]):
            errors.append('字段值错误: phone_loaded_sha 必须是 SHA-256 或 "UNKNOWN"')
    if isinstance(record.get("verdict"), str) and record["verdict"] not in VERDICTS:
        errors.append("字段值错误: verdict 不在允许取值范围: {}".format(record["verdict"]))
    if isinstance(record.get("tested_at"), str):
        try:
            parse_iso8601(record["tested_at"])
        except ValueError:
            errors.append("字段值错误: tested_at 不是合法 ISO8601 时间")
    return errors


def parse_iso8601(value: str) -> datetime:
    """解析 ISO8601 时间 (接受末尾 Z)。返回带时区的 datetime。"""
    if not isinstance(value, str):
        raise ValueError("tested_at 必须是 ISO8601 字符串")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def now_iso8601() -> str:
    """当前 UTC 时间 ISO8601 (末尾 Z)。"""
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _raw_indicates_failure(raw_result: dict) -> bool:
    """raw_result 是否带有明确的超时 / 失败信号。

    只认显式信号, 不猜测: status 为 timeout/failed/error/failure,
    或 timeout==True, 或 error 字段非空。
    """
    if not isinstance(raw_result, dict):
        return False
    status = raw_result.get("status")
    if isinstance(status, str) and status.strip().lower() in (
        "timeout",
        "timed_out",
        "failed",
        "failure",
        "error",
    ):
        return True
    if raw_result.get("timeout") is True:
        return True
    error = raw_result.get("error")
    if isinstance(error, str) and error.strip():
        return True
    if isinstance(error, dict) and error:
        return True
    result = raw_result.get("result")
    if isinstance(result, str) and result.strip().lower() in ("timeout", "failed", "error"):
        return True
    return False


def _extract_latency_ms(raw_result: dict, latency_ms=None):
    """提取延迟, 绝不编造。

    优先用调用方显式传入的 latency_ms (数值型才有效);
    否则取 raw_result["latency_ms"] (数值型才有效)。
    raw_result 里其他键 (round_one_total / available / tcp / receive 等)
    语义与组内显示分不同, 一律不取, 缺失即为 null。
    """
    if latency_ms is not None:
        if isinstance(latency_ms, bool) or not isinstance(latency_ms, (int, float)):
            raise ValueError("latency_ms 必须是 number 或 null")
        return latency_ms
    if isinstance(raw_result, dict):
        value = raw_result.get("latency_ms")
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError("raw_result['latency_ms'] 必须是 number 或 null, 不得编造")
        return value
    return None


def build_evidence_chain(
    candidate_record: dict,
    phone_loaded_sha: str,
    uri_fingerprint: str,
    policy_identifier: str,
    raw_result: dict,
    test_url: str,
    network_bearer,
    tested_at: str,
    latency_ms=None,
    measurement_verified: bool = False,
) -> dict:
    """组装一条证据记录 (数据链关联函数)。

    参数:
        candidate_record: freeze_candidate() 产出的冻结记录 dict。
        phone_loaded_sha: 手机实际加载订阅的 SHA-256, 或 "UNKNOWN"
            (无法独立验证时必须记 "UNKNOWN", 禁止伪造已验证)。
        uri_fingerprint: 被测节点 URI 的 SHA-256 指纹 (不存原始 URI)。
        policy_identifier: 判定策略标识, 应与 POLICY_IDENTIFIER 一致。
        raw_result: Surge 原生返回的原始结果 dict, 原样保留, 不改类型。
        test_url: 本次测速的目标 URL (字符串)。
        network_bearer: wifi / cellular / UNKNOWN (无法确定 -> UNKNOWN)。
        tested_at: ISO8601 测试时间。
        latency_ms: 显式延迟 (可选); 不传则取 raw_result["latency_ms"],
            无数值即为 null, 绝不从其他字段推导。
        measurement_verified: 语义是否已校准。默认 False;
            仅当 Surge API 值与手机界面显示值的语义对照已校准时才传 True。

    返回: 按 schema 的证据记录 dict, verdict 初始为 "UNVERIFIED",
    须经 judge_evidence() 判定后才有最终 verdict。
    """
    if not isinstance(candidate_record, dict):
        raise TypeError("candidate_record 必须是 dict")
    for field in ("candidate_id", "payload_sha256", "member_set_sha256"):
        if field not in candidate_record:
            raise ValueError("candidate_record 缺字段: {}".format(field))
    if not isinstance(raw_result, dict):
        raise TypeError("raw_result 必须是 dict (原始结果原样保留)")
    if not isinstance(test_url, str):
        raise TypeError("test_url 必须是字符串")
    if not isinstance(policy_identifier, str) or not policy_identifier:
        raise ValueError("policy_identifier 必须是非空字符串")
    if not isinstance(uri_fingerprint, str) or not _SHA256_RE.match(uri_fingerprint):
        raise ValueError("uri_fingerprint 必须是 64 位 SHA-256 hex")
    if not isinstance(measurement_verified, bool):
        raise TypeError("measurement_verified 必须是 bool")
    if tested_at is None:
        tested_at = now_iso8601()
    parse_iso8601(tested_at)  # 非法时间直接报错, 不静默改写

    latency = _extract_latency_ms(raw_result, latency_ms)
    bearer = normalize_network_bearer(network_bearer)
    phone_sha = validate_phone_loaded_sha(phone_loaded_sha)

    record = {
        "candidate_id": candidate_record["candidate_id"],
        "payload_sha": candidate_record["payload_sha256"],
        "member_set_sha": candidate_record["member_set_sha256"],
        "phone_loaded_sha": phone_sha,
        "policy_identifier": policy_identifier,
        "uri_fingerprint": uri_fingerprint,
        "test_url": test_url,
        "network_bearer": bearer,
        "latency_ms": latency,
        "raw_result": dict(raw_result),
        "tested_at": tested_at,
        "measurement_verified": measurement_verified,
        "verdict": "UNVERIFIED",
    }
    errors = validate_evidence_schema(record)
    if errors:
        raise ValueError("证据记录 schema 校验失败: {}".format("; ".join(errors)))
    return record


def is_expired(record: dict, now: datetime = None) -> bool:
    """证据是否已过期 (TTL 24h)。时间无法解析 -> 按过期处理 (fail-closed)。"""
    try:
        tested = parse_iso8601(record["tested_at"])
    except (KeyError, ValueError, TypeError, AttributeError):
        return True
    ref = now or datetime.now(timezone.utc)
    if tested > ref:
        # 未来时间超过 5 分钟容差: 时间不可信, 按过期处理。
        return (tested - ref).total_seconds() > 300
    return (ref - tested).total_seconds() > EVIDENCE_TTL_SECONDS


def judge_evidence(record: dict) -> str:
    """判定一条证据记录, 返回 verdict 字符串 (不修改输入)。

    判定顺序 (fail-closed):
      1. schema 不完整 / 类型错误 -> UNVERIFIED
      2. policy_identifier 与当前策略不一致 (版本不一致) -> UNVERIFIED
      3. 已过期 (TTL 24h) -> UNVERIFIED
      4. latency_ms 为 null:
           有明确超时/失败信号 -> FAIL (原始失败证据保留, 延迟仍为 null)
           无失败信号 (未测试) -> UNKNOWN
      5. latency_ms 为数值:
           measurement_verified 为 False (原生语义未校准) -> UNVERIFIED
           <300ms 且 phone_loaded_sha 已验证 -> PASS (合格候选条件之一)
           <300ms 但 phone_loaded_sha 为 UNKNOWN -> UNVERIFIED
               (无法确认手机加载的是同一候选, 不能算合格)
           >=300ms -> ABOVE_TARGET (超过优选目标，但连通成功，必须保留)

    注意: PASS 只是“合格候选条件之一”, 不是生产准入。
    生产下架另由 evidence-validator.py 把关
    (phone UNKNOWN / 钉选保护 / STOP 状态一律拦截)。
    """
    if not isinstance(record, dict):
        return "UNVERIFIED"
    if validate_evidence_schema(record):
        return "UNVERIFIED"
    if record.get("policy_identifier") != POLICY_IDENTIFIER:
        return "UNVERIFIED"
    if is_expired(record):
        return "UNVERIFIED"

    latency = record.get("latency_ms")
    if latency is None:
        if _raw_indicates_failure(record.get("raw_result") or {}):
            return "FAIL"
        return "UNKNOWN"

    if isinstance(latency, bool) or not isinstance(latency, (int, float)):
        return "UNVERIFIED"
    if record.get("measurement_verified") is not True:
        return "UNVERIFIED"
    if latency < LATENCY_THRESHOLD_MS:
        if record.get("phone_loaded_sha") == "UNKNOWN":
            return "UNVERIFIED"
        return "PASS"
    return "ABOVE_TARGET"


def annotate_verdict(record: dict) -> dict:
    """返回 verdict 已更新的证据记录副本 (不修改输入)。"""
    judged = dict(record)
    judged["verdict"] = judge_evidence(record)
    return judged


def check_batch_limits(identifiers, last_batch_at=None, now: datetime = None) -> dict:
    """执行范围约束: 每批最多 10 个 identifier, 每小时最多 1 批。

    参数:
        identifiers: 本批待测 identifier 列表 (节点指纹 / 名称均可)。
        last_batch_at: 上一批次执行时间 (ISO8601 字符串 / datetime / None)。
            None 表示本小时内无上一批。
        now: 参考时间 (默认当前 UTC, 仅供测试注入)。

    返回 {"allowed": bool, "reason": str, "batch_size": int,
          "next_allowed_at": str|None, "max_batch_size": 10,
          "min_interval_seconds": 3600}。
    超限一律不放行, 不自动拆分、不自动延后执行。
    """
    ref = now or datetime.now(timezone.utc)
    if identifiers is None:
        identifiers = []
    try:
        batch = list(identifiers)
    except TypeError:
        return {
            "allowed": False,
            "reason": "identifiers 必须是列表",
            "batch_size": 0,
            "next_allowed_at": None,
            "max_batch_size": MAX_BATCH_SIZE,
            "min_interval_seconds": MIN_BATCH_INTERVAL_SECONDS,
        }
    if len(batch) > MAX_BATCH_SIZE:
        return {
            "allowed": False,
            "reason": "每批最多 {} 个 identifier, 当前 {} 个, 拒绝整批".format(
                MAX_BATCH_SIZE, len(batch)
            ),
            "batch_size": len(batch),
            "next_allowed_at": None,
            "max_batch_size": MAX_BATCH_SIZE,
            "min_interval_seconds": MIN_BATCH_INTERVAL_SECONDS,
        }
    if last_batch_at is None:
        return {
            "allowed": True,
            "reason": "批次合规: {} 个 identifier, 本小时内无上一批".format(len(batch)),
            "batch_size": len(batch),
            "next_allowed_at": None,
            "max_batch_size": MAX_BATCH_SIZE,
            "min_interval_seconds": MIN_BATCH_INTERVAL_SECONDS,
        }
    try:
        if isinstance(last_batch_at, datetime):
            last = last_batch_at
            if last.tzinfo is None:
                last = last.replace(tzinfo=timezone.utc)
        else:
            last = parse_iso8601(last_batch_at)
    except (ValueError, TypeError, AttributeError):
        return {
            "allowed": False,
            "reason": "last_batch_at 无法解析, fail-closed 拒绝本批",
            "batch_size": len(batch),
            "next_allowed_at": None,
            "max_batch_size": MAX_BATCH_SIZE,
            "min_interval_seconds": MIN_BATCH_INTERVAL_SECONDS,
        }
    elapsed = (ref - last).total_seconds()
    if elapsed < MIN_BATCH_INTERVAL_SECONDS:
        from datetime import timedelta

        nxt = last + timedelta(seconds=MIN_BATCH_INTERVAL_SECONDS)
        return {
            "allowed": False,
            "reason": "每小时最多 1 批: 上一批在 {:.0f} 秒前, 须等待".format(elapsed),
            "batch_size": len(batch),
            "next_allowed_at": nxt.isoformat().replace("+00:00", "Z"),
            "max_batch_size": MAX_BATCH_SIZE,
            "min_interval_seconds": MIN_BATCH_INTERVAL_SECONDS,
        }
    return {
        "allowed": True,
        "reason": "批次合规: {} 个 identifier, 距上一批 {:.0f} 秒".format(len(batch), elapsed),
        "batch_size": len(batch),
        "next_allowed_at": None,
        "max_batch_size": MAX_BATCH_SIZE,
        "min_interval_seconds": MIN_BATCH_INTERVAL_SECONDS,
    }


def post_timeout_policy(identifier=None) -> dict:
    """POST 超时处理策略: 不得重发。

    调用方不得自动重试。超时后须人工核查
    (确认手机侧是否已执行、该次测试是否已记入), 再由人工显式决定
    是否以新批次重新发起。函数返回明确的“不得重发”指示。
    """
    return {
        "retry_allowed": False,
        "action": "do_not_resend",
        "instruction": "不得重发: POST 超时后调用方不得自动重试; "
        "须人工核查手机侧执行状态后, 再由人工显式发起新批次。",
        "identifier": identifier,
    }


def build_phone_post_payload(evidence_record: dict, test_url: str = None) -> dict:
    """构造发往手机 Surge 测试接口的请求载荷 (只构造, 不发送)。

    载荷只含指纹与元数据, 不含原始 URI / 密码。
    本沙盒无真机, 任何发送动作都被 post_test_to_phone() 拒绝。
    """
    if not isinstance(evidence_record, dict):
        raise TypeError("evidence_record 必须是 dict")
    return {
        "candidate_id": evidence_record.get("candidate_id"),
        "uri_fingerprint": evidence_record.get("uri_fingerprint"),
        "test_url": test_url or evidence_record.get("test_url"),
        "network_bearer": evidence_record.get("network_bearer"),
        "policy_identifier": evidence_record.get("policy_identifier"),
        "note": "仅载荷构造, 沙盒内无真机, 不实际发送。",
    }


def post_test_to_phone(payload: dict) -> dict:
    """真机 POST 接口 (约束定义, 不实际发送)。

    沙盒内无真机、不得联网调真实手机 / 真实 Surge API,
    本函数永远返回 sent=False, 不执行任何网络 I/O。
    真机执行时由调用方在真机环境按同一载荷格式与批次约束另行实现,
    且 POST 超时适用 post_timeout_policy() (不得重发)。
    """
    return {
        "sent": False,
        "reason": "沙盒内无真机: 未发送。真机 POST 只写接口与约束, 不实际发送。",
        "payload_fingerprint": hashlib.sha256(
            repr(sorted((payload or {}).items())).encode("utf-8")
        ).hexdigest(),
    }


def apply_calibration(record: dict, calibration: dict) -> dict:
    """把口径对照校准结论应用到证据记录副本上 (F3, 不修改输入)。

    measurement_verified 只在 calibration_verdict == "CALIBRATED"
    且 mapping_field 非空时置 True; 其他一切情况 (UNCALIBRATED /
    CONTRADICTED / 缺字段 / 非 dict) 一律 False。
    同时记录 calibration_verdict 与 calibration_mapping_field 供核查。
    verdict 本函数不改写: 调用方须随后用 judge_evidence() 重判。
    校准结论本身由 native-evidence/calibration.py 的 calibrate() 产出。
    """
    if not isinstance(record, dict):
        raise TypeError("record 必须是 dict")
    result = dict(record)
    verdict = calibration.get("verdict") if isinstance(calibration, dict) else None
    mapping = calibration.get("mapping_field") if isinstance(calibration, dict) else None
    result["measurement_verified"] = bool(
        verdict == "CALIBRATED" and isinstance(mapping, str) and mapping
    )
    result["calibration_verdict"] = verdict if isinstance(verdict, str) else "UNCALIBRATED"
    result["calibration_mapping_field"] = mapping if isinstance(mapping, str) else None
    return result


# 证据记录可选附加字段 (F2/F3): 出现时才校验类型与一致性,
# 不出现不强制 (validate_evidence_schema 不要求它们存在)。
OPTIONAL_EVIDENCE_FIELDS = {
    "loaded_proof_level": (str,),
    "loaded_members_verified": (bool,),
    "production_admission": (str,),
    "calibration_verdict": (str,),
    "calibration_mapping_field": (str, type(None)),
}

_LOADED_PROOF_LEVELS = ("BYTE_PROOF", "MEMBERS_VERIFIED", "UNVERIFIED")
_ADMISSIONS = ("GRANTED", "PENDING_REVIEW", "DENIED")
_CALIBRATION_VERDICTS = ("CALIBRATED", "UNCALIBRATED", "CONTRADICTED")


def validate_loaded_proof_fields(record: dict) -> list:
    """校验证据记录上 F2/F3 可选附加字段的类型与一致性, 返回错误列表。

    规则 (fail-closed, 出现即校验, 不出现不强制):
      * loaded_proof_level 只允许 BYTE_PROOF / MEMBERS_VERIFIED / UNVERIFIED。
      * production_admission 只允许 GRANTED / PENDING_REVIEW / DENIED。
      * calibration_verdict 只允许 CALIBRATED / UNCALIBRATED / CONTRADICTED。
      * loaded_members_verified 必须是 bool (不是 bool 即错)。
      * 一致性: BYTE_PROOF 时 phone_loaded_sha 必须是合法 SHA-256
        (弱证明 / 无证明绝不能携带已验证 SHA);
        MEMBERS_VERIFIED / UNVERIFIED 时 phone_loaded_sha 必须是 "UNKNOWN"。
      * 一致性: measurement_verified 为 True 时 calibration_verdict
        必须是 CALIBRATED (语义已校准才可置 True)。
      * 一致性: production_admission 为 GRANTED 时 proof_level 必须是
        BYTE_PROOF; MEMBERS_VERIFIED 时 admission 必须是 PENDING_REVIEW。
    任一错误都说明记录被篡改或误写, 校验器据此判 UNVERIFIED。
    """
    errors = []
    if not isinstance(record, dict):
        return ["证据记录不是 dict"]
    for field, types in OPTIONAL_EVIDENCE_FIELDS.items():
        if field in record and not isinstance(record[field], types):
            errors.append(
                "字段类型错误: {} 应为 {}, 得到 {}".format(
                    field, "/".join(t.__name__ for t in types), type(record[field]).__name__
                )
            )
    level = record.get("loaded_proof_level")
    if level is not None and level not in _LOADED_PROOF_LEVELS:
        errors.append("字段值错误: loaded_proof_level 非法: {!r}".format(level))
    admission = record.get("production_admission")
    if admission is not None and admission not in _ADMISSIONS:
        errors.append("字段值错误: production_admission 非法: {!r}".format(admission))
    calib = record.get("calibration_verdict")
    if calib is not None and calib not in _CALIBRATION_VERDICTS:
        errors.append("字段值错误: calibration_verdict 非法: {!r}".format(calib))
    phone_sha = record.get("phone_loaded_sha")
    if level == "BYTE_PROOF":
        if not (isinstance(phone_sha, str) and _SHA256_RE.match(phone_sha)):
            errors.append(
                "一致性错误: loaded_proof_level 为 BYTE_PROOF 时 "
                'phone_loaded_sha 必须是合法 SHA-256, 不能为 "UNKNOWN"'
            )
    elif level in ("MEMBERS_VERIFIED", "UNVERIFIED"):
        if phone_sha != "UNKNOWN":
            errors.append(
                "一致性错误: loaded_proof_level 为 {} 时 phone_loaded_sha "
                '必须是 "UNKNOWN" (弱证明/无证明不能携带已验证 SHA)'.format(level)
            )
    if record.get("measurement_verified") is True and calib is not None:
        if calib != "CALIBRATED":
            errors.append(
                "一致性错误: measurement_verified 为 True 时 calibration_verdict "
                "必须是 CALIBRATED, 当前为 {}".format(calib)
            )
    if admission == "GRANTED" and level is not None and level != "BYTE_PROOF":
        errors.append(
            "一致性错误: production_admission 为 GRANTED 时 loaded_proof_level "
            "必须是 BYTE_PROOF, 当前为 {}".format(level)
        )
    if level == "MEMBERS_VERIFIED" and admission is not None and admission != "PENDING_REVIEW":
        errors.append(
            "一致性错误: loaded_proof_level 为 MEMBERS_VERIFIED 时 "
            "production_admission 必须是 PENDING_REVIEW, 当前为 {}".format(admission)
        )
    return errors


def apply_loaded_proof(record: dict, proof: dict) -> dict:
    """把已加载证明附加到证据记录副本上 (F2, 不修改输入, 不改写 verdict)。

    proof: phone-loaded-proof.py 的 verify/classify 产出 dict,
    须含 proof_level / production_admission, 可含 loaded_members_verified /
    phone_loaded_sha。
    只有 proof_level 为 BYTE_PROOF 时才把 phone_loaded_sha 写成真实 SHA;
    其他等级下 phone_loaded_sha 保持原值 (一般为 "UNKNOWN")。
    附加后用 validate_loaded_proof_fields() 自检, 不一致直接抛错。
    """
    if not isinstance(record, dict):
        raise TypeError("record 必须是 dict")
    if not isinstance(proof, dict):
        raise TypeError("proof 必须是 dict")
    level = proof.get("proof_level")
    if level not in _LOADED_PROOF_LEVELS:
        raise ValueError("proof_level 非法: {!r}".format(level))
    admission = proof.get("production_admission")
    if admission not in _ADMISSIONS:
        raise ValueError("production_admission 非法: {!r}".format(admission))
    result = dict(record)
    result["loaded_proof_level"] = level
    result["loaded_members_verified"] = bool(proof.get("loaded_members_verified"))
    result["production_admission"] = admission
    if level == "BYTE_PROOF":
        sha = proof.get("phone_loaded_sha")
        if not (isinstance(sha, str) and _SHA256_RE.match(sha)):
            raise ValueError("BYTE_PROOF 必须携带合法 SHA-256 phone_loaded_sha")
        result["phone_loaded_sha"] = sha
    errors = validate_loaded_proof_fields(result)
    if errors:
        raise ValueError("附加已加载证明后一致性校验失败: {}".format("; ".join(errors)))
    return result


if __name__ == "__main__":
    print("native-collector.py: 原生测速采集器, 无独立 CLI。")
    print("关键语义: round-one-total / available / tcp / receive 均不等于")
    print("Smart 组内显示分 (组报第二轮分数); 语义未校准前 measurement_verified")
    print("保持 False, judge_evidence() 判 UNVERIFIED。详见 README.md。")
