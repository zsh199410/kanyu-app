#!/usr/bin/env python3
"""Isolated tests for the #73 dual-channel (B1) probe patch.

Covers design checklist (GPT #6937918471) + final-review P0-1..P0-4
(GPT #6938113969) + GPT #6940445042 P0-1 snapshot race fix
(single immutable pool snapshot; rotation fault injection),
P0-2 private render, P0-3 staged deploy (separate file
tests/test_deploy_matrix.py), P0-4 WAL-safe backup (separate file
tests/test_backup.py).
  Also: wifi/cellular/unknown, in-switch requests, label+SHA alignment,
  old-record compatibility, no impact on old cellular probe & WinnerReport,
  no DIRECT fallback. Plus: caps/circuit independence, wifi-verified never
  promoting cellular verified, and rollback (dual -> old service).

Runs against an isolated PROBE_BASE (temp dir) with a synthetic fixture
pool (TEST-NET hosts, never real nodes). Stdlib only.

Usage:
  python3 -m unittest discover -s tests -v            (local)
  python3 -m unittest tests.test_dual_probe -v        (same)
JS decision-table + full script-run tests live in tests/js_detect_test.js
and run under node (local only; the VPS has no node — there the suite
verifies the JS file SHA instead).
"""
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SERVICE_DIR = os.path.join(ROOT, "service")
FIXTURE_POOL = os.path.join(ROOT, "fixtures", "pool-fixture.txt")
DUAL_JS = os.path.join(ROOT, "script", "probe-task-dual.js")
ORIG_JS = os.path.join(ROOT, "script", "probe-task-orig.js")

sys.path.insert(0, SERVICE_DIR)
import probe_service_dual as dual  # noqa: E402
import probe_service_orig as orig  # noqa: E402

TEST_SEG = "testseg12345678"
# CLIENT_VERSION is read from the script itself so the tests always track
# the injected build id (tools/inject_sha.py).
CLIENT_VERSION = re.search(
    r"const CLIENT_VERSION = '(dual-v1-[0-9a-f]{12})';",
    open(DUAL_JS, encoding="utf-8").read()).group(1)
# POOL_SHA is the sha256 of the fixture pool file bytes — the server-side
# authority for source_version_sha (P0-1).
POOL_SHA = hashlib.sha256(open(FIXTURE_POOL, "rb").read()).hexdigest()
NOW = int(time.time())
# P0-1 snapshot binding: DualBase.setUp issues one batch per channel
# (real _issue_batch, covering all fixture fingerprints) and records it
# here; make_result() defaults to it so existing call sites keep
# working. Tests that need a different binding (expired, wrong channel,
# foreign fingerprint, no batch at all) pass batch_id explicitly.
DEFAULT_BATCH = {"wifi": None, "cellular": None}
DEFAULT_POOL_SHA = {"wifi": None, "cellular": None}


def load_module(name, path):
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_result(fp, name, ts, success, second_ms, network_type="wifi", sha=None,
                state=None, client_version=None, batch_id=None):
    if batch_id is None:
        batch_id = DEFAULT_BATCH.get(network_type)
    if sha is None:
        sha = DEFAULT_POOL_SHA.get(network_type) or POOL_SHA
    return {
        "fingerprint": fp,
        "name": name,
        "ts": ts,
        "state": state or ("measured" if success else "first_failed"),
        "warm_ms": 120,
        "second_request_ms": second_ms,
        "second_status": 204 if success else None,
        "success": success,
        "error": None,
        "network_type": network_type,
        # P0-1: source_version_sha is the POOL content SHA locked in the
        # batch record (server-issued snapshot), batch_id binds the result
        # to that batch, client_version is the script build id. The three
        # are never the same value.
        "source_version_sha": sha,
        "batch_id": batch_id,
        "client_version": CLIENT_VERSION if client_version is None else client_version,
    }


def legacy_result(fp, name, ts, success, second_ms, iface="pdp_ip0"):
    """Old-client shape: no network_type, no sha, raw interface field."""
    return {
        "fingerprint": fp,
        "name": name,
        "ts": ts,
        "state": "measured" if success else "first_failed",
        "warm_ms": 120,
        "second_request_ms": second_ms,
        "second_status": 204 if success else None,
        "success": success,
        "error": None,
        "interface": iface,
    }


def dump_tables(db_path, tables):
    conn = sqlite3.connect(db_path)
    out = {}
    for t in tables:
        rows = conn.execute(f"SELECT * FROM {t} ORDER BY 1, 2").fetchall()
        out[t] = [list(r) for r in rows]
    conn.close()
    return out


def dump_tables_cols(db_path, spec):
    """Dump only the listed columns per table (for orig-vs-dual regression:
    the original service's probe_reports lacks the P0-1 columns)."""
    conn = sqlite3.connect(db_path)
    out = {}
    for t, cols in spec.items():
        q = f"SELECT {', '.join(cols)} FROM {t} ORDER BY 1, 2"
        out[t] = [list(r) for r in conn.execute(q).fetchall()]
    conn.close()
    return out


ORIG_REPORT_COLS = ["id", "fingerprint", "name", "ts", "state", "warm_ms",
                    "second_ms", "second_status", "success", "error", "interface"]
ORIG_NODE_COLS = ["fingerprint", "name", "protocol", "host", "port", "state",
                  "first_seen", "last_seen_in_pool", "last_phone_ts", "last_warm_ms",
                  "last_second_ms", "last_status", "last_success", "last_error",
                  "last_interface", "phone_ok", "phone_fail", "updated_at"]


