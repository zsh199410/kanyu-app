#!/usr/bin/env python3
"""Source lineage tests (isolated, runs on a COPY of the pool snapshot).
Synthetic nodes use TEST-NET addresses (203.0.113.0/24) so no real node
identities appear in output. Run: python3 test_source_lineage.py
Exit 0 = all pass, 1 = any failure.
"""
import json
import os
import shutil
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SNAPSHOT = os.path.join(HERE, "pool-snapshot.db")
TEST_DB = os.path.join(HERE, "test-lineage.db")
MIGRATE = os.path.join(HERE, "migrate_node_sources.py")
sys.path.insert(0, HERE)
import source_lineage as sl

# Synthetic TEST-NET identities (documentation range, never real nodes).
SYN = [
    ("vmess", "203.0.113.11", 443),
    ("trojan", "203.0.113.12", 443),
    ("ss", "203.0.113.13", 443),
    ("vmess", "203.0.113.14", 443),
]
T0 = 1795400000


def run_migrate(*args):
    r = subprocess.run([sys.executable, MIGRATE, TEST_DB, *args],
                       capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def fresh_db():
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)
    shutil.copyfile(SNAPSHOT, TEST_DB)


def counts(conn):
    return {
        "nodes": conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0],
        "node_tests": conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0],
        "phone_failures": conn.execute("SELECT COUNT(*) FROM phone_failures").fetchone()[0],
    }


def insert_syn(conn, identity, source, ts):
    p, h, port = identity
    conn.execute(
        "INSERT OR IGNORE INTO nodes (protocol, host, port, source, name_hint,"
        " first_seen, last_seen, pass_count, test_count, status)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 'active')",
        (p, h, port, source, "synthetic-test-node", ts, ts))
    conn.commit()


