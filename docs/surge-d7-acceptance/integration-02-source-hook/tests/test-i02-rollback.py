#!/usr/bin/env python3
"""Part 8 (integration-02): keep-mode rollback verification (a)(b)(c)
+ zero-write window, on COPIES of the fresh production pool.db snapshot
(work/pool-snapshot.db, 2026-11-24 11:15, 7798 nodes). Never touches
the live DB. Adapted from P1-1 test-rollback-abc.py (same v4 migrate
CLI, new snapshot + i02 paths).

(a) new module / scraper calls actually disabled: after a retained
    rollback, no further record_sighting / status calls are made and the
    lineage state is stable across an observation window.
(b) observation window with no new lineage events, status logs or test
    writes: lineage + node_tests counts identical at window start/end.
(c) DB with attached tables keeps working normally: production liveness
    query + lineage queries return sane results; integrity ok.

Also: zero-write window whole-DB restore on a SECOND copy (snapshot
only -- this path is DISABLED for production by GPT, exercised here
only to prove the CLI distinguishes the two modes); do_check exit
codes and read-only behaviour; --allow-data-loss rejected (exit 2);
--rollback without --backup rejected.
"""
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
POOL = (os.path.join(HERE, "pool") if os.path.exists(os.path.join(HERE, "pool", "crawler.py"))
        else os.path.join(HERE, "..", "pool"))
# Snapshot: default is the i02 work snapshot; override with
# I02_POOL_SNAPSHOT to point at another pool.db copy.
SNAP = os.path.expanduser(os.environ.get(
    "I02_POOL_SNAPSHOT",
    "~/workspace/tester-diag-pr/pr127-integration-02/work/pool-snapshot.db"))
WORK = os.path.join(HERE, "rollback-work")
KEY = b"i02-test-key-do-not-use-in-production"

sys.path.insert(0, POOL)
sys.path.insert(0, os.path.dirname(os.path.abspath(POOL)))
import source_lineage as sl  # noqa: E402


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run_cli(*args):
    r = subprocess.run(
        [sys.executable, os.path.join(POOL, "migrate_node_sources.py"), *args],
        capture_output=True, text=True)
    try:
        rep = json.loads(r.stdout) if r.stdout.strip() else {}
    except Exception:
        rep = {"_raw_stdout": r.stdout, "_stderr": r.stderr}
    return r.returncode, rep


def lineage_counts(conn):
    return {
        "node_variants": conn.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0],
        "node_sources": conn.execute("SELECT COUNT(*) FROM node_sources").fetchone()[0],
        "sighting_events": conn.execute("SELECT COUNT(*) FROM sighting_events").fetchone()[0],
        "source_status_log": conn.execute("SELECT COUNT(*) FROM source_status_log").fetchone()[0],
        "node_tests": conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0],
        "nodes": conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0],
    }


