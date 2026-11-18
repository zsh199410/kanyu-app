"""Negative-case tests for the fail-closed selector controller (A5).

Every test asserts the fail-closed property: when anything is uncertain,
the controller must NOT claim REJECT, must NOT select a proxy, and must
NOT authorise production traffic. All tests run against the mock Surge
HTTP API (tests/mock_surge_api.py) — mock boundary per README.md.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mock_surge_api import DEFAULT_MEMBERS, GROUP_NAME, make_server  # noqa: E402
from test_selector_controller import (  # noqa: E402  (reuse fixtures)
    ControllerTestBase,
    expected_sha,
    healthy_candidates,
)

CTRL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "fail-closed-select")


def _load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(CTRL_DIR, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


controller_mod = _load("selector_controller_neg", "selector-controller.py")
state_mod = _load("selector_state_neg", "selector-state.py")

SurgeApiClient = controller_mod.SurgeApiClient
SelectorController = controller_mod.SelectorController


class TestFailurePaths(ControllerTestBase):
    def test_no_healthy_proxy_does_not_authorise_production(self):
        """All candidates unhealthy -> REJECT, production not authorised."""
        ctl = self.make_controller()
        now = time.time()
        cands = [
            {"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
             "latency_ms": 9999, "tested_at": now - 60},
            {"name": "Test-Proxy-2", "host": "192.0.2.2", "port": 443,
             "latency_ms": 450, "tested_at": now - 60},
        ]
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["state"], "REJECT_VERIFIED")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")
        self.assertFalse(state_mod.allow_production(record))

    def test_single_failing_proxy_never_selects_direct(self):
        """One must-fail proxy: controller must not fall back to DIRECT
        (or to the failing proxy). Only REJECT may be selected."""
        ctl = self.make_controller()
        now = time.time()
        cands = [{"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
                  "latency_ms": 5000, "tested_at": now - 60}]
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertNotIn("DIRECT", self.server.selected_history)
        self.assertNotIn("Test-Proxy-1", self.server.selected_history)

    def test_stale_selection_not_reported_safe(self):
        """Persisted PROXY_VERIFIED with expired evidence must not be
        trusted on startup: load marks it EVIDENCE_EXPIRED and the
        controller falls back to REJECT."""
        ctl = self.make_controller()
        stale = state_mod.new_state(
            "PROXY_VERIFIED", selected_policy="Test-Proxy-2",
            candidate_sha="deadbeef", evidence_ts=time.time() - 7200,
            ttl_seconds=3600, verified=True, now=time.time())
        state_mod.save_state(self.state_path, stale)
        loaded = state_mod.load_state(self.state_path)
        self.assertEqual(loaded["state"], "EVIDENCE_EXPIRED")
        self.assertFalse(loaded["verified"])
        record = ctl.startup_reverify()
        self.assertEqual(record["state"], "EVIDENCE_EXPIRED")
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")
        self.assertFalse(state_mod.allow_production(record))

    def test_controller_crash_recovery_state_is_verifiable(self):
        """Simulated crash: state file survives, new controller instance
        recovers. Matching live selection -> re-verified; changed live
        selection -> not trusted, falls back to REJECT."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        # Crash: drop the instance, keep state file + mock selection.
        ctl2 = self.make_controller()
        record = ctl2.recover()
        self.assertEqual(record["state"], "PROXY_VERIFIED")
        self.assertTrue(record["verified"])
        # Now the device selection changed behind our back: not trusted.
        self.server.selection[GROUP_NAME] = "Test-Proxy-3"
        ctl3 = self.make_controller()
        record = ctl3.recover()
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")
        self.assertFalse(state_mod.allow_production(record))

    def test_api_timeout_is_unknown_never_claims_reject(self):
        """POST timeout -> SELECTION_UNKNOWN. The controller must not
        claim it reached REJECT, because the POST outcome is unknown."""
        server2, _t, url2 = make_server({"post_delay": 2.0})
        try:
            client = SurgeApiClient(url2, timeout=0.3)
            ctl = SelectorController(
                client, self.state_path, allowed_members=list(DEFAULT_MEMBERS),
                log_fn=lambda e, **f: None)
            cands = healthy_candidates()
            record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
            self.assertEqual(record["state"], "SELECTION_UNKNOWN")
            self.assertFalse(record["verified"])
            self.assertNotEqual(record.get("selected_policy"), "REJECT")
            self.assertFalse(state_mod.allow_production(record))
        finally:
            server2.shutdown()
            server2.server_close()

    def test_api_error_refuses_to_continue(self):
        """POST 500 -> SELECTION_UNKNOWN, no production authorisation."""
        server2, _t, url2 = make_server({"post_status": 500})
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

    def test_get_readback_failure_is_unknown(self):
        """POST ok but GET read-back 500 -> SELECTION_UNKNOWN."""
        server2, _t, url2 = make_server({"get_status": 500})
        try:
            client = SurgeApiClient(url2, timeout=5.0)
            ctl = SelectorController(
                client, self.state_path, allowed_members=list(DEFAULT_MEMBERS),
                log_fn=lambda e, **f: None)
            record = ctl.run_cycle([], expected_sha=None)
            self.assertEqual(record["state"], "SELECTION_UNKNOWN")
            self.assertFalse(record["verified"])
        finally:
            server2.shutdown()
            server2.server_close()

    def test_wifi_cellular_switch_reverifies(self):
        """After a network switch the live selection is re-read. Same
        value -> re-verified; changed value -> fall back to REJECT."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        record = ctl.reverify_after_network_change()
        self.assertEqual(record["state"], "PROXY_VERIFIED")
        self.assertTrue(record["verified"])
        self.server.selection[GROUP_NAME] = "Test-Proxy-1"
        record = ctl.reverify_after_network_change()
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")

    def test_candidate_sha_mismatch_refuses_selection(self):
        """Candidate set SHA != expected version -> VERSION_MISMATCH,
        proxy never selected, device ends on REJECT."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        record = ctl.run_cycle(cands, expected_sha="0" * 64)
        self.assertEqual(record["state"], "VERSION_MISMATCH")
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertNotIn("Test-Proxy-2", self.server.selected_history)
        self.assertFalse(state_mod.allow_production(record))

    def test_duplicate_identifiers_refuse_selection(self):
        """Two candidates with the same name -> refuse, fall back to REJECT."""
        ctl = self.make_controller()
        now = time.time()
        cands = [
            {"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
             "latency_ms": 100, "tested_at": now - 60},
            {"name": "Test-Proxy-1", "host": "192.0.2.2", "port": 443,
             "latency_ms": 110, "tested_at": now - 60},
        ]
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertNotIn("Test-Proxy-1", self.server.selected_history)
        self.assertFalse(state_mod.allow_production(record))

    def test_identifier_mapping_failure_refuses_selection(self):
        """Candidate name not in the device member list -> refuse."""
        ctl = self.make_controller()
        now = time.time()
        cands = [{"name": "Ghost-Proxy-9", "host": "192.0.2.9", "port": 443,
                  "latency_ms": 100, "tested_at": now - 60}]
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertNotIn("Ghost-Proxy-9", self.server.selected_history)

    def test_stop_blocks_production(self):
        """STOP checker active -> STOPPED, proxy never selected."""
        ctl = self.make_controller(stop_checker=lambda: True)
        cands = healthy_candidates()
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["state"], "STOPPED")
        self.assertEqual(record["selected_policy"], "REJECT")
        self.assertNotIn("Test-Proxy-2", self.server.selected_history)
        self.assertFalse(state_mod.allow_production(record))

    def test_repeated_state_events_no_race(self):
        """The same cycle repeated 20x (and concurrently) must never
        produce a torn state file or an invalid state."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        sha = expected_sha(cands)
        errors = []

        def worker():
            try:
                for _ in range(5):
                    rec = ctl.run_cycle(cands, expected_sha=sha)
                    assert rec["state"] in state_mod.STATES, rec
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=worker) for _ in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        final = state_mod.load_state(self.state_path)
        self.assertIn(final["state"], state_mod.STATES)
        self.assertEqual(self.server.selection[GROUP_NAME], "Test-Proxy-2")

    def test_device_config_not_loaded_refuses_operation(self):
        """Device does not report the expected group/members -> refuse
        any selection, CONTROLLER_UNAVAILABLE, device selection untouched."""
        server2, _t, url2 = make_server(
            {"groups_members": {GROUP_NAME: ["Test-Proxy-1"]}})
        try:
            client = SurgeApiClient(url2, timeout=5.0)
            ctl = SelectorController(
                client, self.state_path, allowed_members=list(DEFAULT_MEMBERS),
                log_fn=lambda e, **f: None)
            cands = healthy_candidates()
            record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
            self.assertEqual(record["state"], "CONTROLLER_UNAVAILABLE")
            self.assertFalse(record["verified"])
            self.assertEqual(server2.selected_history, [])
            self.assertFalse(state_mod.allow_production(record))
        finally:
            server2.shutdown()
            server2.server_close()

    def test_restart_recovery(self):
        """Restart: fresh controller instance + same state file + same
        live selection -> re-verified PROXY_VERIFIED. The loaded record
        itself was unverified until the live GET confirmed it."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        del ctl
        ctl2 = self.make_controller()
        loaded_before = state_mod.load_state(self.state_path)
        self.assertFalse(loaded_before["verified"])
        record = ctl2.startup_reverify()
        self.assertEqual(record["state"], "PROXY_VERIFIED")
        self.assertTrue(record["verified"])
        self.assertEqual(record["selected_policy"], "Test-Proxy-2")

    def test_concurrent_calls(self):
        """Concurrent run_cycle + rollback calls: no crash, no torn
        state, final persisted state is a valid state and the device
        selection matches one of REJECT / the verified proxy."""
        ctl = self.make_controller()
        cands = healthy_candidates()
        sha = expected_sha(cands)
        errors = []

        def cycle_worker():
            try:
                for _ in range(4):
                    ctl.run_cycle(cands, expected_sha=sha)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        def rollback_worker():
            try:
                for _ in range(4):
                    ctl.rollback_to_reject(manual=True)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=cycle_worker) for _ in range(3)]
        threads += [threading.Thread(target=rollback_worker) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        final = state_mod.load_state(self.state_path)
        self.assertIn(final["state"], state_mod.STATES)
        self.assertIn(self.server.selection[GROUP_NAME],
                      ["REJECT", "Test-Proxy-2"])

    def test_expired_candidate_evidence_refuses_proxy(self):
        """Candidate evidence older than 24h -> unhealthy -> REJECT."""
        ctl = self.make_controller()
        now = time.time()
        cands = [{"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
                  "latency_ms": 100, "tested_at": now - 25 * 3600}]
        record = ctl.run_cycle(cands, expected_sha=expected_sha(cands))
        self.assertEqual(record["state"], "REJECT_VERIFIED")
        self.assertNotIn("Test-Proxy-1", self.server.selected_history)


if __name__ == "__main__":
    unittest.main()
