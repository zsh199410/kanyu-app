#!/usr/bin/env python3
"""Source lineage v3 tests (isolated, runs on COPIES of the pool snapshot).
Synthetic nodes use TEST-NET addresses (203.0.113.0/24) and synthetic
config fingerprints, so no real node identities or credentials appear.
Run: python3 test_source_lineage.py
Exit 0 = all pass, 1 = any failure.

Covers GPT Review 6031702642 negative cases: config variants, mirror
same-group, paused+valid sources coexisting, unknown/duplicate rejection,
scrape order changes / replay / time disorder, legacy unverified,
migration-failure transaction rollback.
"""
import hashlib
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
import migrate_node_sources as mig

# Synthetic TEST-NET identities (documentation range, never real nodes).
SYN = [
    ("vmess", "203.0.113.11", 443),
    ("trojan", "203.0.113.12", 443),
    ("ss", "203.0.113.13", 443),
    ("vmess", "203.0.113.14", 443),
    ("trojan", "203.0.113.15", 443),
    ("vmess", "203.0.113.16", 443),
]
T0 = 1795400000          # fixed "now" for freshness checks
FRESH = 86400            # 24h freshness window

# Synthetic configs for fingerprint tests (passwords are fake test values).
CFG_A = {"protocol": "trojan", "host": "203.0.113.11", "port": 443,
         "sni": "a.example.com", "transport": "ws", "path": "/x",
         "tls": True, "password": "secret-A"}
CFG_A_PW2 = dict(CFG_A, password="secret-B")            # only password differs
CFG_A_UUID = dict(CFG_A, uuid="11111111-2222-3333-4444-555555555555")
CFG_B_SNI = dict(CFG_A, sni="b.example.com")            # SNI variant
CFG_C_TCP = dict(CFG_A, transport="tcp", path=None)     # transport variant
CFG_D_PATH = dict(CFG_A, path="/y")                     # path variant

# Registry mirroring the real source landscape: chenzhihan-base64 and
# matin-ss are paused (two consecutive 0% batches); mirror-a/mirror-b are
# the same independent source (one group); unknown-source is unregistered.
REGISTRY = sl.SourceRegistry(
    groups={
        "g-matin-vmess": ["matin-vmess"],
        "g-matin-trojan": ["matin-trojan"],
        "g-alirewa": ["alirewa-config"],
        "g-mirror": ["mirror-a", "mirror-b"],
        "g-chenzhi": ["chenzhihan-base64"],
        "g-au1": ["au1rxx-v2ray"],
    },
    status={
        "matin-vmess": "active",
        "matin-trojan": "active",
        "alirewa-config": "active",
        "mirror-a": "active",
        "mirror-b": "active",
        "chenzhihan-base64": "paused",
        "matin-ss": "paused",
        "au1rxx-v2ray": "active",
    })


