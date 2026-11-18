# -*- coding: utf-8 -*-
"""F2 手机已加载订阅证明测试 (tests/test_phone_loaded_proof.py)。

覆盖:
  * 字节级证明: 一致 -> BYTE_PROOF 并填入真实 SHA; 不一致 / UNKNOWN /
    非法 SHA -> UNVERIFIED 且 phone_loaded_sha 保持 UNKNOWN。
  * 弱证明 (成员集合): 逐名完全一致 -> MEMBERS_VERIFIED,
    phone_loaded_sha 仍为 UNKNOWN, production_admission 恒为
    PENDING_REVIEW; 缺失 / 多余 / 空集合 / 冻结无成员名 -> UNVERIFIED。
  * classify_loaded_proof: 真实 /v1/policy_groups 形态 (规则 -> 条目列表)
    回放; 仅有 profiles/current + external_resources 时判 UNVERIFIED
    且 insufficient_sources 逐项说明; 手机端上报 SHA 匹配时为 BYTE_PROOF。
  * attach_loaded_proof / collector.apply_loaded_proof:
    弱证明绝不写 SHA, BYTE_PROOF 才写; 校验器对弱证明证据仍判
    eligible_for_removal=False (phone 未验证), 字节证明 + 失败 +
    语义已校准时才可下架。
  * mock 回放: 本地 HTTP 服务器按真实响应形态返回
    /v1/policy_groups, 抓回后做成员集合比对 (不连真机)。

夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123),
不得出现真实节点 URI / 密码。
"""

import hashlib
import importlib.util
import json
import threading
import unittest
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_NATIVE = _HERE.parent / "native-evidence"


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, str(_NATIVE / filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


freeze = _load("candidate_freeze_f2", "candidate-freeze.py")
collector = _load("native_collector_f2", "native-collector.py")
validator = _load("evidence_validator_f2", "evidence-validator.py")
proof = _load("phone_loaded_proof_f2", "phone-loaded-proof.py")

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
    return hashlib.sha256(b"test-phone-loaded-subscription").hexdigest()


def _now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _candidate_with_names():
    """冻结候选 + 补成员名集合 (member_names), 供弱证明比对。"""
    candidate = freeze.freeze_candidate(_fixture_subscription_bytes(), "test-revision-001")
    candidate["member_names"] = list(ALL_NAMES)
    candidate["member_lines"] = [
        line for line in _fixture_subscription_bytes().decode("utf-8").splitlines() if line
    ]
    return candidate


def _real_shape_policy_groups(member_names, group_name="TEST-POOL"):
    """真实 /v1/policy_groups 响应形态的夹具: 规则 -> 条目列表。

    条目字段与真机一致: name / isGroup / enabled / typeDescription /
    lineHash (lineHash 用假值)。
    """
    entries = [
        {
            "name": name,
            "isGroup": False,
            "enabled": True,
            "typeDescription": "Trojan",
            "lineHash": "POLICY::{}".format(hashlib.sha256(name.encode()).hexdigest()[:32]),
        }
        for name in member_names
    ]
    return {
        group_name: entries,
        "OTHER-RULE": [
            {
                "name": "TEST-GROUP",
                "isGroup": True,
                "enabled": True,
                "typeDescription": "Smart 策略组",
                "lineHash": "POLICY::00000000000000000000000000000000",
            }
        ],
    }


class TestByteLevelProof(unittest.TestCase):
    def setUp(self):
        self.candidate = _candidate_with_names()

    def test_match_is_byte_proof(self):
        result = proof.verify_byte_level(
            self.candidate["payload_sha256"], self.candidate
        )
        self.assertEqual(result["proof_level"], "BYTE_PROOF")
        self.assertEqual(result["phone_loaded_sha"], self.candidate["payload_sha256"])
        self.assertEqual(result["production_admission"], "GRANTED")
        self.assertTrue(result["match"])

    def test_mismatch_is_unverified(self):
        other = hashlib.sha256(b"some-other-subscription").hexdigest()
        result = proof.verify_byte_level(other, self.candidate)
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(result["production_admission"], "DENIED")
        self.assertFalse(result["match"])

    def test_unknown_input_is_unverified(self):
        for value in (None, "UNKNOWN", ""):
            result = proof.verify_byte_level(value, self.candidate)
            self.assertEqual(result["proof_level"], "UNVERIFIED")
            self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")

    def test_illegal_sha_is_unverified(self):
        result = proof.verify_byte_level("not-a-sha", self.candidate)
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")

    def test_frozen_without_payload_sha(self):
        result = proof.verify_byte_level(_phone_sha(), {})
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["production_admission"], "DENIED")


