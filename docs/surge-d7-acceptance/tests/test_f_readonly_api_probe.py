# -*- coding: utf-8 -*-
"""F read-only API capability probe tests; offline, no secrets or sockets."""
from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
from urllib.error import HTTPError
import unittest

MODULE = Path(__file__).resolve().parent.parent / "native-evidence" / "f-readonly-api-probe.py"
spec = importlib.util.spec_from_file_location("surge_f_probe", str(MODULE))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class Response:
    def __init__(self, payload):
        self.buf = io.BytesIO(payload)
        self.status = 200
    def read(self, n=None):
        return self.buf.read(n)
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.buf.close()


class FakeOpener:
    def __init__(self, payload):
        self.payload = payload
        self.requests = []
    def open(self, req, timeout=0):
        self.requests.append((req, timeout))
        if isinstance(self.payload, Exception):
            raise self.payload
        return Response(self.payload)


class ProbeTest(unittest.TestCase):
    def test_local_ip_only(self):
        for host in ("https://192.168.5.19:6171", "http://8.8.8.8:6171",
                     "http://surge.example:6171", "http://0.0.0.0:6171",
                     "http://192.168.5.19:6171/foo",
                     "http://user:secret@192.168.5.19:6171"):
            with self.subTest(host=host):
                with self.assertRaises(ValueError):
                    probe.validated_base(host)
        self.assertEqual(probe.validated_base("http://192.168.5.19:6171"),
                         "http://192.168.5.19:6171")

    def test_policy_names_and_identifiers_never_emitted(self):
        obj = {"proxies": ["real-secret-name"],
               "external-policies": [{"name": "secret-node", "identifier": "SECRET"}],
               "policy-groups": ["secret-group"],
               "latency_ms": 310, "available": ["secret-choice"]}
        shape = probe.sanitize_structure(obj)
        text = json.dumps(shape)
        self.assertNotIn("secret", text)
        self.assertEqual(shape["external_policies_count"], 1)
        self.assertEqual(shape["latency_numeric_fields"]["latency_ms"], 310)

    def test_first_pass_makes_only_three_gets_no_retry(self):
        opener = FakeOpener(json.dumps({"available": ["private"]}).encode())
        out = probe.probe("http://192.168.5.19:6171", "secret_key", "免费节点池",
                          opener=opener)
        self.assertEqual(out["post_count"], 0)
        self.assertFalse(out["auto_retry"])
        self.assertEqual(len(opener.requests), 3)
        self.assertEqual(out["calibration_verdict"], "UNCALIBRATED")
        self.assertNotIn("secret_key", json.dumps(out))
        self.assertNotIn("免费节点池", json.dumps(out, ensure_ascii=False))
        for req, timeout in opener.requests:
            self.assertEqual(req.get_method(), "GET")
            self.assertEqual(timeout, 10)
            self.assertEqual(req.get_header("X-key"), "secret_key")

    def test_optional_detail_is_one_extra_get(self):
        opener = FakeOpener(b"{}")
        out = probe.probe("http://127.0.0.1:6171", "key", "Group",
                          policy="secret node", opener=opener)
        self.assertEqual(len(opener.requests), 4)
        self.assertIn("one_policy_detail", out["endpoints"])
        self.assertIn("policy_name=secret%20node",
                      opener.requests[-1][0].full_url)
        self.assertNotIn("secret node", json.dumps(out))

    def test_http_error_does_not_retry_or_emit_body(self):
        exc = HTTPError("http://127.0.0.1:6171/v1/policies", 403, "no", {}, None)
        opener = FakeOpener(exc)
        out = probe.get_once("http://127.0.0.1:6171", "private_key", "/v1/policies",
                             opener=opener)
        self.assertEqual(out["status"], "http_error")
        self.assertEqual(out["http_status"], 403)
        self.assertEqual(len(opener.requests), 1)

    def test_invalid_json_cannot_be_marked_calibrated(self):
        opener = FakeOpener(b"not-json SECRET")
        out = probe.probe("http://127.0.0.1:6171", "key", "Group", opener=opener)
        self.assertEqual(out["calibration_verdict"], "UNCALIBRATED")
        self.assertEqual(out["auto_clean"], "NO_GO")
        self.assertNotIn("SECRET", json.dumps(out))

    def test_missing_key_fails_before_network_access(self):
        opener = FakeOpener(b"{}")
        with self.assertRaises(ValueError):
            probe.get_once("http://127.0.0.1:6171", "", "/v1/policies",
                            opener=opener)
        self.assertEqual(len(opener.requests), 0)

    def test_oversized_api_response_has_no_body_in_output(self):
        opener = FakeOpener(b'{"data":"' + (b"S" * (1024 * 1024)) + b'"}')
        out = probe.get_once("http://127.0.0.1:6171", "secret", "/v1/policies",
                             opener=opener)
        self.assertFalse(out["ok"])
        self.assertEqual(out["status"], "oversize")

    def test_missing_value_does_not_fabricate_latency(self):
        shape = probe.sanitize_structure({"policy": "secret", "available": False})
        self.assertEqual(shape["latency_numeric_fields"], {})


if __name__ == "__main__":
    unittest.main()
