# -*- coding: utf-8 -*-
"""B5 证据校验测试 (tests/test_native_evidence_validator.py)。

覆盖: schema 缺字段拒绝；类型错误拒绝；候选绑定不一致 UNVERIFIED；
过期 UNVERIFIED；phone_loaded_sha UNKNOWN 禁止下架；钉选失败不删除；
判定 <300 / >=300 / 超时 / 未测试；批次限制 10 个 / 小时 1 批；
影子审计十项计数正确，0/30 时 removal_candidates=0 且 NO_SAFE_REMOVAL。

夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123)，
不得出现真实节点 URI / 密码。
"""

import copy
import hashlib
import importlib.util
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_NATIVE = _HERE.parent / "native-evidence"


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, str(_NATIVE / filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


freeze = _load("candidate_freeze_under_test", "candidate-freeze.py")
collector = _load("native_collector_under_test", "native-collector.py")
validator = _load("evidence_validator_under_test", "evidence-validator.py")

# TEST-NET 夹具: 30 行 (21 钉选 + 9 轮换), 密码 test123, 地址 192.0.2.0/24。
PINNED_NAMES = ["TEST-PINNED-{:02d}".format(i) for i in range(1, 22)]
ROTATION_NAMES = ["TEST-ROTATION-{:02d}".format(j) for j in range(1, 10)]
ALL_NAMES = PINNED_NAMES + ROTATION_NAMES


def _fixture_subscription_bytes():
    lines = []
    for i in range(1, 22):
        lines.append("trojan://test123@192.0.2.{}:443#TEST-PINNED-{:02d}".format(i, i))
    for j in range(1, 10):
        lines.append("trojan://test123@192.0.2.{}:443#TEST-ROTATION-{:02d}".format(100 + j, j))
    return ("\n".join(lines) + "\n").encode("utf-8")


def _phone_sha():
    """已验证的手机加载 SHA (测试用假值, 非真实订阅)。"""
    return hashlib.sha256(b"test-phone-loaded-subscription").hexdigest()


def _uri_fp(node_name, octet):
    return collector.fingerprint_uri(
        "trojan://test123@192.0.2.{}:443#{}".format(octet, node_name)
    )


def _now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _hours_ago_iso(hours):
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat().replace(
        "+00:00", "Z"
    )


class ValidatorTestBase(unittest.TestCase):
    def setUp(self):
        self.candidate = freeze.freeze_candidate(
            _fixture_subscription_bytes(), "test-revision-001"
        )

    def make_evidence(self, node_name, octet, latency=None, phone_sha=None,
                      measurement_verified=True, tested_at=None, raw_extra=None,
                      bearer="cellular"):
        """构造一条证据记录 (默认: 手机已验证 + 语义已校准, 便于测判定本身)。"""
        raw = {"node_name": node_name}
        if latency is not None:
            raw["latency_ms"] = latency
        if raw_extra:
            raw.update(raw_extra)
        return collector.build_evidence_chain(
            candidate_record=self.candidate,
            phone_loaded_sha=_phone_sha() if phone_sha is None else phone_sha,
            uri_fingerprint=_uri_fp(node_name, octet),
            policy_identifier=collector.POLICY_IDENTIFIER,
            raw_result=raw,
            test_url="https://example.invalid/generate_204",
            network_bearer=bearer,
            tested_at=tested_at or _now_iso(),
            measurement_verified=measurement_verified,
        )


class TestEvidenceSchemaAndBinding(ValidatorTestBase):
    def test_valid_evidence_passes(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertTrue(result["valid"], result["reasons"])
        self.assertEqual(result["verdict"], "PASS")
        self.assertFalse(result["eligible_for_removal"])  # PASS 不是失败证据, 不可下架

    def test_missing_field_rejected(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        del record["payload_sha"]
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")
        self.assertFalse(result["eligible_for_removal"])

    def test_latency_type_error_rejected(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        record["latency_ms"] = "120"  # 字符串不是合法延迟
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")

    def test_raw_result_type_error_rejected(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        record["raw_result"] = ["not-a-dict"]
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")

    def test_measurement_verified_type_error_rejected(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        record["measurement_verified"] = "yes"
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")

    def test_candidate_binding_mismatch_unverified(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        record["payload_sha"] = "0" * 64
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")
        self.assertTrue(any("绑定不一致" in r for r in result["reasons"]))

    def test_member_set_binding_mismatch_unverified(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        record["member_set_sha"] = "0" * 64
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")

    def test_expired_evidence_unverified(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=120, tested_at=_hours_ago_iso(25)
        )
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")
        self.assertTrue(any("过期" in r for r in result["reasons"]))

    def test_fresh_evidence_not_expired(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=120, tested_at=_hours_ago_iso(23)
        )
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertTrue(result["valid"])
        self.assertEqual(result["verdict"], "PASS")

    def test_policy_version_mismatch_unverified(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        record["policy_identifier"] = "native-evidence-policy-v999"
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertEqual(result["verdict"], "UNVERIFIED")


class TestJudgeEvidence(ValidatorTestBase):
    def test_judge_lt_300_pass(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120)
        self.assertEqual(collector.judge_evidence(record), "PASS")

    def test_judge_lt_300_boundary_299_pass(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=299)
        self.assertEqual(collector.judge_evidence(record), "PASS")

    def test_judge_exactly_300_not_pass(self):
        # 严格 <300: 300ms 整不算合格。
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=300)
        self.assertEqual(collector.judge_evidence(record), "FAIL_LATENCY")

    def test_judge_gte_300_fail_latency(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=500)
        self.assertEqual(collector.judge_evidence(record), "FAIL_LATENCY")

    def test_judge_timeout_fail_keeps_null_latency(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=None,
            raw_extra={"status": "timeout"},
        )
        self.assertIsNone(record["latency_ms"])
        self.assertEqual(collector.judge_evidence(record), "FAIL")
        judged = collector.annotate_verdict(record)
        self.assertIsNone(judged["latency_ms"])
        self.assertEqual(judged["raw_result"]["status"], "timeout")

    def test_judge_untested_unknown(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=None)
        self.assertEqual(collector.judge_evidence(record), "UNKNOWN")

    def test_judge_null_latency_never_pass(self):
        for raw_extra in ({"status": "timeout"}, {}, {"status": "ok"}):
            record = self.make_evidence(
                "TEST-ROTATION-01", 101, latency=None, raw_extra=raw_extra
            )
            self.assertNotEqual(collector.judge_evidence(record), "PASS")

    def test_judge_uncalibrated_semantics_unverified(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=120, measurement_verified=False
        )
        self.assertEqual(collector.judge_evidence(record), "UNVERIFIED")

    def test_judge_phone_unknown_lt_300_unverified(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=120, phone_sha="UNKNOWN"
        )
        self.assertEqual(record["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(collector.judge_evidence(record), "UNVERIFIED")

    def test_judge_expired_unverified(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=120, tested_at=_hours_ago_iso(25)
        )
        self.assertEqual(collector.judge_evidence(record), "UNVERIFIED")

    def test_build_preserves_raw_result_types(self):
        # round-one-total / available 等原始字段原样保留, 不被改写为延迟。
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=131,
            raw_extra={"round_one_total_ms": 1315, "available_ms": 387, "tcp_ms": 210},
        )
        self.assertEqual(record["latency_ms"], 131)
        self.assertEqual(record["raw_result"]["round_one_total_ms"], 1315)
        self.assertEqual(record["raw_result"]["available_ms"], 387)
        self.assertIsInstance(record["raw_result"]["available_ms"], int)

    def test_build_without_explicit_latency_is_null(self):
        # raw_result 里没有 latency_ms -> null, 不从其他字段推导。
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=None,
            raw_extra={"round_one_total_ms": 1315, "available_ms": 387},
        )
        self.assertIsNone(record["latency_ms"])

    def test_invalid_bearer_rejected(self):
        with self.assertRaises(ValueError):
            self.make_evidence("TEST-ROTATION-01", 101, latency=120, bearer="satellite")

    def test_unknown_bearer_when_undetermined(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=120, bearer=None)
        self.assertEqual(record["network_bearer"], "UNKNOWN")


class TestRemovalEligibility(ValidatorTestBase):
    def test_phone_unknown_failure_cannot_remove(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=500, phone_sha="UNKNOWN"
        )
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertEqual(result["verdict"], "FAIL_LATENCY")
        self.assertFalse(result["eligible_for_removal"])

    def test_verified_failure_can_count_for_removal(self):
        record = self.make_evidence("TEST-ROTATION-01", 101, latency=500)
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertTrue(result["eligible_for_removal"])

    def test_pinned_failure_never_removable(self):
        record = self.make_evidence("TEST-PINNED-01", 1, latency=900)
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertTrue(result["is_pinned"])
        self.assertEqual(result["verdict"], "FAIL_LATENCY")
        self.assertFalse(result["eligible_for_removal"])

    def test_verified_timeout_counts_as_credible_failure(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=None, raw_extra={"status": "timeout"}
        )
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertEqual(result["verdict"], "FAIL")
        self.assertTrue(result["eligible_for_removal"])

    def test_uncalibrated_failure_cannot_remove(self):
        record = self.make_evidence(
            "TEST-ROTATION-01", 101, latency=500, measurement_verified=False
        )
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["eligible_for_removal"])


class TestBatchLimits(unittest.TestCase):
    def test_ten_identifiers_allowed(self):
        ids = ["id-{:02d}".format(i) for i in range(10)]
        result = collector.check_batch_limits(ids, None)
        self.assertTrue(result["allowed"], result["reason"])

    def test_eleven_identifiers_rejected(self):
        ids = ["id-{:02d}".format(i) for i in range(11)]
        result = collector.check_batch_limits(ids, None)
        self.assertFalse(result["allowed"])
        self.assertIn("10", result["reason"])

    def test_second_batch_within_hour_rejected(self):
        ids = ["id-01"]
        last = (datetime.now(timezone.utc) - timedelta(minutes=30)).isoformat().replace(
            "+00:00", "Z"
        )
        result = collector.check_batch_limits(ids, last)
        self.assertFalse(result["allowed"])
        self.assertIsNotNone(result["next_allowed_at"])

    def test_batch_after_hour_allowed(self):
        ids = ["id-01"]
        last = (datetime.now(timezone.utc) - timedelta(minutes=61)).isoformat().replace(
            "+00:00", "Z"
        )
        result = collector.check_batch_limits(ids, last)
        self.assertTrue(result["allowed"], result["reason"])

    def test_unparseable_last_batch_rejected(self):
        result = collector.check_batch_limits(["id-01"], "not-a-time")
        self.assertFalse(result["allowed"])

    def test_post_timeout_must_not_resend(self):
        policy = collector.post_timeout_policy("id-01")
        self.assertFalse(policy["retry_allowed"])
        self.assertIn("不得重发", policy["instruction"])
        self.assertEqual(policy["action"], "do_not_resend")

    def test_phone_post_never_sends_in_sandbox(self):
        result = collector.post_test_to_phone({"candidate_id": "cand-test"})
        self.assertFalse(result["sent"])


class TestShadowAudit(ValidatorTestBase):
    def _mixed_evidences(self):
        return [
            self.make_evidence("TEST-ROTATION-01", 101, latency=120),  # PASS
            self.make_evidence("TEST-ROTATION-02", 102, latency=500),  # 可信失败
            self.make_evidence(  # 明确失败: 超时, 但 phone 未验证 -> 不可下架
                "TEST-ROTATION-03", 103, latency=None, phone_sha="UNKNOWN",
                measurement_verified=False, raw_extra={"status": "timeout"}
            ),
            self.make_evidence("TEST-ROTATION-04", 104, latency=None),  # 未测试 UNKNOWN
            self.make_evidence("TEST-PINNED-01", 1, latency=900),  # 钉选失败, 不可删
        ]

    def test_missing_frozen_candidate_never_eligible(self):
        # Fail-closed (GPT review P0): 冻结候选缺失时, 即使证据本身是
        # 可信失败 (TEST-ROTATION-02, latency 500), 也不可计入删除资格。
        evidences = self._mixed_evidences()
        failing = [e for e in evidences
                   if e.get("raw_result", {}).get("node_name") == "TEST-ROTATION-02"][0]
        result = validator.validate_evidence(
            failing, None, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")
        self.assertFalse(result["eligible_for_removal"])
        self.assertFalse(result["checks"]["candidate_binding_ok"])
        audit = validator.audit_shadow(
            ALL_NAMES, evidences, PINNED_NAMES, "RUNNING",
            output_dir=None, candidate_record=None,
        )
        self.assertEqual(audit["removal_candidates"], 0)
        self.assertEqual(audit["decision"], "NO_SAFE_REMOVAL")

    def test_ten_counts_correct(self):
        audit = validator.audit_shadow(
            ALL_NAMES, self._mixed_evidences(), PINNED_NAMES, "RUNNING",
            output_dir=None, candidate_record=self.candidate,
        )
        self.assertEqual(audit["candidate_count"], 30)
        self.assertEqual(audit["evidence_coverage"], 5)
        self.assertEqual(audit["valid_test_count"], 3)
        self.assertEqual(audit["lt_300_count"], 1)
        self.assertEqual(audit["gte_300_count"], 2)
        self.assertEqual(audit["failed_count"], 1)
        self.assertEqual(audit["unknown_count"], 1)
        self.assertEqual(audit["safe_removal_eligible_count"], 1)
        self.assertEqual(audit["removal_candidates"], 1)
        self.assertEqual(audit["removal_candidate_names"], ["TEST-ROTATION-02"])
        self.assertEqual(audit["pinned_integrity"], "21/21")
        self.assertTrue(audit["pinned_intact"])
        self.assertEqual(audit["stop_status"], "RUNNING")
        self.assertEqual(audit["decision"], "REMOVAL_CANDIDATES:1")
        self.assertEqual(len(audit["summary_10"]), 10)

    def test_zero_of_30_no_safe_removal(self):
        audit = validator.audit_shadow(
            ALL_NAMES, [], PINNED_NAMES, "RUNNING",
            output_dir=None, candidate_record=self.candidate,
        )
        self.assertEqual(audit["candidate_count"], 30)
        self.assertEqual(audit["evidence_coverage"], 0)
        self.assertEqual(audit["valid_test_count"], 0)
        self.assertEqual(audit["lt_300_count"], 0)
        self.assertEqual(audit["gte_300_count"], 0)
        self.assertEqual(audit["failed_count"], 0)
        self.assertEqual(audit["unknown_count"], 0)
        self.assertEqual(audit["removal_candidates"], 0)
        self.assertEqual(audit["decision"], "NO_SAFE_REMOVAL")
        self.assertEqual(audit["pinned_integrity"], "21/21")
        self.assertTrue(audit["pinned_intact"])

    def test_stop_forces_no_safe_removal(self):
        audit = validator.audit_shadow(
            ALL_NAMES, self._mixed_evidences(), PINNED_NAMES, "STOP",
            output_dir=None, candidate_record=self.candidate,
        )
        self.assertEqual(audit["removal_candidates"], 0)
        self.assertEqual(audit["decision"], "NO_SAFE_REMOVAL")

    def test_audit_refuses_production_path(self):
        with self.assertRaises(ValueError):
            validator.audit_shadow(
                ALL_NAMES, [], PINNED_NAMES, "RUNNING",
                output_dir="/opt/surge-bridge/modules",
            )

    def test_audit_writes_only_isolated_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "isolated-evidence"
            audit = validator.audit_shadow(
                ALL_NAMES, [], PINNED_NAMES, "RUNNING",
                output_dir=str(out), candidate_record=self.candidate,
            )
            self.assertTrue((out / "shadow-audit.json").exists())
            self.assertEqual(audit["decision"], "NO_SAFE_REMOVAL")


class TestRunExample(ValidatorTestBase):
    def test_example_produces_verifiable_chain_with_unknown_phone(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = validator.run_example(output_dir=tmp)
            chain_path = Path(result["chain_file"])
            self.assertTrue(chain_path.exists())
            # 诚实结论: 沙盒内无真机, phone_loaded_sha 必须为 UNKNOWN。
            self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")
            self.assertEqual(result["evidence_verdict"], "UNVERIFIED")
            self.assertFalse(result["validation"]["eligible_for_removal"])
            # 示例审计: 30 候选 + 1 条证据, 无安全删除资格。
            self.assertEqual(result["example_audit"]["candidate_count"], 30)
            self.assertEqual(result["example_audit"]["evidence_coverage"], 1)
            self.assertEqual(result["example_audit"]["removal_candidates"], 0)
            self.assertEqual(result["example_audit"]["decision"], "NO_SAFE_REMOVAL")
            # 生产当前态复核: 覆盖 0/30, removal 0, NO_SAFE_REMOVAL。
            prod = result["production_state_audit"]
            self.assertEqual(prod["evidence_coverage"], 0)
            self.assertEqual(prod["removal_candidates"], 0)
            self.assertEqual(prod["decision"], "NO_SAFE_REMOVAL")
            self.assertEqual(prod["pinned_integrity"], "21/21")


if __name__ == "__main__":
    unittest.main()
