#!/usr/bin/env python3
"""D5 backup/restore desktop drill (Issue #73, GPT D4 review item 2).

Runs the D4 snapshot/restore path end-to-end on SYNTHETIC data in an
isolation root (<tree>/drills/_d5_work). Nothing here touches
production: no /opt/free-node-program, no real timers/services, no
phone config, no real credentials. All nodes are TEST-NET 192.0.2.x,
password placeholder TEST-ONLY-NOT-A-REAL-NODE.

Coverage (13 pass/fail checks + 1 informational item, D4 9/10口径):
  1  synth_live_built
  2  snapshot_manifest_complete
  3  wal_snapshot_consistent_uncheckpointed_rows   (WAL a)
  4  wal_stale_sidecar_cleared_before_restore     (WAL b, 情形一)
  5  wal_replay_then_checkpoint                   (WAL b, 情形二)
  6  wal_open_sidecar_reproduced_and_cleaned      (WAL c, D4 发现复现)
  7  live_loss_simulated_and_restored             (PROCEDURE §3 顺序推演)
  8  restore_sha_matches_manifest
  9  restored_db_counts_match
 10  restored_publish_parses
 11  restored_config_keys_match
 12  gate_dry_run_restored_equals_snapshot
 13  units_scripts_sha_match_and_verify
 14  legacy_no_manifest                          (信息项, 不计入通过门)

The "stop -> restore -> start" service/timer sequence is a DESKTOP
rehearsal only: no real systemctl start/stop is ever issued; only
`systemd-analyze verify` (read-only) is run against the restored units.

Usage:
  backup_restore_drill.py [--root <work root>] [--log <log json path>]
      [--code-dir <D5 tree>] [--snapshot-script <path>]
Exit 0 = all pass/fail checks pass (informational item excluded).
Stdout: one JSON object (the log). Counts / SHA prefixes only.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

CST = ZoneInfo("Asia/Shanghai")


def cst_now():
    return datetime.now(CST).strftime("%Y-%m-%d %H:%M:%S")

SPEC = {
    "nodes_total": 12, "nodes_checkpointed": 8, "nodes_in_wal": 4,
    "pinned": 3, "blocklist": 2, "tests": 20,
    "probe_nodes": 5, "probe_reports": 10,
    "publish_lines": 8, "publish_pinned": 3, "publish_rotation": 5,
    "publish_prev_lines": 7, "publish_history_lines": 6,
}
PINNED_KEYS = [("trojan", "192.0.2.1", 40000),
               ("trojan", "192.0.2.2", 40001),
               ("trojan", "192.0.2.3", 40002)]
ROTATION_KEYS = [("trojan", "192.0.2.1%d" % i, 40010 + i)
                 for i in range(1, 6)]
BLOCKED_KEYS = [("trojan", "192.0.2.99", 40099),
                ("trojan", "192.0.2.98", 40098)]
WAL_EXTRA_HOSTS = ["192.0.2.2%d" % i for i in range(1, 5)]
LINE_RE = re.compile(r"^\s*[^=]+=\s*([A-Za-z0-9_-]+)\s*,\s*([^,\s]+)\s*,\s*(\d+)")
FAKE_PASSWORD = "TEST-ONLY-NOT-A-REAL-NODE"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def db_counts(path, read_only=True):
    uri = ("file:%s?mode=ro" % path) if read_only else path
    con = sqlite3.connect(uri, uri=True) if read_only else sqlite3.connect(path)
    try:
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")]
        return {t: con.execute("SELECT COUNT(*) FROM %s" % t).fetchone()[0]
                for t in tables if t != "sqlite_sequence"}
    finally:
        con.close()


def sidecar_sizes(path):
    out = {}
    for suf in ("-wal", "-shm"):
        p = path + suf
        out[suf] = os.path.getsize(p) if os.path.exists(p) else None
    return out


def sub_line(name, proto, host, port):
    return ("%s = %s, %s, %d, password=%s, sni=test.invalid"
            % (name, proto, host, port, FAKE_PASSWORD))


def build_live(root):
    """Build the synthetic live tree. Returns (live_dir, pool_conn).

    The pool.db connection is returned OPEN with 4 committed-but-
    un-checkpointed rows sitting in the -wal file, so the snapshot
    step can prove the backup API captures them. Caller must close it
    only after the snapshot and the raw WAL replay copy are done.
    """
    live = os.path.join(root, "live")
    for d in ("data", "publish/history", "config", "systemd", "pool-gate"):
        os.makedirs(os.path.join(live, d), exist_ok=True)
    # --- pool.db (WAL mode) ---
    pool_db = os.path.join(live, "data", "pool.db")
    con = sqlite3.connect(pool_db)
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("CREATE TABLE nodes(id INTEGER PRIMARY KEY, name TEXT, "
                "protocol TEXT, host TEXT, port INTEGER)")
    con.execute("CREATE TABLE pinned(protocol TEXT, host TEXT, port INTEGER)")
    con.execute("CREATE TABLE blocklist(protocol TEXT, host TEXT, port INTEGER)")
    con.execute("CREATE TABLE tests(id INTEGER PRIMARY KEY, node_id INTEGER, "
                "ms INTEGER, success INTEGER)")
    rows = []
    for i, (proto, host, port) in enumerate(PINNED_KEYS, start=1):
        rows.append((i, "D5-P%02d" % i, proto, host, port))
    for i, (proto, host, port) in enumerate(ROTATION_KEYS, start=4):
        rows.append((i, "D5-R%02d" % (i - 3), proto, host, port))
    con.executemany("INSERT INTO nodes VALUES (?,?,?,?,?)", rows)
    con.executemany("INSERT INTO pinned VALUES (?,?,?)", PINNED_KEYS)
    con.executemany("INSERT INTO blocklist VALUES (?,?,?)", BLOCKED_KEYS)
    con.executemany("INSERT INTO tests VALUES (?,?,?,?)",
                    [(i, (i % 8) + 1, 100 + i, 1) for i in range(1, 21)])
    con.commit()
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    # 4 more rows, committed but NOT checkpointed: they live in -wal.
    extra = [(8 + i, "D5-W%02d" % i, "trojan", WAL_EXTRA_HOSTS[i - 1],
              40100 + i) for i in range(1, 5)]
    con.executemany("INSERT INTO nodes VALUES (?,?,?,?,?)", extra)
    con.commit()
    # --- probe.db (WAL mode, fully checkpointed) ---
    probe_db = os.path.join(live, "data", "probe.db")
    pcon = sqlite3.connect(probe_db)
    pcon.execute("PRAGMA journal_mode=WAL")
    pcon.execute("CREATE TABLE probe_nodes(fingerprint TEXT, state TEXT)")
    pcon.execute("CREATE TABLE probe_reports(id INTEGER PRIMARY KEY "
                 "AUTOINCREMENT, fingerprint TEXT, ts INTEGER, success "
                 "INTEGER, second_ms INTEGER, second_status TEXT, "
                 "interface TEXT)")
    fps = ["%032x" % i for i in range(1, 6)]
    pcon.executemany("INSERT INTO probe_nodes VALUES (?,?)",
                     [(fp, "ok") for fp in fps])
    pcon.executemany(
        "INSERT INTO probe_reports(fingerprint, ts, success, second_ms, "
        "second_status, interface) VALUES (?,?,?,?,?,?)",
        [(fps[i % 5], 1794700000 + i, 1, 200 + i, "ok", "pdp_ip0")
         for i in range(10)])
    pcon.commit()
    pcon.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    pcon.close()
    # --- publish files ---
    lines = ([sub_line("D5-P%02d" % i, *k) for i, k in enumerate(PINNED_KEYS, 1)]
             + [sub_line("D5-R%02d" % i, *k)
                for i, k in enumerate(ROTATION_KEYS, 1)])
    with open(os.path.join(live, "publish", "pool-new.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    prev = lines[:2] + lines[3:]
    with open(os.path.join(live, "publish", "pool-new.txt.prev"), "w") as f:
        f.write("\n".join(prev) + "\n")
    with open(os.path.join(live, "publish", "history",
                           "pool-new-prev2.txt"), "w") as f:
        f.write("\n".join(lines[:6]) + "\n")
    # --- config ---
    with open(os.path.join(live, "config.yaml"), "w") as f:
        f.write("pool_name: d5-synthetic-pool\n"
                "pinned_protected: false\n"
                "publish_limit: 150\n"
                "probe_interval_s: 3600\n"
                "version: d5-synthetic-v1\n")
    with open(os.path.join(live, "config", "ui-password"), "w") as f:
        f.write(FAKE_PASSWORD + "\n")
    with open(os.path.join(live, "config", "old-pool-file.txt"), "w") as f:
        f.write(os.path.join(live, "publish", "pool-new.txt") + "\n")
    # --- old sync script (synthetic) ---
    with open(os.path.join(live, "pool-sync.sh"), "w") as f:
        f.write("#!/bin/bash\n# D5 synthetic legacy sync (ungated, isolation only).\n"
                "# Replaced by the gated sync at switch time; kept here so\n"
                "# the snapshot covers the same file set as D4.\n"
                "set -u\nSRC=\"$1\"\n"
                "cp \"$SRC\" \"$2\" 2>/dev/null || true\n")
    # --- units + wrappers (D4 structure, all paths rewritten to live/) ---
    runbook = os.path.join(live, "switch-runbook.md")
    with open(runbook, "w") as f:
        f.write("# D5 synthetic switch runbook (isolation only)\n\n"
                "Order: stop timers -> restore DB first -> restore "
                "publish/config/units -> daemon-reload (simulated) -> "
                "start timers. No real systemctl call is made by the drill.\n")
    units = {
        "pool-gate-publish.service": (
            "[Unit]\nDescription=Free node pool: gated publish (D5 synthetic)\n"
            "Documentation=file://%s\n"
            "After=network-online.target probe-service.service\n"
            "Wants=network-online.target\n\n"
            "[Service]\nType=oneshot\nWorkingDirectory=%s\n"
            "ExecStart=%s\n" % (runbook, os.path.join(live, "pool-gate"),
                                os.path.join(live, "systemd", "gate-publish.sh"))),
        "pool-gate-sync.service": (
            "[Unit]\nDescription=Free node pool: gated sync (D5 synthetic)\n"
            "Documentation=file://%s\n"
            "After=network-online.target probe-service.service\n"
            "Wants=network-online.target\n\n"
            "[Service]\nType=oneshot\nWorkingDirectory=%s\n"
            "ExecStart=%s\n" % (runbook, os.path.join(live, "pool-gate"),
                                os.path.join(live, "systemd", "gate-sync.sh"))),
        "pool-gate-publish.timer": (
            "[Unit]\nDescription=Free node pool: gated publish hourly at :07 (D5 synthetic)\n\n"
            "[Timer]\nOnCalendar=*:07\nRandomizedDelaySec=120\nPersistent=true\n\n"
            "[Install]\nWantedBy=timers.target\n"),
        "pool-gate-sync.timer": (
            "[Unit]\nDescription=Free node pool: gated sync every 15 minutes (D5 synthetic)\n\n"
            "[Timer]\nOnCalendar=*-*-* *:0/15:00\nPersistent=false\n\n"
            "[Install]\nWantedBy=timers.target\n"),
    }
    for name, text in units.items():
        with open(os.path.join(live, "systemd", name), "w") as f:
            f.write(text)
    wrappers = {
        "gate-publish.sh": (
            "#!/bin/bash\n# D5 synthetic gated publish wrapper (D4 structure,\n"
            "# isolation paths only). Gate-first: gate the current source,\n"
            "# then assemble the next version. Refusal is the safe state.\n"
            "set -u\nPROG=\"${PROG:-%s}\"\nGATE=\"${GATE:-%s}\"\n"
            "STATE=\"$GATE/state\"\nLOG=\"$GATE/logs/gate-publish.log\"\n"
            "echo \"gate-publish synthetic: PROG=$PROG STATE=$STATE\"\n"
            % (live, os.path.join(live, "pool-gate"))),
        "gate-sync.sh": (
            "#!/bin/bash\n# D5 synthetic gated sync wrapper (D4 structure,\n"
            "# isolation paths only). Sync gate first; only on rc=0 copy\n"
            "# served -> bridge (tmp+rename, SHA check).\n"
            "set -u\nPROG=\"${PROG:-%s}\"\nGATE=\"${GATE:-%s}\"\n"
            "STATE=\"$GATE/state\"\nLOG=\"$GATE/logs/gate-sync.log\"\n"
            "echo \"gate-sync synthetic: PROG=$PROG STATE=$STATE\"\n"
            % (live, os.path.join(live, "pool-gate"))),
    }
    for name, text in wrappers.items():
        p = os.path.join(live, "systemd", name)
        with open(p, "w") as f:
            f.write(text)
        os.chmod(p, 0o755)
    return live, con


def parse_subscription(path, pool_db):
    con = sqlite3.connect("file:%s?mode=ro" % pool_db, uri=True)
    try:
        pinned = {(r[0], r[1], r[2]) for r in con.execute(
            "SELECT protocol,host,port FROM pinned")}
        blocked = {(r[0], r[1], r[2]) for r in con.execute(
            "SELECT protocol,host,port FROM blocklist")}
    finally:
        con.close()
    n_pin = n_rot = n_blocked = n_unparsed = 0
    total = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            total += 1
            m = LINE_RE.match(line)
            if not m:
                n_unparsed += 1
                continue
            key = (m.group(1), m.group(2), int(m.group(3)))
            if key in blocked:
                n_blocked += 1
            elif key in pinned:
                n_pin += 1
            else:
                n_rot += 1
    return {"lines": total, "pinned": n_pin, "rotation": n_rot,
            "blocked": n_blocked, "unparsed": n_unparsed}


def top_keys(path):
    keys = []
    with open(path) as f:
        for line in f:
            s = line.strip()
            if s and not s.startswith("#") and ":" in s \
                    and not line.startswith(" "):
                keys.append(s.split(":")[0].strip())
    return keys


def snap_rel_to_live_rel(rel):
    """Snapshot layout -> live-tree layout. DBs live under data/,
    units under systemd/; everything else keeps its relative path."""
    if rel in ("pool.db", "probe.db"):
        return os.path.join("data", rel)
    if rel.startswith("units/"):
        return os.path.join("systemd", os.path.basename(rel))
    return rel


def restore_file(snapshot_path, target_path):
    """Restore one DB file per the drill procedure: clear any stale
    -wal/-shm sidecars in the target dir FIRST, then place the main
    DB file. Returns the sizes (bytes) of sidecars removed."""
    removed = {}
    for suf in ("-wal", "-shm"):
        p = target_path + suf
        if os.path.exists(p):
            removed[suf] = os.path.getsize(p)
            os.remove(p)
    os.makedirs(os.path.dirname(target_path), exist_ok=True)
    shutil.copyfile(snapshot_path, target_path)
    return removed


def gate_dry_run(code_dir, workdir, source_file, record_path, probe_db):
    """D3 publish dry-run in a scratch workdir. Returns (rc, error)."""
    sys.path.insert(0, code_dir)
    from pool.publish import run_publish  # noqa: E402
    from pool.recovery import OWNER_ACK_INIT, init_recovery_state  # noqa: E402
    rc0, _ = init_recovery_state(workdir, OWNER_ACK_INIT)
    if rc0 != 0:
        return -1, "init_failed"
    source_sha = sha256_file(source_file)
    candidates = [l.rstrip("\n") for l in open(source_file)
                  if l.strip()]
    rc, res = run_publish(workdir, candidates, record_path, source_sha,
                          probe_db=probe_db, source_file=source_file)
    return rc, res.get("error")


def main(argv=None):
    ap = argparse.ArgumentParser(description="D5 backup/restore drill")
    ap.add_argument("--root", default=None)
    ap.add_argument("--log", default=None)
    ap.add_argument("--code-dir", default=None)
    ap.add_argument("--snapshot-script", default=None)
    args = ap.parse_args(argv)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    tree = os.path.dirname(script_dir)
    root = os.path.abspath(args.root or os.path.join(script_dir, "_d5_work"))
    code_dir = os.path.abspath(args.code_dir or tree)
    snap_script = os.path.abspath(
        args.snapshot_script or os.path.join(script_dir, "snapshot_backup_d5.py"))
    log_path = os.path.abspath(
        args.log or os.path.join(tree, "docs", "backup-restore-drill-log.json"))
    checks = []
    wal_evidence = {}
    gate_evidence = {}
    verify_evidence = {}

    def check(name, ok, detail="", informational=False):
        checks.append({"check": name, "ok": bool(ok),
                       "informational": informational, "detail": str(detail)})
        return bool(ok)

    started = int(time.time())
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root, mode=0o700, exist_ok=True)
    live, pool_con = build_live(root)
    live_pool_db = os.path.join(live, "data", "pool.db")
    live_probe_db = os.path.join(live, "data", "probe.db")

    # ---- 1. synthetic live tree built ----
    try:
        counts = db_counts(live_pool_db)
        pcounts = db_counts(live_probe_db)
        pub = parse_subscription(os.path.join(live, "publish", "pool-new.txt"),
                                 live_pool_db)
        wal_before = sidecar_sizes(live_pool_db)
        ok1 = (counts.get("nodes") == SPEC["nodes_total"]
               and counts.get("pinned") == SPEC["pinned"]
               and counts.get("blocklist") == SPEC["blocklist"]
               and counts.get("tests") == SPEC["tests"]
               and pcounts.get("probe_nodes") == SPEC["probe_nodes"]
               and pcounts.get("probe_reports") == SPEC["probe_reports"]
               and pub == {"lines": 8, "pinned": 3, "rotation": 5,
                           "blocked": 0, "unparsed": 0}
               and wal_before["-wal"] is not None and wal_before["-wal"] > 0)
        wal_evidence["live_wal_bytes_before_snapshot"] = wal_before["-wal"]
        check("synth_live_built", ok1,
              "pool_db=%s probe_db=%s publish=%s live_-wal_bytes=%s"
              % (counts, pcounts, pub, wal_before["-wal"]))
    except Exception as e:  # noqa: BLE001
        check("synth_live_built", False, "%s: %s" % (type(e).__name__, e))

    # ---- WAL (b) 情形二 material: raw copy of live DB + live -wal/-shm
    # (must happen while the live connection is still open and the
    # 4 extra rows are still un-checkpointed).
    replay_dir = os.path.join(root, "wal-replay-src")
    os.makedirs(replay_dir, exist_ok=True)
    for suf in ("", "-wal", "-shm"):
        shutil.copyfile(live_pool_db + suf,
                        os.path.join(replay_dir, "pool.db" + suf))

    # ---- snapshot (D4 logic, via drills/snapshot_backup_d5.py) ----
    snap = os.path.join(root, "snapshot")
    r = subprocess.run([sys.executable, snap_script, "--src", live,
                        "--out", snap], capture_output=True, text=True)
    snap_ok = r.returncode == 0
    manifest = {}
    if snap_ok:
        manifest = json.load(open(os.path.join(snap, "manifest.json")))
    check("snapshot_manifest_complete", snap_ok and bool(manifest),
          "rc=%s files=%s stdout=%s stderr=%s" % (r.returncode,
                                        len(manifest.get("files", {})),
                                        r.stdout.strip()[:200],
                                        r.stderr.strip()[-300:]))
    manifest_files = manifest.get("files", {})

    # ---- 3. WAL (a): snapshot holds the un-checkpointed rows ----
    try:
        snap_counts = db_counts(os.path.join(snap, "pool.db"))
        # This verification read itself leaves -wal/-shm beside the
        # snapshot DB (same D4 effect): clean up after it, or the next
        # check would mistake our own leftovers for the snapshot's.
        snap_sidecars_left = 0
        for suf in ("-wal", "-shm"):
            p = os.path.join(snap, "pool.db" + suf)
            if os.path.exists(p):
                os.remove(p)
                snap_sidecars_left += 1
        wal_evidence["check3_verification_read_sidecars_cleaned"] = \
            snap_sidecars_left
        snap_copy = os.path.join(root, "snap-check-copy.db")
        shutil.copyfile(os.path.join(snap, "pool.db"), snap_copy)
        c = sqlite3.connect(snap_copy)
        ckpt = c.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        after = c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        c.close()
        for suf in ("-wal", "-shm"):
            p = snap_copy + suf
            if os.path.exists(p):
                os.remove(p)
        check("wal_snapshot_consistent_uncheckpointed_rows",
              snap_counts.get("nodes") == SPEC["nodes_total"]
              and after == SPEC["nodes_total"],
              "snapshot_nodes=%s after_checkpoint_nodes=%s checkpoint=%s"
              % (snap_counts.get("nodes"), after, ckpt))
        wal_evidence["snapshot_nodes"] = snap_counts.get("nodes")
        wal_evidence["after_checkpoint_nodes"] = after
    except Exception as e:  # noqa: BLE001
        check("wal_snapshot_consistent_uncheckpointed_rows", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 4. WAL (b) 情形一: stale sidecars cleared before restore ----
    try:
        stale_dir = os.path.join(root, "restore-stale")
        os.makedirs(stale_dir, exist_ok=True)
        stale_db = os.path.join(stale_dir, "pool.db")
        with open(stale_db + "-wal", "wb") as f:
            f.write(b"STALE-TEST-WAL-CONTENT")
        with open(stale_db + "-shm", "wb") as f:
            f.write(b"STALE-TEST-SHM-CONTENT")
        removed = restore_file(os.path.join(snap, "pool.db"), stale_db)
        c = sqlite3.connect(stale_db)
        n = c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        c.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        c.close()
        left = sidecar_sizes(stale_db)
        for suf in ("-wal", "-shm"):
            p = stale_db + suf
            if os.path.exists(p):
                os.remove(p)
        check("wal_stale_sidecar_cleared_before_restore",
              n == SPEC["nodes_total"] and removed.get("-wal") == 22
              and removed.get("-shm") == 22
              and left["-wal"] in (None, 0),
              "removed_stale_sidecars=%s restored_nodes=%s sidecars_after=%s"
              % (removed, n, left))
        wal_evidence["stale_sidecars_removed_bytes"] = removed
        wal_evidence["stale_restore_nodes"] = n
    except Exception as e:  # noqa: BLE001
        check("wal_stale_sidecar_cleared_before_restore", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 5. WAL (b) 情形二: replay the live -wal, then checkpoint ----
    try:
        rp = os.path.join(replay_dir, "pool.db")
        c = sqlite3.connect(rp)
        n_replay = c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        ckpt = c.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        n_after = c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        c.close()
        left = sidecar_sizes(rp)
        check("wal_replay_then_checkpoint",
              n_replay == SPEC["nodes_total"]
              and n_after == SPEC["nodes_total"],
              "replayed_nodes=%s after_checkpoint_nodes=%s "
              "sidecars_after_close=%s" % (n_replay, n_after, left))
        wal_evidence["replay_nodes"] = n_replay
        wal_evidence["replay_after_checkpoint_nodes"] = n_after
    except Exception as e:  # noqa: BLE001
        check("wal_replay_then_checkpoint", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 6. WAL (c): reproduce the D4 finding on the snapshot itself ----
    # The snapshot script now cleans sidecars after its own verification
    # reads, so the snapshot dir must be sidecar-free BEFORE this open.
    # Opening the snapshot pool.db read-only must then reproduce the D4
    # finding (0-byte -wal + 32768-byte -shm), after which deleting them
    # must leave the snapshot dir exactly equal to the manifest set.
    try:
        def snap_tree():
            out = set()
            for r, _d, files in os.walk(snap):
                for fn in files:
                    out.add(os.path.relpath(os.path.join(r, fn), snap))
            return out

        manifest_set = set(manifest_files) | {"manifest.json"}
        pre_sidecars = [p for p in snap_tree()
                        if p.endswith("-wal") or p.endswith("-shm")]
        c = sqlite3.connect("file:%s?mode=ro" % os.path.join(snap, "pool.db"),
                            uri=True)
        n_ro = c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        c.close()
        observed = sidecar_sizes(os.path.join(snap, "pool.db"))
        for suf in ("-wal", "-shm"):
            p = os.path.join(snap, "pool.db" + suf)
            if os.path.exists(p):
                os.remove(p)
        after_set = snap_tree()
        sha_after = sha256_file(os.path.join(snap, "pool.db"))
        check("wal_open_sidecar_reproduced_and_cleaned",
              not pre_sidecars
              and n_ro == SPEC["nodes_total"]
              and observed.get("-wal") == 0
              and observed.get("-shm") == 32768
              and after_set == manifest_set
              and sha_after == manifest_files["pool.db"]["sha256"],
              "sidecars_in_snapshot_before_open=%s ro_nodes=%s "
              "sidecars_observed=%s snapshot_listing_equals_manifest=%s "
              "sha_still_matches_manifest=%s"
              % (pre_sidecars, n_ro, observed, after_set == manifest_set,
                 sha_after == manifest_files["pool.db"]["sha256"]))
        wal_evidence["open_sidecars_observed"] = observed
        wal_evidence["sidecars_in_snapshot_before_open"] = pre_sidecars
    except Exception as e:  # noqa: BLE001
        check("wal_open_sidecar_reproduced_and_cleaned", False,
              "%s: %s" % (type(e).__name__, e))

    # Live connection can close now: snapshot + replay material are taken.
    pool_con.close()

    # ---- legacy no-manifest backup (files only, no manifest) ----
    legacy = os.path.join(root, "legacy")
    for rel in ("data/pool.db", "data/probe.db", "publish/pool-new.txt",
                "publish/pool-new.txt.prev", "config.yaml"):
        s = os.path.join(live, rel)
        d = os.path.join(legacy, rel)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(s, d)
    # NOTE: legacy pool.db was copied as a plain file AFTER the live
    # connection closed (checkpointed on close), so it is a consistent
    # file copy -- exactly the old p1p3 situation (files, no manifest).

    # ---- 7. simulate live loss, then restore per PROCEDURE §3 order ----
    sequence = [
        "stop timers (desktop simulation only: no real systemctl call)",
        "restore DB first (pool.db, probe.db; stale sidecars cleared first)",
        "restore publish files, config, units, wrapper scripts "
        "(re-apply +x to wrappers: snapshot stores mode 600)",
        "daemon-reload (desktop simulation only: no real systemctl call)",
        "start timers (desktop simulation only: no real systemctl call)",
    ]
    lost = os.path.join(root, "live-lost")
    os.rename(live, lost)
    restored_live = live  # restore back into the canonical live/ path
    os.makedirs(restored_live, mode=0o700, exist_ok=True)
    try:
        removed_db = {}
        for name in ("pool.db", "probe.db"):
            removed_db[name] = restore_file(
                os.path.join(snap, name),
                os.path.join(restored_live, "data", name))
        for rel in manifest_files:
            if rel in ("pool.db", "probe.db"):
                continue
            s = os.path.join(snap, rel)
            d = os.path.join(restored_live, snap_rel_to_live_rel(rel))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copyfile(s, d)
        # The snapshot stores every file mode 600, so restored wrapper
        # scripts lose their exec bit: the restore procedure must
        # re-apply +x explicitly (D4 PROCEDURE §3 does not say this --
        # recorded here as a restore-procedure gap to fix).
        for name in ("gate-publish.sh", "gate-sync.sh"):
            os.chmod(os.path.join(restored_live, "systemd", name), 0o755)
        check("live_loss_simulated_and_restored",
              os.path.isdir(restored_live)
              and os.path.exists(os.path.join(restored_live, "data", "pool.db")),
              "sequence=%s stale_sidecars_removed_on_db_restore=%s"
              % (" > ".join(sequence), removed_db))
    except Exception as e:  # noqa: BLE001
        check("live_loss_simulated_and_restored", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 8. restored SHA vs manifest ----
    try:
        mismatches = []
        for rel, meta in manifest_files.items():
            p = os.path.join(restored_live, snap_rel_to_live_rel(rel))
            if not os.path.exists(p) or sha256_file(p) != meta["sha256"]:
                mismatches.append(rel)
        check("restore_sha_matches_manifest", not mismatches,
              "files=%d mismatches=%s" % (len(manifest_files), mismatches))
    except Exception as e:  # noqa: BLE001
        check("restore_sha_matches_manifest", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 9. restored DB counts vs manifest ----
    try:
        rc_pool = db_counts(os.path.join(restored_live, "data", "pool.db"))
        rc_probe = db_counts(os.path.join(restored_live, "data", "probe.db"))
        check("restored_db_counts_match",
              rc_pool == manifest["counts"]["pool.db"]
              and rc_probe == manifest["counts"]["probe.db"],
              "pool_db=%s probe_db=%s" % (rc_pool, rc_probe))
    except Exception as e:  # noqa: BLE001
        check("restored_db_counts_match", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 10. restored publish parses like manifest ----
    try:
        parsed = parse_subscription(
            os.path.join(restored_live, "publish", "pool-new.txt"),
            os.path.join(restored_live, "data", "pool.db"))
        check("restored_publish_parses",
              parsed == manifest["counts"]["publish_file"], str(parsed))
    except Exception as e:  # noqa: BLE001
        check("restored_publish_parses", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 11. restored config keys match ----
    try:
        live_keys = top_keys(os.path.join(lost, "config.yaml"))
        rest_keys = top_keys(os.path.join(restored_live, "config.yaml"))
        with open(os.path.join(restored_live, "config.yaml")) as f:
            pinned_val = [l.strip() for l in f
                          if l.startswith("pinned_protected:")]
        check("restored_config_keys_match",
              rest_keys == live_keys
              and pinned_val == ["pinned_protected: false"],
              "keys=%s pinned_protected=%s" % (rest_keys, pinned_val))
    except Exception as e:  # noqa: BLE001
        check("restored_config_keys_match", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 12. gate dry-run: restored vs snapshot verdict identical ----
    try:
        fix = os.path.join(code_dir, "fixtures")
        record_path = os.path.join(fix, "native_results_fixture.json")
        probe_db = os.path.join(restored_live, "data", "probe.db")
        wd1 = os.path.join(root, "gate-wd-snapshot")
        wd2 = os.path.join(root, "gate-wd-restored")
        os.makedirs(wd1, exist_ok=True)
        os.makedirs(wd2, exist_ok=True)
        rc1, err1 = gate_dry_run(code_dir, wd1,
                                 os.path.join(snap, "publish", "pool-new.txt"),
                                 record_path, probe_db)
        rc2, err2 = gate_dry_run(code_dir, wd2,
                                 os.path.join(restored_live, "publish",
                                              "pool-new.txt"),
                                 record_path, probe_db)
        gate_evidence = {"snapshot": {"rc": rc1, "error": err1},
                         "restored": {"rc": rc2, "error": err2},
                         "identical": (rc1, err1) == (rc2, err2)}
        check("gate_dry_run_restored_equals_snapshot",
              (rc1, err1) == (rc2, err2)
              and rc1 == 1 and err1 == "phone_gate_zero_qualified",
              "snapshot rc=%s err=%s | restored rc=%s err=%s "
              "(expected rc=1 phone_gate_zero_qualified: fixture native "
              "record is for a different version)" % (rc1, err1, rc2, err2))
    except Exception as e:  # noqa: BLE001
        check("gate_dry_run_restored_equals_snapshot", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 13. units + wrappers SHA, then systemd-analyze verify ----
    try:
        unit_names = ["pool-gate-publish.service", "pool-gate-sync.service",
                      "pool-gate-publish.timer", "pool-gate-sync.timer"]
        wrap_names = ["gate-publish.sh", "gate-sync.sh"]
        sha_bad = []
        for name in unit_names + wrap_names:
            rel = "units/" + name
            p = os.path.join(restored_live, "systemd", name)
            if (not os.path.exists(p)
                    or sha256_file(p) != manifest_files[rel]["sha256"]):
                sha_bad.append(name)
        syntax_pat = re.compile(
            r"Failed to parse|Unknown key|Unknown lvalue|syntax error",
            re.IGNORECASE)
        per_unit = {}
        verify_bad = []
        exec_bad = []
        for name in unit_names:
            p = os.path.join(restored_live, "systemd", name)
            v = subprocess.run(["systemd-analyze", "verify", p],
                               capture_output=True, text=True, timeout=120)
            err_lines = [l for l in (v.stderr + v.stdout).splitlines()
                         if l.strip()]
            # systemd-analyze verify also reports errors from unrelated
            # host units (e.g. motd-news.timer, apt-daily.timer);
            # only lines naming OUR unit, or syntax errors, count.
            relevant = [l for l in err_lines
                        if "pool-gate-" in l or syntax_pat.search(l)]
            per_unit[name] = {"exit": v.returncode,
                              "stderr_lines": len(err_lines),
                              "relevant_lines": relevant[:3]}
            if v.returncode != 0 and relevant:
                verify_bad.append(name)
        for name in wrap_names:
            p = os.path.join(restored_live, "systemd", name)
            if not os.access(p, os.X_OK):
                exec_bad.append(name)
        verify_evidence = per_unit
        check("units_scripts_sha_match_and_verify",
              not sha_bad and not verify_bad and not exec_bad,
              "sha_mismatches=%s verify_failures=%s wrappers_not_executable=%s "
              "per_unit_exit=%s"
              % (sha_bad, verify_bad, exec_bad,
                 {k: v["exit"] for k, v in per_unit.items()}))
    except Exception as e:  # noqa: BLE001
        check("units_scripts_sha_match_and_verify", False,
              "%s: %s" % (type(e).__name__, e))

    # ---- 14. legacy no-manifest backup (INFORMATIONAL, not a gate) ----
    try:
        lcounts = db_counts(os.path.join(legacy, "data", "pool.db"))
        llines = [l for l in open(os.path.join(legacy, "publish",
                                               "pool-new.txt"))
                  if l.strip()]
        has_manifest = os.path.exists(os.path.join(legacy, "manifest.json"))
        check("legacy_no_manifest", False,
              "exists, pool_db opens (nodes=%s), subscription parses "
              "(lines=%d), manifest_present=%s -> conclusion: exists, "
              "recoverable, but NO manifest self-proof (informational "
              "item, not a pass/fail gate; same treatment as D4 9/10)"
              % (lcounts.get("nodes"), len(llines), has_manifest),
              informational=True)
    except Exception as e:  # noqa: BLE001
        check("legacy_no_manifest", False,
              "%s: %s" % (type(e).__name__, e), informational=True)

    gated = [c for c in checks if not c["informational"]]
    info = [c for c in checks if c["informational"]]
    passed = sum(1 for c in gated if c["ok"])
    log = {
        "drill": "backup_restore_drill_d5",
        "synthetic": True,
        "root": root,
        "code_dir": code_dir,
        "started_at_cst": cst_now(),
        "finished_at_cst": cst_now(),
        "checks": checks,
        "passed": passed,
        "failed": len(gated) - passed,
        "total_passfail": len(gated),
        "informational": len(info),
        "ok": passed == len(gated),
        "wal": wal_evidence,
        "gate_dry_run": gate_evidence,
        "systemd_verify": verify_evidence,
        "restore_sequence": sequence,
        "spec_counts": SPEC,
        "manifest_files": len(manifest_files),
        "publish_sha_prefix": manifest_files.get(
            "publish/pool-new.txt", {}).get("sha256", "")[:12],
        "note": "All data synthetic (TEST-NET 192.0.2.x, "
                "TEST-ONLY-NOT-A-REAL-NODE). No production paths touched; "
                "no real systemctl start/stop issued.",
    }
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w") as f:
        json.dump(log, f, indent=1, ensure_ascii=False)
    os.chmod(log_path, 0o600)
    print(json.dumps(log, indent=1, ensure_ascii=False))
    return 0 if log["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
