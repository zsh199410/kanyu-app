"""Unit tests for pool/phone_gate.py (D0 isolated implementation).

All tests use a temporary probe.db built by the test itself. No production
files are touched. No secrets, URIs, or credentials appear in any test.
"""

import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool import phone_gate


def make_probe_db(path, now):
    """Create a minimal probe.db with the P0 schema."""
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


def add_node(conn, fp, name, state, now):
    conn.execute(
        """INSERT INTO probe_nodes(fingerprint,name,protocol,host,port,state,
        first_seen,last_seen_in_pool,updated_at) VALUES(?,?,?,?,?,'pending',?,?,?)""",
        (fp, name, "trojan", "example.invalid", 443, now, now, now),
    )
    conn.execute(
        "UPDATE probe_nodes SET state=? WHERE fingerprint=?", (state, fp)
    )
    conn.commit()


def add_report(conn, fp, name, ts, success, second_ms, second_status,
               interface, state="measured"):
    conn.execute(
        """INSERT INTO probe_reports(fingerprint,name,ts,state,warm_ms,
        second_ms,second_status,success,error,interface)
        VALUES(?,?,?,?,?,?,?,?,?,?)""",
        (fp, name, ts, state, 100, second_ms, second_status, success,
         None, interface),
    )
    conn.commit()


