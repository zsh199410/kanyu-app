#!/usr/bin/env python3
"""P0-4 staged deploy / rollback interop matrix for the #73 dual-channel
(B1) probe patch (GPT #6938432964, five precise gates; GPT #6940445042
P0-1 snapshot race, P0-3 staged-script/runbook alignment).

Stages, all with REAL HTTP through a simulated nginx layer (a tiny
reverse proxy in this file) and one shared isolated DB + fixture pool:
  (1) baseline: OLD service + OLD script client (legacy cellular)
  (2) swap service first: NEW service + OLD nginx + OLD script client
  (3) add nginx: NEW service + NEW nginx + OLD script client
      (wifi endpoint becomes reachable; old script never calls it)
  (4) old+new script compat: NEW service + NEW nginx + BOTH clients
      (legacy cellular + ISOLATED new script, played by this harness —
      in production the phone still runs the OLD script at this stage,
      so production wifi REPORTS are NOT part of stage 4; they belong
      to stage 5) + abuse checks
  (5) finally swap script: NEW service + NEW nginx, new script only
      (the harness now plays the phone AFTER the swap: production wifi
      reports arrive here, not in stage 4)
  (R) reverse-order rollback: old script -> old nginx -> old service

Per stage the test records real HTTP statuses, the cellular tables SHA
and a stable cellular-stats snapshot before/after the stage's wifi-only
operations (wifi traffic must NEVER change the cellular tables/stats).
The conventional rollback keeps the wifi tables for audit; DROP TABLE
is FORBIDDEN as a rollback step (GPT #6938432964 gate 5 — the earlier
"optional thorough cleanup" is void) and the test asserts the rollback
script contains no DROP TABLE.

TestDeployScriptStages additionally covers the deploy script itself
(GPT #6940445042 P0-3): the stage argument is required, stages 1 and
4 run alone against the simulated service/proxy and stop, stage 5
fails closed without a private render config, and stage 5 renders +
deploys with the RENDERED product SHA (never the desensitized input
SHA). TestRotationFaultInjection covers the P0-1 race at the HTTP
level: the pool rotates between the snapshot read and the GET tasks
return, and the response must still carry the batch-locked SHA.

Runs in-process (ThreadingHTTPServer on ephemeral ports) so it works in
all four environments (local/VPS x root/non-root). Stdlib only.
"""
import hashlib
import http.client
import json
import os
import re
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SERVICE_DIR = os.path.join(ROOT, "service")
FIXTURE_POOL = os.path.join(ROOT, "fixtures", "pool-fixture.txt")
DUAL_JS = os.path.join(ROOT, "script", "probe-task-dual.js")
ROLLBACK_SH = os.path.join(ROOT, "tools", "rollback_dual.sh")

sys.path.insert(0, SERVICE_DIR)
import probe_service_dual as dual  # noqa: E402
import probe_service_orig as orig  # noqa: E402

TEST_SEG = "testseg12345678"
CLIENT_VERSION = re.search(
    r"const CLIENT_VERSION = '(dual-v1-[0-9a-f]{12})';",
    open(DUAL_JS, encoding="utf-8").read()).group(1)
POOL_SHA = hashlib.sha256(open(FIXTURE_POOL, "rb").read()).hexdigest()
NOW = int(time.time())


def dump_tables(db_path, tables):
    conn = sqlite3.connect(db_path)
    out = {}
    for t in tables:
        rows = conn.execute(f"SELECT * FROM {t} ORDER BY 1, 2").fetchall()
        out[t] = [list(r) for r in rows]
    conn.close()
    return out


def tables_hash(db_path, tables):
    return hashlib.sha256(
        json.dumps(dump_tables(db_path, tables), sort_keys=True).encode()
    ).hexdigest()


def legacy_result(fp, name, ts, success, second_ms, iface="pdp_ip0"):
    return {
        "fingerprint": fp, "name": name, "ts": ts,
        "state": "measured" if success else "first_failed",
        "warm_ms": 120, "second_request_ms": second_ms,
        "second_status": 204 if success else None,
        "success": success, "error": None, "interface": iface,
    }


def new_result(fp, name, ts, success, second_ms, network_type, batch_id, sha=None):
    """New-style client result: bound to the task batch the server locked
    at issuance (P0-1 snapshot binding). sha defaults to the fixture
    pool SHA, which is the locked snapshot SHA of the test batches."""
    return {
        "fingerprint": fp, "name": name, "ts": ts,
        "state": "measured" if success else "first_failed",
        "warm_ms": 120, "second_request_ms": second_ms,
        "second_status": 204 if success else None,
        "success": success, "error": None,
        "network_type": network_type,
        "source_version_sha": POOL_SHA if sha is None else sha,
        "batch_id": batch_id,
        "client_version": CLIENT_VERSION,
    }