def tables_hash(db_path, tables):
    return hashlib.sha256(
        json.dumps(dump_tables(db_path, tables), sort_keys=True).encode()
    ).hexdigest()


class DualBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dual-test-")
        self.base = os.path.join(self.tmp, "probe")
        os.makedirs(os.path.join(self.base, "config"), exist_ok=True)
        os.makedirs(os.path.join(self.base, "data"), exist_ok=True)
        with open(os.path.join(self.base, "config", "probe-path.txt"), "w") as f:
            f.write(TEST_SEG)
        self.pool = os.path.join(self.tmp, "pool.txt")
        with open(self.pool, "w") as f:
            f.write(open(FIXTURE_POOL, encoding="utf-8").read())
        dual.POOL_TXT = self.pool
        orig.POOL_TXT = self.pool
        dual.BASE = self.base
        orig.BASE = self.base
        dual.DB_PATH = os.path.join(self.base, "data", "probe.db")
        orig.DB_PATH = os.path.join(self.base, "data", "probe.db")
        self.db_path = dual.DB_PATH
        # seed both channels' node tables from the fixture pool
        dual.sync_pool()
        dual.sync_pool_wifi()
        # P0-1: seed one batch per channel covering all fixture
        # fingerprints, issued through the real _issue_batch helper.
        conn = sqlite3.connect(self.db_path)
        tasks = [{"fingerprint": fp} for fp, _ in self.fps(12)]
        DEFAULT_BATCH["wifi"] = dual._issue_batch(conn, "wifi", POOL_SHA, tasks)
        DEFAULT_BATCH["cellular"] = dual._issue_batch(conn, "cellular", POOL_SHA, tasks)
        DEFAULT_POOL_SHA["wifi"] = POOL_SHA
        DEFAULT_POOL_SHA["cellular"] = POOL_SHA
        conn.close()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def fps(self, n=12):
        conn = sqlite3.connect(self.db_path)
        rows = conn.execute(
            "SELECT fingerprint, name FROM probe_nodes ORDER BY name").fetchall()
        conn.close()
        return rows[:n]

    def wifi_ingest(self, results):
        return dual.ingest_wifi(results)

    def cell_ingest(self, results):
        return dual.ingest(results)


