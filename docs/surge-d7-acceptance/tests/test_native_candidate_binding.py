# -*- coding: utf-8 -*-
"""B5 候选冻结 / 验证测试 (tests/test_native_candidate_binding.py)。

覆盖: 同一字节同一 ID；字节变化后旧记录失效；指纹不一致拒绝；
成员变化拒绝；candidate_id 确定性。

夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123)，
不得出现真实节点 URI / 密码。
"""

import hashlib
import importlib.util
import unittest
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_NATIVE = _HERE.parent / "native-evidence"


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, str(_NATIVE / filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


freeze = _load("candidate_freeze_under_test", "candidate-freeze.py")

# TEST-NET 夹具订阅: 3 条假节点, 密码 test123, 地址 192.0.2.0/24。
FIXTURE_SUBSCRIPTION = (
    "trojan://test123@192.0.2.10:443#TEST-NODE-01\n"
    "trojan://test123@192.0.2.11:443#TEST-NODE-02\n"
    "trojan://test123@192.0.2.12:443#TEST-NODE-03\n"
).encode("utf-8")


class TestFreezeCandidate(unittest.TestCase):
    def test_record_has_all_required_fields(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        for field in (
            "candidate_id",
            "payload_sha256",
            "member_set_sha256",
            "candidate_created_at",
            "source_revision",
            "policy_fingerprint",
        ):
            self.assertIn(field, record, "冻结记录缺字段: {}".format(field))
        self.assertEqual(record["source_revision"], "test-revision-001")
        self.assertEqual(record["member_count"], 3)

    def test_payload_and_member_sha_are_64_hex(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        self.assertEqual(record["payload_sha256"], hashlib.sha256(FIXTURE_SUBSCRIPTION).hexdigest())
        self.assertRegex(record["payload_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(record["member_set_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(record["policy_fingerprint"], r"^[0-9a-f]{64}$")

    def test_same_bytes_same_candidate_id(self):
        a = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        b = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        self.assertEqual(a["candidate_id"], b["candidate_id"])
        self.assertEqual(a["payload_sha256"], b["payload_sha256"])
        self.assertEqual(a["member_set_sha256"], b["member_set_sha256"])

    def test_candidate_id_deterministic_across_revisions(self):
        # candidate_id 只由订阅字节派生, 不掺入 source_revision / 时间:
        # 同一字节、不同来源版本 -> 同一 ID。
        a = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        b = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-002")
        self.assertEqual(a["candidate_id"], b["candidate_id"])
        self.assertNotEqual(a["source_revision"], b["source_revision"])

    def test_different_bytes_different_candidate_id(self):
        a = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        other = FIXTURE_SUBSCRIPTION + b"trojan://test123@192.0.2.13:443#TEST-NODE-04\n"
        b = freeze.freeze_candidate(other, "test-revision-001")
        self.assertNotEqual(a["candidate_id"], b["candidate_id"])
        self.assertNotEqual(a["payload_sha256"], b["payload_sha256"])
        self.assertNotEqual(a["member_set_sha256"], b["member_set_sha256"])

    def test_verify_valid_for_unchanged_bytes(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        result = freeze.verify_candidate(record, FIXTURE_SUBSCRIPTION)
        self.assertTrue(result["valid"], result["reason"])
        self.assertTrue(all(result["checks"].values()))

    def test_byte_change_invalidates_old_record(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        changed = FIXTURE_SUBSCRIPTION.replace(b"192.0.2.10", b"192.0.2.99")
        result = freeze.verify_candidate(record, changed)
        self.assertFalse(result["valid"])
        self.assertIn("payload_sha256", result["reason"])

    def test_member_removal_invalidates_old_record(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        removed = (
            "trojan://test123@192.0.2.10:443#TEST-NODE-01\n"
            "trojan://test123@192.0.2.11:443#TEST-NODE-02\n"
        ).encode("utf-8")
        result = freeze.verify_candidate(record, removed)
        self.assertFalse(result["valid"])
        # 成员减少时字节已变, payload 校验先行拦截。
        self.assertIn("不一致", result["reason"])

    def test_tampered_member_set_sha_rejected(self):
        # 直接篡改记录的 member_set_sha256 (字节未变): 成员校验必须拦截。
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        record["member_set_sha256"] = "0" * 64
        result = freeze.verify_candidate(record, FIXTURE_SUBSCRIPTION)
        self.assertFalse(result["valid"])
        self.assertIn("member_set_sha256", result["reason"])

    def test_member_addition_invalidates_old_record(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        added = FIXTURE_SUBSCRIPTION + b"trojan://test123@192.0.2.13:443#TEST-NODE-04\n"
        result = freeze.verify_candidate(record, added)
        self.assertFalse(result["valid"])
        # 成员增加时 payload 与 member_set 至少其一不一致。
        self.assertIn("不一致", result["reason"])

    def test_member_reorder_invalidates_old_record(self):
        # 成员集合相同但字节顺序变了: payload 变化 -> 旧记录失效 (字节级冻结)。
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        reordered = (
            "trojan://test123@192.0.2.12:443#TEST-NODE-03\n"
            "trojan://test123@192.0.2.11:443#TEST-NODE-02\n"
            "trojan://test123@192.0.2.10:443#TEST-NODE-01\n"
        ).encode("utf-8")
        result = freeze.verify_candidate(record, reordered)
        self.assertFalse(result["valid"])
        self.assertIn("payload_sha256", result["reason"])

    def test_policy_fingerprint_mismatch_rejected(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        record["policy_fingerprint"] = "0" * 64
        result = freeze.verify_candidate(record, FIXTURE_SUBSCRIPTION)
        self.assertFalse(result["valid"])
        self.assertIn("policy_fingerprint", result["reason"])

    def test_tampered_candidate_id_rejected(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        record["candidate_id"] = "cand-" + "0" * 32
        result = freeze.verify_candidate(record, FIXTURE_SUBSCRIPTION)
        self.assertFalse(result["valid"])
        self.assertIn("candidate_id", result["reason"])

    def test_missing_field_rejected(self):
        record = freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "test-revision-001")
        del record["member_set_sha256"]
        result = freeze.verify_candidate(record, FIXTURE_SUBSCRIPTION)
        self.assertFalse(result["valid"])
        self.assertIn("member_set_sha256", result["reason"])

    def test_non_dict_record_rejected(self):
        result = freeze.verify_candidate("not-a-record", FIXTURE_SUBSCRIPTION)
        self.assertFalse(result["valid"])

    def test_freeze_rejects_non_bytes(self):
        with self.assertRaises(TypeError):
            freeze.freeze_candidate("trojan://test123@192.0.2.10:443", "test-revision-001")

    def test_freeze_rejects_empty_source_revision(self):
        with self.assertRaises(ValueError):
            freeze.freeze_candidate(FIXTURE_SUBSCRIPTION, "  ")


if __name__ == "__main__":
    unittest.main()
