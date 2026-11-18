# -*- coding: utf-8 -*-
"""
B1. 候选冻结模块 (candidate-freeze.py)

为每轮原生测速生成不可变候选 (immutable candidate)。

数据链位置:
    VPS 生成的订阅字节
      -> freeze_candidate() 冻结为候选记录
      -> 手机 Surge 加载该候选 (phone_loaded_sha 独立验证, 见 native-collector.py)
      -> 证据校验器按冻结记录校验绑定 (见 evidence-validator.py)

核心规则 (fail-closed):
  * candidate_id 是确定性的: 同一订阅字节 -> 同一 candidate_id。
  * 订阅字节变化 / policy 指纹不一致 / 成员集合变化时,
    旧冻结记录立即失效, 旧测试结果失去生产准入资格。
  * 本模块只用 Python 3 标准库, 不联网, 不读生产路径, 不写生产路径。

测试夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123),
绝不写真实节点 URI / 密码 / token / 真实出口 IP。
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone

# 判定策略标识。策略文本本身发生变化时必须升级该标识,
# 旧候选随之失效 (policy_fingerprint 校验会拒绝)。
POLICY_IDENTIFIER = "native-evidence-policy-v1"

# 策略指纹 = 策略标识的 SHA-256。冻结记录携带它,
# 校验时与当前策略指纹比对, 不一致即拒绝。
POLICY_FINGERPRINT = hashlib.sha256(POLICY_IDENTIFIER.encode("utf-8")).hexdigest()

CANDIDATE_ID_PREFIX = "cand-"

# 冻结记录必须包含的字段 (任务 B1 要求)。
REQUIRED_FIELDS = (
    "candidate_id",
    "payload_sha256",
    "member_set_sha256",
    "candidate_created_at",
    "source_revision",
    "policy_fingerprint",
)


def compute_payload_sha256(subscription_bytes: bytes) -> str:
    """订阅原始字节的 SHA-256 (hex)。字节级, 顺序/空白变化即变化。"""
    if not isinstance(subscription_bytes, (bytes, bytearray)):
        raise TypeError("subscription_bytes 必须是 bytes")
    return hashlib.sha256(bytes(subscription_bytes)).hexdigest()


def member_lines(subscription_bytes: bytes) -> list:
    """从订阅字节解析成员行集合。

    每行去首尾空白、去空行、去重、排序。
    排序后集合与行顺序无关, 只反映“成员是谁”;
    而 payload_sha256 反映“字节原样是什么”。
    两者配合: 字节变化由 payload 校验捕获, 成员增减由 member_set 校验捕获。
    """
    if not isinstance(subscription_bytes, (bytes, bytearray)):
        raise TypeError("subscription_bytes 必须是 bytes")
    text = bytes(subscription_bytes).decode("utf-8", errors="replace")
    lines = {line.strip() for line in text.splitlines()}
    lines.discard("")
    return sorted(lines)


def compute_member_set_sha256(subscription_bytes: bytes) -> str:
    """成员集合 SHA-256: 排序去重后的成员行以 "\\n" 连接后取 SHA-256。"""
    joined = "\n".join(member_lines(subscription_bytes))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def compute_candidate_id(payload_sha256: str, member_set_sha256: str) -> str:
    """确定性 candidate_id: 仅由 payload 指纹 + 成员集合指纹派生。

    同一订阅字节 -> 同一 candidate_id; 字节不同 -> ID 不同。
    不掺入时间戳 / 随机数 / source_revision, 否则同一字节会得到不同 ID。
    """
    digest = hashlib.sha256(
        "{}|{}".format(payload_sha256, member_set_sha256).encode("utf-8")
    ).hexdigest()
    return CANDIDATE_ID_PREFIX + digest[:32]


def freeze_candidate(subscription_bytes: bytes, source_revision: str) -> dict:
    """冻结一轮候选, 返回冻结记录 dict (可 JSON 序列化)。

    参数:
        subscription_bytes: 本轮订阅的原始字节 (VPS 已生成的订阅原样)。
        source_revision: 订阅来源版本标识, 如发布器提交 SHA / 发布时间戳。
            仅作溯源元数据, 不参与 candidate_id 生成。

    返回字段:
        candidate_id / payload_sha256 / member_set_sha256 /
        candidate_created_at (UTC ISO8601) / source_revision /
        policy_fingerprint, 另附 policy_identifier 与 member_count 供核对。
    """
    if not isinstance(subscription_bytes, (bytes, bytearray)):
        raise TypeError("subscription_bytes 必须是 bytes")
    if not isinstance(source_revision, str) or not source_revision.strip():
        raise ValueError("source_revision 必须是非空字符串")

    payload_sha = compute_payload_sha256(subscription_bytes)
    member_sha = compute_member_set_sha256(subscription_bytes)
    created_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    return {
        "candidate_id": compute_candidate_id(payload_sha, member_sha),
        "payload_sha256": payload_sha,
        "member_set_sha256": member_sha,
        "candidate_created_at": created_at,
        "source_revision": source_revision,
        "policy_fingerprint": POLICY_FINGERPRINT,
        "policy_identifier": POLICY_IDENTIFIER,
        "member_count": len(member_lines(subscription_bytes)),
    }


def freeze_candidate_json(subscription_bytes: bytes, source_revision: str) -> str:
    """freeze_candidate() 的 JSON 字符串形式, 键排序、便于比对与存档。"""
    record = freeze_candidate(subscription_bytes, source_revision)
    return json.dumps(record, ensure_ascii=False, sort_keys=True, indent=2)


def verify_candidate(record: dict, subscription_bytes: bytes) -> dict:
    """校验冻结记录与当前订阅字节是否仍绑定一致。

    返回 {"valid": bool, "reason": str, "checks": {...}}。
    任一检查失败即 valid=False, 旧记录失效,
    基于它的测试结果立即失去生产准入资格 (由 validator 强制执行)。

    校验顺序:
      1. 记录结构完整
      2. policy_fingerprint 与当前策略一致
      3. payload_sha256 与当前字节一致 (字节变化)
      4. member_set_sha256 与当前成员集合一致 (成员变化)
      5. candidate_id 与重算值一致 (确定性)
    """
    checks = {
        "record_complete": False,
        "policy_fingerprint_match": False,
        "payload_match": False,
        "member_set_match": False,
        "candidate_id_match": False,
    }

    def _fail(reason: str) -> dict:
        return {"valid": False, "reason": reason, "checks": checks}

    if not isinstance(record, dict):
        return _fail("冻结记录不是 dict, 无法校验")
    missing = [f for f in REQUIRED_FIELDS if f not in record]
    if missing:
        return _fail("冻结记录缺字段: {}".format(", ".join(missing)))
    checks["record_complete"] = True

    if record.get("policy_fingerprint") != POLICY_FINGERPRINT:
        return _fail(
            "policy_fingerprint 不一致: 记录为 {!r}, 当前策略为 {!r}, "
            "策略已变更, 旧候选失效".format(
                record.get("policy_fingerprint"), POLICY_FINGERPRINT
            )
        )
    checks["policy_fingerprint_match"] = True

    if not isinstance(subscription_bytes, (bytes, bytearray)):
        return _fail("subscription_bytes 必须是 bytes")

    payload_sha = compute_payload_sha256(subscription_bytes)
    if record.get("payload_sha256") != payload_sha:
        return _fail(
            "订阅字节已变化: payload_sha256 不一致 "
            "(记录 {!r} != 当前 {!r}), 旧候选失效".format(
                record.get("payload_sha256"), payload_sha
            )
        )
    checks["payload_match"] = True

    member_sha = compute_member_set_sha256(subscription_bytes)
    if record.get("member_set_sha256") != member_sha:
        return _fail(
            "成员集合已变化: member_set_sha256 不一致 "
            "(记录 {!r} != 当前 {!r}), 旧候选失效".format(
                record.get("member_set_sha256"), member_sha
            )
        )
    checks["member_set_match"] = True

    expected_id = compute_candidate_id(payload_sha, member_sha)
    if record.get("candidate_id") != expected_id:
        return _fail(
            "candidate_id 不一致: 记录 {!r} != 重算 {!r}, 旧候选失效".format(
                record.get("candidate_id"), expected_id
            )
        )
    checks["candidate_id_match"] = True

    return {
        "valid": True,
        "reason": "候选绑定有效: 字节、成员集合、策略指纹、candidate_id 全部一致",
        "checks": checks,
    }


if __name__ == "__main__":
    import sys

    print("candidate-freeze.py: 候选冻结模块, 无独立 CLI。")
    print("用法: 在 Python 中调用 freeze_candidate(subscription_bytes, source_revision)")
    print("      与 verify_candidate(record, subscription_bytes)。")
    print("当前策略: {} (fingerprint {})".format(POLICY_IDENTIFIER, POLICY_FINGERPRINT))
    sys.exit(0)