class TestWifiIsolation(DualBase):
    def test_S01_wifi_ingest_touches_only_wifi_tables(self):
        before_cell = tables_hash(self.db_path, ["probe_reports", "probe_nodes"])
        fps = self.fps(4)
        res = [make_result(fp, name, NOW - 100 + i, True, 120 + i * 10)
               for i, (fp, name) in enumerate(fps)]
        out = self.wifi_ingest(res)
        self.assertEqual(out["accepted"], 4, out)
        self.assertEqual(out["rejected"], 0, out)
        after_cell = tables_hash(self.db_path, ["probe_reports", "probe_nodes"])
        self.assertEqual(before_cell, after_cell,
                         "cellular tables changed by wifi ingest")
        conn = sqlite3.connect(self.db_path)
        n_wifi = conn.execute("SELECT COUNT(*) FROM probe_reports_wifi").fetchone()[0]
        n_wifi_nodes = conn.execute(
            "SELECT COUNT(*) FROM probe_nodes_wifi WHERE last_wifi_ts IS NOT NULL"
        ).fetchone()[0]
        conn.close()
        self.assertEqual(n_wifi, 4)
        self.assertEqual(n_wifi_nodes, 4)

    def test_S02_cellular_ingest_regression_matches_orig(self):
        # Same input sequence through orig service and dual service must
        # produce identical cellular tables (compared on the columns the
        # original schema has; dual additionally stores the P0-1 binding
        # columns, which legacy input leaves NULL).
        fps = self.fps(6)
        seq = []
        for i, (fp, name) in enumerate(fps):
            seq.append(legacy_result(fp, name, NOW - 500 + i, i % 2 == 0, 150 + i * 20))
        orig.ingest([dict(r) for r in seq])
        spec = {"probe_reports": ORIG_REPORT_COLS, "probe_nodes": ORIG_NODE_COLS}
        orig_cell = dump_tables_cols(self.db_path, spec)
        # fresh DB for the dual run
        os.remove(self.db_path)
        dual.sync_pool()
        dual.sync_pool_wifi()
        dual.ingest([dict(r) for r in seq])
        dual_cell = dump_tables_cols(self.db_path, spec)
        self.assertEqual(orig_cell, dual_cell)

    def test_S03_unknown_and_wrong_channel_rejected(self):
        fps = self.fps(3)
        fp, name = fps[0]
        # network_type missing -> rejected by wifi ingest
        r = make_result(fp, name, NOW - 10, True, 100)
        del r["network_type"]
        out = self.wifi_ingest([r])
        self.assertEqual(out["accepted"], 0)
        self.assertEqual(out["rejected"], 1)
        # network_type cellular on wifi ingest -> rejected
        r = make_result(fp, name, NOW - 9, True, 100, network_type="cellular")
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1)
        # malformed sha -> rejected
        r = make_result(fp, name, NOW - 8, True, 100, sha="not-a-sha")
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1)
        # P0-1: a script build id is NOT a pool version -> rejected
        r = make_result(fp, name, NOW - 8, True, 100, sha=CLIENT_VERSION)
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "build id accepted as pool sha")
        # P0-1: well-formed 64-hex but not the batch's LOCKED snapshot
        # sha -> rejected (the batch, not the "current" pool, is checked)
        r = make_result(fp, name, NOW - 8, True, 100, sha="0" * 64)
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "foreign pool sha accepted")
        # P0-1: no batch_id at all -> rejected (wifi requires a binding)
        r = make_result(fp, name, NOW - 8, True, 100)
        del r["batch_id"]
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "unbound wifi result accepted")
        # P0-1: batch issued for the OTHER channel -> rejected
        r = make_result(fp, name, NOW - 8, True, 100,
                        batch_id=DEFAULT_BATCH["cellular"])
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "cellular batch accepted on wifi")
        # P0-1: fingerprint not in the batch's locked set -> rejected
        foreign_fp = "f" * 32
        r = make_result(foreign_fp, "not-in-pool", NOW - 8, True, 100)
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "foreign fingerprint accepted")
        # P0-1: expired batch -> rejected
        import uuid as _uuid
        expired = "b-" + _uuid.uuid4().hex[:16]
        conn = sqlite3.connect(self.db_path)
        conn.execute(
            "INSERT INTO probe_task_batches(batch_id, network_type, pool_sha,"
            " fingerprints, issued_at, expires_at) VALUES(?,?,?,?,?,?)",
            (expired, "wifi", POOL_SHA, json.dumps([fp]),
             NOW - 20000, NOW - 10000))
        conn.commit()
        conn.close()
        r = make_result(fp, name, NOW - 8, True, 100, batch_id=expired)
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "expired batch accepted")
        # P0-1: missing client_version -> rejected (wifi path requires it)
        r = make_result(fp, name, NOW - 8, True, 100)
        del r["client_version"]
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "missing client_version accepted")
        # P0-1: malformed client_version -> rejected
        r = make_result(fp, name, NOW - 8, True, 100, client_version="v2")
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "malformed client_version accepted")
        # unknown network never reaches ingest: client skips; server also
        # rejects network_type == 'unknown'
        r = make_result(fp, name, NOW - 7, True, 100, network_type="unknown")
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1)
        # wifi-labelled record on the cellular ingest path is rejected
        # (defense-in-depth is in do_POST; ingest() itself is legacy, so
        # check the HTTP layer in TestHttpRouting instead)
        conn = sqlite3.connect(self.db_path)
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM probe_reports").fetchone()[0], 0)
        self.assertEqual(conn.execute("SELECT COUNT(*) FROM probe_reports_wifi").fetchone()[0], 0)
        conn.close()

    def test_S06_duplicates_counted_once(self):
        fps = self.fps(2)
        fp, name = fps[0]
        r = make_result(fp, name, NOW - 20, True, 110)
        out1 = self.wifi_ingest([r])
        out2 = self.wifi_ingest([dict(r)])
        self.assertEqual(out1["accepted"], 1)
        self.assertEqual(out2["duplicates"], 1)
        conn = sqlite3.connect(self.db_path)
        ok = conn.execute(
            "SELECT phone_ok_wifi FROM probe_nodes_wifi WHERE fingerprint=?", (fp,)
        ).fetchone()[0]
        conn.close()
        self.assertEqual(ok, 1, "duplicate report double-counted wifi_ok")

    def test_S07_label_and_sha_alignment(self):
        fps = self.fps(4)
        res = [make_result(fp, name, NOW - 60 + i, i % 2 == 0, 140)
               for i, (fp, name) in enumerate(fps)]
        self.wifi_ingest(res)
        conn = sqlite3.connect(self.db_path)
        rows = conn.execute(
            "SELECT network_type, source_version_sha, client_version, batch_id "
            "FROM probe_reports_wifi").fetchall()
        conn.close()
        self.assertEqual(len(rows), 4)
        for nt, sha, cver, bid in rows:
            self.assertEqual(nt, "wifi")
            # P0-1: stored pool sha is the POOL content SHA locked in the
            # batch, batch_id is the batch the result was bound to,
            # client_version is the script build id; the three are never
            # the same value.
            self.assertEqual(sha, POOL_SHA)
            self.assertEqual(cver, CLIENT_VERSION)
            self.assertEqual(bid, DEFAULT_BATCH["wifi"])
            self.assertNotEqual(sha, cver)

    def test_S11_wifi_verified_never_promotes_cellular(self):
        fps = self.fps(2)
        fp, name = fps[0]
        before = dual.stats()
        self.assertEqual(before["verified"], 0)
        self.wifi_ingest([make_result(fp, name, NOW - 30, True, 90)])
        conn = sqlite3.connect(self.db_path)
        wstate = conn.execute(
            "SELECT state FROM probe_nodes_wifi WHERE fingerprint=?", (fp,)).fetchone()[0]
        cstate = conn.execute(
            "SELECT state FROM probe_nodes WHERE fingerprint=?", (fp,)).fetchone()[0]
        conn.close()
        self.assertEqual(wstate, "wifi_verified")
        self.assertEqual(cstate, "pending")
        after = dual.stats()
        self.assertEqual(after["verified"], 0, "cellular verified polluted by wifi")
        self.assertEqual(after["states"].get("verified", 0), 0)

    def test_S10_stats_separation(self):
        fps = self.fps(4)
        self.wifi_ingest([make_result(fp, name, NOW - 40 + i, True, 100 + i)
                          for i, (fp, name) in enumerate(fps)])
        cs = dual.stats()
        ws = dual.stats_wifi()
        self.assertEqual(cs["tested_day"], 0)
        self.assertEqual(cs["qualified_day"], 0)
        self.assertEqual(ws["tested_day"], 4)
        self.assertEqual(ws["qualified_day"], 4)
        self.assertEqual(ws["network_type"], "wifi")
        self.assertEqual(ws["verified"], 4)