class TestMembersWeakProof(unittest.TestCase):
    def setUp(self):
        self.candidate = _candidate_with_names()

    def test_exact_set_is_members_verified(self):
        result = proof.verify_loaded_members(list(ALL_NAMES), self.candidate)
        self.assertEqual(result["proof_level"], "MEMBERS_VERIFIED")
        self.assertTrue(result["loaded_members_verified"])
        # 弱证明永不填入真实 SHA, 准入恒为待审查。
        self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(result["production_admission"], "PENDING_REVIEW")
        self.assertEqual(result["matched_count"], 30)
        self.assertEqual(result["expected_count"], 30)
        self.assertEqual(result["missing"], [])
        self.assertEqual(result["extra"], [])

    def test_order_does_not_matter(self):
        shuffled = list(reversed(ALL_NAMES))
        result = proof.verify_loaded_members(shuffled, self.candidate)
        self.assertEqual(result["proof_level"], "MEMBERS_VERIFIED")

    def test_missing_one_member_fails(self):
        result = proof.verify_loaded_members(ALL_NAMES[:-1], self.candidate)
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertFalse(result["loaded_members_verified"])
        self.assertEqual(result["production_admission"], "DENIED")
        self.assertEqual(result["missing"], ["TEST-ROTATION-09"])

    def test_extra_member_fails(self):
        result = proof.verify_loaded_members(
            list(ALL_NAMES) + ["TEST-INTRUDER-01"], self.candidate
        )
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["extra"], ["TEST-INTRUDER-01"])

    def test_empty_phone_members_fails(self):
        result = proof.verify_loaded_members([], self.candidate)
        self.assertEqual(result["proof_level"], "UNVERIFIED")

    def test_frozen_without_member_names(self):
        candidate = freeze.freeze_candidate(
            _fixture_subscription_bytes(), "test-revision-001"
        )
        result = proof.verify_loaded_members(list(ALL_NAMES), candidate)
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["production_admission"], "DENIED")

    def test_member_set_sha_deterministic(self):
        a = proof.member_set_sha_of_names(ALL_NAMES)
        b = proof.member_set_sha_of_names(list(reversed(ALL_NAMES)))
        self.assertEqual(a, b)
        self.assertEqual(len(a), 64)


class TestClassifyLoadedProof(unittest.TestCase):
    def setUp(self):
        self.candidate = _candidate_with_names()

    def test_real_shape_groups_replay_members_verified(self):
        api = {
            "/v1/policy_groups": _real_shape_policy_groups(ALL_NAMES, "TEST-POOL"),
            "/v1/policies": {"policy-groups": ["TEST-POOL"], "proxies": []},
        }
        result = proof.classify_loaded_proof(api, self.candidate, group_name="TEST-POOL")
        self.assertEqual(result["proof_level"], "MEMBERS_VERIFIED")
        self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(result["production_admission"], "PENDING_REVIEW")
        self.assertTrue(result["loaded_members_verified"])

    def test_group_name_scoping_matters(self):
        # 不指定组名时取全部规则条目并集: OTHER-RULE 的组条目 isGroup=true
        # 不计入, 仍为成员集合一致, 但 reasons 须注明口径更宽。
        api = {"/v1/policy_groups": _real_shape_policy_groups(ALL_NAMES, "TEST-POOL")}
        result = proof.classify_loaded_proof(api, self.candidate)
        self.assertEqual(result["proof_level"], "MEMBERS_VERIFIED")
        self.assertTrue(any("未指定策略组名" in r for r in result["reasons"]))

    def test_profiles_and_resources_only_is_unverified(self):
        api = {
            "/v1/profiles/current": {"profile": "test", "name": "TEST"},
            "/v1/external_resources": {
                "defines": [{"ready": True, "type": "policy-group"}]
            },
        }
        result = proof.classify_loaded_proof(api, self.candidate, group_name="TEST-POOL")
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(result["production_admission"], "DENIED")
        self.assertFalse(result["loaded_members_verified"])
        # insufficient_sources 必须逐项说明为什么不算证明。
        joined = " ".join(result["insufficient_sources"])
        self.assertIn("/v1/profiles/current", joined)
        self.assertIn("/v1/external_resources", joined)

    def test_reported_sha_match_is_byte_proof(self):
        api = {
            "/v1/policy_groups": _real_shape_policy_groups(ALL_NAMES, "TEST-POOL"),
            "phone_loaded_sha": self.candidate["payload_sha256"],
        }
        result = proof.classify_loaded_proof(api, self.candidate, group_name="TEST-POOL")
        self.assertEqual(result["proof_level"], "BYTE_PROOF")
        self.assertEqual(result["phone_loaded_sha"], self.candidate["payload_sha256"])
        self.assertEqual(result["production_admission"], "GRANTED")

    def test_empty_responses_is_unverified(self):
        result = proof.classify_loaded_proof({}, self.candidate, group_name="TEST-POOL")
        self.assertEqual(result["proof_level"], "UNVERIFIED")
        self.assertEqual(result["production_admission"], "DENIED")