def run():
    import tempfile
    tmpdir = tempfile.mkdtemp(prefix="d0-gate-test-")
    now = int(time.time())
    passed = []
    failed = []

    def check(label, cond):
        if cond:
            passed.append(label)
            print("PASS %s" % label)
        else:
            failed.append(label)
            print("FAIL %s" % label)

    # --- fingerprint matches P0 exactly (same algorithm, same inputs) ---
    sys.path.insert(0, "/opt/p2p3-d0")
    import probe_service_reference as ps
    fp_a = phone_gate.fingerprint_of("trojan", "example.invalid", 443,
                                     {"password": "x", "sni": "a.invalid"})
    fp_b = ps.fingerprint_of("trojan", "example.invalid", 443,
                             {"password": "x", "sni": "a.invalid"})
    check("fingerprint_matches_probe_service", fp_a == fp_b and len(fp_a) == 32)
    # param order must not matter (sorted keys)
    fp_c = phone_gate.fingerprint_of("trojan", "example.invalid", 443,
                                     {"sni": "a.invalid", "password": "x"})
    check("fingerprint_param_order_invariant", fp_a == fp_c)
    # display name must not matter
    parsed = phone_gate.parse_surge_line(
        "SomeName = trojan, example.invalid, 443, password=x, sni=a.invalid")
    check("parse_surge_line_ok", parsed is not None and parsed[1] == "trojan")
    check("parse_excludes_name_from_fp",
          phone_gate.fingerprint_of(parsed[1], parsed[2], parsed[3], parsed[4]) == fp_a)
    # unparsable / wrong protocol rejected by parse
    check("parse_rejects_bad_proto",
          phone_gate.parse_surge_line("N = socks, h, 1") is None)
    check("parse_rejects_malformed",
          phone_gate.parse_surge_line("not a line") is None)

    # --- build a probe.db with one node per scenario ---
    db_path = os.path.join(tmpdir, "probe.db")
    conn = make_probe_db(db_path, now)
    scenarios = {}
    # 1. good: verified, recent fast cellular 204 success
    scenarios["good"] = phone_gate.fingerprint_of(
        "trojan", "good.invalid", 443, {"password": "p"})
    # 2. latest failed (older success exists) -> reject
    scenarios["latest_failed"] = phone_gate.fingerprint_of(
        "trojan", "fail.invalid", 443, {"password": "p"})
    # 3. latest slow (>=280) -> reject
    scenarios["latest_slow"] = phone_gate.fingerprint_of(
        "trojan", "slow.invalid", 443, {"password": "p"})
    # 4. stale (older than TTL) -> reject
    scenarios["stale"] = phone_gate.fingerprint_of(
        "trojan", "stale.invalid", 443, {"password": "p"})
    # 5. non-cellular interface -> reject
    scenarios["wifi"] = phone_gate.fingerprint_of(
        "trojan", "wifi.invalid", 443, {"password": "p"})
    # 6. status not 204 -> reject
    scenarios["status200"] = phone_gate.fingerprint_of(
        "trojan", "s200.invalid", 443, {"password": "p"})
    # 7. state not verified -> reject
    scenarios["state_pending"] = phone_gate.fingerprint_of(
        "trojan", "pend.invalid", 443, {"password": "p"})
    # 8. no report at all -> reject
    scenarios["no_report"] = phone_gate.fingerprint_of(
        "trojan", "norep.invalid", 443, {"password": "p"})
    # 9. slow-then-fast: most recent is fast -> admit (recency wins)
    scenarios["recovered"] = phone_gate.fingerprint_of(
        "trojan", "rec.invalid", 443, {"password": "p"})
    # 10. boundary: most recent second_ms exactly 280 -> admit (<= threshold)
    scenarios["boundary_280"] = phone_gate.fingerprint_of(
        "trojan", "b280.invalid", 443, {"password": "p"})

    for key, fp in scenarios.items():
        state = "pending" if key == "state_pending" else "verified"
        add_node(conn, fp, key, state, now)
    # reports (ts relative to now)
    add_report(conn, scenarios["good"], "good", now - 3600, 1, 120, 204, "pdp_ip0")
    add_report(conn, scenarios["latest_failed"], "latest_failed", now - 7200, 1, 100, 204, "pdp_ip0")
    add_report(conn, scenarios["latest_failed"], "latest_failed", now - 1800, 0, None, None, "pdp_ip0")
    add_report(conn, scenarios["latest_slow"], "latest_slow", now - 3600, 1, 450, 204, "pdp_ip0")
    add_report(conn, scenarios["stale"], "stale", now - 90000, 1, 100, 204, "pdp_ip0")
    add_report(conn, scenarios["wifi"], "wifi", now - 3600, 1, 100, 204, "en0")
    add_report(conn, scenarios["status200"], "status200", now - 3600, 1, 100, 200, "pdp_ip0")
    add_report(conn, scenarios["state_pending"], "state_pending", now - 3600, 1, 100, 204, "pdp_ip0")
    add_report(conn, scenarios["recovered"], "recovered", now - 7200, 0, None, None, "pdp_ip0")
    add_report(conn, scenarios["recovered"], "recovered", now - 1800, 1, 150, 204, "pdp_ip0")
    add_report(conn, scenarios["boundary_280"], "boundary_280", now - 1800, 1, 280, 204, "pdp_ip0")
    conn.close()

    admitted, diag = phone_gate.load_verified(db_path, threshold_ms=280,
                                              ttl_seconds=86400, now=now)
    check("admit_good", scenarios["good"] in admitted)
    check("admit_recovered", scenarios["recovered"] in admitted)
    check("admit_boundary_280", scenarios["boundary_280"] in admitted)
    check("reject_latest_failed", scenarios["latest_failed"] not in admitted)
    check("reject_latest_slow", scenarios["latest_slow"] not in admitted)
    check("reject_stale", scenarios["stale"] not in admitted)
    check("reject_wifi", scenarios["wifi"] not in admitted)
    check("reject_status200", scenarios["status200"] not in admitted)
    check("reject_state_pending", scenarios["state_pending"] not in admitted)
    check("reject_no_report", scenarios["no_report"] not in admitted)
    check("admitted_count_is_3", len(admitted) == 3)
    check("diag_counts", diag["admitted"] == 3 and diag["rejected"] == 7)

    # --- gate_lines ---
    lines = [
        "Good = trojan, good.invalid, 443, password=p",
        "Fail = trojan, fail.invalid, 443, password=p",
        "Recovered = trojan, rec.invalid, 443, password=p",
        "BadProto = socks, x.invalid, 1",
        "garbage line",
        "GoodDup = trojan, good.invalid, 443, password=p",
    ]
    kept, gdiag = phone_gate.gate_lines(lines, admitted)
    check("gate_keeps_good_and_recovered", len(kept) == 3)
    check("gate_drops_failed", all("fail.invalid" not in l for l in kept))
    check("gate_drops_unparsable", gdiag["reasons"].get("unparsable_or_protocol", 0) == 2)
    check("gate_same_fp_twice_kept", sum(1 for l in kept if "good.invalid" in l) == 2)

    # --- missing db fails closed ---
    admitted2, diag2 = phone_gate.load_verified(
        os.path.join(tmpdir, "missing.db"), now=now)
    check("missing_db_fails_closed", admitted2 == set() and diag2.get("error") == "probe_db_missing")

    print("\nphone_gate: %d passed, %d failed" % (len(passed), len(failed)))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(run())
