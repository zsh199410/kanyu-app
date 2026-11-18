# -*- coding: utf-8 -*-
"""F3 原生测速口径对照校准测试 (tests/test_api_calibration.py)。

覆盖:
  * parse_api_latency: 字段名 / 数值 / 类型原样保留, 别名
    round-one-total 归一化, 非数值不强转。
  * test_url_scheme: http / https / UNKNOWN 区分。
  * classify_measurement_source: api / ui / group / paired 区分,
    非法 kind 拒绝。
  * build_paired_row: UI 人工读数缺失行不计入配对样本; 非数值 / 负数拒绝。
  * calibrate: 3 行同节点同口径、UI 恒等于某一 API 字段 -> CALIBRATED
    且 mapping 唯一; 样本不足 / 跨节点 / 跨 scheme / 跨 bearer /
    映射不唯一 / 无字段可解释 -> UNCALIBRATED; 同一 API 值对应
    不同 UI 值 -> CONTRADICTED。
  * measurement_verified_from_calibration / apply_calibration:
    只有 CALIBRATED 才能置 True; 否则 False, judge_evidence() 维持
    UNVERIFIED; CALIBRATED + 手机已验证 + <300ms -> PASS。
  * 口径区分: HTTP 与 HTTPS 分开校准, 混用即 UNCALIBRATED。

夹具一律用 TEST-NET 假值 (192.0.2.0/24 + test123),
不得出现真实节点 URI / 密码。
"""

import hashlib
import importlib.util
import unittest
from datetime import datetime, timezone
from pathlib import Path

