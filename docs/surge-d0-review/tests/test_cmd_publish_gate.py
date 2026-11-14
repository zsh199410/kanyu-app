"""Integration test for pool/cli.py cmd_publish phone gate (D0).

Builds a minimal isolated environment in a temp dir (test pool.db, test
probe.db, test publish dir, test config). Monkeypatches read_pinned_lines,
_fresh_records and IpApi so no production file or network is touched.
Verifies:
  - with a non-empty verified set, only verified lines publish;
  - with an empty verified set, publish is REFUSED and the old file is kept;
  - with the gate disabled (phone_gate_enabled=false), behaviour is the old
    one (all VPS-passing lines publish);
  - a verified pinned line and a verified rotation line both publish, while
    an unverified pinned line is dropped (pinned loses its exemption).
No production files are touched. No secrets, URIs, or credentials appear.
"""

import json
import logging
import os
import sqlite3
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool import cli as pool_cli
from pool import db as dbmod
from pool import phone_gate


class StubIpApi:
    def country(self, host):
        return ("HK", "Hong Kong")


class NullLog:
    def info(self, *a, **k):
        pass

    def error(self, *a, **k):
        pass

    def warning(self, *a, **k):
        pass


def build_probe_db(path, now):
    conn = sqlite3.connect(path)
    conn.execute("""CREATE TABLE probe_nodes(
        fingerprint TEXT PRIMARY KEY, name TEXT NOT NULL,
        protocol TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        first_seen INTEGER NOT NULL, last_seen_in_pool INTEGER NOT NULL,
        last_phone_ts INTEGER, last_warm_ms INTEGER, last_second_ms INTEGER,
        last_status INTEGER, last_success INTEGER, last_error TEXT,
        last_interface TEXT, phone_ok INTEGER NOT NULL DEFAULT 0,
        phone_fail INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL
    )""")
    conn.execute("""CREATE TABLE probe_reports(
        id INTEGER PRIMARY KEY AUTOINCREMENT, fingerprint TEXT NOT NULL,
        name TEXT NOT NULL, ts INTEGER NOT NULL, state TEXT NOT NULL,
        warm_ms INTEGER, second_ms INTEGER, second_status INTEGER,
        success INTEGER NOT NULL, error TEXT, interface TEXT,
        UNIQUE(fingerprint, ts)
    )""")
    conn.commit()
    return conn


