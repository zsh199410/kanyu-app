#!/usr/bin/env python3
"""Desktop lease issuer for the device-gate test (P0-E).

Run this on a computer on the SAME Wi-Fi/LAN as the phone, WHILE the
phone is on the device-gate-test profile (device-gate-test.conf loaded).

  python gate-issue-desktop.py [phone_ip]

Default phone_ip is 192.168.5.13. The phone's Surge HTTP API must be
reachable at http://<phone_ip>:6171 with key test123 (the test profile
sets http-api = test123@127.0.0.1:6171).

What it does (one shot, no loop):
  1. Verifies the gate scripts are loaded on the phone
     (GET /v1/features/scripting, GET /v1/scripting).
  2. Verifies the gated group "Test security exit" is loaded with
     exactly REJECT + Test-Proxy-1/2/3.
  3. Selects the lowest-latency healthy test proxy in that group.
  4. Issues a 10-minute lease (bound on-device to the current network
     fingerprint + boot id) and reads it back to confirm LEASE_ACTIVE.

The test proxies are TEST-NET 192.0.2.1-3 (fake, unreachable by design):
a lease being ACTIVE only proves the gate ADMITS the request; the
browser will still fail to load example.com because the test proxy
itself does not exist. The proof is in Surge's request log: the entry
must show the test proxy name (not REJECT).

Real-device fix vs the mock-tested controller: the real Surge HTTP API
requires an X-Key header. gate-controller.py's default urllib client
does not send one (the mock server never required auth), so this runner
injects a request_fn that adds X-Key: test123. That is the only
difference from the library's own client.

Exit code 0 + "LEASE_ACTIVE" means the lease is live. Anything else
prints the controller state and reason; do NOT retry blindly.
"""

import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CTRL_PATH = os.path.join(HERE, "gate-controller.py")

PHONE_IP = sys.argv[1] if len(sys.argv) > 1 else None
BASE_URL = None  # set after discovery
API_KEY = "test123"  # test key from device-gate-test.conf (not a real secret)


def _probe(ip, port=6171, timeout=1.0):
    """True if ip:port accepts a TCP connection (Surge HTTP API host)."""
    import socket
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def discover_phone(subnet="192.168.5", lo=2, hi=254):
    """Scan the LAN for a host listening on 6171 (the phone)."""
    import concurrent.futures
    ips = ["%s.%d" % (subnet, i) for i in range(lo, hi + 1)]
    found = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=40) as pool:
        futs = {pool.submit(_probe, ip): ip for ip in ips}
        for fut in concurrent.futures.as_completed(futs):
            if fut.result():
                found.append(futs[fut])
    return sorted(found)

# Test candidates (TEST-NET only, by construction). Latency values are
# synthetic placeholders for the fake proxies; the controller picks the
# lowest. Evidence timestamps are set to "now" so the 24h freshness
# check passes. These are NOT real measurements.
NOW = time.time()
CANDIDATES = [
    {"name": "Test-Proxy-1", "host": "192.0.2.1", "port": 443,
     "latency_ms": 50, "tested_at": NOW},
    {"name": "Test-Proxy-2", "host": "192.0.2.2", "port": 443,
     "latency_ms": 60, "tested_at": NOW},
    {"name": "Test-Proxy-3", "host": "192.0.2.3", "port": 443,
     "latency_ms": 70, "tested_at": NOW},
]


def request_fn(method, url, body, timeout):
    """urllib request that adds the Surge HTTP API key header."""
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Key", API_KEY)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise RuntimeError("connect failed: %s" % exc)


def resolve_phone():
    """Return the phone's base URL. Uses the argv IP if it answers on
    6171, otherwise scans the LAN (the phone's DHCP address moves)."""
    global BASE_URL
    candidates = []
    if PHONE_IP:
        candidates.append(PHONE_IP)
    if not candidates or not _probe(candidates[0]):
        print("scanning LAN for the phone (port 6171) ...")
        found = discover_phone()
        print("hosts listening on 6171: %s" % (found or "none"))
        for ip in found:
            if ip not in candidates:
                candidates.append(ip)
    if not candidates:
        return None
    BASE_URL = "http://%s:6171" % candidates[0]
    return BASE_URL


def main():
    spec = importlib.util.spec_from_file_location("gate_controller", CTRL_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    base = resolve_phone()
    if base is None:
        print("RESULT: PHONE_NOT_FOUND — no host on 192.168.5.x:6171.")
        print("Check the phone is on the test profile and on Wi-Fi,")
        print("then run again (optionally: python gate-issue-desktop.py <ip>).")
        return 1
    print("phone: %s" % base)
    print("profile must be device-gate-test (gate scripts loaded)")
    api = mod.SurgeApiClient(BASE_URL, request_fn=request_fn, timeout=10.0)
    state_path = os.path.join(HERE, "gate-state-desktop.json")
    ctrl = mod.GateController(
        api_client=api,
        state_path=state_path,
        allowed_members=["Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"],
    )
    record = ctrl.issue_lease(CANDIDATES)
    print(json.dumps(record, ensure_ascii=False, indent=2))
    state = record.get("state")
    if state == "LEASE_ACTIVE":
        print("RESULT: LEASE_ACTIVE — lease live for 10 min.")
        print("Now open example.com on the phone; the request log must")
        print("show the test proxy name (not REJECT).")
        return 0
    print("RESULT: %s — %s" % (state, record.get("reason", "")))
    return 1


if __name__ == "__main__":
    sys.exit(main())