def start_service(module, base, pool):
    module.BASE = base
    module.DB_PATH = os.path.join(base, "data", "probe.db")
    module.POOL_TXT = pool
    srv = ThreadingHTTPServer(("127.0.0.1", 0), module.Handler)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    return srv, srv.server_address[1]


class _Proxy(BaseHTTPRequestHandler):
    """Simulated nginx layer. Class attrs set per stage:
    target_port, seg, wifi_enabled."""
    target_port = 0
    seg = TEST_SEG
    wifi_enabled = False

    def log_message(self, *a):
        pass

    def _reply(self, code, body_bytes, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def _handle(self):
        path = urlparse(self.path).path
        if path == "/" + self.seg + "-wifi" and not self.wifi_enabled:
            # Old nginx: no -wifi location -> 404, never reaches the service.
            return self._reply(404, json.dumps(
                {"ok": False, "error": "not found (old nginx: no wifi location)"}
            ).encode())
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length > 0 else None
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host", "content-length", "connection")}
        if body is not None:
            headers["Content-Length"] = str(len(body))
        conn = http.client.HTTPConnection("127.0.0.1", self.target_port, timeout=10)
        conn.request(self.command, self.path, body=body, headers=headers)
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        self._reply(resp.status, data,
                    resp.getheader("Content-Type") or "application/json")

    do_GET = _handle
    do_POST = _handle


def start_proxy(target_port, wifi_enabled):
    _Proxy.target_port = target_port
    _Proxy.seg = TEST_SEG
    _Proxy.wifi_enabled = wifi_enabled
    srv = ThreadingHTTPServer(("127.0.0.1", 0), _Proxy)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    return srv, srv.server_address[1]


class MatrixBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dual-matrix-")
        self.base = os.path.join(self.tmp, "probe")
        os.makedirs(os.path.join(self.base, "config"), exist_ok=True)
        os.makedirs(os.path.join(self.base, "data"), exist_ok=True)
        with open(os.path.join(self.base, "config", "probe-path.txt"), "w") as f:
            f.write(TEST_SEG)
        self.pool = os.path.join(self.tmp, "pool.txt")
        with open(self.pool, "w") as f:
            f.write(open(FIXTURE_POOL, encoding="utf-8").read())
        self.db_path = os.path.join(self.base, "data", "probe.db")
        dual.BASE = self.base
        dual.DB_PATH = self.db_path
        dual.POOL_TXT = self.pool
        orig.BASE = self.base
        orig.DB_PATH = self.db_path
        orig.POOL_TXT = self.pool
        dual.sync_pool()
        dual.sync_pool_wifi()
        self.servers = []
        self.stage_log = []

    def tearDown(self):
        for srv in self.servers:
            try:
                srv.shutdown()
                srv.server_close()
            except Exception:
                pass
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _serve(self, module, wifi_enabled):
        srv, port = start_service(module, self.base, self.pool)
        self.servers.append(srv)
        proxy, pport = start_proxy(port, wifi_enabled)
        self.servers.append(proxy)
        return pport, port

    def _req(self, port, method, channel, action=None, results=None,
             net_hdr=None, raw_body=None, raw_headers=None):
        url = f"/{TEST_SEG}" + ("-wifi" if channel == "wifi" else "")
        headers = {}
        if action:
            headers["X-Probe-Action"] = action
        if net_hdr:
            headers["X-Probe-Network"] = net_hdr
        if raw_headers:
            headers.update(raw_headers)
        body = raw_body
        if results is not None:
            body = json.dumps({"results": results}).encode()
            headers["Content-Type"] = "application/json"
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.request(method, url, body=body, headers=headers)
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        try:
            parsed = json.loads(data.decode())
        except Exception:
            parsed = {"_raw": data[:200].decode("utf-8", "replace")}
        return resp.status, parsed

    def _cell_sha(self):
        return tables_hash(self.db_path, ["probe_reports", "probe_nodes"])

    def _cell_stats(self):
        """Stable cellular-stats subset (excludes avg_alive_seconds,
        which is time-varying). Used to prove wifi ops never move
        cellular stats."""
        code, body = self._req(self._cur_proxy, "GET", "cellular", action="stats")
        self.assertEqual(code, 200, body)
        return {k: body[k] for k in
                ("total", "states", "verified", "tested_hour", "tested_day",
                 "qualified_day")}

    def _fps(self, n=12):
        conn = sqlite3.connect(self.db_path)
        rows = conn.execute(
            "SELECT fingerprint, name FROM probe_nodes ORDER BY name").fetchall()
        conn.close()
        return rows[:n]

    def _wifi_row_count(self):
        conn = sqlite3.connect(self.db_path)
        n = conn.execute("SELECT COUNT(*) FROM probe_reports_wifi").fetchone()[0]
        conn.close()
        return n

    def _log(self, stage, **kw):
        entry = {"stage": stage}
        entry.update(kw)
        self.stage_log.append(entry)

    def _new_client_round(self, port, channel, ts, success=True, second_ms=95):
        """New-style client flow: GET tasks (locks a batch), then report
        the first task with its batch binding. Returns
        (report_body, task, batch_id)."""
        code, body = self._req(port, "GET", channel, action="tasks",
                               net_hdr=channel if channel == "wifi" else None)
        self.assertEqual(code, 200, body)
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA)
        self.assertRegex(body["info"]["batch_id"], r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(body["tasks"]), 0, body)
        t = body["tasks"][0]
        code, rbody = self._req(port, "POST", channel, results=[
            new_result(t["fingerprint"], t["name"], ts, success, second_ms,
                       channel, body["info"]["batch_id"])],
            net_hdr="wifi" if channel == "wifi" else None)
        self.assertEqual(code, 200, rbody)
        return rbody, t, body["info"]["batch_id"]

    def _stop_all(self):
        for srv in self.servers:
            try:
                srv.shutdown()
                srv.server_close()
            except Exception:
                pass
        self.servers = []