_HERE = Path(__file__).resolve().parent
_NATIVE = _HERE.parent / "native-evidence"


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(name, str(_NATIVE / filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


freeze = _load("candidate_freeze_f3", "candidate-freeze.py")
collector = _load("native_collector_f3", "native-collector.py")
calibration = _load("calibration_f3", "calibration.py")

PINNED_NAMES = ["TEST-PINNED-{:02d}".format(i) for i in range(1, 22)]
ROTATION_NAMES = ["TEST-ROTATION-{:02d}".format(j) for j in range(1, 10)]


def _fixture_subscription_bytes():
    lines = []
    for i in range(1, 22):
        lines.append("trojan://test123@192.0.2.{}:443#TEST-PINNED-{:02d}".format(i, i))
    for j in range(1, 10):
        lines.append("trojan://test123@192.0.2.{}:443#TEST-ROTATION-{:02d}".format(100 + j, j))
    return ("\n".join(lines) + "\n").encode("utf-8")


def _now_iso():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _api_sample(node, round_one_total, available, tcp=50, receive=80, latency=None):
    sample = {
        "node_name": node,
        "round-one-total": round_one_total,
        "available": available,
        "tcp": tcp,
        "receive": receive,
    }
    if latency is not None:
        sample["latency_ms"] = latency
    return sample


def _paired_rows(node="TEST-ROTATION-01", ui_field="available",
                 scheme_url="https://example.invalid/generate_204",
                 bearer="cellular", count=3):
    """构造 count 行配对样本: UI 值恒等于 ui_field 对应的 API 值。"""
    rows = []
    values = [(1315, 387), (1200, 210), (1500, 150)]
    for i in range(count):
        r1, avail = values[i % len(values)]
        api = _api_sample(node, r1, avail)
        ui = {"round_one_total": r1, "available": avail}[ui_field]
        rows.append(
            calibration.build_paired_row(
                api, ui, group_selection=node,
                test_url=scheme_url, network_bearer=bearer,
                sampled_at=_now_iso(),
            )
        )
    return rows


class TestParseApiLatency(unittest.TestCase):
    def test_fields_and_types_preserved(self):
        parsed = calibration.parse_api_latency(
            {"round-one-total": 1315, "available": 387.5, "tcp": 50, "receive": 80}
        )
        self.assertEqual(parsed["fields"]["round_one_total"], 1315)
        self.assertEqual(parsed["fields"]["available"], 387.5)
        self.assertEqual(parsed["types"]["round_one_total"], "int")
        self.assertEqual(parsed["types"]["available"], "float")
        self.assertIn("round_one_total", parsed["present"])
        self.assertIn("round-one-total", parsed["raw_keys"])

    def test_string_value_not_coerced(self):
        parsed = calibration.parse_api_latency({"available": "387"})
        self.assertIsNone(parsed["fields"]["available"])
        self.assertEqual(parsed["types"]["available"], "str")
        self.assertNotIn("available", parsed["present"])

    def test_bool_is_not_latency(self):
        parsed = calibration.parse_api_latency({"available": True})
        self.assertIsNone(parsed["fields"]["available"])

    def test_missing_fields_are_none(self):
        parsed = calibration.parse_api_latency({"node_name": "TEST-ROTATION-01"})
        self.assertIsNone(parsed["fields"]["round_one_total"])
        self.assertEqual(parsed["present"], [])

    def test_non_dict_raises(self):
        with self.assertRaises(TypeError):
            calibration.parse_api_latency("not-a-dict")


class TestSchemeAndSource(unittest.TestCase):
    def test_scheme(self):
        self.assertEqual(
            calibration.test_url_scheme("https://example.invalid/generate_204"), "https"
        )
        self.assertEqual(
            calibration.test_url_scheme("http://www.gstatic.com/generate_204"), "http"
        )
        self.assertEqual(calibration.test_url_scheme("ftp://example.invalid/x"), "UNKNOWN")
        self.assertEqual(calibration.test_url_scheme(None), "UNKNOWN")
        self.assertEqual(calibration.test_url_scheme(""), "UNKNOWN")

    def test_source_kinds(self):
        for kind in ("api", "ui", "group", "paired"):
            self.assertEqual(
                calibration.classify_measurement_source({"kind": kind}), kind
            )
        self.assertEqual(calibration.classify_measurement_source({}), "UNKNOWN")
        with self.assertRaises(ValueError):
            calibration.classify_measurement_source({"kind": "bogus"})


class TestPairedRows(unittest.TestCase):
    def test_row_without_ui_is_not_usable(self):
        row = calibration.build_paired_row(
            _api_sample("TEST-ROTATION-01", 1315, 387), None,
            test_url="https://example.invalid/generate_204",
        )
        self.assertIsNone(row["ui_value"])
        self.assertIsNone(row["ui_source"])
        result = calibration.calibrate([row])
        self.assertEqual(result["usable_count"], 0)
        self.assertEqual(result["verdict"], "UNCALIBRATED")

    def test_invalid_ui_rejected(self):
        with self.assertRaises(ValueError):
            calibration.build_paired_row(
                _api_sample("TEST-ROTATION-01", 1315, 387), "387"
            )
        with self.assertRaises(ValueError):
            calibration.build_paired_row(
                _api_sample("TEST-ROTATION-01", 1315, 387), -5
            )
        with self.assertRaises(ValueError):
            calibration.build_paired_row(
                _api_sample("TEST-ROTATION-01", 1315, 387), True
            )


class TestCalibrate(unittest.TestCase):
    def test_calibrated_on_available(self):
        result = calibration.calibrate(_paired_rows(ui_field="available"))
        self.assertEqual(result["verdict"], "CALIBRATED")
        self.assertEqual(result["mapping_field"], "available")
        self.assertEqual(result["paired_count"], 3)
        self.assertEqual(result["usable_count"], 3)
        self.assertEqual(result["scheme"], "https")
        self.assertEqual(result["node"], "TEST-ROTATION-01")
        self.assertEqual(len(result["comparison_table"]), 3)

    def test_calibrated_on_round_one_total(self):
        result = calibration.calibrate(_paired_rows(ui_field="round_one_total"))
        self.assertEqual(result["verdict"], "CALIBRATED")
        self.assertEqual(result["mapping_field"], "round_one_total")

    def test_too_few_samples(self):
        result = calibration.calibrate(_paired_rows(count=2))
        self.assertEqual(result["verdict"], "UNCALIBRATED")
        self.assertIsNone(result["mapping_field"])

    def test_mixed_schemes_uncalibrated(self):
        rows = _paired_rows(count=2) + _paired_rows(
            count=1, scheme_url="http://www.gstatic.com/generate_204"
        )
        result = calibration.calibrate(rows)
        self.assertEqual(result["verdict"], "UNCALIBRATED")
        self.assertIsNone(result["mapping_field"])

    def test_mixed_nodes_uncalibrated(self):
        rows = _paired_rows(count=2) + _paired_rows(count=1, node="TEST-ROTATION-02")
        result = calibration.calibrate(rows)
        self.assertEqual(result["verdict"], "UNCALIBRATED")

    def test_mixed_bearers_uncalibrated(self):
        rows = _paired_rows(count=2) + _paired_rows(count=1, bearer="wifi")
        result = calibration.calibrate(rows)
        self.assertEqual(result["verdict"], "UNCALIBRATED")

    def test_ambiguous_mapping_uncalibrated(self):
        # UI 值同时等于 available 与 tcp (两字段数值相同): 映射不唯一。
        rows = []
        for i, v in enumerate((100, 200, 150)):
            api = _api_sample("TEST-ROTATION-01", 999, v, tcp=v, receive=1)
            rows.append(
                calibration.build_paired_row(
                    api, v, test_url="https://example.invalid/generate_204",
                    network_bearer="cellular",
                )
            )
        result = calibration.calibrate(rows)
        self.assertEqual(result["verdict"], "UNCALIBRATED")
        self.assertIsNone(result["mapping_field"])

    def test_no_field_explains_ui(self):
        rows = []
        for i, (r1, avail) in enumerate([(1315, 387), (1200, 210), (1500, 150)]):
            api = _api_sample("TEST-ROTATION-01", r1, avail)
            rows.append(
                calibration.build_paired_row(
                    api, 9999, test_url="https://example.invalid/generate_204",
                    network_bearer="cellular",
                )
            )
        result = calibration.calibrate(rows)
        self.assertEqual(result["verdict"], "UNCALIBRATED")

    def test_contradicted_same_api_different_ui(self):
        rows = []
        for ui in (387, 200, 387):
            api = _api_sample("TEST-ROTATION-01", 1315, 387)
            rows.append(
                calibration.build_paired_row(
                    api, ui, test_url="https://example.invalid/generate_204",
                    network_bearer="cellular",
                )
            )
        result = calibration.calibrate(rows)
        self.assertEqual(result["verdict"], "CONTRADICTED")

    def test_http_and_https_calibrate_separately(self):
        http_rows = _paired_rows(
            scheme_url="http://www.gstatic.com/generate_204", ui_field="available"
        )
        https_rows = _paired_rows(
            scheme_url="https://example.invalid/generate_204", ui_field="available"
        )
        self.assertEqual(calibration.calibrate(http_rows)["verdict"], "CALIBRATED")
        self.assertEqual(calibration.calibrate(https_rows)["verdict"], "CALIBRATED")
        self.assertEqual(
            calibration.calibrate(http_rows + https_rows)["verdict"], "UNCALIBRATED"
        )


class TestMeasurementVerifiedGate(unittest.TestCase):
    def test_only_calibrated_verifies(self):
        self.assertTrue(
            calibration.measurement_verified_from_calibration(
                {"verdict": "CALIBRATED", "mapping_field": "available"}
            )
        )
        for bad in (
            {"verdict": "UNCALIBRATED", "mapping_field": "available"},
            {"verdict": "CONTRADICTED", "mapping_field": "available"},
            {"verdict": "CALIBRATED", "mapping_field": None},
            {"verdict": "CALIBRATED"},
            {},
            None,
            "CALIBRATED",
        ):
            self.assertFalse(calibration.measurement_verified_from_calibration(bad))

    def _evidence(self, latency, phone_sha, measurement_verified=False):
        candidate = freeze.freeze_candidate(
            _fixture_subscription_bytes(), "test-revision-001"
        )
        raw = {"node_name": "TEST-ROTATION-01", "latency_ms": latency}
        return collector.build_evidence_chain(
            candidate_record=candidate,
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

    def test_apply_calibration_gates_judgement(self):
        phone_sha = hashlib.sha256(b"test-phone-loaded-subscription").hexdigest()
        record = self._evidence(120, phone_sha)
        # 未校准 -> False, 维持 UNVERIFIED。
        uncal = collector.apply_calibration(
            record, {"verdict": "UNCALIBRATED", "mapping_field": None}
        )
        self.assertFalse(uncal["measurement_verified"])
        self.assertEqual(collector.judge_evidence(uncal), "UNVERIFIED")
        # 已校准 -> True, <300ms + 手机已验证 -> PASS。
        cal = collector.apply_calibration(
            record, {"verdict": "CALIBRATED", "mapping_field": "available"}
        )
        self.assertTrue(cal["measurement_verified"])
        self.assertEqual(cal["calibration_verdict"], "CALIBRATED")
        self.assertEqual(cal["calibration_mapping_field"], "available")
        self.assertEqual(collector.judge_evidence(cal), "PASS")
        # apply_calibration 不改写已有 verdict 字段本身 (只置标志位)。
        self.assertEqual(record["verdict"], "UNVERIFIED")

    def test_calibration_module_apply_matches_collector(self):
        phone_sha = hashlib.sha256(b"test-phone-loaded-subscription").hexdigest()
        record = self._evidence(120, phone_sha)
        via_cal = calibration.apply_calibration_to_evidence(
            record, {"verdict": "CALIBRATED", "mapping_field": "available"}
        )
        via_col = collector.apply_calibration(
            record, {"verdict": "CALIBRATED", "mapping_field": "available"}
        )
        self.assertEqual(
            via_cal["measurement_verified"], via_col["measurement_verified"]
        )
        self.assertTrue(via_cal["measurement_verified"])

    def test_uncalibrated_never_passes_even_if_phone_verified(self):
        phone_sha = hashlib.sha256(b"test-phone-loaded-subscription").hexdigest()
        record = self._evidence(120, phone_sha, measurement_verified=False)
        self.assertEqual(collector.judge_evidence(record), "UNVERIFIED")


if __name__ == "__main__":
    unittest.main()
