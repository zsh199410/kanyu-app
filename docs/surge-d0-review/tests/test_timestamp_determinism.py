"""Deterministic timestamp tie-break tests for pool/phone_gate.py (D0).

GPT second review item 1 (2026-11-14): the gate must pick the most recent
report DETERMINISTICALLY. _most_recent_report() uses
ORDER BY ts DESC, id DESC. id is INTEGER PRIMARY KEY AUTOINCREMENT in
probe_reports, so a larger id is always a later insertion.

IMPORTANT: the production probe_reports table has UNIQUE(fingerprint, ts),
so two reports for the same fingerprint can NEVER share the same ts in
production. These tests therefore build their temp DB WITHOUT that UNIQUE
bound -- the only way to construct same-ts rows -- to prove the id
tie-break works if such rows ever appear (e.g. after a schema change or
a manual import). The tie-break is a defensive determinism guarantee,
not a path reachable through normal P0 ingest.

Also covers the STRICT timestamp rule from the same GPT item:
0 < ts <= now, ANY future ts rejected outright, no +600 s allowance.

All tests use temporary probe.db files built by the test itself. No
production files are touched. No secrets, URIs, or credentials appear
in any test: hosts are *.invalid, passwords are single-letter placeholders.
"""

import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool import phone_gate


def make_probe_db_no_unique(path):
    """Create a minimal probe.db WITHOUT UNIQUE(fingerprint, ts).

    Identical to the P0 schema except the UNIQUE bound is dropped, so the
    test can insert two reports for one fingerprint with the same ts.
    Production keeps UNIQUE(fingerprint, ts); see module docstring.
    """
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
        success INTEGER NOT NULL, error TEXT, interface TEXT
    )""")
    conn.commit()
    return conn


def add_node(conn, fp, name, now, state="verified"):
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
               interface, warm_ms=100, error=None, state="measured"):
    conn.execute(
        """INSERT INTO probe_reports(fingerprint,name,ts,state,warm_ms,
        second_ms,second_status,success,error,interface)
        VALUES(?,?,?,?,?,?,?,?,?,?)""",
        (fp, name, ts, state, warm_ms, second_ms, second_status, success,
         error, interface),
    )
    conn.commit()
    return conn.execute("SELECT last_insert_rowid()").fetchone()[0]


def fp_for(host):
    return phone_gate.fingerprint_of(
        "trojan", host, 443, {"password": "p"})


def run():
    import tempfile
    tmpdir = tempfile.mkdtemp(prefix="d0-ts-det-")
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

    db_path = os.path.join(tmpdir, "probe.db")
    conn = make_probe_db_no_unique(db_path)

    def good(fp, name, ts):
        return add_report(conn, fp, name, ts, 1, 120, 204, "pdp_ip0")

    # --- (a) same ts, good inserted first, bad second (bad has bigger id) ---
    # The max-id row (bad) must win: rejected.
    fp_a_bad_wins = fp_for("a-bad-wins.invalid")
    add_node(conn, fp_a_bad_wins, "a-bad-wins", now)
    id_a_good = good(fp_a_bad_wins, "a-bad-wins", now - 3600)
    id_a_bad = add_report(conn, fp_a_bad_wins, "a-bad-wins", now - 3600,
                          0, None, None, "pdp_ip0", error="timeout")
    check("same_ts_ids_increase", id_a_bad > id_a_good)

    # --- (b) same ts, bad inserted first, good second (good has bigger id) ---
    # The max-id row (good) must win: admitted.
    fp_b_good_wins = fp_for("b-good-wins.invalid")
    add_node(conn, fp_b_good_wins, "b-good-wins", now)
    add_report(conn, fp_b_good_wins, "b-good-wins", now - 3600,
               0, None, None, "pdp_ip0", error="timeout")
    good(fp_b_good_wins, "b-good-wins", now - 3600)

    # --- (c) same ts, failure priority: success then failure -> rejected;
    # failure then success -> admitted. (Same mechanism as (a)/(b),
    # framed as the failure-priority rule GPT asked to prove.) ---
    fp_c_fail_last = fp_for("c-fail-last.invalid")
    fp_c_good_last = fp_for("c-good-last.invalid")
    add_node(conn, fp_c_fail_last, "c-fail-last", now)
    add_node(conn, fp_c_good_last, "c-good-last", now)
    good(fp_c_fail_last, "c-fail-last", now - 1800)
    add_report(conn, fp_c_fail_last, "c-fail-last", now - 1800,
               0, None, None, "pdp_ip0", error="timeout")
    add_report(conn, fp_c_good_last, "c-good-last", now - 1800,
               0, None, None, "pdp_ip0", error="timeout")
    good(fp_c_good_last, "c-good-last", now - 1800)

    # --- (d) same ts, expired: two reports at one ts older than TTL ---
    # Both orders must be rejected as stale (the tie-break picks one row,
    # but EITHER row is stale, so the outcome is the same).
    fp_d_stale_good_last = fp_for("d-stale-good-last.invalid")
    fp_d_stale_bad_last = fp_for("d-stale-bad-last.invalid")
    add_node(conn, fp_d_stale_good_last, "d-stale-good-last", now)
    add_node(conn, fp_d_stale_bad_last, "d-stale-bad-last", now)
    stale_ts = now - 90000  # 25 h ago, past the 24 h TTL
    add_report(conn, fp_d_stale_good_last, "d-stale-good-last", stale_ts,
               0, None, None, "pdp_ip0", error="timeout")
    good(fp_d_stale_good_last, "d-stale-good-last", stale_ts)
    good(fp_d_stale_bad_last, "d-stale-bad-last", stale_ts)
    add_report(conn, fp_d_stale_bad_last, "d-stale-bad-last", stale_ts,
               0, None, None, "pdp_ip0", error="timeout")

    # --- (e) same ts, future: two reports at one future ts ---
    # Both orders must be rejected as ts_invalid (strict rule: ts <= now).
    fp_e_future_good_last = fp_for("e-future-good-last.invalid")
    fp_e_future_bad_last = fp_for("e-future-bad-last.invalid")
    add_node(conn, fp_e_future_good_last, "e-future-good-last", now)
    add_node(conn, fp_e_future_bad_last, "e-future-bad-last", now)
    future_ts = now + 3600
    add_report(conn, fp_e_future_good_last, "e-future-good-last", future_ts,
               0, None, None, "pdp_ip0", error="timeout")
    good(fp_e_future_good_last, "e-future-good-last", future_ts)
    good(fp_e_future_bad_last, "e-future-bad-last", future_ts)
    add_report(conn, fp_e_future_bad_last, "e-future-bad-last", future_ts,
               0, None, None, "pdp_ip0", error="timeout")

    # --- (f) same ts, slow then fast (fast has bigger id) -> admitted;
    # fast then slow (slow has bigger id) -> rejected. ---
    fp_f_fast_last = fp_for("f-fast-last.invalid")
    fp_f_slow_last = fp_for("f-slow-last.invalid")
    add_node(conn, fp_f_fast_last, "f-fast-last", now)
    add_node(conn, fp_f_slow_last, "f-slow-last", now)
    add_report(conn, fp_f_fast_last, "f-fast-last", now - 3600,
               1, 400, 204, "pdp_ip0")
    good(fp_f_fast_last, "f-fast-last", now - 3600)
    good(fp_f_slow_last, "f-slow-last", now - 3600)
    add_report(conn, fp_f_slow_last, "f-slow-last", now - 3600,
               1, 400, 204, "pdp_ip0")

    # --- (g) direct _most_recent_report check: same-ts rows, max id wins ---
    # Query the raw function and confirm it returns the max-id row's values.
    row_a = phone_gate._most_recent_report(conn, fp_a_bad_wins)
    check("most_recent_returns_max_id_row",
          row_a is not None and row_a[1] == 0 and row_a[5] == "timeout")
    row_b = phone_gate._most_recent_report(conn, fp_b_good_wins)
    check("most_recent_returns_max_id_good_row",
          row_b is not None and row_b[1] == 1 and row_b[2] == 120)
    row_f = phone_gate._most_recent_report(conn, fp_f_slow_last)
    check("most_recent_returns_max_id_slow_row",
          row_f is not None and row_f[2] == 400)

    conn.close()
    admitted, diag = phone_gate.load_verified(db_path, threshold_ms=280,
                                              ttl_seconds=86400, now=now)

    # (a) bad (bigger id) wins at same ts -> rejected
    check("same_ts_bad_after_good_rejected", fp_a_bad_wins not in admitted)
    # (b) good (bigger id) wins at same ts -> admitted
    check("same_ts_good_after_bad_admitted", fp_b_good_wins in admitted)
    # (c) failure priority at same ts
    check("same_ts_fail_last_rejected", fp_c_fail_last not in admitted)
    check("same_ts_good_last_admitted", fp_c_good_last in admitted)
    # (d) same-ts expired pair -> stale, both orders rejected
    check("same_ts_stale_good_last_rejected",
          fp_d_stale_good_last not in admitted)
    check("same_ts_stale_bad_last_rejected",
          fp_d_stale_bad_last not in admitted)
    # (e) same-ts future pair -> ts_invalid, both orders rejected
    check("same_ts_future_good_last_rejected",
          fp_e_future_good_last not in admitted)
    check("same_ts_future_bad_last_rejected",
          fp_e_future_bad_last not in admitted)
    # (f) same-ts slow/fast tie-break
    check("same_ts_fast_last_admitted", fp_f_fast_last in admitted)
    check("same_ts_slow_last_rejected", fp_f_slow_last not in admitted)
    # diag: 10 nodes; admitted 3 (b-good-wins, c-good-last, f-fast-last);
    # rejected 7. Reasons follow the gate's fixed check order
    # (state -> success -> ms -> status -> interface -> ts -> TTL):
    # latest_failed 4 (a, c-fail-last, d-stale-bad-last, e-future-bad-last --
    # for the last two the max-id row is a failure, so the failure check
    # fires BEFORE the stale/ts check; the node is still rejected either
    # way), latest_slow 1 (f-slow-last), latest_stale 1 (d-stale-good-last
    # only -- its max-id row is good but stale), latest_ts_invalid 1
    # (e-future-good-last only -- its max-id row is good but future).
    check("diag_counts_det",
          diag["admitted"] == 3 and diag["rejected"] == 7)
    check("diag_reason_det_failed",
          diag["reasons"].get("latest_failed", 0) == 4)
    check("diag_reason_det_slow",
          diag["reasons"].get("latest_slow_or_missing_ms", 0) == 1)
    check("diag_reason_det_stale",
          diag["reasons"].get("latest_stale", 0) == 1)
    check("diag_reason_det_ts_invalid",
          diag["reasons"].get("latest_ts_invalid", 0) == 1)

    # --- (h) strict future boundary (separate DB, WITH the UNIQUE bound,
    # to prove the rule also holds on a production-shaped table) ---
    db2_path = os.path.join(tmpdir, "probe2.db")
    conn2 = sqlite3.connect(db2_path)
    conn2.execute("""CREATE TABLE probe_nodes(
        fingerprint TEXT PRIMARY KEY, name TEXT NOT NULL,
        protocol TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        first_seen INTEGER NOT NULL, last_seen_in_pool INTEGER NOT NULL,
        last_phone_ts INTEGER, last_warm_ms INTEGER, last_second_ms INTEGER,
        last_status INTEGER, last_success INTEGER, last_error TEXT,
        last_interface TEXT, phone_ok INTEGER NOT NULL DEFAULT 0,
        phone_fail INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL
    )""")
    conn2.execute("""CREATE TABLE probe_reports(
        id INTEGER PRIMARY KEY AUTOINCREMENT, fingerprint TEXT NOT NULL,
        name TEXT NOT NULL, ts INTEGER NOT NULL, state TEXT NOT NULL,
        warm_ms INTEGER, second_ms INTEGER, second_status INTEGER,
        success INTEGER NOT NULL, error TEXT, interface TEXT,
        UNIQUE(fingerprint, ts)
    )""")
    conn2.commit()
    fp_h_plus1 = fp_for("h-plus1.invalid")
    fp_h_now = fp_for("h-now.invalid")
    fp_h_plus600 = fp_for("h-plus600.invalid")
    for fp, name in ((fp_h_plus1, "h-plus1"), (fp_h_now, "h-now"),
                     (fp_h_plus600, "h-plus600")):
        add_node(conn2, fp, name, now)
    add_report(conn2, fp_h_plus1, "h-plus1", now + 1, 1, 120, 204, "pdp_ip0")
    add_report(conn2, fp_h_now, "h-now", now, 1, 120, 204, "pdp_ip0")
    add_report(conn2, fp_h_plus600, "h-plus600", now + 600, 1, 120, 204,
               "pdp_ip0")
    conn2.close()
    admitted2, _ = phone_gate.load_verified(db2_path, threshold_ms=280,
                                            ttl_seconds=86400, now=now)
    # ts = now + 1 (1 second in the future) is rejected under the strict rule
    check("strict_future_plus1_rejected", fp_h_plus1 not in admitted2)
    # ts = now exactly is admitted (boundary is inclusive)
    check("strict_ts_now_admitted", fp_h_now in admitted2)
    # ts = now + 600 (the OLD allowance) is now rejected
    check("strict_future_plus600_rejected", fp_h_plus600 not in admitted2)

    print("passed %d, failed %d" % (len(passed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(run())
