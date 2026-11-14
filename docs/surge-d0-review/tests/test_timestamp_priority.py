"""Timestamp-priority tests for pool/phone_gate.py (D0, GPT review item 2).

Proves load_verified() selects the MOST RECENT probe report by timestamp
(ts DESC), never by insertion order, and that every later bad report
overrides an older good one. Each scenario has a good->bad (reject) and
bad->good (admit)对照 pair where applicable.

All tests use a temporary probe.db built by the test itself. No production
files are touched. No secrets, URIs, or credentials appear in any test:
hosts are *.invalid, passwords are single-letter placeholders.
"""

import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool import phone_gate


def make_probe_db(path):
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


def fp_for(host):
    return phone_gate.fingerprint_of(
        "trojan", host, 443, {"password": "p"})


def run():
    import tempfile
    tmpdir = tempfile.mkdtemp(prefix="d0-ts-test-")
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
    conn = make_probe_db(db_path)

    def good(fp, name, ts):
        add_report(conn, fp, name, ts, 1, 120, 204, "pdp_ip0")

    # --- (a) later failure overrides older success ---
    fp_fail_after = fp_for("a-fail-after.invalid")
    fp_good_after = fp_for("a-good-after.invalid")
    add_node(conn, fp_fail_after, "a-fail-after", now)
    add_node(conn, fp_good_after, "a-good-after", now)
    good(fp_fail_after, "a-fail-after", now - 7200)
    add_report(conn, fp_fail_after, "a-fail-after", now - 1800, 0, None,
               None, "pdp_ip0", error="timeout")
    add_report(conn, fp_good_after, "a-good-after", now - 7200, 0, None,
               None, "pdp_ip0", error="timeout")
    good(fp_good_after, "a-good-after", now - 1800)

    # --- (b) later timeout overrides older success ---
    fp_timeout = fp_for("b-timeout.invalid")
    fp_timeout_flag = fp_for("b-timeout-flag.invalid")
    fp_good_after_to = fp_for("b-good-after.invalid")
    add_node(conn, fp_timeout, "b-timeout", now)
    add_node(conn, fp_timeout_flag, "b-timeout-flag", now)
    add_node(conn, fp_good_after_to, "b-good-after", now)
    good(fp_timeout, "b-timeout", now - 7200)
    add_report(conn, fp_timeout, "b-timeout", now - 1800, 0, None, None,
               "pdp_ip0", warm_ms=3000, error="HTTP request timeout")
    good(fp_timeout_flag, "b-timeout-flag", now - 7200)
    # success flag set but second request missing/timed out -> must reject
    add_report(conn, fp_timeout_flag, "b-timeout-flag", now - 1800, 1, None,
               None, "pdp_ip0", warm_ms=3000, error="timeout")
    add_report(conn, fp_good_after_to, "b-good-after", now - 7200, 0, None,
               None, "pdp_ip0", warm_ms=3000, error="HTTP request timeout")
    good(fp_good_after_to, "b-good-after", now - 1800)

    # --- (c) later >=300ms overrides older success ---
    fp_s310 = fp_for("c-310.invalid")
    fp_s500 = fp_for("c-500.invalid")
    fp_s281 = fp_for("c-281.invalid")
    fp_good_after_slow = fp_for("c-good-after.invalid")
    for fp, name in ((fp_s310, "c-310"), (fp_s500, "c-500"),
                     (fp_s281, "c-281"), (fp_good_after_slow, "c-good-after")):
        add_node(conn, fp, name, now)
    good(fp_s310, "c-310", now - 7200)
    add_report(conn, fp_s310, "c-310", now - 1800, 1, 310, 204, "pdp_ip0")
    good(fp_s500, "c-500", now - 7200)
    add_report(conn, fp_s500, "c-500", now - 1800, 1, 500, 204, "pdp_ip0")
    good(fp_s281, "c-281", now - 7200)
    add_report(conn, fp_s281, "c-281", now - 1800, 1, 281, 204, "pdp_ip0")
    add_report(conn, fp_good_after_slow, "c-good-after", now - 7200, 1, 500,
               204, "pdp_ip0")
    good(fp_good_after_slow, "c-good-after", now - 1800)

    # --- (d) later network change off cellular overrides older success ---
    fp_wifi = fp_for("d-wifi.invalid")
    fp_iface_empty = fp_for("d-iface-empty.invalid")
    fp_iface_none = fp_for("d-iface-none.invalid")
    fp_good_after_wifi = fp_for("d-good-after.invalid")
    fp_cell_other = fp_for("d-pdp-ip1.invalid")
    for fp, name in ((fp_wifi, "d-wifi"), (fp_iface_empty, "d-iface-empty"),
                     (fp_iface_none, "d-iface-none"),
                     (fp_good_after_wifi, "d-good-after"),
                     (fp_cell_other, "d-pdp-ip1")):
        add_node(conn, fp, name, now)
    good(fp_wifi, "d-wifi", now - 7200)
    add_report(conn, fp_wifi, "d-wifi", now - 1800, 1, 120, 204, "en0")
    good(fp_iface_empty, "d-iface-empty", now - 7200)
    add_report(conn, fp_iface_empty, "d-iface-empty", now - 1800, 1, 120,
               204, "")
    good(fp_iface_none, "d-iface-none", now - 7200)
    add_report(conn, fp_iface_none, "d-iface-none", now - 1800, 1, 120,
               204, None)
    add_report(conn, fp_good_after_wifi, "d-good-after", now - 7200, 1, 120,
               204, "en0")
    good(fp_good_after_wifi, "d-good-after", now - 1800)
    # any pdp_ip* interface counts as cellular (pdp_ip1, not only pdp_ip0)
    add_report(conn, fp_cell_other, "d-pdp-ip1", now - 1800, 1, 120, 204,
               "pdp_ip1")

    # --- (e) abnormal timestamps ---
    fp_future_far = fp_for("e-future-far.invalid")
    fp_future_skew = fp_for("e-future-skew.invalid")
    fp_ts_zero = fp_for("e-ts-zero.invalid")
    fp_stale_far = fp_for("e-stale-far.invalid")
    fp_ttl_edge_ok = fp_for("e-ttl-edge-ok.invalid")
    fp_ttl_edge_over = fp_for("e-ttl-edge-over.invalid")
    for fp, name in ((fp_future_far, "e-future-far"),
                     (fp_future_skew, "e-future-skew"),
                     (fp_ts_zero, "e-ts-zero"),
                     (fp_stale_far, "e-stale-far"),
                     (fp_ttl_edge_ok, "e-ttl-edge-ok"),
                     (fp_ttl_edge_over, "e-ttl-edge-over")):
        add_node(conn, fp, name, now)
    # far-future ts (1h ahead) must be rejected, not treated as fresh
    add_report(conn, fp_future_far, "e-future-far", now + 3600, 1, 120, 204,
               "pdp_ip0")
    # small future skew (5 min) is admitted: P0 ingest itself allows
    # ts <= now + 600, so the gate mirrors that allowance
    add_report(conn, fp_future_skew, "e-future-skew", now + 300, 1, 120, 204,
               "pdp_ip0")
    add_report(conn, fp_ts_zero, "e-ts-zero", 0, 1, 120, 204, "pdp_ip0")
    add_report(conn, fp_stale_far, "e-stale-far", now - 90000, 1, 120, 204,
               "pdp_ip0")
    add_report(conn, fp_ttl_edge_ok, "e-ttl-edge-ok", now - 86400, 1, 120,
               204, "pdp_ip0")
    add_report(conn, fp_ttl_edge_over, "e-ttl-edge-over", now - 86401, 1,
               120, 204, "pdp_ip0")
    conn.close()

    admitted, diag = phone_gate.load_verified(db_path, threshold_ms=280,
                                              ttl_seconds=86400, now=now)

    # (a)
    check("reject_fail_after_good", fp_fail_after not in admitted)
    check("admit_good_after_fail", fp_good_after in admitted)
    # (b)
    check("reject_timeout_after_good", fp_timeout not in admitted)
    check("reject_timeout_flag_missing_ms", fp_timeout_flag not in admitted)
    check("admit_good_after_timeout", fp_good_after_to in admitted)
    # (c)
    check("reject_slow_310_after_good", fp_s310 not in admitted)
    check("reject_slow_500_after_good", fp_s500 not in admitted)
    check("reject_slow_281_after_good", fp_s281 not in admitted)
    check("admit_good_after_slow", fp_good_after_slow in admitted)
    # (d)
    check("reject_wifi_after_good", fp_wifi not in admitted)
    check("reject_iface_empty_after_good", fp_iface_empty not in admitted)
    check("reject_iface_none_after_good", fp_iface_none not in admitted)
    check("admit_good_after_wifi", fp_good_after_wifi in admitted)
    check("admit_cellular_pdp_ip1", fp_cell_other in admitted)
    # (e)
    check("reject_future_ts_far", fp_future_far not in admitted)
    check("admit_future_ts_within_skew", fp_future_skew in admitted)
    check("reject_ts_zero", fp_ts_zero not in admitted)
    check("reject_stale_far_past", fp_stale_far not in admitted)
    check("admit_ttl_boundary_exact", fp_ttl_edge_ok in admitted)
    check("reject_ttl_boundary_over", fp_ttl_edge_over not in admitted)
    # totals: 20 nodes in this DB; admitted 7 (a-good-after, b-good-after,
    # c-good-after, d-good-after, d-pdp-ip1, e-future-skew, e-ttl-edge-ok);
    # rejected 13. (Scenarios f and g use separate DBs below.)
    check("diag_counts", diag["admitted"] == 7 and diag["rejected"] == 13)
    check("diag_reason_latest_failed",
          diag["reasons"].get("latest_failed", 0) == 2)
    check("diag_reason_latest_slow",
          diag["reasons"].get("latest_slow_or_missing_ms", 0) == 4)
    check("diag_reason_latest_interface",
          diag["reasons"].get("latest_interface_not_cellular", 0) == 3)
    check("diag_reason_latest_ts_invalid",
          diag["reasons"].get("latest_ts_invalid", 0) == 2)
    check("diag_reason_latest_stale",
          diag["reasons"].get("latest_stale", 0) == 2)

    # --- (f) fingerprint change: same name/host, new port or param ---
    fp_old = fp_for("f-change.invalid")
    db2_path = os.path.join(tmpdir, "probe2.db")
    conn2 = make_probe_db(db2_path)
    add_node(conn2, fp_old, "f-change", now)
    add_report(conn2, fp_old, "f-change", now - 1800, 1, 120, 204, "pdp_ip0")
    conn2.close()
    admitted2, _ = phone_gate.load_verified(db2_path, threshold_ms=280,
                                            ttl_seconds=86400, now=now)
    check("fp_change_old_fp_admitted", fp_old in admitted2)
    lines = [
        "SameName = trojan, f-change.invalid, 443, password=p",
        "SameName = trojan, f-change.invalid, 8443, password=p",
        "SameName = trojan, f-change.invalid, 443, password=p, sni=other.invalid",
    ]
    kept, gdiag = phone_gate.gate_lines(lines, admitted2)
    check("fp_change_port_dropped",
          len(kept) == 1 and "8443" not in kept[0])
    check("fp_change_param_dropped",
          all("other.invalid" not in l for l in kept))
    check("fp_change_old_line_kept",
          kept == ["SameName = trojan, f-change.invalid, 443, password=p"])

    # --- (g) insertion order must not matter: older good report inserted
    # AFTER a newer bad report (bigger id, smaller ts) must still lose ---
    db3_path = os.path.join(tmpdir, "probe3.db")
    conn3 = make_probe_db(db3_path)
    fp_bad_wins = fp_for("g-bad-wins.invalid")
    fp_good_wins = fp_for("g-good-wins.invalid")
    add_node(conn3, fp_bad_wins, "g-bad-wins", now)
    add_node(conn3, fp_good_wins, "g-good-wins", now)
    # bad-wins: newer bad inserted FIRST (smaller id), older good SECOND
    add_report(conn3, fp_bad_wins, "g-bad-wins", now - 1800, 0, None, None,
               "pdp_ip0", error="timeout")
    add_report(conn3, fp_bad_wins, "g-bad-wins", now - 7200, 1, 120, 204,
               "pdp_ip0")
    # good-wins: older bad inserted FIRST, newer good SECOND
    add_report(conn3, fp_good_wins, "g-good-wins", now - 7200, 0, None, None,
               "pdp_ip0", error="timeout")
    add_report(conn3, fp_good_wins, "g-good-wins", now - 1800, 1, 120, 204,
               "pdp_ip0")
    # prove the ids really are in the "misleading" order
    ids = conn3.execute(
        "SELECT fingerprint, id, ts FROM probe_reports ORDER BY id").fetchall()
    conn3.close()
    bad_ids = [i for f, i, t in ids if f == fp_bad_wins]
    bad_ts = [t for f, i, t in ids if f == fp_bad_wins]
    check("insert_order_ids_misleading",
          bad_ids[0] < bad_ids[1] and bad_ts[0] > bad_ts[1])
    admitted3, _ = phone_gate.load_verified(db3_path, threshold_ms=280,
                                            ttl_seconds=86400, now=now)
    check("reject_insert_order_bad_wins", fp_bad_wins not in admitted3)
    check("admit_insert_order_good_wins", fp_good_wins in admitted3)

    print("\ntimestamp_priority: %d passed, %d failed"
          % (len(passed), len(failed)))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(run())
