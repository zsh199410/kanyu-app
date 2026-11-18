"""Device-gate tests, part 1 (P0-E): happy paths + rule/event/sweep
logic executed as REAL JavaScript under Node, conf audit, controller
issuance.

The JS tests run device-gate/gate-script.js, gate-events.js and
gate-sweep.js in tests/mock_surge_runtime.js (Node vm + mocked Surge
globals). They prove the script LOGIC against scripted inputs. They do
NOT prove real-device behaviour — see device-gate/README.md for the
UNPROVEN list (hot-path $surge availability, http-api evaluate
persistence/echo, event ordering, real evaluate response shape).

Run:  cd tests && python3 -m unittest test_device_gate -v
Logs: tests/logs/device-gate-*.log (written by the test runner command,
not by the tests themselves).
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import mock_gate_api  # noqa: E402
from mock_gate_api import GROUP_NAME  # noqa: E402

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "device-gate"))
import check_gate_conf  # noqa: E402
import importlib.util  # noqa: E402

_SPEC = importlib.util.spec_from_file_location(
    "gate_controller_mod",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "device-gate", "gate-controller.py"),
)
gate_controller = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gate_controller)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
GATE_DIR = os.path.join(REPO, "device-gate")
CONF_PATH = os.path.join(GATE_DIR, "device-gate-test.conf")
RULE_JS = os.path.join(GATE_DIR, "gate-script.js")
EVENTS_JS = os.path.join(GATE_DIR, "gate-events.js")
SWEEP_JS = os.path.join(GATE_DIR, "gate-sweep.js")
RUNTIME_JS = os.path.join(HERE, "mock_surge_runtime.js")

LEASE_KEY = "device-gate-lease-v1"
BOOT_KEY = "device-gate-boot-v1"
LASTSEEN_KEY = "device-gate-lastseen-v1"
EXPECTED_SHA = "0543b83dfdd1b7555afbcb76a7b11643d1662f863352710b6bc7d8badd0afabd"
NOW = 1700000000

NETWORK_A = {
    "wifi": {"ssid": "HomeWiFi", "bssid": "aa:bb:cc:dd:ee:ff"},
    "v4": {"primaryAddress": "192.168.5.10", "primaryInterface": "en0",
           "primaryRouter": "192.168.5.1"},
    "v6": {"primaryAddress": "", "primaryInterface": ""},
    "dns": ["192.168.5.1"],
    "cellular-data": {"carrier": "China Mobile", "radio": "5G"},
}
NETWORK_B = dict(NETWORK_A, wifi={"ssid": "CafeWiFi", "bssid": "11:22:33:44:55:66"})


def py_fingerprint(network: dict) -> str:
    """Python mirror of gate-script.js networkFingerprint (test oracle)."""
    wifi = network.get("wifi") or {}
    v4 = network.get("v4") or {}
    v6 = network.get("v6") or {}
    cell = network.get("cellular-data") or network.get("cellularData") or {}
    parts = [
        "ssid=" + (wifi.get("ssid") or ""),
        "bssid=" + (wifi.get("bssid") or ""),
        "v4addr=" + (v4.get("primaryAddress") or ""),
        "v4if=" + (v4.get("primaryInterface") or ""),
        "v4router=" + (v4.get("primaryRouter") or ""),
        "v6addr=" + (v6.get("primaryAddress") or ""),
        "v6if=" + (v6.get("primaryInterface") or ""),
        "dns=" + ",".join(network.get("dns") or []),
        "carrier=" + (cell.get("carrier") or ""),
        "radio=" + (cell.get("radio") or ""),
    ]
    h = 0x811C9DC5
    for ch in "|".join(parts):
        h ^= ord(ch)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return "fnv1a-%08x" % h


def make_lease(**over):
    lease = {
        "v": 1,
        "proxy": "Test-Proxy-1",
        "candidate_sha": EXPECTED_SHA,
        "issued_at": NOW,
        "expires_at": NOW + 600,
        "ttl_seconds": 600,
        "net_fp": py_fingerprint(NETWORK_A),
        "boot_id": "boot-1",
        "stopped": False,
    }
    lease.update(over)
    return lease


def make_candidates(now=NOW):
    return [
        {"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
         "latency_ms": 120, "tested_at": now - 60},
        {"name": "Test-Proxy-2", "host": "192.0.2.2", "port": 443,
         "latency_ms": 180, "tested_at": now - 60},
        {"name": "Test-Proxy-3", "host": "192.0.2.3", "port": 443,
         "latency_ms": 250, "tested_at": now - 60},
    ]


class NodeHarness:
    """Runs one mock-runtime invocation; owns its temp dir."""

    def __init__(self, test_case):
        self.tmp = tempfile.TemporaryDirectory()
        test_case.addCleanup(self.tmp.cleanup)
        self.dir = self.tmp.name

    def run(self, mode, script_path, scenario, store_seed=None):
        store_path = os.path.join(self.dir, "store.json")
        with open(store_path, "w", encoding="utf-8") as fh:
            json.dump(store_seed or {}, fh)
        scen_path = os.path.join(self.dir, "scenario.json")
        with open(scen_path, "w", encoding="utf-8") as fh:
            json.dump(scenario, fh)
        proc = subprocess.run(
            ["node", RUNTIME_JS, mode, script_path, store_path, scen_path],
            capture_output=True, text=True, timeout=30)
        assert proc.returncode == 0, f"node harness failed: {proc.stderr}"
        out = json.loads(proc.stdout)
        assert out.get("runError") is None, f"JS threw: {out.get('runError')}"
        return out

    def assertEqual(self, a, b, msg=""):
        assert a == b, msg or f"{a!r} != {b!r}"


def rule_scenario(**over):
    scen = {
        "network": NETWORK_A,
        "decisions": {GROUP_NAME: "Test-Proxy-1"},
        "now": NOW,
        "scriptName": "gate-rule",
        "scriptType": "rule",
    }
    scen.update(over)
    return scen


def lease_store(lease, boot_id="boot-1", last_seen=None):
    store = {}
    if lease is not None:
        store[LEASE_KEY] = json.dumps(lease)
    if boot_id is not None:
        store[BOOT_KEY] = boot_id
    if last_seen is not None:
        store[LASTSEEN_KEY] = str(last_seen)
    return store


class TestConfAudit(unittest.TestCase):
    def test_real_conf_passes(self):
        self.assertEqual(check_gate_conf.check_conf(CONF_PATH), [])

    def test_mutations_fail(self):
        with open(CONF_PATH, encoding="utf-8") as fh:
            text = fh.read()
        cases = {
            "direct added": text.replace("FINAL,REJECT", "FINAL,DIRECT"),
            "final changed": text.replace("FINAL,REJECT", "FINAL,Test-Proxy-1"),
            "extra bypass rule": text.replace(
                "SCRIPT,gate-rule,测试安全出口",
                "DOMAIN-SUFFIX,example.com,Test-Proxy-1\nSCRIPT,gate-rule,测试安全出口"),
            "script not first": text.replace(
                "SCRIPT,gate-rule,测试安全出口\nFINAL,REJECT",
                "FINAL,REJECT\nSCRIPT,gate-rule,测试安全出口"),
            "missing network-changed event": "\n".join(
                line for line in text.splitlines()
                if not line.startswith("gate-events-net =")) + "\n",
            "subscription URL added": text.replace(
                "# No external subscription / no MITM in this test profile.",
                "# No external subscription / no MITM in this test profile.\n"
                "subscription = https://example.com/sub.txt"),
            "wrong script filename in URL": text.replace(
                "/gate-script.js", "/evil.js"),
            "http script URL": text.replace(
                "https://muse.ai/files/", "http://muse.ai/files/"),
            "http-api with a non-test key": text.replace(
                "http-api = test123@0.0.0.0:6171",
                "http-api = hunter2@0.0.0.0:6171"),
            "cron too frequent": text.replace('"*/10 * * * *"', '"* * * * *"'),
            "proxy outside test-net": text.replace("192.0.2.1", "203.0.113.1"),
            "wrong password": text.replace("password=test123", "password=hunter2"),
            "group missing reject-first": text.replace(
                "= select, REJECT, Test-Proxy-1", "= select, Test-Proxy-1, REJECT"),
        }
        for name, mutated in cases.items():
            with self.subTest(case=name):
                with tempfile.NamedTemporaryFile("w", suffix=".conf",
                                                delete=False) as fh:
                    fh.write(mutated)
                    path = fh.name
                try:
                    self.assertNotEqual(check_gate_conf.check_conf(path), [],
                                        f"{name} should fail audit")
                finally:
                    os.unlink(path)


class TestRuleScriptJS(unittest.TestCase):
    def setUp(self):
        self.h = NodeHarness(self)

    def run_rule(self, lease, **scen_over):
        store = lease_store(lease, boot_id=scen_over.pop("boot_id", "boot-1"),
                            last_seen=scen_over.pop("last_seen", None))
        return self.h.run("rule", RULE_JS, rule_scenario(**scen_over), store)

    def test_valid_lease_matches(self):
        out = self.run_rule(make_lease())
        self.assertTrue(out["doneCalled"])
        self.assertEqual(out["doneValue"], {"matched": True})
        self.assertEqual(out["store"][LASTSEEN_KEY], str(NOW))

    def test_no_lease_denies(self):
        out = self.run_rule(None)
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_expired_lease_denies(self):
        out = self.run_rule(make_lease(), now=NOW + 601)
        self.assertEqual(out["doneValue"], {"matched": False})
        self.assertTrue(any("lease-expired" in line for line in out["logs"]))

    def test_stopped_denies(self):
        out = self.run_rule(make_lease(stopped=True))
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_sha_mismatch_denies(self):
        out = self.run_rule(make_lease(candidate_sha="0" * 64))
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_proxy_not_allowed_denies(self):
        out = self.run_rule(make_lease(proxy="Evil-Proxy"))
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_network_change_denies(self):
        out = self.run_rule(make_lease(), network=NETWORK_B)
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_boot_mismatch_denies(self):
        out = self.run_rule(make_lease(), boot_id="boot-2")
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_no_boot_id_denies(self):
        out = self.run_rule(make_lease(), boot_id=None)
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_selection_mismatch_denies(self):
        out = self.run_rule(
            make_lease(), decisions={GROUP_NAME: "Test-Proxy-2"})
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_unknown_selection_denies(self):
        out = self.run_rule(make_lease(), decisions={})
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_clock_back_before_issue_denies(self):
        lease = make_lease(issued_at=NOW + 1000, expires_at=NOW + 1600)
        out = self.run_rule(lease)
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_clock_back_vs_lastseen_denies(self):
        out = self.run_rule(make_lease(), last_seen=NOW + 500)
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_corrupt_lease_json_denies(self):
        store = lease_store(None)
        store[LEASE_KEY] = "{not json"
        store[BOOT_KEY] = "boot-1"
        out = self.h.run("rule", RULE_JS, rule_scenario(), store)
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_ttl_inconsistent_denies(self):
        out = self.run_rule(make_lease(expires_at=NOW + 999))
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_bad_lease_version_denies(self):
        out = self.run_rule(make_lease(v=2))
        self.assertEqual(out["doneValue"], {"matched": False})

    def test_fingerprint_parity_python_vs_js(self):
        """networkFingerprint in gate-script.js must equal the Python oracle."""
        prog = (
            "const fs=require('fs'),vm=require('vm');"
            "const src=fs.readFileSync(process.argv[1],'utf-8');"
            "const sb={console:{log(){}},"
            "$persistentStore:{read:()=>null,write:()=>true},"
            "$network:JSON.parse(process.argv[2]),"
            "$script:{startTime:1700000000},"
            "$surge:{selectGroupDetails:()=>({decisions:{}})},"
            "$done:()=>{}};"
            "vm.createContext(sb);vm.runInContext(src,sb);"
            "process.stdout.write(sb.networkFingerprint(sb.$network));"
        )
        proc = subprocess.run(
            ["node", "-e", prog, RULE_JS, json.dumps(NETWORK_A)],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout, py_fingerprint(NETWORK_A))

    def test_js_syntax_parses(self):
        proc = subprocess.run(["node", "--check", RULE_JS],
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        for path in (EVENTS_JS, SWEEP_JS):
            proc = subprocess.run(["node", "--check", path],
                                  capture_output=True, text=True, timeout=30)
            self.assertEqual(proc.returncode, 0, f"{path}: {proc.stderr}")


class TestEventScripts(unittest.TestCase):
    def setUp(self):
        self.h = NodeHarness(self)

    def event(self, name, lease=None, boot_id="boot-1"):
        store = lease_store(lease, boot_id=boot_id, last_seen=NOW)
        scen = {"eventName": name, "now": NOW,
                "decisions": {GROUP_NAME: "Test-Proxy-1"},
                "network": NETWORK_A}
        return self.h.run("event", EVENTS_JS, scen, store)

    def test_engine_started_revokes_and_mints_boot(self):
        out = self.event("engine-started", lease=make_lease())
        self.assertTrue(out["doneCalled"])
        self.assertNotIn(LEASE_KEY, out["store"])
        self.assertNotIn(LASTSEEN_KEY, out["store"])
        new_boot = out["store"].get(BOOT_KEY)
        self.assertTrue(new_boot and new_boot != "boot-1")
        self.assertTrue(new_boot.startswith("boot-"))
        self.assertIn({"method": "setSelectGroupPolicy",
                       "group": GROUP_NAME, "policy": "REJECT"},
                      out["surgeCalls"])

    def test_network_changed_revokes(self):
        out = self.event("network-changed", lease=make_lease())
        self.assertNotIn(LEASE_KEY, out["store"])
        self.assertEqual(out["store"].get(BOOT_KEY), "boot-1")  # boot kept
        self.assertIn({"method": "setSelectGroupPolicy",
                       "group": GROUP_NAME, "policy": "REJECT"},
                      out["surgeCalls"])

    def test_profile_reloaded_revokes(self):
        out = self.event("profile-reloaded", lease=make_lease())
        self.assertNotIn(LEASE_KEY, out["store"])
        self.assertIn({"method": "setSelectGroupPolicy",
                       "group": GROUP_NAME, "policy": "REJECT"},
                      out["surgeCalls"])

    def test_manual_event_preserves_state(self):
        out = self.event("manually", lease=make_lease())
        self.assertIn(LEASE_KEY, out["store"])
        self.assertEqual(out["surgeCalls"], [])

    def test_old_lease_denied_after_reboot(self):
        """Full chain: boot 1 lease valid -> engine-started (boot 2) ->
        the SAME lease must now deny (boot mismatch + lease deleted)."""
        first = self.event("engine-started", lease=make_lease())
        boot2 = first["store"][BOOT_KEY]
        out = self.h.run("rule", RULE_JS,
                         rule_scenario(decisions={GROUP_NAME: "REJECT"}),
                         first["store"])
        self.assertEqual(out["doneValue"], {"matched": False})
        self.assertNotEqual(boot2, "boot-1")


class TestCronSweep(unittest.TestCase):
    def setUp(self):
        self.h = NodeHarness(self)

    def sweep(self, lease, decisions, now=NOW):
        store = lease_store(lease, boot_id="boot-1")
        scen = {"now": now, "decisions": decisions, "network": NETWORK_A}
        return self.h.run("cron", SWEEP_JS, scen, store)

    def test_valid_lease_untouched(self):
        out = self.sweep(make_lease(), {GROUP_NAME: "Test-Proxy-1"})
        self.assertIn(LEASE_KEY, out["store"])
        self.assertEqual(out["surgeCalls"], [])

    def test_expired_lease_revoked_and_reject(self):
        out = self.sweep(make_lease(), {GROUP_NAME: "Test-Proxy-1"},
                         now=NOW + 601)
        self.assertNotIn(LEASE_KEY, out["store"])
        self.assertIn({"method": "setSelectGroupPolicy",
                       "group": GROUP_NAME, "policy": "REJECT"},
                      out["surgeCalls"])

    def test_no_lease_with_proxy_selected_forces_reject(self):
        out = self.sweep(None, {GROUP_NAME: "Test-Proxy-2"})
        self.assertIn({"method": "setSelectGroupPolicy",
                       "group": GROUP_NAME, "policy": "REJECT"},
                      out["surgeCalls"])

    def test_no_lease_already_reject_no_action(self):
        out = self.sweep(None, {GROUP_NAME: "REJECT"})
        self.assertEqual(out["surgeCalls"], [])

    def test_corrupt_lease_revoked(self):
        store = lease_store(None)
        store[LEASE_KEY] = "{broken"
        out = self.h.run("cron", SWEEP_JS,
                         {"now": NOW, "decisions": {GROUP_NAME: "Test-Proxy-1"},
                          "network": NETWORK_A}, store)
        self.assertNotIn(LEASE_KEY, out["store"])
        self.assertIn({"method": "setSelectGroupPolicy",
                       "group": GROUP_NAME, "policy": "REJECT"},
                      out["surgeCalls"])


class _ControllerCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state_path = os.path.join(self.tmp.name, "gate-state.json")
        self.store_path = os.path.join(self.tmp.name, "store.json")
        with open(self.store_path, "w", encoding="utf-8") as fh:
            json.dump({BOOT_KEY: "boot-1"}, fh)
        self.behavior = {
            "store_path": self.store_path,
            "network": NETWORK_A,
            "now": NOW,
        }

    def start_server(self, **over):
        behavior = dict(self.behavior)
        behavior.update(over)
        self.server, self.thread, base_url = mock_gate_api.make_server(behavior)
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.server.server_close)
        return base_url

    def make_controller(self, base_url, **over):
        now_box = {"now": NOW}
        kwargs = dict(
            api_client=gate_controller.SurgeApiClient(base_url),
            state_path=self.state_path,
            allowed_members=["Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"],
            now_fn=lambda: now_box["now"],
        )
        kwargs.update(over)
        ctrl = gate_controller.GateController(**kwargs)
        ctrl._now_box = now_box
        return ctrl


class TestGateControllerIssue(_ControllerCase):
    def test_issue_happy_path_active(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_ACTIVE")
        self.assertTrue(rec["verified"])
        self.assertEqual(rec["selected_policy"], "Test-Proxy-1")
        with open(self.store_path, encoding="utf-8") as fh:
            store = json.load(fh)
        lease = json.loads(store[LEASE_KEY])
        self.assertEqual(lease["proxy"], "Test-Proxy-1")
        self.assertEqual(lease["candidate_sha"], EXPECTED_SHA)
        self.assertEqual(lease["net_fp"], py_fingerprint(NETWORK_A))
        self.assertEqual(lease["boot_id"], "boot-1")
        self.assertEqual(lease["issued_at"], NOW)
        self.assertEqual(lease["expires_at"], NOW + 600)
        self.assertNotIn("DIRECT", self.server.selected_history)
        # No secrets in any evaluated script text.
        for text in self.server.evaluate_history:
            self.assertNotIn("test123", text)
            self.assertNotIn("192.0.2", text)
            self.assertNotIn("password", text)

    def test_issue_no_echo_is_unverified_not_active(self):
        base_url = self.start_server(evaluate_echo=False)
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_ISSUED_UNVERIFIED")
        self.assertFalse(rec["verified"])

    def test_issue_gate_script_missing(self):
        base_url = self.start_server(scripts_present=["gate-rule"])
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "GATE_SCRIPT_MISSING")
        self.assertFalse(rec["verified"])
        self.assertEqual(self.server.selected_history, [])

    def test_issue_scripting_disabled(self):
        base_url = self.start_server(scripting_enabled=False)
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "SCRIPTING_DISABLED")
        self.assertEqual(self.server.selected_history, [])

    def test_issue_sha_mismatch(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), "f" * 64)
        self.assertEqual(rec["state"], "GATE_UNKNOWN")
        self.assertEqual(self.server.selected_history, [])

    def test_issue_stop_flag(self):
        stop_path = os.path.join(self.tmp.name, "STOP")
        with open(stop_path, "w") as fh:
            fh.write("stop")
        base_url = self.start_server()
        ctrl = self.make_controller(base_url, stop_path=stop_path)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "STOPPED")
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")

    def test_revoke_after_issue(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.issue_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_ACTIVE")
        rec = ctrl.revoke_lease("test revoke")
        self.assertEqual(rec["state"], "LEASE_REVOKED")
        self.assertTrue(rec["verified"])
        self.assertEqual(self.server.selection[GROUP_NAME], "REJECT")
        with open(self.store_path, encoding="utf-8") as fh:
            self.assertNotIn(LEASE_KEY, json.load(fh))

    def test_check_status_active_then_expired(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        self.assertEqual(ctrl.issue_lease(make_candidates(), EXPECTED_SHA)["state"],
                         "LEASE_ACTIVE")
        self.assertEqual(ctrl.check_lease_status()["state"], "LEASE_ACTIVE")
        ctrl._now_box["now"] = NOW + 601
        rec = ctrl.check_lease_status()
        self.assertEqual(rec["state"], "LEASE_EXPIRED")

    def test_startup_reverify_no_prior_state(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        rec = ctrl.startup_reverify()
        self.assertEqual(rec["state"], "NO_LEASE")

    def test_startup_reverify_reconfirms_active(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        self.assertEqual(ctrl.issue_lease(make_candidates(), EXPECTED_SHA)["state"],
                         "LEASE_ACTIVE")
        ctrl2 = self.make_controller(base_url)  # fresh process, same state file
        rec = ctrl2.startup_reverify()
        self.assertEqual(rec["state"], "LEASE_ACTIVE")
        self.assertTrue(rec["verified"])

    def test_renew_reissues_with_new_timestamps(self):
        base_url = self.start_server()
        ctrl = self.make_controller(base_url)
        self.assertEqual(ctrl.issue_lease(make_candidates(), EXPECTED_SHA)["state"],
                         "LEASE_ACTIVE")
        ctrl._now_box["now"] = NOW + 300
        rec = ctrl.renew_lease(make_candidates(), EXPECTED_SHA)
        self.assertEqual(rec["state"], "LEASE_ACTIVE")
        with open(self.store_path, encoding="utf-8") as fh:
            lease = json.loads(json.load(fh)[LEASE_KEY])
        self.assertEqual(lease["issued_at"], NOW + 300)
        self.assertEqual(lease["expires_at"], NOW + 900)


if __name__ == "__main__":
    unittest.main()
