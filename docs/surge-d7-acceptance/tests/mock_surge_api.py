"""Mock Surge HTTP API server for tests (MOCK ONLY — not a real device).

Simulates the subset of the Surge HTTP API the selector controller uses:
  POST /v1/policy_groups/select
  GET  /v1/policy_groups/select?group_name=<name>
  GET  /v1/policy_groups

Behaviour knobs (passed to make_server / set on server.behavior):
  post_status (default 200), get_status (200), groups_status (200),
  post_delay / get_delay (seconds; simulate timeouts),
  post_ignored (POST returns 200 but does not change the selection),
  get_policy_override (GET returns this policy regardless of stored state),
  groups_members (dict group -> [member names]; default TEST members).

The mock records every policy the controller asked to select
(`server.selected_history`) so tests can assert DIRECT was never selected.

MOCK BOUNDARY: this server only mimics the HTTP surface. It proves the
controller's logic against timeouts / errors / mismatches. It does NOT
prove anything about a real phone: real Surge persistence across reboot,
real on-device behaviour after controller loss, and real select-group
semantics must be verified on a real device (see README.md).
"""

from __future__ import annotations

import json
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GROUP_NAME = "测试安全出口"
DEFAULT_MEMBERS = ["Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"]


class MockSurgeServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, behavior=None):
        super().__init__(address, handler)
        self.behavior = dict(behavior or {})
        self.selection: dict[str, str] = {GROUP_NAME: "REJECT"}
        self.selected_history: list[str] = []
        self.lock = threading.Lock()

    def members_for(self, group: str):
        custom = self.behavior.get("groups_members")
        if custom is not None:
            return custom.get(group)
        if group == GROUP_NAME:
            return list(DEFAULT_MEMBERS)
        return None


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

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        behavior = self.server.behavior
        if parsed.path != "/v1/policy_groups/select":
            return self._send_json(404, {"error": "not found"})
        delay = behavior.get("post_delay", 0)
        if delay:
            time.sleep(delay)
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
                time.sleep(delay)
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
    """Start a mock server on an ephemeral port. Returns (server, thread,
    base_url). Caller must call server.shutdown() + server_close()."""
    server = MockSurgeServer((host, port), _Handler, behavior=behavior)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://{host}:{server.server_address[1]}"
    return server, thread, base_url
