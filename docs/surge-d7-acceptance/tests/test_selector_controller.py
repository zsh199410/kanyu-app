"""Normal-path tests for the fail-closed selector controller (A5).

All tests run against tests/mock_surge_api.py — a MOCK Surge HTTP API.
No real device, no real Surge, no production config is touched.
See README.md for the mock boundary.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mock_surge_api import DEFAULT_MEMBERS, GROUP_NAME, make_server  # noqa: E402

CTRL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "fail-closed-select")


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(CTRL_DIR, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


controller_mod = _load("selector_controller", "selector-controller.py")
state_mod = _load("selector_state", "selector-state.py")
check_mod = _load("check_conf", "check_conf.py")

SurgeApiClient = controller_mod.SurgeApiClient
SelectorController = controller_mod.SelectorController


def healthy_candidates(now=None):
    now = time.time() if now is None else now
    return [
        {"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
         "latency_ms": 180, "tested_at": now - 60},
        {"name": "Test-Proxy-2", "host": "192.0.2.2", "port": 443,
         "latency_ms": 120, "tested_at": now - 60},
        {"name": "Test-Proxy-3", "host": "192.0.2.3", "port": 443,
         "latency_ms": 240, "tested_at": now - 60},
    ]


def expected_sha(candidates):
    return controller_mod.compute_candidate_sha(candidates)


class ControllerTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state_path = os.path.join(self.tmp.name, "state.json")
        self.stop_path = os.path.join(self.tmp.name, "STOP")
        self.server, self.thread, self.base_url = make_server()
        self.logs = []

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def make_controller(self, timeout=5.0, **kwargs):
        client = SurgeApiClient(self.base_url, timeout=timeout)
        return SelectorController(
            client, self.state_path,
            allowed_members=list(DEFAULT_MEMBERS),
            stop_path=self.stop_path,
            log_fn=lambda event, **f: self.logs.append((event, f)),
            **kwargs,
        )


class TestNormalPaths(ControllerTestBase):
    def test_explicit_reject_verified(self):
        """No candidates -> explicit REJECT, read-back REJECT."""
        ctl = self.make_controller()
        record = ctl.run_cycle([], expected_sha=None)
        self.assertEqual(record["state"], "REJECT_VERIFIED")
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertTrue(record["verified"])
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")
        self.assertFalse(state_mod.allow_production(record))

    def test_select_healthy_proxy_verified(self):
        """Healthy candidates -> lowest-latency proxy, read-back agrees."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["state"], "PROXY_VERIFIED")
        self.assertEqual(record["selected_policy"], "Test-Proxy-2")  # 120ms
        self.assertTrue(record["verified"])
        self.assertEqual(self.server.selection[GROUP_NAME], "Test-Proxy-2")
        self.assertTrue(state_mod.allow_production(record))

    def test_state_persistence_roundtrip(self):
        """Save -> load is marked unverified -> startup re-verify trusts it
        only after a live GET confirms the same selection."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        loaded = state_mod.load_state(self.state_path)
        self.assertEqual(loaded["selected_policy"], "Test-Proxy-2")
        # Loaded state is NEVER trusted as verified.
        self.assertFalse(loaded["verified"])
        self.assertTrue(loaded["needs_revalidation"])
        # Startup re-verification confirms the live selection matches.
        ctl2 = self.make_controller()
        record = ctl2.startup_reverify()
        self.assertEqual(record["state"], "PROXY_VERIFIED")
        self.assertTrue(record["verified"])

    def test_stop_check_blocks_and_rejects(self):
        """STOP file present -> STOPPED, device ends on REJECT."""
        open(self.stop_path, "w").close()
        ctl = self.make_controller()
        record = ctl.run_cycle(healthy_candidates())
        self.assertEqual(record["state"], "STOPPED")
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")
        self.assertFalse(state_mod.allow_production(record))

    def test_conf_static_check_passes_on_real_file(self):
        """The real conf file parses clean under the real checker."""
        conf = os.path.join(CTRL_DIR, "safe-egress-test.conf")
        errors = check_mod.check_conf(conf)
        self.assertEqual(errors, [], f"conf violations: {errors}")

    def test_readback_mismatch_is_unknown_not_safe(self):
        """POST ok but GET returns a different policy -> UNKNOWN."""
        server2, _t, url2 = make_server(
            {"get_policy_override": "Test-Proxy-3"})
        try:
            client = SurgeApiClient(url2, timeout=5.0)
            ctl = SelectorController(
                client, self.state_path, allowed_members=list(DEFAULT_MEMBERS),
                log_fn=lambda e, **f: None)
            cands = healthy_candidates()
            record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
            self.assertEqual(record["state"], "SELECTION_UNKNOWN")
            self.assertFalse(record["verified"])
            self.assertFalse(state_mod.allow_production(record))
        finally:
            server2.shutdown()
            server2.server_close()

    def test_manual_rollback_to_reject(self):
        """Human rollback entry point: explicit REJECT + read-back."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(self.server.selection[GROUP_NAME], "Test-Proxy-2")
        record = ctl.rollback_to_reject(manual=True)
        self.assertEqual(record["state"], "REJECT_VERIFIED")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")

    def test_logs_contain_no_secrets(self):
        """Structured logs must never carry passwords, tokens or URIs."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        blob = json.dumps(self.logs, ensure_ascii=False)
        self.assertNotIn("test123", blob)
        self.assertNotIn("trojan://", blob)
        self.assertNotIn("192.0.2.1", blob)  # hosts are not logged either
        self.assertIn("Test-Proxy-2", blob)  # names are fine


if __name__ == "__main__":
    unittest.main()
