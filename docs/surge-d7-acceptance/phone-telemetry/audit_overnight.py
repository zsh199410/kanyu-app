#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only overnight evidence audit, no proxy credentials and no writes."""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import sqlite3

from receiver import parse_pool
from import_per_observation_v2 import ro_connection, check_schema, ImportRefused


def report(staging, production, pool):
    raw = Path(pool).read_bytes()
    by_name = parse_pool(raw)
    by_key = {key:name for name,key in by_name.items()}
    sha = hashlib.sha256(raw).hexdigest()
    prod = ro_connection(production)
    stage = ro_connection(staging)
    try:
        check_schema(prod, "pinned", ("protocol","host","port"))
        check_schema(prod, "blocklist", ("protocol","host","port"))
        check_schema(prod, "phone_failures", ("protocol","host","port","reported_at","source"))
        check_schema(stage, "phone_observations", ("nonce","protocol","host","port",
                     "status","trusted","received_at","pool_sha","probe_mode","bearer"))
        pinned = {tuple(r) for r in prod.execute("SELECT protocol,host,port FROM pinned")}
        blocked = {tuple(r) for r in prod.execute("SELECT protocol,host,port FROM blocklist")}
        pins = pinned - blocked
        columns = {r[1] for r in stage.execute("PRAGMA table_info(phone_observations)")}
        reason_expr = "reason" if "reason" in columns else "'legacy_no_reason' AS reason"
        rows = stage.execute("SELECT nonce,protocol,host,port,status,trusted,"
                   "received_at,pool_sha,probe_mode,bearer," + reason_expr +
                   " FROM phone_observations").fetchall()
        summary = Counter(row[4] for row in rows)
        reasons = Counter((row[4],row[10],row[8]) for row in rows)
        failures = defaultdict(list)
        missing = []
        for nonce,proto,host,port,status,trusted,ts,record_sha,mode,bearer,reason in rows:
            key = (proto,host,port)
            if status != "failure":
                continue
            failures[key].append((nonce,ts,mode,trusted,record_sha))
            if not trusted or key in pins or key in blocked or key not in by_key or record_sha != sha:
                continue
            found = prod.execute("""SELECT 1 FROM phone_failures WHERE
                protocol=? AND host=? AND port=? AND source='surge-url-test'
                AND reported_at BETWEEN ? AND ? LIMIT 1""",
                (proto,host,port,ts-300,ts+300)).fetchone()
            if not found:
                missing.append({"name":by_key[key],"nonce_prefix":nonce[:8],
                                "reported_at":ts,"method":mode})
        breakdown = []
        for key,entries in sorted(failures.items(), key=lambda x:(-len(x[1]),by_key.get(x[0],""))):
            breakdown.append({
                "name":by_key.get(key,"<not_in_current_pool>"),
                "pinned":key in pins,
                "count":len(entries),
                "hour_buckets":len({e[1]//3600 for e in entries}),
                "trusted":sum(int(e[3]==1) for e in entries),
            })
        import_cols=[]
        if prod.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='phone_import_log'").fetchone():
            import_cols=[r[1] for r in prod.execute("PRAGMA table_info(phone_import_log)")]
        return {
            "pool_count":len(by_key),"protected_pin_count":len(pins),
            "staging_rows":len(rows),"statuses":dict(summary),
            "unknown_reasons":[{"status":s,"reason":r,"probe_mode":m,"count":n}
                               for (s,r,m),n in sorted(reasons.items())],
            "failed_node_breakdown":breakdown,
            "failure_count_by_breakdown":sum(e["count"] for e in breakdown),
            "eligible_missing_import":missing,
            "eligible_missing_count":len(missing),
            "existing_phone_import_log_columns":import_cols,
            "read_only":True,
        }
    finally:
        prod.close()
        stage.close()


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--staging",required=True)
    p.add_argument("--production-db",required=True)
    p.add_argument("--pool",required=True)
    args=p.parse_args()
    try:
        r=report(args.staging,args.production_db,args.pool)
    except (ImportRefused,sqlite3.Error,OSError,ValueError):
        print('{"ok":false,"decision":"AUDIT_REFUSED"}')
        return 78
    print(json.dumps({"ok":True,**r},sort_keys=True,ensure_ascii=False))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
