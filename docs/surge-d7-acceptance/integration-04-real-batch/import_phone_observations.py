#!/usr/bin/env python3
"""Import vetted phone-failure observations from the staging DB into the
production pool.db phone_failures table (PR #118 + phone-first prune).

Read-only on the staging DB. Writes ONLY to phone_failures +
phone_import_log in the production pool.db. Never deletes. Fail-closed:
any integrity problem -> import nothing (rollback, non-zero exit).

Admission (must ALL hold for a staging row to be imported):
  * status == 'failure' (success/unknown rows are never imported)
  * trusted == 1 (an untrusted failure row is an integrity anomaly ->
    fail the whole import, do not import anything)
  * control_verified == 1 AND probe_mode == 'external_policy_id' AND
    bearer == 'cellular' (integration-01, G10): a failure without a
    same-batch independent control is diagnostic history, never imported
  * (protocol, host, port) resolves to a CURRENT pool node
  * the key is NOT a canonical pin and NOT blocklisted
  * the nonce has not been imported before (dedupe via phone_import_log)

The receiver is NOT a deletion authorizer; this importer + the prune
admission rules (auto_prune_phone_first.py) are the gate.

Integration-01 v2 (Review 6033276893, fix 5): the v2 receiver records
trial_generation and dual_target_ok per observation. This importer reads
them when present (PRAGMA detection; a pre-v2 staging DB yields null/0)
and writes them into the phone_failures detail as audit metadata. The
G10 gate is unchanged; no generation gate is added here, because
formal-pool evidence has no trial generation to compare against, and
pre-v2 trusted rows carry no generation.

Integration-04 (Review 6034204978, point 3): the importer now actually
CLASSIFIES on trial_generation (phone_evidence.classify_row, shared with
the v2 importer). An integer generation means the row is trial evidence
and is NEVER imported here (skipped as trial_generation_bound) -- a
trial row must never become formal prune evidence, even if it carries
cv=1 / external_policy_id / cellular. A null generation means formal
historical evidence and continues through the G10 gate; imported rows
carry an explicit evidence_class=formal_historical marker in the
detail so the prune consumer can tell the classes apart without
re-reading the staging DB.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sqlite3
import sys
import time
from pathlib import Path

from phone_evidence import classify_row

VALID_PROTOCOLS = {"trojan", "vmess", "ss"}
PHONE_FAILURE_SOURCE = "surge-url-test"
MAX_BODY_POOL_BYTES = 2 * 1024 * 1024


def parse_pool(raw: bytes):
    """Parse pool bytes -> {key: name}. Strict; mirrors auto_prune.parse_pool."""
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_BODY_POOL_BYTES:
        raise ValueError("invalid_pool_size")
    text = raw.decode("utf-8", errors="strict")
    by_key = {}
    by_name = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("not_a_proxy_declaration")
        name, _, definition = line.partition("=")
        name, definition = name.strip(), definition.strip()
        if not name or not definition:
            raise ValueError("not_a_proxy_declaration")
        parts = [p.strip() for p in definition.split(",")]
        if len(parts) < 3:
            raise ValueError("not_a_proxy_declaration")
        proto = parts[0].lower()
        if proto not in VALID_PROTOCOLS:
            raise ValueError("unrecognized_proxy_type")
        try:
            port = int(parts[2])
        except ValueError as exc:
            raise ValueError("invalid_port") from exc
        if not 1 <= port <= 65535 or not parts[1]:
            raise ValueError("invalid_identity")
        key = (proto, parts[1].lower(), port)
        if name in by_name or key in by_key:
            raise ValueError("duplicate_identity")
        by_key[key] = name
        by_name[name] = key
    if len(by_key) < 22:
        raise ValueError("pool_unexpectedly_short")
    return by_key


def read_pool_keys(pool_path: str):
    raw = Path(pool_path).read_bytes()
    return parse_pool(raw)


def read_pin_blocked(pool_db_path: str):
    """Return (pin_keys, blocked_keys) from the production pool.db (read-only)."""
    uri = "file:" + pool_db_path + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=8.0)
    try:
        conn.execute("PRAGMA query_only=ON")
        pinned = {(r[0], r[1], r[2]) for r in conn.execute(
            "SELECT protocol,host,port FROM pinned")}
        blocked = {(r[0], r[1], r[2]) for r in conn.execute(
            "SELECT protocol,host,port FROM blocklist")}
        return pinned - blocked, blocked
    finally:
        conn.close()


def main() -> int:
    ap = argparse.ArgumentParser(description="Import vetted phone failures.")
    ap.add_argument("--staging-db", default="/opt/phone-telemetry/phone-observations.sqlite3")
    ap.add_argument("--pool-db", default="/opt/free-node-program/data/pool.db")
    ap.add_argument("--pool-file", default="/opt/free-node-program/publish/pool-new.txt")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    def log(msg):
        if not args.quiet:
            print(msg, flush=True)

    try:
        # --- Fail-closed preconditions ---
        if not os.path.isfile(args.staging_db):
            print("FAIL-CLOSED: staging DB missing: " + args.staging_db, file=sys.stderr)
            return 2
        if not os.path.isfile(args.pool_db):
            print("FAIL-CLOSED: production pool.db missing: " + args.pool_db, file=sys.stderr)
            return 2
        if not os.path.isfile(args.pool_file):
            print("FAIL-CLOSED: pool file missing: " + args.pool_file, file=sys.stderr)
            return 2
        pool_keys = read_pool_keys(args.pool_file)
        pins, blocked = read_pin_blocked(args.pool_db)

        # --- Read staging (read-only) ---
        uri = "file:" + args.staging_db + "?mode=ro"
        scon = sqlite3.connect(uri, uri=True, timeout=8.0)
        try:
            scon.execute("PRAGMA query_only=ON")
            tables = {r[0] for r in scon.execute(
                "SELECT name FROM sqlite_master WHERE type='table'")}
            if not {"batches", "phone_observations"} <= tables:
                print("FAIL-CLOSED: staging DB missing required tables", file=sys.stderr)
                return 2
            staging_cols = {r[1] for r in scon.execute("PRAGMA table_info(phone_observations)")}
            extra = [n for n in ("trial_generation", "dual_target_ok") if n in staging_cols]
            rows = scon.execute(
                "SELECT nonce,protocol,host,port,status,probe_mode,trusted,"
                "received_at,bearer,pool_sha,control_verified"
                + ("," + ",".join(extra) if extra else "")
                + " FROM phone_observations ORDER BY received_at").fetchall()
        finally:
            scon.close()

        # --- Validate + classify (no writes yet) ---
        # Any trusted==0 failure row is an integrity anomaly: the receiver
        # converts untrusted failures to 'unknown', so such a row must never
        # exist. Fail the whole import.
        for row in rows:
            (nonce, proto, host, port, status, mode, trusted,
             received_at, bearer, pool_sha, cv) = row[:11]
            if status == "failure" and trusted != 1:
                print("FAIL-CLOSED: untrusted failure row in staging DB "
                      "(nonce prefix %s); import aborted" % str(nonce)[:8],
                      file=sys.stderr)
                return 2

        to_import = []  # (nonce, proto, host, port, received_at, mode, bearer, pool_sha, gen, dual)
        skipped = {}
        for row in rows:
            (nonce, proto, host, port, status, mode, trusted,
             received_at, bearer, pool_sha, cv) = row[:11]
            # v2 audit columns (fix 5): position 11/12 only when the
            # staging DB has them; otherwise null/0 (legacy rows).
            gen = row[11 + extra.index("trial_generation")] if "trial_generation" in extra else None
            dual = row[11 + extra.index("dual_target_ok")] if "dual_target_ok" in extra else 0
            key = (proto, host, port)
            if status != "failure":
                skipped.setdefault("not_failure_" + str(status), 0)
                skipped["not_failure_" + str(status)] += 1
                continue
            # Integration-04 (Review 6034204978, point 3): classify on
            # trial_generation FIRST, before the G10 gate. An integer
            # generation is trial evidence and is NEVER imported by this
            # formal importer (skipped as trial_generation_bound), even
            # with cv=1 / external_policy_id / cellular. A null
            # generation is formal historical evidence and continues.
            ev_class = classify_row(gen)
            if ev_class == "trial_bound":
                skipped["trial_generation_bound"] = skipped.get("trial_generation_bound", 0) + 1
                continue
            # G10 trusted-failure gate (integration-01): only
            # control_verified=1 + external_policy_id + cellular failures
            # are consumable evidence; the rest is diagnostic history.
            if cv != 1 or mode != "external_policy_id" or bearer != "cellular":
                skipped["untrusted_failure_evidence"] = skipped.get("untrusted_failure_evidence", 0) + 1
                continue
            if key not in pool_keys:
                skipped["not_current_pool_node"] = skipped.get("not_current_pool_node", 0) + 1
                continue
            if key in pins:
                skipped["pin"] = skipped.get("pin", 0) + 1
                continue
            if key in blocked:
                skipped["blocklisted"] = skipped.get("blocklisted", 0) + 1
                continue
            to_import.append((nonce, proto, host, port, received_at, mode, bearer, pool_sha, gen, dual))

        # --- Write vetted rows (dedupe via phone_import_log) ---
        conn = sqlite3.connect(args.pool_db, timeout=10.0)
        try:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                "CREATE TABLE IF NOT EXISTS phone_failures ("
                "protocol TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL,"
                " reported_at INTEGER NOT NULL, source TEXT NOT NULL,"
                " detail TEXT NOT NULL)")
            conn.execute(
                "CREATE TABLE IF NOT EXISTS phone_import_log ("
                "nonce TEXT PRIMARY KEY, imported_at INTEGER NOT NULL)")
            conn.execute(
                "CREATE INDEX IF NOT EXISTS phone_failures_by_identity "
                "ON phone_failures(protocol,host,port,reported_at)")
            imported = 0
            already = 0
            for (nonce, proto, host, port, received_at, mode, bearer, pool_sha, gen, dual) in to_import:
                if conn.execute(
                        "SELECT 1 FROM phone_import_log WHERE nonce=?",
                        (nonce,)).fetchone():
                    already += 1
                    continue
                # v2 audit metadata (fix 5): generation and dual-target
                # evidence ride in the detail; audit-only, never a gate.
                # Integration-04: the evidence class is explicit so the
                # prune consumer can tell formal historical rows from
                # trial rows without re-reading the staging DB.
                detail = ("probe_mode=%s bearer=%s control_verified=1 nonce_prefix=%s pool_sha_prefix=%s"
                          " trial_generation=%s dual_target_ok=%s evidence_class=formal_historical"
                          % (mode, bearer, str(nonce)[:8], str(pool_sha)[:8], gen, dual))
                conn.execute(
                    "INSERT INTO phone_failures "
                    "(protocol,host,port,reported_at,source,detail) "
                    "VALUES (?,?,?,?,?,?)",
                    (proto, host, port, int(received_at),
                     PHONE_FAILURE_SOURCE, detail))
                conn.execute(
                    "INSERT INTO phone_import_log (nonce,imported_at) VALUES (?,?)",
                    (nonce, int(time.time())))
                imported += 1
                log("IMPORTED %s|%s|%d reported_at=%d source=%s nonce_prefix=%s"
                    % (proto, host, port, int(received_at),
                       PHONE_FAILURE_SOURCE, str(nonce)[:8]))
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

        log("import_phone_observations: imported=%d already_imported=%d "
            "skipped=%s staging_rows=%d" % (imported, already, skipped, len(rows)))
        return 0
    except Exception as exc:  # fail-closed: import nothing on any error
        print("FAIL-CLOSED: importer error: %s: %s" % (type(exc).__name__, exc),
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