def main():
    os.makedirs(WORK, exist_ok=True)
    print("snapshot sha:", sha(SNAP)[:16])
    now = int(time.time())

    # ---- Copy A: retained rollback after post-backup writes ----
    db_a = os.path.join(WORK, "copy-a.db")
    shutil.copyfile(SNAP, db_a)
    # --check on the unmigrated copy is a read-only dry-run: ok=True,
    # table_exists False, would_backfill_rows == nodes (7798). It must
    # not write anything.
    d0 = sha(db_a)
    rc, rep = run_cli(db_a, "--check")
    print("A --check before migrate: rc", rc, "ok", rep.get("ok"),
          "table_exists", rep.get("table_exists"),
          "would_backfill_rows", rep.get("would_backfill_rows"))
    assert rc == 0 and rep.get("ok") is True
    assert rep.get("table_exists") is False
    assert rep.get("would_backfill_rows") == 7798, rep
    assert sha(db_a) == d0, "--check modified the file!"
    rc, rep = run_cli(db_a, "--backup-dir", os.path.join(WORK, "backups-a"))
    print("A migrate rc:", rc, "backfilled:", rep.get("backfilled_rows"),
          "lineage_rows:", rep.get("lineage_rows"))
    assert rc == 0 and rep.get("ok") is True
    backup_a = rep["backup_path"]
    conn = sqlite3.connect(db_a)
    c0 = lineage_counts(conn)
    print("A post-migrate counts:", c0)
    assert c0["node_sources"] == c0["nodes"] and c0["sighting_events"] == 0
    # Post-backup writes, all three kinds GPT named:
    # (1) new node_tests row
    conn.execute(
        "INSERT INTO node_tests VALUES ('trojan','203.0.113.99',443,?, 'pass','synthetic', 123.0)",
        (now,))
    # (2) sighting event on an EXISTING key (legacy row for a real node)
    row = conn.execute(
        "SELECT protocol, host, port FROM nodes LIMIT 1").fetchone()
    proto, host, port = row
    cfg = {"protocol": proto, "host": host, "port": int(port),
           "password": "synthetic-only", "sni": "synthetic.example"}
    fp = sl.config_fingerprint(cfg, KEY)
    r = sl.record_sighting(conn, proto, host, int(port), fp, "synthetic-src",
                           now, evidence="i02-run-1",
                           event_id="i02-ev-1")
    assert r["accepted"] is True, r
    # (3) status-log change
    sl.set_source_status(conn, "synthetic-src", "paused", now, "i02 test")
    conn.commit()
    c1 = lineage_counts(conn)
    print("A after post-backup writes:", c1)
    assert c1["node_tests"] == c0["node_tests"] + 1
    assert c1["sighting_events"] == 1 and c1["source_status_log"] == 1
    conn.close()
    digest_before = sha(db_a)
    rc, rep = run_cli(db_a, "--rollback", "--backup", backup_a)
    print("A rollback rc:", rc, "mode:", rep.get("mode"),
          "whole_db_restore:", rep.get("whole_db_restore"))
    print("A rollback changes:", rep.get("post_backup_changes"))
    assert rc == 0 and rep.get("mode") == "retained"
    assert rep.get("whole_db_restore") == "refused"
    assert sha(db_a) == digest_before, "retained rollback modified the file!"
    print("A file digest unchanged after retained rollback: OK")
    # (a)+(b): disable calls, observe a window, assert stability.
    conn = sqlite3.connect(db_a)
    w0 = lineage_counts(conn)
    time.sleep(2)  # observation window; NO record_sighting/status/test calls
    w1 = lineage_counts(conn)
    print("A window start:", w0)
    print("A window end  :", w1)
    assert w0 == w1, "lineage/test state moved during the disabled window"
    # (c): DB with attached tables still works normally.
    live = conn.execute(
        "SELECT protocol, host, port, ms FROM node_tests "
        "WHERE result='pass' ORDER BY protocol, host, port, tested_at DESC LIMIT 5"
    ).fetchall()
    lin = sl.lineage(conn, proto, host, int(port), fp)
    integ = conn.execute("PRAGMA integrity_check").fetchone()[0]
    print("A (c) liveness rows:", len(live), "| lineage rows for test variant:",
          len(lin), "| integrity:", integ)
    assert len(live) == 5 and len(lin) == 1 and integ == "ok"
    conn.close()
    print("A (a)(b)(c): ROLLBACK COMPLETE (retained)")

    # ---- Copy B: zero-write window whole-DB restore (snapshot only) ----
    db_b = os.path.join(WORK, "copy-b.db")
    shutil.copyfile(SNAP, db_b)
    rc, rep = run_cli(db_b, "--backup-dir", os.path.join(WORK, "backups-b"))
    assert rc == 0 and rep.get("ok") is True
    backup_b = rep["backup_path"]
    rc, rep = run_cli(db_b, "--rollback", "--backup", backup_b)
    print("B rollback rc:", rc, "mode:", rep.get("mode"),
          "whole_db_restore:", rep.get("whole_db_restore"))
    assert rc == 0 and rep.get("mode") == "restored"
    conn = sqlite3.connect(db_b)
    has = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'"
    ).fetchone()
    print("B lineage tables gone after restore:", has is None)
    assert has is None
    conn.close()
    print("B zero-write restore on snapshot copy: OK "
          "(production use of this path is DISABLED by GPT)")

    # ---- Exit codes ----
    rc, rep = run_cli(db_a, "--check")
    print("do_check on migrated DB: rc", rc, "ok", rep.get("ok"))
    assert rc == 0
    r = subprocess.run(
        [sys.executable, os.path.join(POOL, "migrate_node_sources.py"),
         db_a, "--rollback", "--backup", backup_a, "--allow-data-loss"],
        capture_output=True, text=True)
    print("--allow-data-loss rejected, exit:", r.returncode)
    assert r.returncode == 2
    r = subprocess.run(
        [sys.executable, os.path.join(POOL, "migrate_node_sources.py"),
         db_a, "--rollback"],
        capture_output=True, text=True)
    print("--rollback without --backup rejected, exit:", r.returncode)
    assert r.returncode == 2
    print("\nALL I02 ROLLBACK CHECKS PASSED")


if __name__ == "__main__":
    main()