class TestCapsAndCircuit(DualBase):
    def test_S08_caps_independent(self):
        fps = self.fps(12)
        # Timestamps must all fall inside the CURRENT clock hour, or the
        # hourly cap never trips. Guard the first minute of an hour.
        now = int(time.time())
        if now % 3600 < 60:
            time.sleep(61 - (now % 3600))
            now = int(time.time())
        hour_start = now - (now % 3600)
        base = max(hour_start + 1, now - 300)
        # 20 wifi reports this hour (reuse fps with distinct ts)
        res = []
        for i in range(20):
            fp, name = fps[i % len(fps)]
            res.append(make_result(fp, name, base + i, i % 3 != 0, 200))
        # ingest in batches of 8 (server limit per call)
        for j in range(0, len(res), 8):
            self.wifi_ingest(res[j:j + 8])
        tasks_w, info_w = dual.next_tasks_wifi()
        self.assertEqual(tasks_w, [])
        self.assertEqual(info_w["reason"], "wifi_hour_cap_reached")
        # cellular budget untouched: still offers tasks
        tasks_c, info_c = dual.next_tasks()
        self.assertGreater(len(tasks_c), 0, info_c)
        self.assertEqual(info_c["reason"], "ok")

    def test_S09_circuit_independent(self):
        fps = self.fps(8)
        # 8 distinct hosts failing in-window on wifi -> wifi circuit trips
        res = [make_result(fp, name, NOW - 100 + i, False, None)
               for i, (fp, name) in enumerate(fps)]
        out = self.wifi_ingest(res)
        self.assertTrue(out.get("circuit_tripped"), out)
        conn = sqlite3.connect(self.db_path)
        wc = conn.execute(
            "SELECT value FROM probe_meta WHERE key='wifi_circuit_until'").fetchone()
        cc = conn.execute(
            "SELECT value FROM probe_meta WHERE key='circuit_until'").fetchone()
        conn.close()
        self.assertIsNotNone(wc, "wifi circuit did not trip")
        self.assertIsNone(cc, "cellular circuit polluted by wifi failures")
        # cellular tasks still offered while wifi circuit is open
        tasks_c, info_c = dual.next_tasks()
        self.assertGreater(len(tasks_c), 0, info_c)
        tasks_w, info_w = dual.next_tasks_wifi()
        self.assertEqual(tasks_w, [])
        self.assertTrue(info_w["reason"].startswith("wifi_circuit_open"))