def main():
    passed = []
    failed = []

    def check(name, cond, detail=""):
        (passed if cond else failed).append(name)
        print(("PASS " if cond else "FAIL ") + name + ((" | " + str(detail)) if detail else ""))

    fresh_db()
    conn = sqlite3.connect(TEST_DB)
    base = counts(conn)
    conn.close()

    # 1. --check dry-run does not modify the DB.
    rc, out, _ = run_migrate("--check")
    rep = json.loads(out)
    check("check dry-run ok", rc == 0 and rep.get("dry_run") is True)
    conn = sqlite3.connect(TEST_DB)
    check("check leaves no node_sources table",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'").fetchone() is None)
    check("check leaves counts unchanged", counts(conn) == base)
    conn.close()

    # 2. Migrate run 1 (backfill), run 2 (idempotent).
    rc1, out1, _ = run_migrate()
    rep1 = json.loads(out1)
    check("migrate run1 ok", rc1 == 0 and rep1.get("ok") is True,
          f"backfilled={rep1.get('backfilled_rows')}")
    conn = sqlite3.connect(TEST_DB)
    check("backfill rows == nodes", rep1.get("lineage_rows") == base["nodes"],
          f"lineage={rep1.get('lineage_rows')} nodes={base['nodes']}")
    check("counts unchanged after migrate", counts(conn) == base)
    # Sample: a real node's lineage source matches its nodes.source.
    row = conn.execute(
        "SELECT n.source, l.source FROM nodes n JOIN node_sources l"
        " ON n.protocol=l.protocol AND n.host=l.host AND n.port=l.port"
        " LIMIT 1").fetchone()
    check("backfill source matches nodes.source", row is not None and row[0] == row[1])
    conn.close()
    rc2, out2, _ = run_migrate()
    rep2 = json.loads(out2)
    check("migrate run2 idempotent ok", rc2 == 0 and rep2.get("ok") is True)
    check("migrate run2 backfills 0", rep2.get("backfilled_rows") == 0)

    # 3. Upsert + primary source + lineage (synthetic nodes).
    conn = sqlite3.connect(TEST_DB)
    insert_syn(conn, SYN[0], "src-alpha", T0)
    sl.record_sighting(conn, *SYN[0], "src-alpha", T0)
    sl.record_sighting(conn, *SYN[0], "src-beta", T0 + 100)
    sl.record_sighting(conn, *SYN[0], "src-alpha", T0 + 200)
    conn.commit()
    lin = sl.lineage(conn, *SYN[0])
    check("two lineage rows for two sources", len(lin) == 2)
    alpha = [r for r in lin if r["source"] == "src-alpha"][0]
    check("repeat sighting bumps count + last_seen",
          alpha["sighting_count"] == 2 and alpha["last_seen"] == T0 + 200)
    check("primary source is most recent",
          sl.primary_source(conn, *SYN[0]) == "src-alpha")
    check("distinct source count is 2 (reporting only)",
          sl.distinct_source_count(conn, *SYN[0]) == 2)
    check("history untouched by upserts", counts(conn)["node_tests"] == base["node_tests"]
          and counts(conn)["phone_failures"] == base["phone_failures"])

    # 4. Diversity rules.
    insert_syn(conn, SYN[1], "src-alpha", T0)
    insert_syn(conn, SYN[2], "src-beta", T0)
    insert_syn(conn, SYN[3], "src-gamma", T0)
    for ident, src in [(SYN[1], "src-alpha"), (SYN[2], "src-beta"), (SYN[3], "src-gamma")]:
        sl.record_sighting(conn, *ident, src, T0)
    conn.commit()
    d3 = sl.batch_diversity(conn, [SYN[1], SYN[2], SYN[3]])
    check("3 nodes / 3 primary sources passes",
          d3["passes"] is True and d3["distinct"] == 3, d3)
    d2 = sl.batch_diversity(conn, [SYN[1], SYN[2], SYN[1]])
    check("2 distinct primary sources fails", d2["passes"] is False and d2["distinct"] == 2, d2)
    d1 = sl.batch_diversity(conn, [SYN[1], SYN[1], SYN[1]])
    check("1 primary source fails (max_share 1.0)",
          d1["passes"] is False and abs(d1["max_share"] - 1.0) < 1e-9, d1)
    # One node seen in 2 sources still counts as ONE node, toward primary only.
    # SYN[0] primary src-alpha, SYN[2] src-beta, SYN[3] src-gamma.
    d_multi = sl.batch_diversity(conn, [SYN[0], SYN[2], SYN[3]])
    check("multi-source node counts once (distinct 3, total 3)",
          d_multi["distinct"] == 3 and d_multi["total"] == 3, d_multi)
    d_single = sl.batch_diversity(conn, [SYN[0]])
    check("single multi-source node is distinct 1, not 2",
          d_single["distinct"] == 1 and d_single["total"] == 1, d_single)
    # Node with no lineage rows: counted under None, adds no distinct source.
    ghost = ("vmess", "203.0.113.99", 443)
    insert_syn(conn, ghost, "src-alpha", T0)
    conn.commit()
    d_ghost = sl.batch_diversity(conn, [ghost, SYN[1], SYN[2]])
    check("unattributed node adds no distinct source",
          d_ghost["distinct"] == 2 and d_ghost["counts"].get(None) == 1, d_ghost)
    conn.close()

    # 5. Rollback: drop table, everything else unchanged (synthetic nodes stay).
    conn = sqlite3.connect(TEST_DB)
    pre_rollback = counts(conn)
    conn.close()
    rc3, out3, _ = run_migrate("--rollback")
    rep3 = json.loads(out3)
    check("rollback ok", rc3 == 0 and rep3.get("ok") is True)
    conn = sqlite3.connect(TEST_DB)
    check("rollback removes node_sources",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'").fetchone() is None)
    check("rollback leaves counts unchanged (incl. synthetic nodes)",
          counts(conn) == pre_rollback)
    check("rollback integrity ok",
          conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
    conn.close()

    print(f"source lineage: {len(passed)}/{len(passed) + len(failed)} PASS")
    if failed:
        print("FAILED:", failed)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