class TestDeployMatrix(MatrixBase):
    def test_P04_full_matrix(self):
        # Guard the first minute of an hour (timestamps must stay inside
        # the current clock hour for the cap checks below).
        now = int(time.time())
        if now % 3600 < 60:
            time.sleep(61 - (now % 3600))
        ts = int(time.time()) - 120
        fps = self._fps(12)

        # ---- Stage 1: BASELINE — old service + old nginx + old script ----
        proxy_port, svc_port = self._serve(orig, wifi_enabled=False)
        self._cur_proxy = proxy_port
        base_cell_sha = self._cell_sha()
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        self.assertGreater(len(body["tasks"]), 0, body)
        # orig service has no pool_sha / batch_id in info (legacy behaviour)
        self.assertNotIn("pool_sha", body["info"])
        self.assertNotIn("batch_id", body["info"])
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[0][0], fps[0][1], ts, False, None)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        # wifi path is unreachable through old nginx: 404, never forwarded
        code, _ = self._req(proxy_port, "GET", "wifi", action="tasks",
                            net_hdr="wifi")
        self.assertEqual(code, 404)
        code, _ = self._direct(svc_port, "GET", "wifi", action="tasks",
                               net_hdr="wifi")
        self.assertEqual(code, 404)
        base_cell_stats = self._cell_stats()
        conn = sqlite3.connect(self.db_path)
        self.assertEqual(conn.execute(
            "SELECT COUNT(*) FROM probe_reports_wifi").fetchone()[0], 0)
        conn.close()
        self._log("1-baseline", cell_tasks=200, cell_report=200,
                  wifi_tasks=404, wifi_direct=404,
                  cell_sha=base_cell_sha[:12])
        self._stop_all()

        # ---- Stage 2: SWAP SERVICE FIRST — new service + old nginx + old script ----
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=False)
        self._cur_proxy = proxy_port
        before = self._cell_sha()
        before_stats = self._cell_stats()
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA)
        self.assertRegex(body["info"]["batch_id"], r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(body["tasks"]), 0, body)
        # FAILURE on purpose: three fast cellular successes would trip
        # REPLENISH_TARGET and make later stages' tasks GETs legitimately
        # answer target_met instead of ok.
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[1][0], fps[1][1], ts + 2, False, None)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        # wifi still 404 at the old nginx layer (service swap alone does
        # not expose it); cellular tables changed ONLY by the intended
        # cellular ingest
        code, _ = self._req(proxy_port, "GET", "wifi", action="tasks",
                            net_hdr="wifi")
        self.assertEqual(code, 404)
        code, _ = self._req(proxy_port, "POST", "wifi", results=[
            new_result(fps[2][0], fps[2][1], ts + 3, True, 110, "wifi",
                       "b-0000000000000000")],
            net_hdr="wifi")
        self.assertEqual(code, 404)
        mid = self._cell_sha()
        self.assertNotEqual(before, mid, "cellular ingest did not land")
        self.assertEqual(self._cell_stats()["tested_day"],
                         before_stats["tested_day"] + 1)
        self._log("2-swap-service", cell_tasks=200, cell_report=200,
                  wifi_tasks=404, wifi_report=404)
        self._stop_all()

        # ---- Stage 3: ADD NGINX — new service + new nginx + old script ----
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=True)
        self._cur_proxy = proxy_port
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        # FAILURE on purpose (see stage 2): keep qualified_hour < 3 so
        # later stages can still fetch cellular tasks.
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[2][0], fps[2][1], ts + 4, False, None)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        # wifi endpoint is now reachable at the HTTP level (old script
        # never calls it, but the route exists and answers with a batch).
        # Capture the cellular baseline AFTER the intended cellular
        # ingest, then prove the wifi tasks GET alone moves nothing.
        # NOTE: stats() runs sync_pool(), which rewrites updated_at, so
        # the stats snapshot is always taken BEFORE the SHA baseline.
        before_stats = self._cell_stats()
        before = self._cell_sha()
        code, body = self._req(proxy_port, "GET", "wifi", action="tasks",
                               net_hdr="wifi")
        self.assertEqual(code, 200, body)
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA)
        self.assertRegex(body["info"]["batch_id"], r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(body["tasks"]), 0, body)
        after = self._cell_sha()
        after_stats = self._cell_stats()
        self.assertEqual(before, after,
                         "wifi tasks GET changed cellular tables")
        self.assertEqual(before_stats, after_stats,
                         "wifi tasks GET changed cellular stats")
        self._log("3-add-nginx", cell_tasks=200, cell_report=200,
                  wifi_tasks=200)
        self._stop_all()

        # ---- Stage 4: OLD+NEW SCRIPT COMPAT — both clients live ----
        # NOTE (GPT #6940445042 P0-3): the wifi round trip below is the
        # ISOLATED new-script simulation — this harness plays the new
        # client. In production the phone still runs the OLD script at
        # this stage, so production wifi REPORTS are NOT part of stage 4;
        # they are verified in stage 5, after the script swap.
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=True)
        self._cur_proxy = proxy_port
        # old script (legacy cellular) still works; FAILURE on purpose
        # (see stage 2) so the new-style cellular round below can still
        # fetch tasks.
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[3][0], fps[3][1], ts + 5, False, None)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        # new script on wifi: full tasks -> report round trip
        # NOTE: stats() runs sync_pool(), which rewrites updated_at, so
        # the stats snapshot is always taken BEFORE the SHA baseline.
        before_stats = self._cell_stats()
        before_wifi = self._cell_sha()
        rbody, wifi_task, wifi_batch = self._new_client_round(
            proxy_port, "wifi", ts + 6, success=True, second_ms=95)
        self.assertEqual(rbody["accepted"], 1, rbody)
        after_wifi = self._cell_sha()
        after_stats = self._cell_stats()
        self.assertEqual(before_wifi, after_wifi,
                         "wifi report changed cellular tables")
        self.assertEqual(before_stats, after_stats,
                         "wifi report changed cellular stats")
        # remember the first wifi report for the duplicate replay below
        self._wifi_first = (wifi_task, ts + 6, wifi_batch)
        # new script on cellular: batch-bound report also works
        rbody, _t, _b = self._new_client_round(proxy_port, "cellular", ts + 7,
                                               success=True, second_ms=105)
        self.assertEqual(rbody["accepted"], 1, rbody)
        self.assertEqual(self._wifi_row_count(), 1,
                         "wifi rows changed by cellular report")
        self._log("4-compat", legacy_cell=200, wifi_new=200, cell_new=200)
        self._stop_all()

        # ---- Stage 5: FINALLY SWAP SCRIPT — new script only ----
        # Production wifi reports arrive HERE (after the swap): the
        # harness now plays the phone with the new script.
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=True)
        self._cur_proxy = proxy_port
        # NOTE: stats() runs sync_pool(), which rewrites updated_at, so
        # the stats snapshot is always taken BEFORE the SHA baseline.
        before_stats = self._cell_stats()
        before = self._cell_sha()
        rbody, _t, _b = self._new_client_round(proxy_port, "wifi", ts + 9,
                                               success=True, second_ms=88)
        self.assertEqual(rbody["accepted"], 1, rbody)
        after = self._cell_sha()
        after_stats = self._cell_stats()
        self.assertEqual(before, after,
                         "stage-5 wifi report changed cellular tables")
        self.assertEqual(before_stats, after_stats,
                         "stage-5 wifi report changed cellular stats")
        rbody, _t, _b = self._new_client_round(proxy_port, "cellular", ts + 10,
                                               success=True, second_ms=92)
        self.assertEqual(rbody["accepted"], 1, rbody)
        self._log("5-swap-script", wifi_new=200, cell_new=200)
        self._stop_all()

        # ---- Stage 6: ABUSE — wifi-path abuse must not touch cellular ----
        # (placed after stage 5 because the flood below trips the wifi
        # hour cap, after which no further wifi tasks can be issued in
        # this hour)
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=True)
        self._cur_proxy = proxy_port
        # NOTE: stats() runs sync_pool(), which rewrites updated_at, so
        # the stats snapshot is always taken BEFORE the SHA baseline.
        abuse_stats = self._cell_stats()
        abuse_before = self._cell_sha()
        # malformed JSON
        code, _ = self._req(proxy_port, "POST", "wifi",
                            raw_body=b"{not json",
                            raw_headers={"Content-Type": "application/json",
                                         "X-Probe-Network": "wifi"})
        self.assertEqual(code, 400)
        # oversized body
        code, _ = self._req(proxy_port, "POST", "wifi",
                            raw_body=b"x" * 70000,
                            raw_headers={"Content-Type": "application/json",
                                         "X-Probe-Network": "wifi"})
        self.assertEqual(code, 400)
        # wifi-labelled record on the cellular path
        code, _ = self._req(proxy_port, "POST", "cellular", results=[
            new_result(fps[4][0], fps[4][1], ts + 8, True, 100, "wifi",
                       "b-0000000000000000")])
        self.assertEqual(code, 400)
        # header/path mismatch
        code, _ = self._req(proxy_port, "GET", "wifi", action="tasks",
                            net_hdr="cellular")
        self.assertEqual(code, 400)
        # duplicate wifi report counted once: replay the stage-4 wifi
        # report exactly (same fingerprint + ts + batch) -> duplicate
        wt, wts, wbatch = self._wifi_first
        dup = new_result(wt["fingerprint"], wt["name"], wts, True, 95,
                         "wifi", wbatch)
        code, body = self._req(proxy_port, "POST", "wifi", results=[dup],
                               net_hdr="wifi")
        self.assertEqual(code, 200, body)
        self.assertEqual(body["duplicates"], 1, body)
        abuse_after = self._cell_sha()
        abuse_after_stats = self._cell_stats()
        self.assertEqual(abuse_before, abuse_after,
                         "wifi-path abuse changed cellular tables")
        self.assertEqual(abuse_stats, abuse_after_stats,
                         "wifi-path abuse changed cellular stats")
        # cellular still fully functional after the abuse
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        self.assertGreater(len(body["tasks"]), 0, body)
        # wifi hour cap does not consume the cellular budget: flood the
        # wifi path with 20 bound reports (one batch, its own task set,
        # distinct ts per report), then cellular tasks must still flow.
        now = int(time.time())
        if now % 3600 < 60:
            time.sleep(61 - (now % 3600))
            now = int(time.time())
        hour_start = now - (now % 3600)
        base = max(hour_start + 1, now - 300)
        code, body = self._req(proxy_port, "GET", "wifi", action="tasks",
                               net_hdr="wifi")
        self.assertEqual(code, 200, body)
        flood_batch = body["info"]["batch_id"]
        flood_tasks = body["tasks"]
        self.assertGreater(len(flood_tasks), 0, body)
        flood = []
        for i in range(20):
            t = flood_tasks[i % len(flood_tasks)]
            flood.append(new_result(t["fingerprint"], t["name"], base + i,
                                    i % 3 != 0, 200, "wifi", flood_batch))
        for j in range(0, len(flood), 8):
            code, body = self._req(proxy_port, "POST", "wifi",
                                   results=flood[j:j + 8], net_hdr="wifi")
            self.assertEqual(code, 200, body)
        code, body = self._req(proxy_port, "GET", "wifi", action="tasks",
                               net_hdr="wifi")
        self.assertEqual(code, 200, body)
        self.assertEqual(body["tasks"], [])
        self.assertEqual(body["info"]["reason"], "wifi_hour_cap_reached")
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        self.assertGreater(len(body["tasks"]), 0, body)
        self._log("6-abuse", malformed=400, oversized=400, wrong_channel=400,
                  mismatch=400, duplicate=1, wifi_cap="reached",
                  cellular_still_ok=True)
        self._stop_all()

        # ---- Rollback R1: restore OLD script (new service still in place) ----
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=True)
        self._cur_proxy = proxy_port
        # wifi rows at rollback start (stage 6 flood included): the
        # rollback must preserve all of them.
        wifi_rows_before = self._wifi_row_count()
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[5][0], fps[5][1], ts + 11, True, 115)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        self.assertEqual(self._wifi_row_count(), wifi_rows_before,
                         "rollback to old script lost wifi rows")
        self._log("R1-old-script", cell_tasks=200, cell_report=200,
                  wifi_rows_preserved=True)
        self._stop_all()

        # ---- Rollback R2: remove nginx wifi location ----
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=False)
        self._cur_proxy = proxy_port
        code, _ = self._req(proxy_port, "GET", "wifi", action="tasks",
                            net_hdr="wifi")
        self.assertEqual(code, 404)
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[6][0], fps[6][1], ts + 12, True, 125)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        self.assertEqual(self._wifi_row_count(), wifi_rows_before,
                         "nginx rollback lost wifi rows")
        self._log("R2-old-nginx", wifi_tasks=404, cell_tasks=200,
                  cell_report=200, wifi_rows_preserved=True)
        self._stop_all()

        # ---- Rollback R3: restore OLD service ----
        proxy_port, svc_port = self._serve(orig, wifi_enabled=False)
        self._cur_proxy = proxy_port
        code, body = self._req(proxy_port, "GET", "cellular", action="tasks")
        self.assertEqual(code, 200, body)
        self.assertNotIn("pool_sha", body["info"])
        code, body = self._req(proxy_port, "POST", "cellular", results=[
            legacy_result(fps[7][0], fps[7][1], ts + 13, True, 135)])
        self.assertEqual(code, 200, body)
        self.assertEqual(body["accepted"], 1, body)
        # wifi path 404s at the nginx layer AND at the old service itself
        code, _ = self._req(proxy_port, "GET", "wifi", action="tasks",
                            net_hdr="wifi")
        self.assertEqual(code, 404)
        code, _ = self._direct(svc_port, "GET", "wifi", action="tasks",
                               net_hdr="wifi")
        self.assertEqual(code, 404)
        # wifi tables retained for audit; cellular verified count intact
        self.assertEqual(self._wifi_row_count(), wifi_rows_before,
                         "service rollback dropped wifi rows")
        code, body = self._req(proxy_port, "GET", "cellular", action="stats")
        self.assertEqual(code, 200, body)
        self.assertGreaterEqual(body["verified"], 1, body)
        self._log("R3-old-service", cell_tasks=200, cell_report=200,
                  wifi_tasks=404, wifi_rows_preserved=True,
                  verified=body["verified"])
        self._stop_all()

        # ---- Gate 5: DROP TABLE is forbidden as a rollback step ----
        rollback_src = open(ROLLBACK_SH, encoding="utf-8").read()
        self.assertNotIn("DROP TABLE", rollback_src,
                         "rollback script still offers DROP TABLE")
        self.assertNotIn("drop table", rollback_src.lower(),
                         "rollback script still offers DROP TABLE")
        # the rollback script must state that wifi tables are kept
        self.assertIn("wifi", rollback_src.lower())
        # full stage log is complete: 5 stages + abuse + 3 rollback steps
        stages = [e["stage"] for e in self.stage_log]
        self.assertEqual(stages, ["1-baseline", "2-swap-service",
                                  "3-add-nginx", "4-compat",
                                  "5-swap-script", "6-abuse",
                                  "R1-old-script", "R2-old-nginx",
                                  "R3-old-service"])

    def _direct(self, port, method, channel, action=None, results=None,
                net_hdr=None):
        url = f"/{TEST_SEG}" + ("-wifi" if channel == "wifi" else "")
        headers = {}
        if action:
            headers["X-Probe-Action"] = action
        if net_hdr:
            headers["X-Probe-Network"] = net_hdr
        body = None
        if results is not None:
            body = json.dumps({"results": results}).encode()
            headers["Content-Type"] = "application/json"
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.request(method, url, body=body, headers=headers)
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        try:
            parsed = json.loads(data.decode())
        except Exception:
            parsed = {"_raw": data[:200].decode("utf-8", "replace")}
        return resp.status, parsed

    def _stop_all(self):
        for srv in self.servers:
            try:
                srv.shutdown()
                srv.server_close()
            except Exception:
                pass
        self.servers = []