def run():
    passed = []
    failed = []

    def check(label, cond):
        if cond:
            passed.append(label)
            print("PASS %s" % label)
        else:
            failed.append(label)
            print("FAIL %s" % label)

    now = int(time.time())
    tmpdir = tempfile.mkdtemp(prefix="d0-cmdpub-")
    base = os.path.join(tmpdir, "base")
    os.makedirs(os.path.join(base, "data"))
    os.makedirs(os.path.join(base, "publish"))

    # --- probe.db: one verified pinned, one verified rotation, one failed ---
    probe_db = os.path.join(tmpdir, "probe.db")
    pconn = build_probe_db(probe_db, now)
    fp_pin_ok = phone_gate.fingerprint_of("trojan", "pinok.invalid", 443, {"password": "pw1"})
    fp_rot_ok = phone_gate.fingerprint_of("trojan", "rotok.invalid", 443, {"password": "pw2"})
    fp_pin_bad = phone_gate.fingerprint_of("trojan", "pinbad.invalid", 443, {"password": "pw3"})
    for fp, name in ((fp_pin_ok, "PinOk"), (fp_rot_ok, "RotOk"), (fp_pin_bad, "PinBad")):
        pconn.execute(
            """INSERT INTO probe_nodes(fingerprint,name,protocol,host,port,state,
            first_seen,last_seen_in_pool,updated_at) VALUES(?,?,?,?,?,'pending',?,?,?)""",
            (fp, name, "trojan", "example.invalid", 443, now, now, now))
        pconn.execute("UPDATE probe_nodes SET state='verified' WHERE fingerprint=?", (fp,))
    # reports: pin_ok + rot_ok fast cellular 204; pin_bad latest failed
    for fp, name in ((fp_pin_ok, "PinOk"), (fp_rot_ok, "RotOk")):
        pconn.execute(
            """INSERT INTO probe_reports(fingerprint,name,ts,state,warm_ms,second_ms,
            second_status,success,error,interface) VALUES(?,?,?,?,?,?,?,?,?,?)""",
            (fp, name, now - 1800, "measured", 100, 120, 204, 1, None, "pdp_ip0"))
    pconn.execute(
        """INSERT INTO probe_reports(fingerprint,name,ts,state,warm_ms,second_ms,
        second_status,success,error,interface) VALUES(?,?,?,?,?,?,?,?,?,?)""",
        (fp_pin_bad, "PinBad", now - 7200, "measured", 100, 90, 204, 1, None, "pdp_ip0"))
    pconn.execute(
        """INSERT INTO probe_reports(fingerprint,name,ts,state,warm_ms,second_ms,
        second_status,success,error,interface) VALUES(?,?,?,?,?,?,?,?,?,?)""",
        (fp_pin_bad, "PinBad", now - 600, "first_failed", 3000, None, None, 0, "timeout", "pdp_ip0"))
    # pin_bad state must reflect the latest failure -> expired
    pconn.execute("UPDATE probe_nodes SET state='expired' WHERE fingerprint=?", (fp_pin_bad,))
    pconn.commit()
    pconn.close()

    # --- pool.db (test copy, full schema via dbmod.connect) ---
    pool_db = os.path.join(base, "data", "pool.db")
    conn = dbmod.connect(pool_db)
    # pinned table: pin_ok + pin_bad are pinned
    for proto, host, port, name in (
            ("trojan", "pinok.invalid", 443, "PinOk"),
            ("trojan", "pinbad.invalid", 443, "PinBad")):
        conn.execute("INSERT INTO pinned VALUES (?,?,?,?,?,?)",
                     (proto, host, port, name, now, "test"))
    # nodes table: rot_ok passes VPS gate (last_result pass, fresh, rate 1.0)
    conn.execute(
        """INSERT INTO nodes(protocol,host,port,source,name_hint,first_seen,
        last_seen,last_test_at,last_result,pass_count,test_count)
        VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        ("trojan", "rotok.invalid", 443, "test", "RotOk", now - 10000,
         now - 1000, now - 1000, "pass", 10, 10))
    conn.execute(
        "INSERT INTO node_tests VALUES (?,?,?,?,?,?,?)",
        ("trojan", "rotok.invalid", 443, now - 1000, "pass", "", 120.0))
    conn.commit()

    # --- config.yaml (phone gate ON, probe db = temp probe.db) ---
    with open(os.path.join(base, "config.yaml"), "w") as f:
        f.write("per_country_cap: 40\n")
        f.write("publish_max_lines: 150\n")
        f.write("publish_max_vps_ms: 300\n")
        f.write("publish_fresh_hours: 24\n")
        f.write("publish_min_pass_rate: 0.5\n")
        f.write("winner_clean_enabled: false\n")
        f.write("phone_gate_enabled: true\n")
        f.write("phone_gate_threshold_ms: 280\n")
        f.write("phone_gate_ttl_seconds: 86400\n")
        f.write("phone_gate_probe_db: %s\n" % probe_db)
    with open(os.path.join(base, "private-hosts.txt"), "w") as f:
        f.write("# test\n")

    # --- old publish file (the "current" pool, 3 lines) ---
    old_lines = [
        "PinOk = trojan, pinok.invalid, 443, password=pw1",
        "PinBad = trojan, pinbad.invalid, 443, password=pw3",
        "RotOk = trojan, rotok.invalid, 443, password=pw2",
    ]
    with open(os.path.join(base, "publish", "pool-new.txt"), "w") as f:
        for l in old_lines:
            f.write(l + "\n")

    # --- monkeypatch production-dependent helpers ---
    pinned_lines = [
        ("PinOk", "trojan", "pinok.invalid", 443, old_lines[0]),
        ("PinBad", "trojan", "pinbad.invalid", 443, old_lines[1]),
    ]
    orig_read_pinned = pool_cli.read_pinned_lines
    orig_fresh = pool_cli._fresh_records
    orig_ipapi = pool_cli.IpApi
    pool_cli.read_pinned_lines = lambda b: list(pinned_lines)
    pool_cli._fresh_records = lambda b, skip=None: ([], {})
    pool_cli.IpApi = StubIpApi
    log = NullLog()

    class Args:
        pass

    try:
        # --- case 1: gate ON, verified set = {pin_ok, rot_ok} ---
        rc = pool_cli.cmd_publish(Args(), base, log)
        out_lines = [l.strip() for l in open(
            os.path.join(base, "publish", "pool-new.txt")) if l.strip()]
        check("gate_on_publish_rc0", rc == 0)
        check("gate_on_keeps_verified_pinned",
              any("pinok.invalid" in l for l in out_lines))
        check("gate_on_keeps_verified_rotation",
              any("rotok.invalid" in l for l in out_lines))
        check("gate_on_drops_unverified_pinned",
              all("pinbad.invalid" not in l for l in out_lines))
        check("gate_on_total_is_2", len(out_lines) == 2)
        # published_first should only retain the published rotation node
        rows = conn.execute("SELECT protocol,host,port FROM published_first").fetchall()
        check("published_first_only_kept",
              rows == [("trojan", "rotok.invalid", 443)])

        # --- case 2: gate ON but verified set is EMPTY -> refuse, keep old ---
        # rebuild the old file first (case 1 overwrote it)
        with open(os.path.join(base, "publish", "pool-new.txt"), "w") as f:
            for l in old_lines:
                f.write(l + "\n")
        # empty the probe.db verified set by marking everything expired
        pconn = sqlite3.connect(probe_db)
        pconn.execute("UPDATE probe_nodes SET state='expired'")
        pconn.commit()
        pconn.close()
        # capture stdout (cmd_publish prints JSON)
        import io, contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc2 = pool_cli.cmd_publish(Args(), base, log)
        out2 = buf.getvalue()
        after = [l.strip() for l in open(
            os.path.join(base, "publish", "pool-new.txt")) if l.strip()]
        check("zero_qualified_refuses_rc1", rc2 == 1)
        check("zero_qualified_keeps_old_file", after == old_lines)
        check("zero_qualified_reports_safe_state",
              "zero_qualified_safe_state" in out2
              and "phone_gate_zero_qualified" in out2)

        # --- case 3: gate OFF -> old behaviour (all 3 publish) ---
        with open(os.path.join(base, "config.yaml"), "a") as f:
            f.write("phone_gate_enabled: false\n")
        # restore old file
        with open(os.path.join(base, "publish", "pool-new.txt"), "w") as f:
            for l in old_lines:
                f.write(l + "\n")
        buf3 = io.StringIO()
        with contextlib.redirect_stdout(buf3):
            rc3 = pool_cli.cmd_publish(Args(), base, log)
        out3_lines = [l.strip() for l in open(
            os.path.join(base, "publish", "pool-new.txt")) if l.strip()]
        check("gate_off_restores_old_behaviour",
              rc3 == 0 and len(out3_lines) == 3)
        check("gate_off_keeps_unverified_pinned",
              any("pinbad.invalid" in l for l in out3_lines))
    finally:
        pool_cli.read_pinned_lines = orig_read_pinned
        pool_cli._fresh_records = orig_fresh
        pool_cli.IpApi = orig_ipapi
        conn.close()

    print("\ncmd_publish_gate: %d passed, %d failed" % (len(passed), len(failed)))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(run())
