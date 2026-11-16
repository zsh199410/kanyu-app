#!/usr/bin/env python3
"""Validate a native-results-v1 record (Issue #73, D3 gate input).

This script ONLY validates and reports. It NEVER creates native
evidence: in particular it must never convert P0 probe-service reports
(HTTP HEAD probes) into native results -- P0 is a health signal only,
never admission evidence. A native run enters the record only by the
owner's phone native full-group test, transcribed by the assistant.

Usage:
  validate-native-record.py --record <file> [--source-file <file>]
      [--code-dir /opt/pool-gate] [--probe-db <file>]

Exit 0 = record is well-formed (coverage may still be 0 -- that is a
gate matter, reported plainly, not a format error).
Exit 1 = malformed record. Exit 2 = usage.
Stdout is one JSON object: format checks, per-run stats, and (when
--source-file is given) whether any run covers the source version and
how many of the source file's fingerprints have a fresh same-version
native pass. Counts and SHA prefixes only -- no node data.
"""
import argparse
import hashlib
import json
import os
import sys
import time


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description="validate native-results-v1")
    ap.add_argument("--record", required=True)
    ap.add_argument("--source-file", default=None)
    ap.add_argument("--code-dir", default="/opt/pool-gate")
    ap.add_argument("--probe-db", default=None,
                    help="P0 health context ONLY (counts); never evidence")
    args = ap.parse_args(argv)
    out = {"ok": False, "record": os.path.basename(args.record)}
    now = int(time.time())
    out["checked_at"] = now
    if not os.path.exists(args.record):
        out["error"] = "native_record_missing"
        print(json.dumps(out))
        return 1
    try:
        with open(args.record, encoding="utf-8") as f:
            record = json.load(f)
    except (OSError, ValueError):
        out["error"] = "native_record_unreadable"
        print(json.dumps(out))
        return 1
    if not isinstance(record, dict) or record.get("format") != "native-results-v1":
        out["error"] = "native_record_bad_format"
        print(json.dumps(out))
        return 1
    runs = record.get("runs")
    if not isinstance(runs, list) or not runs:
        out["error"] = "native_record_no_runs"
        print(json.dumps(out))
        return 1
    run_stats = []
    for run in runs:
        if not isinstance(run, dict):
            out["error"] = "native_record_bad_run"
            print(json.dumps(out))
            return 1
        vsha = run.get("version_sha")
        ts = run.get("tested_at")
        results = run.get("results")
        if not isinstance(vsha, str) or len(vsha) != 64:
            out["error"] = "native_record_bad_run"
            print(json.dumps(out))
            return 1
        if not isinstance(ts, int) or ts <= 0 or ts > now:
            out["error"] = "native_record_bad_run"
            print(json.dumps(out))
            return 1
        if not isinstance(results, list):
            out["error"] = "native_record_bad_run"
            print(json.dumps(out))
            return 1
        n_pass = n_fail = 0
        for r in results:
            if not isinstance(r, dict):
                out["error"] = "native_record_bad_result"
                print(json.dumps(out))
                return 1
            fp = r.get("fingerprint")
            if not isinstance(fp, str) or len(fp) != 32:
                out["error"] = "native_record_bad_result"
                print(json.dumps(out))
                return 1
            if not isinstance(r.get("success"), bool):
                out["error"] = "native_record_bad_result"
                print(json.dumps(out))
                return 1
            ms = r.get("ms")
            if ms is not None and not isinstance(ms, int):
                out["error"] = "native_record_bad_result"
                print(json.dumps(out))
                return 1
            if r["success"] and ms is not None and ms < 300:
                n_pass += 1
            else:
                n_fail += 1
        run_stats.append({
            "version_sha_prefix": vsha[:12],
            "age_hours": round((now - ts) / 3600, 2),
            "results": len(results),
            "pass_lt300": n_pass,
            "fail_or_slow": n_fail,
            "fresh_24h": (now - ts) <= 24 * 3600,
        })
    out["runs"] = run_stats
    if args.source_file:
        if not os.path.exists(args.source_file):
            out["error"] = "source_file_missing"
            print(json.dumps(out))
            return 1
        src_sha = sha256_file(args.source_file)
        out["source_sha_prefix"] = src_sha[:12]
        covering = [r for r in run_stats
                    if r["version_sha_prefix"] == src_sha[:12]]
        out["covers_source_version"] = bool(covering)
        # Admission coverage via the real gate code (same function the
        # publish path uses). Code dir is injectable for isolation.
        sys.path.insert(0, args.code_dir)
        try:
            from pool.native_gate import load_native_allowlist
            admitted, conditional, diag = load_native_allowlist(
                args.record, src_sha,
                probe_db=args.probe_db, now=now)
            out["admitted_for_source"] = len(admitted)
            out["conditional_for_source"] = len(conditional)
            out["gate_rejected"] = diag.get("rejected", 0)
            out["gate_reasons"] = diag.get("reasons", {})
        except Exception as e:  # noqa: BLE001 - report, don't crash
            out["gate_error"] = "%s: %s" % (type(e).__name__, e)
    if args.probe_db:
        # P0 health context ONLY. Probe reports are HTTP HEAD probes
        # from the phone script; they are not native Surge speed-test
        # results and can never admit a line.
        try:
            import sqlite3
            con = sqlite3.connect("file:%s?mode=ro" % args.probe_db,
                                  uri=True)
            cur = con.cursor()
            out["p0_context"] = {
                "nodes": cur.execute(
                    "SELECT COUNT(*) FROM probe_nodes").fetchone()[0],
                "verified": cur.execute(
                    "SELECT COUNT(*) FROM probe_nodes "
                    "WHERE state='verified'").fetchone()[0],
                "reports_24h": cur.execute(
                    "SELECT COUNT(*) FROM probe_reports "
                    "WHERE ts > strftime('%s','now')-86400").fetchone()[0],
                "note": "health only, never admission evidence",
            }
            con.close()
        except Exception as e:  # noqa: BLE001
            out["p0_context_error"] = "%s: %s" % (type(e).__name__, e)
    out["ok"] = True
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
