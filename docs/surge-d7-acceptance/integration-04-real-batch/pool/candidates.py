"""Read-only candidate computation (integration-04, GPT #73 comment
7123361053, 2026-11-24 13:52).

Inputs (all explicit, nothing inferred from a live service):
  * latest complete crawl batch per source (crawl_batches /
    crawl_batch_members, via batch_state.qualified_batch_members);
  * config identity: the HMAC config fingerprint stored with each batch
    member (protocol/host/port/fingerprint -- no credential, no URI);
  * unified admission result: supplied per identity+fingerprint, or --
    when no supplied result exists -- the lineage proof that the member
    passed the gate at crawl time (a node_sources row for this source +
    fingerprint). A member with neither is excluded as
    admission_unknown. The supplied result wins when present.
  * persistent blocklist: the DB blocklist table, optionally unioned
    with a rejected_nodes.json file (strict load).

Outputs (JSON-serialisable report): one verdict row per batch member
(admitted / excluded + fixed reason vocabulary), the admitted set
grouped by independent source group, and the current batchable count:
the number of disjoint valid batches formable from the admitted set,
where a valid batch has >=3 members from >=3 distinct independent
groups with no group above 1/3 of the batch. Batches are packed
greedily as triples (one member per group): each triple trivially
satisfies the <=1/3 rule, and greedy "take from the 3 largest groups"
is optimal for the triple count. If the count is 0 it is reported as
0 -- never padded, never rounded up.

Grouped round-robin sub-batches (same comment): source diversity is a
gate on the CANDIDATE SET, not a requirement that every phone round
tests the whole set at once. When testing all candidate groups at once
leaves no independent control slot in a probe run, the admitted set
may be partitioned into round-robin sub-batches for phone verification
only. partition_sub_batches() interleaves candidates across groups and
chunks them so each probe run keeps `control_slots` slots free for an
independent control (C4). Sub-batches are diagnostic-only by
construction: every sub-batch carries publish_eligible=False, and
nothing in this module writes, promotes, deletes or unblocks. The full
set's diversity (and the batchable count) is always evaluated on the
COMPLETE admitted set, never per sub-batch. G6=0 still means
diagnostic-only: verify_promotion's PHONE_EVIDENCE_READY still needs a
control_verified success in the chain, and a sub-batch success alone
never becomes a promotion.

This module is strictly read-only: it opens the DB in read-only mode
when given a path, never writes, never deletes, never touches the
network, and never reads credentials. It is the only entry point that
combines batch + identity + admission + blocklist into a candidate
report; it does not replace the gate, pre_filter, tester or publish
chain.
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time

from . import batch_state as bs
from .blocklist_common import load_rejected_strict
from .lineage_adapter import load_registry

DEFAULT_TTL_S = 86400            # 24h, same as batch_state.BATCH_TTL_S
DEFAULT_RUN_CAP = 6              # probe-run manifest cap
DEFAULT_CONTROL_SLOTS = 1        # slots kept free for an independent control
MIN_GROUPS_PER_BATCH = 3         # diversity rule: >=3 independent groups
MAX_GROUP_SHARE = 1.0 / 3.0      # diversity rule: no group above 1/3

# Fixed exclusion reasons (stable vocabulary for the report).
REASON_OK = "ok"


def load_blocked(conn):
    """Blocked triples from the DB blocklist table (empty table -> empty set)."""
    try:
        rows = conn.execute(
            "SELECT protocol, host, port FROM blocklist").fetchall()
    except sqlite3.Error:
        return set()
    return {(p, h, int(po)) for (p, h, po) in rows}


def _group_of(registry, source):
    for group, members in registry.groups.items():
        if source in members:
            return group
    return None


def _lineage_proves_gate(conn, source, fingerprint):
    """True iff node_sources holds this source+fingerprint (gate passed at
    crawl time). Read-only; a missing lineage schema means no proof."""
    try:
        row = conn.execute(
            "SELECT 1 FROM node_sources WHERE source=? AND fingerprint=? LIMIT 1",
            (source, fingerprint)).fetchone()
    except sqlite3.Error:
        return False
    return row is not None


def _pack_batches(admitted):
    """Greedy disjoint triples from distinct groups.

    admitted: list of candidate rows (dicts with a "group" key).
    Returns the list of batches; each batch is a list of rows, one per
    group. Greedy "take from the 3 largest groups" is optimal for the
    triple count. Every batch satisfies >=3 groups and <=1/3 per group.
    """
    by_group = {}
    for row in admitted:
        by_group.setdefault(row["group"], []).append(row)
    batches = []
    while True:
        ranked = sorted(by_group.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        top = [g for g, rows in ranked[:MIN_GROUPS_PER_BATCH] if rows]
        if len(top) < MIN_GROUPS_PER_BATCH:
            break
        batch = [by_group[g].pop(0) for g in top]
        batches.append(batch)
    return batches


def partition_sub_batches(admitted, *, run_cap=DEFAULT_RUN_CAP,
                          control_slots=DEFAULT_CONTROL_SLOTS):
    """Partition the admitted set into round-robin sub-batches.

    The admitted list is interleaved across groups (one member per
    group in rotation) and chunked so no sub-batch exceeds
    run_cap - control_slots members: each probe run keeps control_slots
    free for an independent control (C4). The union of the sub-batches
    is exactly the admitted set, and diversity is NOT re-evaluated per
    sub-batch -- it belongs to the full candidate set. Every sub-batch
    is marked publish_eligible=False: sub-batch results are diagnostic
    verification only and must never enter a publish decision.
    """
    if run_cap < 2:
        raise ValueError("run_cap must be >= 2")
    if control_slots < 0 or control_slots >= run_cap:
        raise ValueError("control_slots must satisfy 0 <= slots < run_cap")
    max_per = run_cap - control_slots
    by_group = {}
    for row in admitted:
        by_group.setdefault(row["group"], []).append(row)
    interleaved = []
    groups = sorted(by_group)
    idx = {g: 0 for g in groups}
    while True:
        progressed = False
        for g in groups:
            rows = by_group[g]
            if idx[g] < len(rows):
                interleaved.append(rows[idx[g]])
                idx[g] += 1
                progressed = True
        if not progressed:
            break
    out = []
    for i in range(0, len(interleaved), max_per):
        chunk = interleaved[i:i + max_per]
        out.append({
            "round": len(out),
            "purpose": "round_robin_verification",
            "publish_eligible": False,
            "control_slots_reserved": control_slots,
            "members": [{"protocol": r["protocol"], "host": r["host"],
                         "port": r["port"], "source": r["source"],
                         "group": r["group"]} for r in chunk],
        })
    return out


def compute_candidates(conn, registry, *, now=None, ttl_s=DEFAULT_TTL_S,
                       admission=None, blocked=None, disabled=(),
                       run_cap=DEFAULT_RUN_CAP,
                       control_slots=DEFAULT_CONTROL_SLOTS):
    """Compute the candidate report from live (read-only) DB state.

    conn: sqlite connection (read-only use; this function never writes).
    registry: SourceRegistry from lineage_adapter.load_registry.
    admission: optional dict {(protocol, host, port, fingerprint):
    (ok, reason)} -- the current unified admission result per config
    identity. Missing entries fall back to the lineage proof.
    blocked: optional set of (protocol, host, port) triples; when None
    it is loaded from the DB blocklist table.
    disabled: current disabled_sources set (consumption-time check).
    """
    now = int(time.time()) if now is None else int(now)
    admission = admission or {}
    if blocked is None:
        blocked = load_blocked(conn)
    disabled = set(disabled or ())
    known_sources = {s for members in registry.groups.values() for s in members}
    registry_status = dict(registry.status)

    sources_report = {}
    rows = []  # one verdict row per batch member
    try:
        batch_sources = {r[0] for r in conn.execute(
            "SELECT DISTINCT source FROM crawl_batches").fetchall()}
    except sqlite3.Error:
        # No batch schema yet: no source has a consumable batch. The
        # per-source qualified_batch_members call below reports
        # schema_missing for every source; the report totals zero batches.
        batch_sources = set()
    for source in sorted(batch_sources | known_sources):
        group = _group_of(registry, source)
        members, reason = bs.qualified_batch_members(
            conn, source, now, ttl_s=ttl_s, disabled=disabled,
            registry_status=registry_status, known_sources=known_sources)
        try:
            batch_row = conn.execute(
                "SELECT status, completed_at FROM crawl_batches WHERE source=?"
                " ORDER BY started DESC, id DESC LIMIT 1", (source,)).fetchone()
        except sqlite3.Error:
            batch_row = None
        sources_report[source] = {
            "group": group,
            "batch_status": batch_row[0] if batch_row else None,
            "batch_completed_at": batch_row[1] if batch_row else None,
            "consumable_reason": reason,
            "members": len(members) if members else 0,
        }
        if members is None:
            continue
        for (proto, host, port, fp) in members:
            key = (proto, host, port)
            verdict, why, adm_src = "admitted", REASON_OK, None
            if group is None:
                verdict, why = "excluded", "source_unknown_group"
            elif key in blocked:
                verdict, why = "excluded", "blocklisted"
            elif (proto, host, port, fp) in admission:
                ok, adm_reason = admission[(proto, host, port, fp)]
                adm_src = "supplied"
                if not ok:
                    verdict, why = "excluded", "admission_%s" % adm_reason
            elif _lineage_proves_gate(conn, source, fp):
                adm_src = "lineage_at_crawl"
            else:
                verdict, why = "excluded", "admission_unknown"
            rows.append({
                "protocol": proto, "host": host, "port": port,
                "source": source, "group": group, "fingerprint": fp,
                "verdict": verdict, "reason": why,
                "admission_source": adm_src,
            })
    admitted = [r for r in rows if r["verdict"] == "admitted"]
    excluded = [r for r in rows if r["verdict"] == "excluded"]
    groups_count = {}
    for r in admitted:
        groups_count[r["group"]] = groups_count.get(r["group"], 0) + 1
    batches = _pack_batches(admitted)
    sub_batches = partition_sub_batches(
        admitted, run_cap=run_cap, control_slots=control_slots)
    return {
        "now": now,
        "ttl_seconds": ttl_s,
        "sources": sources_report,
        "candidates": rows,
        "admitted": admitted,
        "excluded": excluded,
        "diversity": {
            "groups": groups_count,
            "independent_groups": len(groups_count),
            "min_groups_per_batch": MIN_GROUPS_PER_BATCH,
            "max_group_share": MAX_GROUP_SHARE,
        },
        "batchable": len(batches),
        "batches": [[{"protocol": r["protocol"], "host": r["host"],
                      "port": r["port"], "source": r["source"],
                      "group": r["group"]} for r in b] for b in batches],
        "sub_batches": sub_batches,
        "run_cap": run_cap,
        "control_slots_reserved": control_slots,
    }


def _load_admission_file(path):
    """Admission file: JSON object {"protocol|host|port|fingerprint":
    {"ok": bool, "reason": str}}. Strict: malformed file -> raise."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("admission file must be a JSON object")
    out = {}
    for k, v in data.items():
        parts = k.split("|")
        if len(parts) != 4:
            raise ValueError("admission key must be protocol|host|port|fingerprint: %r" % k)
        proto, host, port_s, fp = parts
        try:
            port = int(port_s)
        except ValueError:
            raise ValueError("admission key has a non-integer port: %r" % k)
        if not isinstance(v, dict) or "ok" not in v:
            raise ValueError("admission value must be an object with 'ok': %r" % (v,))
        out[(proto, host, port, fp)] = (bool(v["ok"]), str(v.get("reason") or ""))
    return out


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Read-only candidate report: latest complete batch + "
                    "config identity + unified admission + persistent "
                    "blocklist -> per-candidate verdicts + batchable count.")
    p.add_argument("--db", required=True, help="pool.db path (opened read-only)")
    p.add_argument("--registry", required=True, help="source_groups.json path")
    p.add_argument("--rejected", default=None,
                   help="optional rejected_nodes.json (strict load, unioned with the DB blocklist)")
    p.add_argument("--admission", default=None,
                   help="optional admission JSON file (protocol|host|port|fingerprint -> {ok, reason})")
    p.add_argument("--now", type=int, default=None)
    p.add_argument("--ttl", type=int, default=DEFAULT_TTL_S)
    p.add_argument("--run-cap", type=int, default=DEFAULT_RUN_CAP)
    p.add_argument("--control-slots", type=int, default=DEFAULT_CONTROL_SLOTS)
    args = p.parse_args(argv)
    if not os.path.isfile(args.db):
        print("FAIL-CLOSED: db file missing: %s" % args.db, file=sys.stderr)
        return 2
    registry, _meta = load_registry(args.registry)
    admission = _load_admission_file(args.admission) if args.admission else {}
    blocked = None
    conn = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True)
    try:
        blocked = load_blocked(conn)
        if args.rejected:
            rejected = load_rejected_strict(args.rejected)
            blocked = blocked | set(rejected.keys())
        report = compute_candidates(
            conn, registry, now=args.now, ttl_s=args.ttl,
            admission=admission, blocked=blocked,
            run_cap=args.run_cap, control_slots=args.control_slots)
    finally:
        conn.close()
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
