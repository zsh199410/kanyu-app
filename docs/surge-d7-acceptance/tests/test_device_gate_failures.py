"""Device-gate tests, part 2 (P0-E): failure modes.

Covers: controller API timeouts / errors / ignored POSTs / lying
read-backs, candidate validation failures, corrupt on-device lease
state, clock anomalies seen from the controller side, damaged state
files, restart recovery, and concurrent issuance. Every test asserts
the controller NEVER reports a lease active (or a revoke confirmed)
without a read-back, and NEVER selects DIRECT.

Run:  cd tests && python3 -m unittest test_device_gate_failures -v
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mock_gate_api  # noqa: E402
from mock_gate_api import GROUP_NAME  # noqa: E402
from test_device_gate import (  # noqa: E402
    EXPECTED_SHA, GATE_DIR, GROUP_NAME as _G, LEASE_KEY, BOOT_KEY,
    NETWORK_A, NOW, NodeHarness, make_candidates, make_lease,
    py_fingerprint, rule_scenario, lease_store,
)
import importlib.util  # noqa: E402

_SPEC = importlib.util.spec_from_file_location(
    "gate_controller_mod",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "device-gate", "gate-controller.py"),
)
gate_controller = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gate_controller)

RULE_JS = os.path.join(GATE_DIR, "gate-script.js")
EVENTS_JS = os.path.join(GATE_DIR, "gate-events.js")
RUNTIME_JS = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "mock_surge_runtime.js")


class _ControllerCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state_path = os.path.join(self.tmp.name, "gate-state.json")
        self.store_path = os.path.join(self.tmp.name, "store.json")
        with open(self.store_path, "w", encoding="utf-8") as fh:
            json.dump({BOOT_KEY: "boot-1"}, fh)
        self.behavior = {"store_path": self.store_path,
                         "network": NETWORK_A, "now": NOW}

    def start_server(self, **over):
        behavior = dict(self.behavior)
        behavior.update(over)
        self.server, self.thread, base_url = mock_gate_api.make_server(behavior)
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.server_close)
        return base_url

    def make_controller(self, base_url, **over):
        self.now_box = {"now": NOW}
        kwargs = dict(
            api_client=gate_controller.SurgeApiClient(base_url, timeout=2.0),
            state_path=self.state_path,
            allowed_members=["Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"],
            now_fn=lambda: self.now_box["now"],
        )
        kwargs.update(over)
        return gate_controller.GateController(**kwargs)

    def seed_store_lease(self, lease):
        with open(self.store_path, encoding="utf-8") as fh:
            store = json.load(fh)
        if lease is None:
            store.pop(LEASE_KEY, None)
        else:
            store[LEASE_KEY] = json.dumps(lease)
        with open(self.store_path, "w", encoding="utf-8") as fh:
            json.dump(store, fh)


class TestControllerApiFailures(_ControllerCase):
    def test_post_timeout_is_not_active(self):
        base_url = self.start_server(post_delay=5)
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertIn(rec["state"],
                      ("CONTROLLER_UNAVAILABLE", "GATE_UNKNOWN"))
        self.assertFalse(rec["verified"])

    def test_get_groups_500_blocks_issue(self):
        base_url = self.start_server(groups_status=500)
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "CONTROLLER_UNAVAILABLE")
        self.assertEqual(self.server.selected_history, [])

    def test_post_ignored_readback_mismatch(self):
        base_url = self.start_server(post_ignored=True)
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertFalse(rec["verified"])

    def test_lying_get_override_blocks_active(self):
        base_url = self.start_server(get_policy_override="Test-Proxy-2")
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertFalse(rec["verified"])

    def test_evaluate_500_blocks_issue(self):
        base_url = self.start_server(evaluate_status=500)
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "CONTROLLER_UNAVAILABLE")
        self.assertFalse(rec["verified"])

    def test_group_not_loaded(self):
        base_url = self.start_server(groups_members={})
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertIn(rec["state"], ("CONTROLLER_UNAVAILABLE", "GATE_UNKNOWN"))
        self.assertEqual(self.server.selected_history, [])

    def test_no_boot_id_on_device_mints_one_and_issues(self):
        """engine-started never ran -> the issue script mints a boot id
        and stores it, so the first issuance can succeed. A later
        engine-started still mints a fresh boot id and deletes the
        lease, so reboot revocation is preserved."""
        with open(self.store_path, "w", encoding="utf-8") as fh:
            json.dump({}, fh)
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_ACTIVE")
        self.assertTrue(rec["verified"])
        self.assertIsNotNone(rec["lease"])
        self.assertTrue(str(rec["lease"]["boot_id"]).startswith("boot-"))
        with open(self.store_path, encoding="utf-8") as fh:
            store = json.load(fh)
        self.assertEqual(store.get("device-gate-boot-v1"),
                         rec["lease"]["boot_id"])


class TestControllerCandidateFailures(_ControllerCase):
    def test_duplicate_candidates_refused(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        cands = make_candidates() + [dict(make_candidates()[0])]
        rec = ctrl.issue_lease(cands, EXPECTED_SHA)
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertEqual(self.server.selected_history, [])

    def test_unknown_member_refused(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        cands = make_candidates()
        cands[0] = dict(cands[0], name="Real-Node-1")
        rec = ctrl.issue_lease(cands, EXPECTED_SHA)
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertEqual(self.server.selected_history, [])

    def test_unhealthy_latency_no_lease(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        cands = [dict(c, latency_ms=999) for c in make_candidates()]
        rec = ctrl.issue_lease(cands, EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_REVOKED")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")

    def test_non_testnet_host_refused(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        cands = make_candidates()
        cands[0] = dict(cands[0], host="203.0.113.9")
        rec = ctrl.issue_lease(cands, EXPECTED_SHA)
        # The bad candidate is unhealthy; the other two are healthy, so
        # issuance proceeds for a healthy one — but the bad host is never
        # selected. Assert the selected proxy is a healthy TEST-NET one.
        self.assertEqual(rec["state"], "LEASE_ACTIVE")
        self.assertIn(rec["selected_policy"], ("Test-Proxy-2", "Test-Proxy-3"))

    def test_stale_evidence_refused(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        cands = [dict(c, tested_at=NOW - 25 * 3600) for c in make_candidates()]
        rec = ctrl.issue_lease(cands, EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_REVOKED")


class TestControllerLeaseStateFailures(_ControllerCase):
    def test_corrupt_stored_lease_is_unknown(self):
        self.seed_store_lease(None)
        with open(self.store_path, encoding="utf-8") as fh:
            store = json.load(fh)
        store[LEASE_KEY] = "{broken json"
        with open(self.store_path, "w", encoding="utf-8") as fh:
            json.dump(store, fh)
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.check_lease_status()
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertFalse(rec["verified"])

    def test_selection_differs_from_lease_is_unknown(self):
        self.seed_store_lease(make_lease())
        base_url = self.start_server()
        self.server.selection[GROUP_NAME] = "Test-Proxy-2"
        ctrl = self.make_controller(base_url)
        rec = ctrl.check_lease_status()
        self.assertEqual(rec["state"], "GATE_UNKNOWN")

    def test_lease_from_future_clock_is_unknown(self):
        lease = make_lease(issued_at=NOW + 3600, expires_at=NOW + 4200)
        self.seed_store_lease(lease)
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.check_lease_status()
        self.assertEqual(rec["state"], "GATE_UNKNOWN")

    def test_no_lease_status(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        self.assertEqual(ctrl.check_lease_status()["state"], "NO_LEASE")

    def test_damaged_state_file_is_not_trusted(self):
        with open(self.state_path, "w", encoding="utf-8") as fh:
            fh.write("{damaged")
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.startup_reverify()
        self.assertEqual(rec["state"], "NO_LEASE")

    def test_forged_active_state_file_is_not_trusted(self):
        """A state file claiming LEASE_ACTIVE/verified must be re-read
        from the device; with no lease stored it must collapse."""
        forged = gate_controller.new_state(
            "LEASE_ACTIVE", selected_policy="Test-Proxy-1",
            candidate_sha=EXPECTED_SHA, verified=True, now=NOW)
        gate_controller.save_state(self.state_path, forged)
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.startup_reverify()
        self.assertEqual(rec["state"], "NO_LEASE")
        self.assertFalse(rec["verified"])

    def test_revoke_unconfirmed_when_post_ignored(self):
        # Both revoke channels must fail: the evaluate script's
        # setSelectGroupPolicy (evaluate_surge_set_ok=False) AND the
        # HTTP API POST (post_ignored=True). Start from a proxy
        # selection so the REJECT read-back must fail.
        base_url = self.start_server(post_ignored=True,
                                     evaluate_surge_set_ok=False)
        self.server.selection[GROUP_NAME] = "Test-Proxy-1"
        ctrl = self.make_controller(base_url)
        rec = ctrl.revoke_lease("test")
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertFalse(rec["verified"])

    def test_never_selects_direct(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        ctrl.revoke_lease("test")
        ctrl.check_lease_status()
        self.assertNotIn("DIRECT", self.server.selected_history)


class TestControllerConcurrencyAndRestart(_ControllerCase):
    def test_concurrent_issue_is_serialised(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        results = []

        def run():
            results.append(ctrl.issue_lease(make_candidates(), EXPECTED_SHA))

        threads = [threading.Thread(target=run) for _ in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=60)
        self.assertEqual(len(results), 4)
        self.assertTrue(all(r["state"] == "LEASE_ACTIVE" for r in results))
        self.assertTrue(all(r["verified"] for r in results))

    def test_restart_then_lease_expired(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        self.assertEqual(ctrl.issue_lease(make_candidates(), EXPECTED_SHA)["state"],
                         "LEASE_ACTIVE")
        # Controller process restarts; the lease expired meanwhile.
        ctrl2 = self.make_controller(base_url)
        ctrl2._now_box = {"now": NOW}
        self.now_box["now"] = NOW + 3600
        ctrl2.now_fn = lambda: NOW + 3600
        rec = ctrl2.startup_reverify()
        self.assertEqual(rec["state"], "LEASE_EXPIRED")


class TestRuleScriptEdgeCases(unittest.TestCase):
    def setUp(self):
        self.h = NodeHarness(self)

    def test_missing_script_file_is_a_harness_error_not_a_match(self):
        """Models 'script missing': the rule cannot run, so in Surge the
        SCRIPT rule is treated as not matched -> FINAL,REJECT. The mock
        cannot run a missing file at all; assert that loudly instead of
        silently treating it as a match."""
        store_path = os.path.join(self.h.dir, "store.json")
        scen_path = os.path.join(self.h.dir, "scenario.json")
        with open(store_path, "w", encoding="utf-8") as fh:
            json.dump({}, fh)
        with open(scen_path, "w", encoding="utf-8") as fh:
            json.dump(rule_scenario(), fh)
        proc = subprocess.run(
            ["node", RUNTIME_JS, "rule",
             os.path.join(GATE_DIR, "no-such-script.js"),
             store_path, scen_path],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(proc.returncode, 0)

    def test_lastseen_cache_survives_across_requests(self):
        """Two sequential requests share the store: the second sees the
        first run's lastSeen. A clock set back between them then denies."""
        store = lease_store(make_lease(), boot_id="boot-1")
        scen = rule_scenario()
        out1 = self.h.run("rule", RULE_JS, scen, store)
        self.assertEqual(out1["doneValue"], {"matched": True})
        out2 = self.h.run("rule", RULE_JS,
                          rule_scenario(now=NOW - 500), out1["store"])
        self.assertEqual(out2["doneValue"], {"matched": False})

    def test_stale_boot_after_second_reboot(self):
        """Two engine-started runs mint two different boot ids; a lease
        bound to the first boot must deny after the second boot."""
        store = lease_store(make_lease(), boot_id="boot-1")
        scen = {"eventName": "engine-started", "now": NOW,
                "decisions": {GROUP_NAME: "REJECT"}, "network": NETWORK_A}
        out1 = self.h.run("event", EVENTS_JS, scen, store)
        boot2 = out1["store"][BOOT_KEY]
        scen2 = {"eventName": "engine-started", "now": NOW + 5,
                 "decisions": {GROUP_NAME: "REJECT"}, "network": NETWORK_A}
        out2 = self.h.run("event", EVENTS_JS, scen2, out1["store"])
        boot3 = out2["store"][BOOT_KEY]
        self.assertNotEqual(boot2, boot3)
        # Lease issued under boot2 must deny under boot3.
        lease2 = make_lease(boot_id=boot2)
        store3 = lease_store(lease2, boot_id=boot3)
        out3 = self.h.run("rule", RULE_JS,
                          rule_scenario(decisions={GROUP_NAME: "Test-Proxy-1"}),
                          store3)
        self.assertEqual(out3["doneValue"], {"matched": False})

    def test_setselectgrouppolicy_failure_still_revokes_lease(self):
        """Even if setSelectGroupPolicy fails, the event must delete the
        lease (the rule script then denies on no-lease)."""
        store = lease_store(make_lease(), boot_id="boot-1")
        scen = {"eventName": "network-changed", "now": NOW,
                "decisions": {GROUP_NAME: "Test-Proxy-1"},
                "network": NETWORK_A, "surgeSetOk": False}
        out = self.h.run("event", EVENTS_JS, scen, store)
        self.assertNotIn(LEASE_KEY, out["store"])
        self.assertEqual(
            out["surgeCalls"],
            [{"method": "setSelectGroupPolicy",
              "group": GROUP_NAME, "policy": "REJECT"}])


if __name__ == "__main__":
    unittest.main()