def run_migrate(*args):
    r = subprocess.run([sys.executable, MIGRATE, TEST_DB, *args],
                       capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def fresh_db():
    if os.path.exists(TEST_DB):
        os.remove(TEST_DB)
    shutil.copyfile(SNAPSHOT, TEST_DB)
    for suffix in ("-wal", "-shm"):
        if os.path.exists(TEST_DB + suffix):
            os.remove(TEST_DB + suffix)


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


def file_sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def main():
    passed = []
    failed = []

    def check(name, cond, detail=""):
        (passed if cond else failed).append(name)
        print(("PASS " if cond else "FAIL ") + name + ((" | " + str(detail)) if detail else ""))

    # ------------------------------------------------ A. fingerprint
    fp_a = sl.config_fingerprint(CFG_A)
    check("fingerprint is 64-hex", len(fp_a) == 64 and all(c in "0123456789abcdef" for c in fp_a))
    check("fingerprint deterministic", sl.config_fingerprint(CFG_A) == fp_a)
    check("password-only difference keeps fingerprint",
          sl.config_fingerprint(CFG_A_PW2) == fp_a)
    check("uuid-only difference keeps fingerprint",
          sl.config_fingerprint(CFG_A_UUID) == fp_a)
    check("SNI variant changes fingerprint",
          sl.config_fingerprint(CFG_B_SNI) != fp_a)
    check("transport variant changes fingerprint",
          sl.config_fingerprint(CFG_C_TCP) != fp_a)
    check("path variant changes fingerprint",
          sl.config_fingerprint(CFG_D_PATH) != fp_a)
    check("no credential string in fingerprint input/output",
          "secret-A" not in fp_a and "secret-B" not in sl.config_fingerprint(CFG_A_PW2))
    try:
        sl.config_fingerprint({"password": "only-a-password"})
        check("credential-only config raises", False)
    except ValueError:
        check("credential-only config raises", True)
    try:
        sl.config_fingerprint("trojan://user:pass@host:443")
        check("raw URI string raises", False)
    except ValueError:
        check("raw URI string raises", True)

    # ------------------------------------------------ B. record_sighting
    fresh_db()
    conn = sqlite3.connect(TEST_DB)
    sl.ensure_schema(conn)
    conn.commit()
    base = counts(conn)
    fp_b = sl.config_fingerprint(CFG_B_SNI)
    r = sl.record_sighting(conn, *SYN[0], fp_a, "matin-vmess", T0, "run-1", "ev-1")
    check("first sighting accepted", r["accepted"] is True, r)
    conn.commit()
    lin = sl.lineage(conn, *SYN[0], fp_a)
    check("one lineage row after first sighting", len(lin) == 1, lin)
    check("first sighting count=1 first=last=T0",
          lin[0]["sighting_count"] == 1 and lin[0]["first_seen"] == T0 and lin[0]["last_seen"] == T0)
    check("variant row verified", sl.variants(conn, *SYN[0])[0]["verified"] is True)
    r = sl.record_sighting(conn, *SYN[0], fp_a, "matin-vmess", T0 + 100, "run-2", "ev-2")
    check("later sighting accepted", r["accepted"] is True)
    conn.commit()
    lin = sl.lineage(conn, *SYN[0], fp_a)
    check("later sighting count=2 last=T0+100",
          lin[0]["sighting_count"] == 2 and lin[0]["last_seen"] == T0 + 100
          and lin[0]["first_seen"] == T0)
    # Out-of-order: a sighting between first and last must not move last_seen back.
    r = sl.record_sighting(conn, *SYN[0], fp_a, "matin-vmess", T0 + 50, "run-3", "ev-3")
    check("out-of-order sighting accepted as new evidence", r["accepted"] is True)
    conn.commit()
    lin = sl.lineage(conn, *SYN[0], fp_a)
    check("out-of-order keeps last_seen at max",
          lin[0]["sighting_count"] == 3 and lin[0]["last_seen"] == T0 + 100
          and lin[0]["first_seen"] == T0, lin)
    # Older than first_seen: first_seen moves down, last_seen stays.
    r = sl.record_sighting(conn, *SYN[0], fp_a, "matin-vmess", T0 - 500, "run-0", "ev-0")
    check("older sighting accepted", r["accepted"] is True)
    conn.commit()
    lin = sl.lineage(conn, *SYN[0], fp_a)
    check("older sighting moves first_seen down only",
          lin[0]["sighting_count"] == 4 and lin[0]["first_seen"] == T0 - 500
          and lin[0]["last_seen"] == T0 + 100, lin)
    # Exact replay: same variant/source/ts -> no-op.
    r = sl.record_sighting(conn, *SYN[0], fp_a, "matin-vmess", T0 + 100, "run-2b", "ev-2x")
    check("exact replay is no-op", r["accepted"] is False, r)
    conn.commit()
    lin = sl.lineage(conn, *SYN[0], fp_a)
    check("replay does not bump count", lin[0]["sighting_count"] == 4, lin)
    # Same event_id twice -> no-op.
    r = sl.record_sighting(conn, *SYN[0], fp_a, "alirewa-config", T0 + 200, "run-4", "ev-1")
    check("same event_id is no-op", r["accepted"] is False, r)
    # Missing evidence / bad ts / legacy fingerprint -> ValueError.
    for bad_kwargs, label in [
            (dict(evidence=""), "empty evidence raises"),
            (dict(evidence=None), "None evidence raises"),
            (dict(ts=-1), "negative ts raises"),
            (dict(ts="x"), "non-int ts raises")]:
        try:
            kw = dict(protocol=SYN[0][0], host=SYN[0][1], port=SYN[0][2],
                      fingerprint=fp_a, source="matin-vmess", ts=T0 + 300,
                      evidence="run-x", event_id="ev-x")
            kw.update(bad_kwargs)
            sl.record_sighting(conn, **kw)
            check(label, False)
        except ValueError:
            check(label, True)
    try:
        sl.record_sighting(conn, *SYN[0], sl.LEGACY_FINGERPRINT, "matin-vmess",
                           T0 + 300, "run-x", "ev-x")
        check("legacy fingerprint sighting raises", False)
    except ValueError:
        check("legacy fingerprint sighting raises", True)
    check("history untouched by sightings", counts(conn) == base)
    conn.close()

    # ------------------------------------------------ C. variants
    conn = sqlite3.connect(TEST_DB)
    sl.record_sighting(conn, *SYN[0], fp_b, "matin-vmess", T0, "run-1", "ev-1b")
    sl.record_sighting(conn, *SYN[0], fp_b, "alirewa-config", T0 + 10, "run-1", "ev-1c")
    conn.commit()
    vs = sl.variants(conn, *SYN[0])
    check("same triplet two fingerprints = two variants", len(vs) == 2, vs)
    check("same triplet same fingerprint two sources = one variant",
          len([v for v in vs if v["fingerprint"] == fp_b]) == 1)
    lin_b = sl.lineage(conn, *SYN[0], fp_b)
    check("variant B has two source rows", len(lin_b) == 2, lin_b)
    lin_all = sl.lineage(conn, *SYN[0])
    check("triplet lineage covers both variants", len(lin_all) == 3, lin_all)
    conn.close()

    # ------------------------------------------------ D. registry + qualification
    conn = sqlite3.connect(TEST_DB)
    # Paused-only variant: SYN[1] seen only in chenzhihan-base64 (paused).
    sl.record_sighting(conn, *SYN[1], fp_a, "chenzhihan-base64", T0, "run-1", "ev-p1")
    # Paused + active: SYN[2] in paused first, then active (fresher).
    sl.record_sighting(conn, *SYN[2], fp_a, "chenzhihan-base64", T0 - 100, "run-1", "ev-p2")
    sl.record_sighting(conn, *SYN[2], fp_a, "matin-trojan", T0, "run-2", "ev-a2")
    # Stale-only: SYN[3] in active source but older than the fresh window.
    sl.record_sighting(conn, *SYN[3], fp_a, "matin-vmess", T0 - FRESH - 100, "run-1", "ev-s3")
    # Unregistered source only: SYN[4].
    sl.record_sighting(conn, *SYN[4], fp_a, "some-unknown-source", T0, "run-1", "ev-u4")
    # Mirror group: SYN[5] in mirror-a and mirror-b (same group).
    sl.record_sighting(conn, *SYN[5], fp_a, "mirror-a", T0 - 50, "run-1", "ev-m5a")
    sl.record_sighting(conn, *SYN[5], fp_a, "mirror-b", T0, "run-2", "ev-m5b")
    conn.commit()
    check("paused-only variant has no qualified group",
          sl.qualified_source_group(conn, REGISTRY, *SYN[1], fp_a, T0, FRESH) is None)
    check("paused+active variant qualifies under the active group",
          sl.qualified_source_group(conn, REGISTRY, *SYN[2], fp_a, T0, FRESH) == "g-matin-trojan")
    check("stale-only variant has no qualified group",
          sl.qualified_source_group(conn, REGISTRY, *SYN[3], fp_a, T0, FRESH) is None)
    check("unregistered-source variant has no qualified group",
          sl.qualified_source_group(conn, REGISTRY, *SYN[4], fp_a, T0, FRESH) is None)
    check("mirror sources share one qualified group",
          sl.qualified_source_group(conn, REGISTRY, *SYN[5], fp_a, T0, FRESH) == "g-mirror")
    ps = sl.primary_source(conn, *SYN[1], fp_a)
    check("primary_source display still shows paused source (display only)",
          ps is not None and ps["source"] == "chenzhihan-base64" and ps["verified"] is True, ps)
    check("legacy variant never qualifies",
          sl.qualified_source_group(conn, REGISTRY, *SYN[0], sl.LEGACY_FINGERPRINT, T0, FRESH) is None)
    try:
        sl.SourceRegistry(groups={"g1": ["x"], "g2": ["x"]})
        check("source in two groups raises", False)
    except ValueError:
        check("source in two groups raises", True)
    check("unregistered source status is unverified",
          REGISTRY.status_of("no-such-source") == "unverified")
    conn.close()

    # ------------------------------------------------ E. batch_diversity
    conn = sqlite3.connect(TEST_DB)
    # Second variant under g-matin-trojan (for the GPT example's "A,A"):
    # SYN[1] already has fp_a from paused chenzhihan; add fp_b from active
    # matin-trojan so (SYN[1], fp_b) qualifies under g-matin-trojan.
    sl.record_sighting(conn, *SYN[1], fp_b, "matin-trojan", T0, "run-1", "ev-t1")
    conn.commit()
    # GPT example: A,A,B,C,unknown,unknown -- unknowns must be rejected, so
    # A is 2/4 > 1/3 and the batch FAILS (v2 wrongly diluted A to 2/6=1/3).
    d = sl.batch_diversity(conn, REGISTRY,
                           [(*SYN[2], fp_a), (*SYN[1], fp_b), (*SYN[5], fp_a),
                            (*SYN[0], fp_b), (*SYN[4], fp_a), (*SYN[3], fp_a)],
                           T0, FRESH)
    check("GPT example A,A,B,C,unknown,unknown FAILS",
          d["passes"] is False and d["total"] == 4 and len(d["rejected"]) == 2
          and abs(d["max_share"] - 0.5) < 1e-9, d)
    check("GPT example rejected reasons are no_qualified_group",
          all(r["reason"] == "no_qualified_source_group" for r in d["rejected"]), d)
    check("GPT example counts A=2 B=1 C=1 over accepted only",
          d["counts"] == {"g-matin-trojan": 2, "g-mirror": 1, "g-alirewa": 1}, d)
    # 3 variants / 3 qualified groups passes.
    d3 = sl.batch_diversity(conn, REGISTRY,
                            [(*SYN[2], fp_a), (*SYN[5], fp_a), (*SYN[0], fp_b)],
                            T0, FRESH)
    check("3 variants / 3 qualified groups passes",
          d3["passes"] is True and d3["distinct"] == 3 and d3["total"] == 3, d3)
    # Duplicate variant in the batch is rejected, rest counted.
    ddup = sl.batch_diversity(conn, REGISTRY,
                              [(*SYN[2], fp_a), (*SYN[2], fp_a), (*SYN[5], fp_a),
                               (*SYN[0], fp_b)],
                              T0, FRESH)
    check("duplicate variant rejected, rest counted",
          ddup["total"] == 3 and len(ddup["rejected"]) == 1
          and ddup["rejected"][0]["reason"] == "duplicate_variant", ddup)
    # All unknown -> nothing accepted, fails.
    dall = sl.batch_diversity(conn, REGISTRY,
                              [(*SYN[4], fp_a), (*SYN[3], fp_a), (*SYN[1], fp_a)],
                              T0, FRESH)
    check("all unqualified -> total 0, fails",
          dall["passes"] is False and dall["total"] == 0 and len(dall["rejected"]) == 3, dall)
    # Mirror group counts once: two variants both in g-mirror + one other.
    # SYN[0]/fp_a's most recent qualified sighting is matin-vmess at T0+100,
    # so record a FRESHER mirror-a sighting (T0+200) to move it to g-mirror.
    sl.record_sighting(conn, *SYN[0], fp_a, "mirror-a", T0 + 200, "run-9", "ev-m0")
    conn.commit()
    dmir = sl.batch_diversity(conn, REGISTRY,
                              [(*SYN[0], fp_a), (*SYN[5], fp_a), (*SYN[2], fp_a)],
                              T0, FRESH)
    check("two mirror-group variants count as one group",
          dmir["distinct"] == 2 and dmir["counts"].get("g-mirror") == 2, dmir)
    # Share exactly 1/3 passes; above 1/3 fails.
    check("diversity history untouched", counts(conn) == base)
    conn.close()

    # ------------------------------------------------ F. migration
    fresh_db()
    before_sha = file_sha(TEST_DB)
    rc, out, _ = run_migrate("--check")
    rep = json.loads(out)
    check("check dry-run ok", rc == 0 and rep.get("dry_run") is True, rep)
    check("check is read-only (file hash unchanged)", file_sha(TEST_DB) == before_sha)
    conn = sqlite3.connect(TEST_DB)
    check("check creates no lineage tables",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'").fetchone() is None)
    check("check leaves counts unchanged", counts(conn) == base)
    conn.close()

    # Migrate run 1.
    rc1, out1, _ = run_migrate("--backup-dir", os.path.join(HERE, "test-backups"))
    rep1 = json.loads(out1)
    check("migrate run1 ok", rc1 == 0 and rep1.get("ok") is True, rep1)
    backup_path = rep1.get("backup_path")
    check("migrate created a backup file",
          backup_path is not None and os.path.exists(backup_path), backup_path)
    conn = sqlite3.connect(TEST_DB)
    check("backfill legacy variants == nodes",
          conn.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0] == base["nodes"])
    check("backfill legacy source rows == sourced nodes",
          conn.execute("SELECT COUNT(*) FROM node_sources WHERE fingerprint='legacy'").fetchone()[0]
          == conn.execute("SELECT COUNT(*) FROM nodes WHERE source IS NOT NULL AND source != ''").fetchone()[0])
    check("backfill creates zero verified rows",
          conn.execute("SELECT COUNT(*) FROM node_sources WHERE verified=1").fetchone()[0] == 0)
    check("backfill legacy rows carry NO observation times",
          conn.execute("SELECT COUNT(*) FROM node_sources WHERE fingerprint='legacy'"
                       " AND (first_seen IS NOT NULL OR last_seen IS NOT NULL)").fetchone()[0] == 0)
    check("backfill legacy rows carry no evidence",
          conn.execute("SELECT COUNT(*) FROM node_sources WHERE fingerprint='legacy'"
                       " AND last_evidence IS NOT NULL").fetchone()[0] == 0)
    check("counts unchanged after migrate", counts(conn) == base)
    check("integrity ok after migrate",
          conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
    # A backfilled (legacy) node never qualifies for diversity.
    row = conn.execute("SELECT protocol, host, port FROM nodes LIMIT 1").fetchone()
    check("legacy node has no qualified group",
          sl.qualified_source_group(conn, REGISTRY, row[0], row[1], row[2],
                                    sl.LEGACY_FINGERPRINT, T0, FRESH) is None)
    check("legacy node primary_source is display-only legacy",
          (lambda ps: ps is not None and ps["legacy"] is True)(
              sl.primary_source(conn, row[0], row[1], row[2], sl.LEGACY_FINGERPRINT)))
    conn.close()
    # Migrate run 2: idempotent no-op.
    rc2, out2, _ = run_migrate("--backup-dir", os.path.join(HERE, "test-backups"))
    rep2 = json.loads(out2)
    check("migrate run2 idempotent ok",
          rc2 == 0 and rep2.get("ok") is True and rep2.get("already_migrated") is True, rep2)
    check("migrate run2 backfills 0", rep2.get("backfilled_rows") == 0)

    # Migration failure rolls back: force verify to fail inside the txn.
    fresh_db()
    conn = sqlite3.connect(TEST_DB)
    orig_verify = mig.verify_inside_txn
    mig.verify_inside_txn = lambda *a, **k: ["forced verification failure"]
    try:
        rc3, rep3 = mig.do_migrate(conn, TEST_DB, os.path.join(HERE, "test-backups"))
    finally:
        mig.verify_inside_txn = orig_verify
    check("forced verify failure returns 1", rc3 == 1 and rep3.get("ok") is False, rep3)
    check("failed migration leaves no lineage tables",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'").fetchone() is None
          and conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_variants'").fetchone() is None)
    check("failed migration leaves counts unchanged", counts(conn) == base)
    check("failed migration backup still exists",
          rep3.get("backup_path") is not None and os.path.exists(rep3.get("backup_path")))
    conn.close()

    # v2-layout node_sources -> fail-closed, untouched.
    fresh_db()
    conn = sqlite3.connect(TEST_DB)
    conn.execute(
        "CREATE TABLE node_sources (protocol TEXT, host TEXT, port INTEGER,"
        " source TEXT, first_seen INTEGER, last_seen INTEGER,"
        " sighting_count INTEGER)")
    conn.commit()
    conn.close()
    rc4, out4, _ = run_migrate("--backup-dir", os.path.join(HERE, "test-backups"))
    rep4 = json.loads(out4)
    check("v2-layout table fails closed", rc4 == 1 and rep4.get("ok") is False, rep4)
    conn = sqlite3.connect(TEST_DB)
    check("v2-layout table untouched after refusal",
          [r[1] for r in conn.execute("PRAGMA table_info(node_sources)")]
          == ["protocol", "host", "port", "source", "first_seen", "last_seen", "sighting_count"])
    check("no v3 tables created after refusal",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_variants'").fetchone() is None)
    conn.close()

    # Rollback: no --backup -> exit 2, untouched.
    fresh_db()
    rc5, out5, _ = run_migrate("--rollback")
    rep5 = json.loads(out5)
    check("rollback without --backup refused (exit 2)", rc5 == 2 and rep5.get("ok") is False, rep5)
    # Migrate, add verified sightings, rollback without --allow-data-loss refuses.
    rc6, out6, _ = run_migrate("--backup-dir", os.path.join(HERE, "test-backups"))
    rep6 = json.loads(out6)
    backup6 = rep6.get("backup_path")
    check("migrate for rollback test ok", rc6 == 0 and rep6.get("ok") is True)
    conn = sqlite3.connect(TEST_DB)
    sl.record_sighting(conn, *SYN[0], fp_a, "matin-vmess", T0, "run-9", "ev-r9")
    conn.commit()
    conn.close()
    rc7, out7, _ = run_migrate("--rollback", "--backup", backup6)
    rep7 = json.loads(out7)
    check("rollback refuses when it would destroy verified rows",
          rc7 == 1 and rep7.get("ok") is False, rep7)
    conn = sqlite3.connect(TEST_DB)
    check("refused rollback leaves lineage intact",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'").fetchone() is not None)
    conn.close()
    rc8, out8, _ = run_migrate("--rollback", "--backup", backup6, "--allow-data-loss")
    rep8 = json.loads(out8)
    check("rollback with --allow-data-loss restores",
          rc8 == 0 and rep8.get("ok") is True, rep8)
    conn = sqlite3.connect(TEST_DB)
    check("restored DB has no lineage tables",
          conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'").fetchone() is None)
    check("restored counts match backup", counts(conn) == base)
    check("restored integrity ok",
          conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
    conn.close()

    # ------------------------------------------------ G. source status log
    fresh_db()
    rc9, out9, _ = run_migrate("--backup-dir", os.path.join(HERE, "test-backups"))
    conn = sqlite3.connect(TEST_DB)
    sl.set_source_status(conn, "matin-ss", "paused", T0, "two 0% batches")
    sl.set_source_status(conn, "matin-ss", "active", T0 + 100, "recovered")
    conn.commit()
    check("status log returns latest status",
          sl.current_source_status(conn, "matin-ss") == "active")
    check("unlogged source is unverified",
          sl.current_source_status(conn, "never-seen-source") == "unverified")
    reg2 = sl.registry_from_log(conn, {"g-matin-ss": ["matin-ss"]})
    check("registry_from_log builds status",
          reg2.status_of("matin-ss") == "active" and reg2.group_of("matin-ss") == "g-matin-ss")
    try:
        sl.set_source_status(conn, "x", "bogus", T0)
        check("bad status raises", False)
    except ValueError:
        check("bad status raises", True)
    conn.close()

    print(f"source lineage v3: {len(passed)}/{len(passed) + len(failed)} PASS")
    if failed:
        print("FAILED:", failed)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