class TestVersionBindingP01(DualBase):
    def test_P01_tasks_info_carries_pool_sha_and_batch(self):
        # The server is the authority: tasks info.pool_sha is the sha256
        # of the pool file bytes currently on disk, and info.batch_id is
        # the batch binding locked at issuance (snapshot sha + task
        # fingerprint set + validity window). The batch record must exist
        # in probe_task_batches and its fingerprint set must equal the
        # issued tasks.
        tasks, info = dual.next_tasks()
        self.assertEqual(info["pool_sha"], POOL_SHA)
        self.assertRegex(info["batch_id"], r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(tasks), 0, info)
        conn = sqlite3.connect(self.db_path)
        row = conn.execute(
            "SELECT network_type, pool_sha, fingerprints, issued_at, expires_at "
            "FROM probe_task_batches WHERE batch_id=?",
            (info["batch_id"],)).fetchone()
        conn.close()
        self.assertIsNotNone(row, "no batch record for issued tasks")
        net, psha, fps_json, issued_at, expires_at = row
        self.assertEqual(net, "cellular")
        self.assertEqual(psha, POOL_SHA)
        self.assertEqual(sorted(json.loads(fps_json)),
                         sorted(t["fingerprint"] for t in tasks))
        self.assertGreater(expires_at, issued_at)
        tasks_w, info_w = dual.next_tasks_wifi()
        self.assertEqual(info_w["pool_sha"], POOL_SHA)
        self.assertRegex(info_w["batch_id"], r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(tasks_w), 0, info_w)
        self.assertNotEqual(info_w["batch_id"], info["batch_id"])

    def test_P01_cellular_legacy_accepted_new_binding_enforced(self):
        fps = self.fps(4)
        # legacy old-script shape (no sha, no batch_id, no client_version)
        # -> accepted, stored binding columns stay NULL.
        out = self.cell_ingest([legacy_result(fps[0][0], fps[0][1], NOW - 400, True, 120)])
        self.assertEqual(out["accepted"], 1, out)
        conn = sqlite3.connect(self.db_path)
        row = conn.execute(
            "SELECT source_version_sha, client_version, batch_id FROM probe_reports "
            "WHERE fingerprint=?", (fps[0][0],)).fetchone()
        conn.close()
        self.assertEqual(row, (None, None, None))
        # new-style cellular result bound to its issued batch -> accepted
        # and stored.
        r = make_result(fps[1][0], fps[1][1], NOW - 300, True, 120,
                        network_type="cellular")
        out = self.cell_ingest([r])
        self.assertEqual(out["accepted"], 1, out)
        conn = sqlite3.connect(self.db_path)
        row = conn.execute(
            "SELECT source_version_sha, client_version, batch_id FROM probe_reports "
            "WHERE fingerprint=?", (fps[1][0],)).fetchone()
        conn.close()
        self.assertEqual(row, (POOL_SHA, CLIENT_VERSION, DEFAULT_BATCH["cellular"]))
        # sha that is not the batch's LOCKED snapshot sha -> rejected
        r = make_result(fps[2][0], fps[2][1], NOW - 200, True, 120,
                        network_type="cellular", sha="0" * 64)
        out = self.cell_ingest([r])
        self.assertEqual(out["accepted"], 0, out)
        self.assertEqual(out["rejected"], 1, out)
        # script build id as pool sha -> rejected (the P0-1 confusion)
        r = make_result(fps[2][0], fps[2][1], NOW - 200, True, 120,
                        network_type="cellular", sha=CLIENT_VERSION)
        out = self.cell_ingest([r])
        self.assertEqual(out["rejected"], 1, out)
        # sha WITHOUT batch_id -> rejected (new-style client, no binding)
        r = make_result(fps[2][0], fps[2][1], NOW - 200, True, 120,
                        network_type="cellular")
        del r["batch_id"]
        out = self.cell_ingest([r])
        self.assertEqual(out["rejected"], 1, out)
        # batch issued for the OTHER channel -> rejected
        r = make_result(fps[2][0], fps[2][1], NOW - 200, True, 120,
                        network_type="cellular", batch_id=DEFAULT_BATCH["wifi"])
        out = self.cell_ingest([r])
        self.assertEqual(out["rejected"], 1, out)
        # malformed client_version -> rejected
        r = make_result(fps[3][0], fps[3][1], NOW - 100, True, 120,
                        network_type="cellular", client_version="v9")
        out = self.cell_ingest([r])
        self.assertEqual(out["rejected"], 1, out)

    def test_P01_pool_change_between_tasks_and_report(self):
        # Snapshot binding (GPT #6938432964): tasks are issued under pool
        # version A; the pool file is then republished (same nodes,
        # different bytes -> new SHA). Results bound to batch A are STILL
        # accepted — the batch's locked sha is A, and the "current" pool
        # file is never consulted at ingest. Results claiming the new sha
        # WITHOUT a batch for it are rejected; a fresh batch issued after
        # the republish binds to the new sha and is accepted.
        fps = self.fps(2)
        old_bound = make_result(fps[0][0], fps[0][1], NOW - 50, True, 100,
                                sha=POOL_SHA, batch_id=DEFAULT_BATCH["wifi"])
        out = self.wifi_ingest([old_bound])
        self.assertEqual(out["accepted"], 1, out)
        conn = sqlite3.connect(self.db_path)
        stored_sha = conn.execute(
            "SELECT source_version_sha FROM probe_reports_wifi "
            "WHERE fingerprint=?", (fps[0][0],)).fetchone()[0]
        conn.close()
        # stored under the OLD snapshot sha: an old batch is never
        # re-labelled as new-pool qualified.
        self.assertEqual(stored_sha, POOL_SHA)
        with open(self.pool, "a", encoding="utf-8") as f:
            f.write("\n# rotated: same nodes, new bytes\n")
        new_sha = hashlib.sha256(open(self.pool, "rb").read()).hexdigest()
        self.assertNotEqual(new_sha, POOL_SHA)
        no_batch = make_result(fps[1][0], fps[1][1], NOW - 40, True, 100,
                               sha=new_sha)
        del no_batch["batch_id"]
        out = self.wifi_ingest([no_batch])
        self.assertEqual(out["rejected"], 1, "new sha without a batch accepted")
        _tasks, info = dual.next_tasks_wifi()
        self.assertEqual(info["pool_sha"], new_sha)
        self.assertGreater(len(_tasks), 0, info)
        # use a fingerprint from the fresh batch's own locked set
        tfp, tname = _tasks[0]["fingerprint"], _tasks[0]["name"]
        new_bound = make_result(tfp, tname, NOW - 40, True, 100,
                                sha=new_sha, batch_id=info["batch_id"])
        out = self.wifi_ingest([new_bound])
        self.assertEqual(out["accepted"], 1, out)

    def test_P01_rotation_between_snapshot_and_get_return(self):
        # GPT #6940445042 P0-1 fault injection: rotate the pool file
        # AFTER the snapshot read but BEFORE the tasks response is
        # built. The returned info.pool_sha must still be the
        # batch-locked (pre-rotation) SHA; the old batch's report must
        # be accepted and stored under the OLD sha (never re-labelled
        # as new-pool qualified); the same batch claiming the NEW sha
        # must be rejected; a fresh batch after the rotation binds to
        # the NEW sha.
        real_snapshot = dual._pool_snapshot

        def rotating_snapshot():
            sha, lines = real_snapshot()
            with open(self.pool, "a", encoding="utf-8") as f:
                f.write("\n# rotated mid-flight: same nodes, new bytes\n")
            return sha, lines

        dual._pool_snapshot = rotating_snapshot
        try:
            tasks, info = dual.next_tasks_wifi()
        finally:
            dual._pool_snapshot = real_snapshot
        new_sha = hashlib.sha256(open(self.pool, "rb").read()).hexdigest()
        self.assertNotEqual(new_sha, POOL_SHA)
        self.assertEqual(info["pool_sha"], POOL_SHA,
                         "GET return overwrote the batch-locked SHA")
        self.assertRegex(info["batch_id"], r"^b-[0-9a-f]{16}$")
        self.assertGreater(len(tasks), 0, info)
        conn = sqlite3.connect(self.db_path)
        row = conn.execute(
            "SELECT pool_sha FROM probe_task_batches WHERE batch_id=?",
            (info["batch_id"],)).fetchone()
        conn.close()
        self.assertIsNotNone(row, "no batch record for issued tasks")
        self.assertEqual(row[0], POOL_SHA)
        # old batch report accepted, stored under the OLD snapshot sha
        t = tasks[0]
        out = self.wifi_ingest([make_result(
            t["fingerprint"], t["name"], NOW - 10, True, 100,
            sha=POOL_SHA, batch_id=info["batch_id"])])
        self.assertEqual(out["accepted"], 1, out)
        conn = sqlite3.connect(self.db_path)
        stored = conn.execute(
            "SELECT source_version_sha FROM probe_reports_wifi "
            "WHERE fingerprint=?", (t["fingerprint"],)).fetchone()[0]
        conn.close()
        self.assertEqual(stored, POOL_SHA,
                         "old batch re-labelled as new-pool qualified")
        # same batch claiming the NEW sha -> rejected
        t2 = tasks[1]
        out = self.wifi_ingest([make_result(
            t2["fingerprint"], t2["name"], NOW - 9, True, 100,
            sha=new_sha, batch_id=info["batch_id"])])
        self.assertEqual(out["rejected"], 1, out)
        # a fresh batch after the rotation binds to the NEW sha
        tasks2, info2 = dual.next_tasks_wifi()
        self.assertEqual(info2["pool_sha"], new_sha)
        self.assertGreater(len(tasks2), 0, info2)

    def test_P01_batch_window_enforced(self):
        # A batch whose validity window has closed rejects results even
        # when sha and fingerprint match; a batch issued in the future
        # (clock skew beyond the allowance) does the same.
        import uuid as _uuid
        fps = self.fps(1)
        fp, name = fps[0]
        conn = sqlite3.connect(self.db_path)
        expired = "b-" + _uuid.uuid4().hex[:16]
        conn.execute(
            "INSERT INTO probe_task_batches(batch_id, network_type, pool_sha,"
            " fingerprints, issued_at, expires_at) VALUES(?,?,?,?,?,?)",
            (expired, "wifi", POOL_SHA, json.dumps([fp]),
             NOW - 20000, NOW - 10000))
        future = "b-" + _uuid.uuid4().hex[:16]
        conn.execute(
            "INSERT INTO probe_task_batches(batch_id, network_type, pool_sha,"
            " fingerprints, issued_at, expires_at) VALUES(?,?,?,?,?,?)",
            (future, "wifi", POOL_SHA, json.dumps([fp]),
             NOW + 3600, NOW + 3600 + 7200))
        conn.commit()
        conn.close()
        r = make_result(fp, name, NOW - 8, True, 100, batch_id=expired)
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "expired batch accepted")
        r = make_result(fp, name, NOW - 8, True, 100, batch_id=future)
        out = self.wifi_ingest([r])
        self.assertEqual(out["rejected"], 1, "future batch accepted")

    def test_P01_db_migration_adds_binding_columns(self):
        # A DB created by the ORIGINAL service (old schema) gains the
        # P0-1 columns when the dual service opens it. Existing rows keep
        # working; new columns are NULL until new data arrives.
        import shutil
        tmp2 = tempfile.mkdtemp(prefix="dual-migrate-")
        try:
            base2 = os.path.join(tmp2, "probe")
            os.makedirs(os.path.join(base2, "config"), exist_ok=True)
            os.makedirs(os.path.join(base2, "data"), exist_ok=True)
            with open(os.path.join(base2, "config", "probe-path.txt"), "w") as f:
                f.write(TEST_SEG)
            orig.BASE = base2
            orig.DB_PATH = os.path.join(base2, "data", "probe.db")
            orig.POOL_TXT = self.pool
            orig.db().close()
            conn = sqlite3.connect(orig.DB_PATH)
            cols = {r[1] for r in conn.execute(
                "PRAGMA table_info(probe_reports)").fetchall()}
            conn.close()
            self.assertNotIn("source_version_sha", cols)
            self.assertNotIn("client_version", cols)
            dual.BASE = base2
            dual.DB_PATH = os.path.join(base2, "data", "probe.db")
            dual.POOL_TXT = self.pool
            dual.db().close()
            conn = sqlite3.connect(dual.DB_PATH)
            cols = {r[1] for r in conn.execute(
                "PRAGMA table_info(probe_reports)").fetchall()}
            cols_w = {r[1] for r in conn.execute(
                "PRAGMA table_info(probe_reports_wifi)").fetchall()}
            tables = {r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
            conn.close()
            self.assertIn("source_version_sha", cols)
            self.assertIn("client_version", cols)
            self.assertIn("batch_id", cols)
            self.assertIn("client_version", cols_w)
            self.assertIn("batch_id", cols_w)
            self.assertIn("probe_task_batches", tables)
        finally:
            shutil.rmtree(tmp2, ignore_errors=True)


class TestTrustBoundaryP03(unittest.TestCase):
    def test_P03_disclaimers_present_and_no_gate_code_path(self):
        src = open(os.path.join(SERVICE_DIR, "probe_service_dual.py"),
                   encoding="utf-8").read()
        # The trust boundary is stated in the module docstring, the wifi
        # ingest docstring and the channel check.
        low = src.lower()
        for needle in (
            "trust boundary (p0-3)",
            "cannot prove the real transport interface",
            "never promoted to native full-group",
            "never serve as p0 gate evidence",
            "no p0 gate / native-acceptance code path at all",
            # P0-3 (GPT #6938432964): labels are client declarations.
            "client-declared",
            "client assertion",
        ):
            self.assertIn(needle, low, "missing disclaimer: " + needle)
        # No P0 gate / native-acceptance path anywhere in the code: strip
        # comments and docstrings, then 'gate' and 'native' must be gone.
        code = re.sub(r'"""[\s\S]*?"""', ' ', src)
        code = re.sub(r"'''[\s\S]*?'''", ' ', code)
        code_lines = []
        for line in code.splitlines():
            code_lines.append(line.split('#', 1)[0])
        code_only = "\n".join(code_lines)
        self.assertNotIn("gate", code_only.lower())
        self.assertNotIn("native", code_only.lower())
        self.assertNotIn("/opt/pool-gate", src)
        # the service never opens any DB other than its own probe.db
        self.assertNotIn("/opt/free-node-program/data", src)


class TestCompatAndRollback(DualBase):
    def test_S12_old_client_compat(self):
        fps = self.fps(3)
        seq = [legacy_result(fp, name, NOW - 300 + i, True, 130 + i * 10)
               for i, (fp, name) in enumerate(fps)]
        out = self.cell_ingest(seq)
        self.assertEqual(out["accepted"], 3, out)
        # old stats shape: same keys as the original service
        s = dual.stats()
        for k in ("total", "states", "verified", "coverage_24h", "tested_hour",
                  "tested_day", "qualified_day", "circuit_open"):
            self.assertIn(k, s)
        self.assertEqual(s["verified"], 3)
        # old cellular rows survive later wifi activity untouched
        before = tables_hash(self.db_path, ["probe_reports", "probe_nodes"])
        self.wifi_ingest([make_result(fps[0][0], fps[0][1], NOW - 5, True, 90)])
        after = tables_hash(self.db_path, ["probe_reports", "probe_nodes"])
        self.assertEqual(before, after)

    def test_S13_winner_report_isolation(self):
        src = open(os.path.join(SERVICE_DIR, "probe_service_dual.py"),
                   encoding="utf-8").read()
        # The pre-existing comment "(like winner-report)" names the other
        # service's protection model; the meaningful check is that this
        # service never touches the winner_reports table or pool.db.
        self.assertNotIn("winner_report", src.lower())
        self.assertNotIn("winner_reports", src.lower())
        self.assertNotIn("pool.db", src)
        # the service never opens any DB other than its own probe.db
        self.assertNotIn("/opt/free-node-program/data", src)

    def test_S14_rollback_to_old_service(self):
        # Seed cellular + wifi data through the dual service, then roll back
        # to the ORIGINAL service code on the same DB directory.
        fps = self.fps(3)
        # Only 2 fast successes: 3 would hit REPLENISH_TARGET and make
        # next_tasks() legitimately answer target_met instead of ok.
        self.cell_ingest([legacy_result(fp, name, NOW - 200 + i, True, 120)
                         for i, (fp, name) in enumerate(fps[:2])])
        self.wifi_ingest([make_result(fps[0][0], fps[0][1], NOW - 50, True, 95)])
        before_cell = dump_tables(self.db_path, ["probe_reports", "probe_nodes"])
        # rollback: original module on the same base
        orig.sync_pool()
        tasks, info = orig.next_tasks()
        self.assertEqual(info["reason"], "ok")
        s = orig.stats()
        self.assertEqual(s["verified"], 2)
        after_cell = dump_tables(self.db_path, ["probe_reports", "probe_nodes"])
        self.assertEqual(before_cell, after_cell)
        # wifi tables still exist on disk but the old code never reads them
        conn = sqlite3.connect(self.db_path)
        n = conn.execute("SELECT COUNT(*) FROM probe_reports_wifi").fetchone()[0]
        conn.close()
        self.assertEqual(n, 1, "wifi rows lost by rollback (must be preserved)")
        # old client still ingests fine after rollback
        out = orig.ingest([legacy_result(fps[1][0], fps[1][1], NOW - 10, True, 110)])
        self.assertEqual(out["accepted"], 1, out)


class TestHttpRouting(DualBase):
    PORT = 18099

    def setUp(self):
        super().setUp()
        env = dict(os.environ)
        env["PROBE_BASE"] = self.base
        env["PROBE_POOL_TXT"] = self.pool
        env["PROBE_PORT"] = str(self.PORT)
        self.proc = subprocess.Popen(
            [sys.executable, os.path.join(SERVICE_DIR, "probe_service_dual.py")],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.base_url = f"http://127.0.0.1:{self.PORT}/{TEST_SEG}"
        for _ in range(50):
            try:
                self._get("stats", "cellular")
                break
            except Exception:
                time.sleep(0.1)

    def tearDown(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        super().tearDown()

    def _get(self, action, channel, net_hdr=None):
        url = self.base_url + ("-wifi" if channel == "wifi" else "")
        req = urllib.request.Request(url, method="GET")
        req.add_header("X-Probe-Action", action)
        if net_hdr:
            req.add_header("X-Probe-Network", net_hdr)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode())

    def _post(self, results, channel, net_hdr=None):
        url = self.base_url + ("-wifi" if channel == "wifi" else "")
        req = urllib.request.Request(
            url, data=json.dumps({"results": results}).encode(),
            method="POST")
        req.add_header("Content-Type", "application/json")
        if net_hdr:
            req.add_header("X-Probe-Network", net_hdr)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode())

    def test_S04_header_path_mismatch_400(self):
        code, _ = self._get("tasks", "cellular", net_hdr="wifi")
        self.assertEqual(code, 400)
        code, _ = self._get("tasks", "wifi", net_hdr="cellular")
        self.assertEqual(code, 400)
        code, body = self._get("tasks", "cellular", net_hdr="cellular")
        self.assertEqual(code, 200)
        self.assertTrue(body["ok"])

    def test_S03_http_wifi_label_rejected_on_cellular_path(self):
        fps = self.fps(2)
        fp, name = fps[0]
        # wifi-labelled record posted to the cellular path -> 400
        code, _ = self._post(
            [make_result(fp, name, NOW - 10, True, 100)], "cellular")
        self.assertEqual(code, 400)
        # same record on the wifi path -> 200
        code, body = self._post(
            [make_result(fp, name, NOW - 10, True, 100)], "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertEqual(body["accepted"], 1, body)
        # old client (no network header, no network_type) on cellular path -> 200
        code, body = self._post(
            [legacy_result(fps[1][0], fps[1][1], NOW - 9, True, 110)], "cellular")
        self.assertEqual(code, 200)
        self.assertEqual(body["accepted"], 1, body)
        # unknown path -> 404
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.PORT}/nope", method="GET")
        req.add_header("X-Probe-Action", "tasks")
        try:
            urllib.request.urlopen(req, timeout=5)
            self.fail("expected 404")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)

    def test_S05_midrun_switch_rejected(self):
        # Batch 1 (wifi) accepted; batch 2 same run re-labelled cellular
        # and posted to the wifi endpoint -> rejected; batch 1 intact.
        fps = self.fps(3)
        b1 = [make_result(fp, name, NOW - 30 + i, True, 100 + i)
              for i, (fp, name) in enumerate(fps[:2])]
        code, body = self._post(b1, "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertEqual(body["accepted"], 2, body)
        b2 = [make_result(fps[2][0], fps[2][1], NOW - 5, True, 100,
                           network_type="cellular")]
        code, body = self._post(b2, "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertEqual(body["accepted"], 0, body)
        self.assertEqual(body["rejected"], 1, body)
        conn = sqlite3.connect(self.db_path)
        n = conn.execute("SELECT COUNT(*) FROM probe_reports_wifi").fetchone()[0]
        conn.close()
        self.assertEqual(n, 2, "switched batch leaked into wifi table")

    def test_E2E_both_channels(self):
        # Full HTTP round trip: tasks -> report, per channel.
        code, body = self._get("tasks", "cellular")
        self.assertEqual(code, 200)
        self.assertGreater(len(body["tasks"]), 0, body)
        # P0-1: tasks info always carries the pool SHA (server authority).
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA)
        code, body = self._get("tasks", "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertGreater(len(body["tasks"]), 0, body)
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA)
        fps = self.fps(2)
        code, body = self._post(
            [make_result(fps[0][0], fps[0][1], NOW - 3, True, 88)],
            "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertEqual(body["accepted"], 1, body)
        code, body = self._get("stats", "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertEqual(body["tested_day"], 1)
        self.assertEqual(body["network_type"], "wifi")
        code, body = self._get("stats", "cellular")
        self.assertEqual(code, 200)
        self.assertEqual(body["tested_day"], 0)

    def test_S15_tasks_info_pool_sha_on_early_return(self):
        # P0-1: even when tasks are refused (cap / circuit / target met),
        # the info still carries pool_sha, so the client never reports
        # results without a pool version to bind them to.
        now = int(time.time())
        if now % 3600 < 60:
            time.sleep(61 - (now % 3600))
            now = int(time.time())
        hour_start = now - (now % 3600)
        base = max(hour_start + 1, now - 300)
        fps = self.fps(12)
        res = []
        for i in range(20):
            fp, name = fps[i % len(fps)]
            res.append(make_result(fp, name, base + i, i % 3 != 0, 200))
        for j in range(0, len(res), 8):
            dual.ingest_wifi(res[j:j + 8])
        code, body = self._get("tasks", "wifi", net_hdr="wifi")
        self.assertEqual(code, 200)
        self.assertEqual(body["tasks"], [])
        self.assertEqual(body["info"]["reason"], "wifi_hour_cap_reached")
        self.assertEqual(body["info"]["pool_sha"], POOL_SHA)


class TestScriptStatic(unittest.TestCase):
    def test_J03_client_version_injection_verifies(self):
        # P0-1: the injected constant is CLIENT_VERSION (script build id),
        # never SOURCE_VERSION_SHA.
        data = open(DUAL_JS, "rb").read()
        self.assertNotIn(b"SOURCE_VERSION_SHA", data)
        m = re.search(rb"const CLIENT_VERSION = 'dual-v1-([0-9a-f]{12})';", data)
        self.assertIsNotNone(m, "CLIENT_VERSION constant not found")
        sha12 = m.group(1).decode()
        norm = re.sub(rb"dual-v1-[0-9a-f]{12}", b"dual-v1-000000000000", data)
        self.assertEqual(hashlib.sha256(norm).hexdigest()[:12], sha12)
        self.assertEqual("dual-v1-" + sha12, CLIENT_VERSION)

    def test_J02_no_sensitive_values_sent(self):
        src = open(DUAL_JS, encoding="utf-8").read()
        # SSID is only read inside detectNetwork; never placed in a result.
        push = src[src.index("results.push({"):src.index("});", src.index("results.push({"))]
        self.assertNotIn("ssid", push.lower())
        self.assertNotIn("interface", push.lower())
        self.assertIn("network_type: networkType", push)
        # P0-1: pool sha comes from the server (poolSha), client version
        # is the script build id; the two fields are distinct.
        self.assertIn("source_version_sha: poolSha", push)
        self.assertIn("client_version: CLIENT_VERSION", push)
        self.assertNotIn("pdp_ip", push)

    def test_J04_no_direct_fallback(self):
        src = open(DUAL_JS, encoding="utf-8").read()
        self.assertNotIn("policy: 'DIRECT'", src)
        self.assertNotIn('policy: "DIRECT"', src)
        self.assertIn("policy: identifier", src)
        self.assertIn("Never falls back to DIRECT", src)

    def test_J05_unknown_is_fail_closed_in_source(self):
        src = open(DUAL_JS, encoding="utf-8").read()
        self.assertIn("return 'unknown';", src)
        self.assertIn("unknown or ambiguous network (fail-closed)", src)
        self.assertIn("network_changed", src)
        # old gate is gone: no bare isCellular() skip
        self.assertNotIn("isCellular()", src)


if __name__ == "__main__":
    unittest.main(verbosity=2)