class TestRotationFaultInjection(MatrixBase):
    def test_P01_rotation_between_snapshot_and_get_return_http(self):
        # GPT #6940445042 P0-1, HTTP level: the pool rotates AFTER the
        # snapshot read but BEFORE the GET tasks response is built. The
        # response must still carry the batch-locked (pre-rotation) SHA;
        # the old batch's report is accepted and stored under the OLD
        # sha (never re-labelled as new-pool qualified).
        proxy_port, _svc_port = self._serve(dual, wifi_enabled=True)
        self._cur_proxy = proxy_port
        ts = int(time.time()) - 120
        real_snapshot = dual._pool_snapshot

        def rotating_snapshot():
            sha, lines = real_snapshot()
            with open(self.pool, "a", encoding="utf-8") as f:
                f.write("\n# rotated mid-flight: same nodes, new bytes\n")
            return sha, lines

        dual._pool_snapshot = rotating_snapshot
        try:
            code, body = self._req(proxy_port, "GET", "wifi",
                                   action="tasks", net_hdr="wifi")
        finally:
            dual._pool_snapshot = real_snapshot
        self.assertEqual(code, 200, body)
        new_sha = hashlib.sha256(open(self.pool, "rb").read()).hexdigest()
        self.assertNotEqual(new_sha, POOL_SHA)
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA,
                         "GET return overwrote the batch-locked SHA")
        batch_id = body["info"]["batch_id"]
        self.assertRegex(batch_id, r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(body["tasks"]), 0, body)
        t = body["tasks"][0]
        code, rbody = self._req(proxy_port, "POST", "wifi", results=[
            new_result(t["fingerprint"], t["name"], ts, True, 100,
                       "wifi", batch_id)], net_hdr="wifi")
        self.assertEqual(code, 200, rbody)
        self.assertEqual(rbody["accepted"], 1, rbody)
        conn = sqlite3.connect(self.db_path)
        stored = conn.execute(
            "SELECT source_version_sha FROM probe_reports_wifi "
            "WHERE fingerprint=?", (t["fingerprint"],)).fetchone()[0]
        conn.close()
        self.assertEqual(stored, POOL_SHA,
                         "old batch re-labelled as new-pool qualified")
        # same batch claiming the NEW sha -> rejected
        t2 = body["tasks"][1]
        code, rbody = self._req(proxy_port, "POST", "wifi", results=[
            new_result(t2["fingerprint"], t2["name"], ts + 1, True, 100,
                       "wifi", batch_id, sha=new_sha)], net_hdr="wifi")
        self.assertEqual(code, 200, rbody)
        self.assertEqual(rbody["rejected"], 1, rbody)
        # a fresh batch after the rotation binds to the NEW sha
        code, body2 = self._req(proxy_port, "GET", "wifi",
                                action="tasks", net_hdr="wifi")
        self.assertEqual(code, 200, body2)
        self.assertEqual(body2["info"]["pool_sha"], new_sha)


