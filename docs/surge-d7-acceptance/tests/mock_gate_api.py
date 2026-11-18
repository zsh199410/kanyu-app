"""Mock Surge HTTP API server for the device-gate controller (P0-E).

MOCK ONLY — not a real device. Extends the task-A mock surface with
the scripting endpoints the gate controller uses:

  GET  /v1/policy_groups
  GET  /v1/policy_groups/select?group_name=<name>
  POST /v1/policy_groups/select
  GET  /v1/scripting                  -> {"scripts": [{"name": ...}]}
  GET  /v1/features/scripting         -> {"scripting": bool}
  POST /v1/scripting/evaluate         -> executes script_text in the
       REAL Node mock Surge runtime (tests/mock_surge_runtime.js) so
       controller-generated issue/read/revoke scripts run against a
       shared mock $persistentStore file, exactly as the gate JS does.

Behaviour knobs (passed to make_server / set on server.behavior):
  scripting_enabled (default True), scripts_present (default all gate
  scripts), evaluate_echo (default True: the response carries the
  script's $done() value under "result"; False simulates a real device
  whose evaluate response carries no echo), evaluate_status (200),
  post_status / get_status / groups_status (200), post_delay /
  get_delay / evaluate_delay (seconds), post_ignored, get_policy_override,
  groups_members, store_path (mock $persistentStore JSON file),
  network / decisions (mock $network and select-group decisions fed to
  the Node runtime for evaluate calls).

The mock records every evaluate script_text (server.evaluate_history)
so tests can assert issuance scripts contain lease fields and no
passwords / tokens / URIs.

MOCK BOUNDARY: executing the real JS in Node proves the controller <->
script contract in the mock. It does NOT prove that a real device's
POST /v1/scripting/evaluate persists $persistentStore writes, returns
a $done() echo, or exposes the same /v1/features/scripting response
shape. Those need a real device (see device-gate/README.md).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GROUP_NAME = "测试安全出口"
DEFAULT_MEMBERS = ["Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"]
REQUIRED_SCRIPTS = [
    "gate-rule",
    "gate-events-boot",
    "gate-events-net",
    "gate-events-profile",
    "gate-sweep",
]

_HERE = os.path.dirname(os.path.abspath(__file__))
_RUNTIME_JS = os.path.join(_HERE, "mock_surge_runtime.js")
_REPO_ROOT = os.path.dirname(_HERE)
_GATE_DIR = os.path.join(_REPO_ROOT, "device-gate")


class MockGateServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, behavior=None):
        super().__init__(address, handler)
        self.behavior = dict(behavior or {})
        self.selection: dict[str, str] = {GROUP_NAME: "REJECT"}
        self.selected_history: list[str] = []
        self.evaluate_history: list[str] = []
        self.lock = threading.Lock()
        store_path = self.behavior.get("store_path")
        if store_path:
            self.store_path = store_path
        else:
            fd, self.store_path = tempfile.mkstemp(
                prefix="mock-gate-store-", suffix=".json")
            os.close(fd)
            with open(self.store_path, "w", encoding="utf-8") as fh:
                json.dump({}, fh)
        self._tmpdir = tempfile.mkdtemp(prefix="mock-gate-scenario-")

    def members_for(self, group: str):
        custom = self.behavior.get("groups_members")
        if custom is not None:
            return custom.get(group)
        if group == GROUP_NAME:
            return list(DEFAULT_MEMBERS)
        return None

    def run_evaluate(self, script_text: str):
        """Run script_text in the Node mock runtime against the shared
        store file. Returns (done_value, run_error)."""
        behavior = self.behavior
        scenario = {
            "script_text": script_text,
            "network": behavior.get("network") or {},
            "decisions": dict(self.selection),
            "now": behavior.get("now") or 1700000000,
            "surgeSetOk": behavior.get("evaluate_surge_set_ok", True),
        }
        scen_path = os.path.join(self._tmpdir, f"scen-{len(self.evaluate_history)}.json")
        with open(scen_path, "w", encoding="utf-8") as fh:
            json.dump(scenario, fh)
        proc = subprocess.run(
            ["node", _RUNTIME_JS, "evaluate", "-", self.store_path, scen_path],
            capture_output=True, text=True, timeout=30,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"node mock runtime failed: {proc.stderr[:500]}")
        out = json.loads(proc.stdout)
        if out.get("runError"):
            raise RuntimeError(f"mock script error: {out['runError'][:500]}")
        # Mirror device-side group selection changes back into the mock,
        # but only when the mocked $surge call actually took effect.
        if self.behavior.get("evaluate_surge_set_ok", True):
            for call in out.get("surgeCalls") or []:
                if call.get("method") == "setSelectGroupPolicy":
                    self.selection[call["group"]] = call["policy"]
        return out.get("doneValue"), out.get("runError")


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # silence test output
        pass

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            return {}

    # -- scripting ------------------------------------------------------
    def _handle_evaluate(self):
        behavior = self.server.behavior
        delay = behavior.get("evaluate_delay", 0)
        if delay:
            import time as _time
            _time.sleep(delay)
        status = behavior.get("evaluate_status", 200)
        if status != 200:
            return self._send_json(status, {"error": f"mock evaluate failure {status}"})
        data = self._read_json()
        script_text = data.get("script_text") or ""
        with self.server.lock:
            self.server.evaluate_history.append(script_text)
        try:
            done_value, _err = self.server.run_evaluate(script_text)
        except Exception as exc:  # noqa: BLE001 - mock surface
            return self._send_json(500, {"error": f"mock evaluate error: {exc}"})
        if behavior.get("evaluate_echo", True):
            return self._send_json(200, {"result": done_value})
        return self._send_json(200, {})

    # -- HTTP verbs -------------------------------------------------------
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        behavior = self.server.behavior
        if parsed.path == "/v1/scripting/evaluate":
            return self._handle_evaluate()
        if parsed.path != "/v1/policy_groups/select":
            return self._send_json(404, {"error": "not found"})
        delay = behavior.get("post_delay", 0)
        if delay:
            import time as _time
            _time.sleep(delay)
        status = behavior.get("post_status", 200)
        if status != 200:
            return self._send_json(status, {"error": f"mock POST failure {status}"})
        data = self._read_json()
        group = data.get("group_name")
        policy = data.get("policy")
        with self.server.lock:
            self.server.selected_history.append(policy)
            members = self.server.members_for(group)
            if members is None:
                return self._send_json(404, {"error": "group not found"})
            if policy != "REJECT" and policy not in members:
                return self._send_json(400, {"error": f"unknown policy {policy}"})
            if not behavior.get("post_ignored", False):
                self.server.selection[group] = policy
        return self._send_json(200, {"policy": policy})

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        behavior = self.server.behavior
        if parsed.path == "/v1/features/scripting":
            return self._send_json(200, {"scripting": bool(behavior.get("scripting_enabled", True))})
        if parsed.path == "/v1/scripting":
            names = behavior.get("scripts_present", list(REQUIRED_SCRIPTS))
            return self._send_json(200, {"scripts": [{"name": n} for n in names]})
        if parsed.path == "/v1/policy_groups":
            status = behavior.get("groups_status", 200)
            if status != 200:
                return self._send_json(status, {"error": "mock groups failure"})
            groups = {}
            for group in [GROUP_NAME]:
                members = self.server.members_for(group)
                if members is None:
                    continue
                with self.server.lock:
                    sel = self.server.selection.get(group, "REJECT")
                groups[group] = {"policy": sel, "members": ["REJECT"] + members}
            return self._send_json(200, {"groups": groups})
        if parsed.path == "/v1/policy_groups/select":
            delay = behavior.get("get_delay", 0)
            if delay:
                import time as _time
                _time.sleep(delay)
            status = behavior.get("get_status", 200)
            if status != 200:
                return self._send_json(status, {"error": "mock GET failure"})
            group = (query.get("group_name") or [None])[0]
            override = behavior.get("get_policy_override")
            if override is not None:
                return self._send_json(200, {"policy": override})
            with self.server.lock:
                if group not in self.server.selection:
                    return self._send_json(404, {"error": "group not found"})
                return self._send_json(200, {"policy": self.server.selection[group]})
        return self._send_json(404, {"error": "not found"})


def make_server(behavior=None, host="127.0.0.1", port=0):
    """Start a mock gate server on an ephemeral port. Returns
    (server, thread, base_url). Caller must shutdown() + server_close()."""
    server = MockGateServer((host, port), _Handler, behavior=behavior)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://{host}:{server.server_address[1]}"
    return server, thread, base_url
