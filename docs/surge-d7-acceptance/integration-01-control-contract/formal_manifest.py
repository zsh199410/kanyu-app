#!/usr/bin/env python3
"""Formal-pool manifest generator (read-only publisher of record).

Reads the formal pool file + formal phone-observations DB (read-only) +
a source-group registry, and writes formal-manifest.json (atomic replace).
The generator NEVER writes the pool file, the observations DB, or any
publish state, and must not become a second formal publisher (G5).

Eligible controls (C6/C7 + known source group):
  * member of the current formal pool file;
  * >=1 trusted cellular success (external_policy_id) in the last 24h (C6);
  * zero trusted cellular failures (external_policy_id) in the last 24h (C7);
  * source_group known in the registry. Members without a verified group
    are 'unknown' and can never serve as C4 independent controls (G6).
  * not a member of the trial pool (C2, enforced here for usability;
    the receiver's V4 check remains the authoritative backstop).

Generation starts at 0 and increments only when the pool SHA changes
(member-set change implies a SHA change). Health-timestamp-only changes
never bump the generation (A17).

Exit codes: 0 ok; 2 fail-closed (bad pool/registry/prior manifest/DB).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from receiver import parse_pool

HEALTH_WINDOW_S = 86400  # 24h (G4)


def load_registry(path):
    """Return {identity_key: source_group}. Missing file -> all unknown
    (warn, proceed). Malformed file -> fail-closed."""
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError:
        print("WARN: source-group registry missing (%s); all groups unknown" % path,
              file=sys.stderr)
        return {}
    try:
        data = json.loads(raw)
        entries = data["entries"]
        if not isinstance(entries, dict):
            raise ValueError("registry entries is not an object")
    except (ValueError, KeyError) as e:
        raise SystemExit("FAIL-CLOSED: malformed source-group registry: %s" % e)
    groups = {}
    for key, value in entries.items():
        if not isinstance(value, dict) or not isinstance(value.get("source_group"), str):
            raise SystemExit("FAIL-CLOSED: malformed registry entry for %s" % key)
        groups[key] = value["source_group"]
    return groups


def read_prior_manifest(path):
    """Return (generation, pool_sha) of the existing manifest, or (None, None)
    when no manifest exists yet. Malformed existing manifest -> fail-closed."""
    if not Path(path).exists():
        return None, None
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        gen = data["generation"]
        sha = data["pool_sha"]
    except (OSError, ValueError, KeyError) as e:
        raise SystemExit("FAIL-CLOSED: existing manifest unreadable: %s" % e)
    if type(gen) is not int or not isinstance(sha, str):
        raise SystemExit("FAIL-CLOSED: existing manifest has bad generation/pool_sha")
    return gen, sha


def main(argv=None):
    p = argparse.ArgumentParser(description="Generate formal-pool manifest (read-only)")
    p.add_argument("--pool", default="/opt/free-node-program/publish/pool-new.txt")
    p.add_argument("--db", default="/opt/phone-telemetry/phone-observations.sqlite3")
    p.add_argument("--registry", default="/opt/phone-telemetry/formal-source-groups.json")
    p.add_argument("--out", default="/opt/phone-telemetry/formal-manifest.json")
    p.add_argument("--trial-pool", default="/opt/surge-bridge/modules/probation-new.txt")
    p.add_argument("--min-pool", type=int, default=22)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--now", type=int, default=None, help="epoch override (tests only)")
    args = p.parse_args(argv)
    now = int(time.time()) if args.now is None else args.now
    window_from = now - HEALTH_WINDOW_S

    try:
        pool_raw = Path(args.pool).read_bytes()
    except OSError as e:
        print("FAIL-CLOSED: cannot read formal pool: %s" % e, file=sys.stderr)
        return 2
    try:
        pool_by_name = parse_pool(pool_raw, min_pool=args.min_pool)
    except ValueError as e:
        print("FAIL-CLOSED: formal pool parse failed: %s" % e, file=sys.stderr)
        return 2
    pool_sha = hashlib.sha256(pool_raw).hexdigest()

    groups = load_registry(args.registry)

    trial_identities = set()
    trial_excluded = 0
    try:
        trial_raw = Path(args.trial_pool).read_bytes()
        trial_by_name = parse_pool(trial_raw, min_pool=1)
        trial_identities = set(trial_by_name.values())
    except (OSError, ValueError):
        print("WARN: trial pool unreadable; C2 exclusion skipped this run",
              file=sys.stderr)

    try:
        conn = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True, timeout=8)
        conn.execute("PRAGMA query_only=ON")
        try:
            success_24h = {tuple(r[:3]): r[3] for r in conn.execute(
                "SELECT protocol,host,port,MAX(received_at) FROM phone_observations"
                " WHERE status='success' AND trusted=1 AND bearer='cellular'"
                " AND probe_mode='external_policy_id' AND received_at>? GROUP BY protocol,host,port",
                (window_from,)).fetchall()}
            failure_24h = {tuple(r[:3]) for r in conn.execute(
                "SELECT protocol,host,port FROM phone_observations"
                " WHERE status='failure' AND trusted=1 AND bearer='cellular'"
                " AND probe_mode='external_policy_id' AND received_at>? GROUP BY protocol,host,port",
                (window_from,)).fetchall()}
            last_failure = {tuple(r[:3]): r[3] for r in conn.execute(
                "SELECT protocol,host,port,MAX(received_at) FROM phone_observations"
                " WHERE status='failure' AND trusted=1 AND bearer='cellular'"
                " AND probe_mode='external_policy_id' GROUP BY protocol,host,port").fetchall()}
        finally:
            conn.close()
    except sqlite3.Error as e:
        print("FAIL-CLOSED: formal observations DB unreadable: %s" % e, file=sys.stderr)
        return 2

    eligible = []
    unknown_group = 0
    for name, identity in sorted(pool_by_name.items()):
        proto, host, port = identity
        if identity in trial_identities:
            trial_excluded += 1
            continue
        group = groups.get("%s|%s|%d" % (proto, host, port), "unknown")
        if group == "unknown":
            unknown_group += 1
            continue
        if identity not in success_24h:
            continue
        if identity in failure_24h:
            continue
        eligible.append({
            "name": name,
            "protocol": proto,
            "host": host,
            "port": port,
            "source_group": group,
            "last_trusted_success": success_24h[identity],
            "last_trusted_failure": last_failure.get(identity),
        })

    prior_gen, prior_sha = read_prior_manifest(args.out)
    if prior_gen is None:
        generation = 0
    elif prior_sha != pool_sha:
        generation = prior_gen + 1
    else:
        generation = prior_gen

    manifest = {
        "pool_sha": pool_sha,
        "generation": generation,
        "updated_at": datetime.fromtimestamp(now, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "lines": len(pool_by_name),
        "entries": len(pool_by_name),
        "status": "FORMAL",
        "eligible_controls": eligible,
    }
    summary = {"ok": True, "pool_sha_prefix": pool_sha[:12], "generation": generation,
               "members": len(pool_by_name), "eligible": len(eligible),
               "unknown_group": unknown_group, "trial_excluded": trial_excluded,
               "wrote": not args.dry_run}
    if args.dry_run:
        print(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2))
        return 0
    out_path = Path(args.out)
    tmp_path = out_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
                        encoding="utf-8")
    os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, out_path)
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