DEPLOY_SH = os.path.join(ROOT, "tools", "deploy_dual.sh")
RENDER_TOOL = os.path.join(ROOT, "tools", "render_probe_script.py")


class TestDeployScriptStages(MatrixBase):
    """GPT #6940445042 P0-3: deploy_dual.sh is genuinely staged — one
    stage per invocation, each stopping after its gate. Stages 1 and 4
    run alone against the simulated service/proxy; stage 5 fails closed
    without a private render config and renders + deploys with the
    RENDERED product SHA (never the desensitized input SHA)."""

    def _desensitized_script(self):
        # Redact the isolation script's real probe URL without knowing
        # its value (regex over the URL shape only).
        src = open(DUAL_JS, encoding="utf-8").read()
        des = re.sub(r"https://[^/]+:8443/[^'\"]+",
                     "https://<probe-host>:8443/<random-path>", src)
        assert "<probe-host>" in des and "<random-path>" in des
        path = os.path.join(self.tmp, "desens.js")
        open(path, "w", encoding="utf-8").write(des)
        return path

    def _deploy_env(self, svc_port, proxy_port):
        env = dict(os.environ)
        env["PROBE_BASE"] = self.base
        env["PROBE_LOCAL_BASE"] = f"http://127.0.0.1:{svc_port}"
        env["PROBE_PUBLIC_BASE"] = f"http://127.0.0.1:{proxy_port}"
        return env

    def _run_deploy(self, args, env):
        import subprocess
        return subprocess.run(
            ["bash", DEPLOY_SH] + args, env=env,
            capture_output=True, text=True, timeout=60)

    def test_stage_arg_required(self):
        env = dict(os.environ)
        r = self._run_deploy([], env)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("usage", r.stderr.lower())
        r = self._run_deploy(["9"], env)
        self.assertNotEqual(r.returncode, 0)
        r = self._run_deploy(["2"], env)
        self.assertNotEqual(r.returncode, 0)
        r = self._run_deploy(["5", "only-one-arg"], env)
        self.assertNotEqual(r.returncode, 0)

    def test_stage1_runs_alone_and_stops(self):
        proxy_port, svc_port = self._serve(orig, wifi_enabled=False)
        env = self._deploy_env(svc_port, proxy_port)
        r = self._run_deploy(["1"], env)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        self.assertIn("cellular tasks: 200", r.stdout)
        self.assertIn("wifi tasks (public): 404", r.stdout)
        self.assertIn("stage 1 complete", r.stdout)
        # stage 1 changes nothing: the cellular tables are untouched
        self.assertEqual(self._wifi_row_count(), 0)

    def test_stage4_runs_alone_and_stops(self):
        proxy_port, svc_port = self._serve(dual, wifi_enabled=True)
        env = self._deploy_env(svc_port, proxy_port)
        r = self._run_deploy(["4"], env)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        self.assertIn("cellular tasks: 200", r.stdout)
        self.assertIn("wifi tasks (public): 200", r.stdout)
        self.assertIn("wifi tasks, wrong header: 400", r.stdout)
        self.assertIn("stage 4 complete", r.stdout)

    def test_stage5_fail_closed_without_render_conf(self):
        proxy_port, svc_port = self._serve(dual, wifi_enabled=True)
        env = self._deploy_env(svc_port, proxy_port)
        dst = os.path.join(self.tmp, "probe-task.js")
        env["SCRIPT_DST"] = dst
        des = self._desensitized_script()
        sha = hashlib.sha256(open(des, "rb").read()).hexdigest()
        r = self._run_deploy(["5", des, sha], env)
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertFalse(os.path.exists(dst),
                         "stage 5 wrote the script without a render conf")

    def test_stage5_renders_and_deploys(self):
        proxy_port, svc_port = self._serve(dual, wifi_enabled=True)
        env = self._deploy_env(svc_port, proxy_port)
        # private render conf (fixture values only)
        vhost = os.path.join(self.tmp, "vhost.conf")
        open(vhost, "w").write("# fixture vhost\n")
        with open(os.path.join(self.base, "config",
                               "deploy-render.conf"), "w") as f:
            f.write("PROBE_HOST=probe-test.example\n")
            f.write(f"NGINX_CONF={vhost}\n")
        dst = os.path.join(self.tmp, "probe-task.js")
        env["SCRIPT_DST"] = dst
        # simulate the currently deployed OLD script (stage 5 backs it up)
        with open(dst, "w") as f:
            f.write("/* old deployed script */\n")
        # Stage 5 now requires the immutable manifest produced by stage 2.
        # Seed all original targets in this isolated fixture first.
        service_dst = os.path.join(self.tmp, "probe_service.py")
        service_new = os.path.join(self.tmp, "candidate_service.py")
        with open(service_dst, "w") as f:
            f.write("# old fixture service\\n")
        with open(service_new, "w") as f:
            f.write("# new fixture service\\n")
        env["SERVICE_DST"] = service_dst
        service_sha = hashlib.sha256(open(service_new, "rb").read()).hexdigest()
        stage2 = self._run_deploy(["2", service_new, service_sha], env)
        self.assertEqual(stage2.returncode, 0, stage2.stderr + stage2.stdout)
        des = self._desensitized_script()
        sha_in = hashlib.sha256(open(des, "rb").read()).hexdigest()
        r = self._run_deploy(["5", des, sha_in], env)
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        self.assertTrue(os.path.exists(dst))
        data = open(dst, encoding="utf-8").read()
        self.assertNotIn("<probe-host>", data)
        self.assertNotIn("<random-path>", data)
        self.assertNotIn("<nginx-vhost>", data)
        m = re.search(r"const PROBE_URL = '(https://[^']+)'", data)
        self.assertIsNotNone(m)
        self.assertEqual(
            m.group(1), f"https://probe-test.example:8443/{TEST_SEG}")
        # CLIENT_VERSION recomputed from the rendered content
        raw = open(dst, "rb").read()
        norm = re.sub(rb"dual-v1-[0-9a-f]{12}",
                      b"dual-v1-000000000000", raw)
        cver = re.search(
            rb"const CLIENT_VERSION = '(dual-v1-[0-9a-f]{12})';",
            raw).group(1).decode()
        self.assertEqual(hashlib.sha256(norm).hexdigest()[:12],
                         cver.split("-")[2])
        # the deployed product SHA is the RENDERED sha, never the
        # desensitized input sha
        sha_out = hashlib.sha256(raw).hexdigest()
        self.assertNotEqual(sha_out, sha_in)
        self.assertIn(f"sha256={sha_out}", r.stdout)
        # the old script was backed up next to the destination
        bak = [fn for fn in os.listdir(self.tmp)
               if fn.startswith("probe-task.js.bak-")]
        self.assertEqual(len(bak), 1, bak)
        self.assertIn("old deployed script",
                      open(os.path.join(self.tmp, bak[0])).read())

    def test_stage_structure(self):
        src = open(DEPLOY_SH, encoding="utf-8").read()
        # genuine stage dispatch: one stage per invocation
        self.assertIn('case "$STAGE" in', src)
        # stage 2 backs up via the SQLite backup API (P0-4), never a
        # plain cp of the live WAL database
        self.assertIn("backup_db.py", src)
        self.assertNotIn("cp /opt/probe-service/data/probe.db", src)
        # stage 5 renders privately (P0-2)
        self.assertIn("render_probe_script.py", src)
        # the old straight-through run (service -> nginx -> script in
        # one invocation) is gone
        self.assertNotIn("step 3: phone script", src)
        self.assertNotIn("step 1: service", src)
        # all five stages exist as independent functions
        for n in ("1", "2", "3", "4", "5"):
            self.assertIn(f"stage_{n}()", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