class TestAttachAndValidatorIntegration(unittest.TestCase):
    def setUp(self):
        self.candidate = _candidate_with_names()

    def _evidence(self, latency, phone_sha="UNKNOWN", measurement_verified=False):
        raw = {"node_name": "TEST-ROTATION-01", "latency_ms": latency}
        return collector.build_evidence_chain(
            candidate_record=self.candidate,
            phone_loaded_sha=phone_sha,
            uri_fingerprint=collector.fingerprint_uri(
                "trojan://test123@192.0.2.101:443#TEST-ROTATION-01"
            ),
            policy_identifier=collector.POLICY_IDENTIFIER,
            raw_result=raw,
            test_url="https://example.invalid/generate_204",
            network_bearer="cellular",
            tested_at=_now_iso(),
            measurement_verified=measurement_verified,
        )

    def test_weak_proof_never_writes_sha(self):
        record = self._evidence(500)
        attached = collector.apply_loaded_proof(
            record,
            {
                "proof_level": "MEMBERS_VERIFIED",
                "loaded_members_verified": True,
                "production_admission": "PENDING_REVIEW",
                "phone_loaded_sha": "UNKNOWN",
            },
        )
        self.assertEqual(attached["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(attached["production_admission"], "PENDING_REVIEW")
        # 弱证明 + 失败延迟 + 语义已校准, 仍不可下架 (phone 未验证)。
        judged = collector.apply_calibration(
            attached, {"verdict": "CALIBRATED", "mapping_field": "available"}
        )
        judged["verdict"] = collector.judge_evidence(judged)
        result = validator.validate_evidence(judged, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["eligible_for_removal"])
        self.assertTrue(result["checks"]["loaded_proof_ok"])

    def test_byte_proof_enables_removal_when_failure_and_calibrated(self):
        record = self._evidence(500)
        attached = collector.apply_loaded_proof(
            record,
            {
                "proof_level": "BYTE_PROOF",
                "loaded_members_verified": False,
                "production_admission": "GRANTED",
                "phone_loaded_sha": self.candidate["payload_sha256"],
            },
        )
        self.assertEqual(attached["phone_loaded_sha"], self.candidate["payload_sha256"])
        calibrated = collector.apply_calibration(
            attached, {"verdict": "CALIBRATED", "mapping_field": "available"}
        )
        calibrated["verdict"] = collector.judge_evidence(calibrated)
        result = validator.validate_evidence(
            calibrated, self.candidate, pinned_names=PINNED_NAMES
        )
        self.assertEqual(result["verdict"], "FAIL_LATENCY")
        self.assertTrue(result["eligible_for_removal"])

    def test_inconsistent_proof_fields_rejected(self):
        record = self._evidence(500)
        record["loaded_proof_level"] = "MEMBERS_VERIFIED"
        record["phone_loaded_sha"] = _phone_sha()  # 弱证明却带已验证 SHA: 篡改
        record["production_admission"] = "PENDING_REVIEW"
        errors = collector.validate_loaded_proof_fields(record)
        self.assertTrue(errors)
        result = validator.validate_evidence(record, self.candidate, pinned_names=PINNED_NAMES)
        self.assertFalse(result["valid"])
        self.assertEqual(result["verdict"], "UNVERIFIED")
        self.assertFalse(result["eligible_for_removal"])

    def test_measurement_verified_without_calibration_rejected(self):
        record = self._evidence(120, phone_sha=_phone_sha(), measurement_verified=True)
        record["calibration_verdict"] = "UNCALIBRATED"
        errors = collector.validate_loaded_proof_fields(record)
        self.assertTrue(errors)

    def test_invalid_proof_level_raises(self):
        record = self._evidence(500)
        with self.assertRaises(ValueError):
            collector.apply_loaded_proof(
                record,
                {"proof_level": "BOGUS", "production_admission": "DENIED"},
            )
        with self.assertRaises(ValueError):
            proof.attach_loaded_proof(record, {"proof_level": "BOGUS"})

    def test_byte_proof_without_sha_raises(self):
        record = self._evidence(500)
        with self.assertRaises(ValueError):
            collector.apply_loaded_proof(
                record,
                {
                    "proof_level": "BYTE_PROOF",
                    "production_admission": "GRANTED",
                    "phone_loaded_sha": "UNKNOWN",
                },
            )


class _MockGroupsHandler(BaseHTTPRequestHandler):
    payload = {}

    def log_message(self, *args):
        pass

    def do_GET(self):
        body = json.dumps(self.payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class TestMockReplay(unittest.TestCase):
    """mock 回放: 本地 HTTP 服务器按真实 /v1/policy_groups 形态
    返回数据, 客户端抓回后做成员集合比对。只证明解析逻辑,
    不证明真机 (见模块 docstring)。"""

    def test_fetch_and_classify_replay(self):
        candidate = _candidate_with_names()
        _MockGroupsHandler.payload = _real_shape_policy_groups(ALL_NAMES, "TEST-POOL")
        server = ThreadingHTTPServer(("127.0.0.1", 0), _MockGroupsHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = "http://127.0.0.1:{}/v1/policy_groups".format(server.server_address[1])
            with urllib.request.urlopen(url, timeout=10) as resp:
                fetched = json.loads(resp.read().decode("utf-8"))
        finally:
            server.shutdown()
            server.server_close()
        result = proof.classify_loaded_proof(
            {"/v1/policy_groups": fetched}, candidate, group_name="TEST-POOL"
        )
        self.assertEqual(result["proof_level"], "MEMBERS_VERIFIED")
        self.assertEqual(result["phone_loaded_sha"], "UNKNOWN")
        self.assertEqual(result["production_admission"], "PENDING_REVIEW")


if __name__ == "__main__":
    unittest.main()
