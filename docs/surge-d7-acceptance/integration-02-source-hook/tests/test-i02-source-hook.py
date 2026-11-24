#!/usr/bin/env python3
"""Integration-02 isolation tests: source hook + normalization + latest
batch binding (D1/D2/D3/D5/B10/O1, B4 R1/R2, rollback (a)(b)(c)).

Runs in isolation against COPIES of the live pool package (this
directory's pool/) + the v4 frozen module. No live files, no live DB,
no network except file:// synthetic subscriptions. All samples are
SYNTHETIC (TEST-NET 203.0.113.0/24, synthetic passwords/uuids).
No real credentials, no real subscription lines, no real node identity.

Exit 0 = every numbered check passed. Exit 1 = a check failed (the
failing check name is printed). Dual-entry divergences are ASSERTED
against their documented expected outcomes (V3/D2, V4/S2 pre-filtered,
T5/S4 B10-refused) -- they are not failures, and they are not hidden.

Conventions (same as P1-1): KEY is a synthetic test key, never a
production key. NOW is a fixed synthetic "now".
"""
import base64
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# Path resolution works in BOTH layouts:
#   workspace harness: <...>/work/i02-harness/ (pool/ next to this script)
#   PR package:        <...>/integration-02-source-hook/tests/ (pool/ one up)
POOL = (os.path.join(HERE, "pool") if os.path.exists(os.path.join(HERE, "pool", "crawler.py"))
        else os.path.join(HERE, "..", "pool"))
sys.path.insert(0, HERE)
sys.path.insert(0, POOL)
# `import pool.xxx` needs the DIRECTORY CONTAINING the pool package on
# the path: in the harness layout that is HERE itself, in the PR layout
# it is tests/.. (pr-source/). POOL itself stays on the path so the
# migrate script's plain `import source_lineage` keeps working.
sys.path.insert(0, os.path.dirname(os.path.abspath(POOL)))

from pool.crawler import crawl_records, parse_record  # noqa: E402
from pool.rules import build_surge_line, is_valid_uuid, pre_filter  # noqa: E402
from pool.cli import surge_line_to_record  # noqa: E402  (real cli.py function)
from pool import source_lineage as sl  # noqa: E402
from pool import lineage_adapter as la  # noqa: E402

KEY = b"i02-test-key-do-not-use-in-production"
NOW = 1795480000  # fixed synthetic "now" (2026-11-24 ~10:00 CST)
WORK = os.path.join(HERE, "scrape-work")
os.makedirs(WORK, exist_ok=True)

PASSED = []
FAILED = []


def check(name, cond, detail=""):
    if cond:
        PASSED.append(name)
        print(f"  PASS {name}" + (f" -- {detail}" if detail else ""))
    else:
        FAILED.append(name)
        print(f"  FAIL {name}" + (f" -- {detail}" if detail else ""))


def vmess_uri(obj):
    raw = json.dumps(obj, separators=(",", ":")).encode()
    return "vmess://" + base64.b64encode(raw).decode()


def field_diff(a, b):
    keys = sorted(set(a) | set(b))
    return {k: (a.get(k), b.get(k)) for k in keys if a.get(k) != b.get(k)}


def registry_path():
    """source_groups.json: PR layout (tests/../source_groups.json) or
    workspace layout (../../pr-source/)."""
    for cand in (os.path.join(HERE, "..", "source_groups.json"),
                 os.path.join(HERE, "source_groups.json"),
                 os.path.join(HERE, "..", "..", "pr-source", "source_groups.json")):
        if os.path.exists(cand):
            return cand
    return os.path.join(HERE, "source_groups.json")


# ===========================================================================
# Part 1: dual-entry regression (17 cases, P1-1 B6 set, finalized adapter)
# ===========================================================================
print("=== Part 1: dual-entry regression (finalized adapter + B10 rules) ===")
CASES = [
    ("T1 trojan ws+sni+path+host",
     "trojan://syn-pw-001@203.0.113.10:443?sni=cdn.example.com&type=ws&path=%2Fws&host=ws.example.com#synthetic-1"),
    ("T2 trojan tcp plain",
     "trojan://syn-pw-002@203.0.113.11:443?sni=cdn.example.com#synthetic-2"),
    ("T3 trojan sni via peer",
     "trojan://syn-pw-003@203.0.113.12:443?peer=peer.example.com&type=ws&path=%2F#synthetic-3"),
    ("T4 trojan path set but no ws",
     "trojan://syn-pw-004@203.0.113.13:443?sni=cdn.example.com&path=%2Funused&type=tcp#synthetic-4"),
    ("T5 trojan password with %2C comma",
     "trojan://syn-pw%2C005@203.0.113.14:443?sni=cdn.example.com#synthetic-5"),
    ("T6 trojan password with %2C%20",
     "trojan://syn-pw%2C%20006@203.0.113.15:443?sni=cdn.example.com#synthetic-6"),
    ("V1 vmess ws+tls+sni+path+host",
     vmess_uri({"v": "2", "ps": "synthetic-v1", "add": "203.0.113.20", "port": 443,
                "id": "11111111-2222-3333-4444-555555555555", "aid": "0",
                "scy": "auto", "net": "ws", "type": "none", "host": "ws.example.com",
                "path": "/ws", "tls": "tls", "sni": "cdn.example.com"})),
    ("V2 vmess tcp+tls",
     vmess_uri({"v": "2", "ps": "synthetic-v2", "add": "203.0.113.21", "port": 443,
                "id": "11111111-2222-3333-4444-555555555556", "aid": "0",
                "scy": "auto", "net": "tcp", "tls": "tls"})),
    ("V3 vmess scy=aes-128-gcm",
     vmess_uri({"v": "2", "ps": "synthetic-v3", "add": "203.0.113.22", "port": 443,
                "id": "11111111-2222-3333-4444-555555555557", "aid": "0",
                "scy": "aes-128-gcm", "net": "ws", "type": "none",
                "host": "", "path": "/ws", "tls": "tls"})),
    ("V4 vmess net=grpc",
     vmess_uri({"v": "2", "ps": "synthetic-v4", "add": "203.0.113.23", "port": 443,
                "id": "11111111-2222-3333-4444-555555555558", "aid": "0",
                "scy": "auto", "net": "grpc", "tls": "tls"})),
    ("V5 vmess net=tcp but path+host set",
     vmess_uri({"v": "2", "ps": "synthetic-v5", "add": "203.0.113.24", "port": 443,
                "id": "11111111-2222-3333-4444-555555555559", "aid": "0",
                "scy": "auto", "net": "tcp", "type": "none",
                "host": "ws.example.com", "path": "/unused", "tls": "tls"})),
    ("V6 vmess tls=false tcp",
     vmess_uri({"v": "2", "ps": "synthetic-v6", "add": "203.0.113.25", "port": 80,
                "id": "11111111-2222-3333-4444-555555555560", "aid": "0",
                "scy": "auto", "net": "tcp", "tls": ""})),
    ("S1 ss plain aes-256-gcm",
     "ss://YWVzLTI1Ni1nY206c3luLXB3LXNzMDAx@203.0.113.30:8388#synthetic-s1"),
    ("S2 ss with plugin",
     "ss://YWVzLTI1Ni1nY206c3luLXB3LXNzMDAy@203.0.113.31:8388?plugin=v2ray-plugin%3Btls%3Bhost%3Dexample.com#synthetic-s2"),
    ("S3 ss password with %2C (b64 userinfo)",
     "ss://YWVzLTI1Ni1nY206c3luLXB3JTJDLXN zMDAz@203.0.113.32:8388#synthetic-s3".replace(" ", "")),
    ("S4 ss PLAIN userinfo password with %2C comma",
     "ss://aes-256-gcm:syn-pw%2C-s004@203.0.113.33:8388#synthetic-s4"),
    ("S5 ss b64 userinfo password with colon",
     "ss://" + base64.b64encode(b"aes-256-gcm:syn-pw:with-colon").decode()
     + "@203.0.113.34:8388#synthetic-s5"),
]
SRC = "synthetic-src"
PRIVATE = set()

raw_match = 0
canon_match = 0
results = {}
for label, uri in CASES:
    rec_a = parse_record(uri, SRC)
    assert rec_a is not None and not isinstance(rec_a, tuple), label
    try:
        line = build_surge_line(rec_a, "合成-1")
    except ValueError as e:
        results[label] = ("BUILD_REFUSED", str(e))
        continue
    rec_b = surge_line_to_record(line)
    assert rec_b is not None, label
    fp_raw_a = sl.config_fingerprint(rec_a, KEY)
    fp_raw_b = sl.config_fingerprint(rec_b, KEY)
    ca, cb = la.canonical_config(rec_a), la.canonical_config(rec_b)
    fp_can_a = sl.config_fingerprint(ca, KEY)
    fp_can_b = sl.config_fingerprint(cb, KEY)
    results[label] = ("OK", fp_raw_a == fp_raw_b, fp_can_a == fp_can_b,
                      field_diff(rec_a, rec_b), ca, cb)
    raw_match += (fp_raw_a == fp_raw_b)
    canon_match += (fp_can_a == fp_can_b)

# Expected: raw 0/17 (name_hint/source differ by construction).
check("P1-raw-0/17", raw_match == 0, f"raw_match={raw_match}")
# Expected consistent (canonical match): T1-T4, V1, V2, V5, V6, S1, S3, S5.
for lbl in ["T1 trojan ws+sni+path+host", "T2 trojan tcp plain",
            "T3 trojan sni via peer", "T4 trojan path set but no ws",
            "V1 vmess ws+tls+sni+path+host", "V2 vmess tcp+tls",
            "V5 vmess net=tcp but path+host set", "V6 vmess tls=false tcp",
            "S1 ss plain aes-256-gcm", "S3 ss password with %2C (b64 userinfo)",
            "S5 ss b64 userinfo password with colon"]:
    st = results[lbl]
    check(f"P1-canon-{lbl.split()[0]}", st[0] == "OK" and st[2] is True,
          f"status={st[0]} canon_match={st[2] if st[0]=='OK' else '-'}")
# T5/S4: B10 -- build must now REFUSE (was: truncated password, canonical mismatch).
for lbl in ["T5 trojan password with %2C comma",
            "S4 ss PLAIN userinfo password with %2C comma"]:
    check(f"P1-B10-{lbl.split()[0]}-refused", results[lbl][0] == "BUILD_REFUSED",
          f"status={results[lbl][0]}")
# T6: pre-existing refusal (", " password).
check("P1-T6-refused", results["T6 trojan password with %2C%20"][0] == "BUILD_REFUSED")
# V3: D2 -- canonical mismatch, and the ONLY differing canonical field is security.
st = results["V3 vmess scy=aes-128-gcm"]
check("P1-V3-D2-diverges", st[0] == "OK" and st[2] is False, f"canon_match={st[2]}")
ca, cb = st[4], st[5]
check("P1-V3-only-security-differs",
      {k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k)} == {"security"},
      f"diff_keys={[k for k in set(ca)|set(cb) if ca.get(k)!=cb.get(k)]}")
# V4: canonical mismatch (grpc vs tcp) + pre_filter refuses + O1 gate refuses.
st = results["V4 vmess net=grpc"]
rec_v4 = parse_record([u for l, u in CASES if l.startswith("V4")][0], SRC)
check("P1-V4-diverges", st[0] == "OK" and st[2] is False)
# NOTE: pre_filter checks below use a hostname host. The synthetic
# 203.0.113.x TEST-NET addresses are classified private by ipaddress,
# so pre_filter would refuse them as 'private-host' before reaching
# the transport/method checks -- a test artifact, not a production
# path (real subscriptions carry public hosts). The host value is
# irrelevant to the transport/method reasons being asserted.
rec_v4_h = dict(rec_v4, host="grpc.example.invalid")
check("P1-V4-prefilter-refuses",
      pre_filter(rec_v4_h, PRIVATE) == (False, "unsupported-transport"),
      f"{pre_filter(rec_v4_h, PRIVATE)}")
check("P1-V4-O1-gate-refuses",
      la.admission_gate(rec_v4) == (False, "unsupported-transport", "grpc"))
# S2: canonical mismatch (plugin vs None) + pre_filter refuses (ss-plugin).
st = results["S2 ss with plugin"]
rec_s2 = parse_record([u for l, u in CASES if l.startswith("S2")][0], SRC)
check("P1-S2-diverges", st[0] == "OK" and st[2] is False)
rec_s2_h = dict(rec_s2, host="plugin.example.invalid")
check("P1-S2-prefilter-refuses",
      pre_filter(rec_s2_h, PRIVATE) == (False, "ss-plugin"),
      f"{pre_filter(rec_s2_h, PRIVATE)}")
check("P1-S2-plugin-kept-in-canonical",
      la.canonical_config(rec_s2).get("plugin") is not None)
# V6: round-trips, but pre_filter refuses non-tls from publish.
rec_v6 = parse_record([u for l, u in CASES if l.startswith("V6")][0], SRC)
rec_v6_h = dict(rec_v6, host="nontls.example.invalid")
check("P1-V6-prefilter-refuses-nontls",
      pre_filter(rec_v6_h, PRIVATE) == (False, "vmess-non-tls"))
# Auth-variant distinction through the canonical path.
a1 = parse_record("trojan://syn-pw-AAA@203.0.113.40:443?sni=cdn.example.com#x", SRC)
a2 = parse_record("trojan://syn-pw-BBB@203.0.113.40:443?sni=cdn.example.com#x", SRC)
a3 = parse_record("trojan://syn-pw-AAA@203.0.113.40:443?sni=cdn.example.com#other-name", SRC)
check("P1-auth-variant-differs",
      sl.config_fingerprint(la.canonical_config(a1), KEY)
      != sl.config_fingerprint(la.canonical_config(a2), KEY))
check("P1-display-name-same-fp",
      sl.config_fingerprint(la.canonical_config(a1), KEY)
      == sl.config_fingerprint(la.canonical_config(a3), KEY))
print(f"  [P1 totals: raw {raw_match}/17, canonical {canon_match}/17 "
      f"(+2 B10-refused, +1 pre-existing refused)]")

# ===========================================================================
# Part 2: hook Test A vs Test B with the REAL crawl_records + on_observation
# ===========================================================================
print("=== Part 2: hook placement, real crawl_records ===")


def vmess_uri_hp(host, port, uuid, net="ws", tls="tls", scy="auto", ps="syn"):
    """vmess URI builder with (host, port, uuid) args (P1-1 scrape set)."""
    obj = {"v": "2", "ps": ps, "add": host, "port": port, "id": uuid,
           "aid": "0", "scy": scy, "net": net, "tls": tls}
    return "vmess://" + base64.b64encode(
        json.dumps(obj, separators=(",", ":")).encode()).decode()


SOURCES = {
    "syn-a": [
        "trojan://syn-pw-a1@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1",
        "trojan://syn-pw-a2@203.0.113.102:443?sni=cdn.example.com#n2",
        vmess_uri_hp("203.0.113.103", 443, "aaaaaaaa-1111-2222-3333-444444444444"),
    ],
    "syn-b": [
        "trojan://syn-pw-b1@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1-mirror",
        "trojan://syn-pw-b2@203.0.113.104:443?sni=cdn.example.com#n4",
        "ss://YWVzLTI1Ni1nY206c3luLXB3LWI1@203.0.113.105:8388#n5",
    ],
    "syn-c": [
        vmess_uri_hp("203.0.113.103", 443, "aaaaaaaa-1111-2222-3333-444444444444"),
        "trojan://syn-pw-c1@203.0.113.106:443?sni=cdn.example.com#n6",
        "trojan://syn-pw-c2@203.0.113.107:443?sni=cdn.example.com#n7",
    ],
    "syn-d": [
        "trojan://syn-pw-a1@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1",
        vmess_uri_hp("203.0.113.103", 443, "aaaaaaaa-1111-2222-3333-444444444444"),
    ],
}
SOURCES["syn-c"].append(
    "trojan://syn-pw-OTHER@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1-altpw")
for name, lines in SOURCES.items():
    with open(os.path.join(WORK, f"{name}.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
with open(os.path.join(WORK, "sources.yaml"), "w") as f:
    for name in SOURCES:
        f.write(f"- name: {name}\n")
        f.write(f"  url: file://{WORK}/{name}.txt\n")
        f.write("  protocols: [trojan, vmess, ss]\n")

reg_syn = sl.SourceRegistry(
    groups={"g-a": ["syn-a", "syn-d"], "g-b": ["syn-b"], "g-c": ["syn-c"]},
    status={"syn-a": "active", "syn-b": "active", "syn-c": "active",
            "syn-d": "active"})


def fresh_conn():
    c = sqlite3.connect(":memory:")
    sl.ensure_schema(c)
    return c


# Test A: hook AFTER dedup (forbidden position, reproduced for proof).
records_a, counts_a = crawl_records(os.path.join(WORK, "sources.yaml"), skip=set())
conn_a = fresh_conn()
for i, rec in enumerate(records_a):
    r = sl.record_sighting(conn_a, rec["protocol"], rec["host"], int(rec["port"]),
                           sl.config_fingerprint(la.canonical_config(rec), KEY),
                           rec["source"], NOW - 60, evidence="i02-scrape-A",
                           event_id=f"i02-A-{i}")
    assert r["accepted"], r
conn_a.commit()
lin_a = sl.lineage(conn_a, "trojan", "203.0.113.101", 443)
vars_a = sl.variants(conn_a, "trojan", "203.0.113.101", 443)
check("P2-A-records", counts_a["total"] == 12 and counts_a["unique"] == 7,
      f"total={counts_a['total']} unique={counts_a['unique']}")
check("P2-A-101-one-row", len(lin_a) == 1 and lin_a[0]["source"] == "syn-a",
      f"rows={[(x['source'], x['sighting_count']) for x in lin_a]}")
check("P2-A-101-one-variant", len(vars_a) == 1)
conn_a.close()

# Test B: hook PER PARSED LINE via the real on_observation parameter.
conn_b = fresh_conn()
rec_b = la.LineageRecorder(conn_b, KEY, reg_syn, "i02-scrape-B", NOW - 60)
records_b, counts_b = crawl_records(os.path.join(WORK, "sources.yaml"), skip=set(),
                                    on_observation=rec_b.observe)
conn_b.commit()
check("P2-B-same-records-as-no-hook", records_b == records_a,
      "hook must not change dedup / records")
check("P2-B-same-counts", counts_b["total"] == 12 and counts_b["unique"] == 7
      and counts_b.get("observation_errors", 0) == 0,
      f"counts={counts_b}")
check("P2-B-12-sightings", rec_b.recorded == 12, f"recorded={rec_b.recorded}")
check("P2-B-9-variants", rec_b.summary()["variants"] == 9,
      f"variants={rec_b.summary()['variants']}")
lin_b = sl.lineage(conn_b, "trojan", "203.0.113.101", 443)
vars_b = sl.variants(conn_b, "trojan", "203.0.113.101", 443)
check("P2-B-101-three-variants", len(vars_b) == 3, f"variants={len(vars_b)}")
check("P2-B-101-four-lineage-rows", len(lin_b) == 4,
      f"rows={sorted((x['source'], x['sighting_count']) for x in lin_b)}")
by_fp = {}
for v in vars_b:
    rows = sl.lineage(conn_b, "trojan", "203.0.113.101", 443, v["fingerprint"])
    by_fp[v["fingerprint"][:8]] = sorted(r["source"] for r in rows)
check("P2-B-101-variant-sources",
      sorted(sum(by_fp.values(), [])) == ["syn-a", "syn-b", "syn-c", "syn-d"],
      f"{by_fp}")
# Evidence binds every sighting to this batch.
ev = conn_b.execute("SELECT DISTINCT evidence FROM sighting_events").fetchall()
check("P2-B-one-evidence", ev == [("i02-scrape-B",)], f"{ev}")
check("P2-B-evidence-format", rec_b.summary()["evidence"] == "i02-scrape-B")
conn_b.close()

# Hook failure isolation: a raising callback is counted, crawl unaffected.
def boom(rec):
    raise RuntimeError("synthetic hook failure")
records_c, counts_c = crawl_records(os.path.join(WORK, "sources.yaml"), skip=set(),
                                    on_observation=boom)
check("P2-hook-error-counted", counts_c.get("observation_errors") == 12,
      f"errors={counts_c.get('observation_errors')}")
check("P2-hook-error-crawl-intact", records_c == records_a,
      "failing hook must not lose crawl records")

# ===========================================================================
# Part 3: registries (real file + synthetic R1/R2) and batch checks
# ===========================================================================
print("=== Part 3: registries and batch diversity ===")
reg_real, meta = la.load_registry(registry_path())
check("P3-real-registry-loads", meta["groups"] == 3 and meta["sources"] == 10,
      f"{meta}")
check("P3-real-registry-paused",
      sorted(meta["paused"]) == ["chenzhihan-base64", "matin-ss"])
check("P3-au1rxx-folded-into-chenzhihan",
      reg_real.group_of("au1rxx-v2ray") == "G-chenzhihan")
check("P3-barryfar-not-a-group", reg_real.group_of("barry-far") is None)
check("P3-paused-never-qualifies",
      reg_real.is_qualified("chenzhihan-base64") is False
      and reg_real.is_qualified("matin-ss") is False
      and reg_real.is_qualified("matin-vmess") is True)
check("P3-unknown-never-qualifies",
      reg_real.is_qualified("not-a-source") is False)
# Malformed registry rejected.
bad_path = os.path.join(WORK, "bad-groups.json")
with open(bad_path, "w") as f:
    json.dump({"groups": {"g": ["x", "y"], "h": ["y"]}}, f)
try:
    la.load_registry(bad_path)
    check("P3-duplicate-source-rejected", False, "no error raised")
except ValueError:
    check("P3-duplicate-source-rejected", True)
with open(bad_path, "w") as f:
    json.dump({"groups": {"g": ["x"]}, "paused": ["zzz"]}, f)
try:
    la.load_registry(bad_path)
    check("P3-unknown-paused-rejected", False, "no error raised")
except ValueError:
    check("P3-unknown-paused-rejected", True)

# Synthetic R1 (all active) vs R2 (syn-b paused) on the Part-2 DB.
conn = fresh_conn()
rec_r = la.LineageRecorder(conn, KEY, reg_syn, "i02-scrape-B", NOW - 60)
crawl_records(os.path.join(WORK, "sources.yaml"), skip=set(),
              on_observation=rec_r.observe)
conn.commit()
all_vars = []
for (proto, host, port) in conn.execute(
        "SELECT DISTINCT protocol, host, port FROM node_variants").fetchall():
    for v in sl.variants(conn, proto, host, port):
        all_vars.append((proto, host, port, v["fingerprint"]))
check("P3-total-variants-9", len(all_vars) == 9, f"{len(all_vars)}")


def group_of(c, reg):
    return sl.qualified_source_group(conn, reg, c[0], c[1], c[2], c[3], NOW)


by_group = {}
for c in all_vars:
    by_group.setdefault(group_of(c, reg_syn), []).append(c)
check("P3-three-groups", set(by_group) == {"g-a", "g-b", "g-c"},
      f"{ {g: len(v) for g, v in by_group.items()} }")
three = [by_group["g-a"][0], by_group["g-b"][0], by_group["g-c"][0]]
d3 = sl.batch_diversity(conn, reg_syn, three, NOW)
check("P3-3var-one-per-group-passes", d3["passes"] is True, f"{d3['counts']}")
d9 = sl.batch_diversity(conn, reg_syn, all_vars, NOW)
check("P3-9var-balanced-passes",
      d9["passes"] is True and d9["distinct"] == 3
      and abs(d9["max_share"] - 1 / 3) < 1e-9, f"{d9['counts']}")
reg_r2 = sl.SourceRegistry(
    groups={"g-a": ["syn-a", "syn-d"], "g-b": ["syn-b"], "g-c": ["syn-c"]},
    status={"syn-a": "active", "syn-b": "paused", "syn-c": "active",
            "syn-d": "active"})
d9_r2 = sl.batch_diversity(conn, reg_r2, all_vars, NOW)
check("P3-R2-paused-rejects-exclusive",
      d9_r2["passes"] is False
      and all(r["reason"] == "no_qualified_source_group"
              for r in d9_r2["rejected"]),
      f"rejected={len(d9_r2['rejected'])}")
# R2 nuance: a paused source's sightings ARE recorded; a shared variant
# still qualifies through another active source (pause != deletion).
pw_a1 = [c for c in all_vars
         if c[0] == "trojan" and c[1] == "203.0.113.101"
         and sl.lineage(conn, *c[:3], c[3])
         and "syn-a" in [r["source"] for r in sl.lineage(conn, *c[:3], c[3])]][0]
check("P3-R2-shared-variant-still-qualifies",
      sl.qualified_source_group(conn, reg_r2, *pw_a1[:3], pw_a1[3], NOW) == "g-a")
# GPT example A,A,B,C,unknown,unknown must NOT pass.
extra = []
for i, (h, src) in enumerate([("203.0.113.111", "syn-a"), ("203.0.113.112", "syn-a"),
                              ("203.0.113.113", "syn-b"), ("203.0.113.114", "syn-c")]):
    rec = {"protocol": "trojan", "host": h, "port": 443, "source": src,
           "name_hint": "", "password": f"syn-pw-x{i}", "t_type": "tcp",
           "sni": None, "ws": False, "ws_path": "/", "ws_host": None,
           "skip_verify": False}
    fp = sl.config_fingerprint(la.canonical_config(rec), KEY)
    sl.record_sighting(conn, "trojan", h, 443, fp, src, NOW - 60,
                       evidence="i02-scrape-1", event_id=f"i02-gpt-{i}")
    extra.append(("trojan", h, 443, fp))
conn.commit()
gpt_batch = extra + [("trojan", "203.0.113.115", 443, "0" * 64),
                     ("trojan", "203.0.113.116", 443, "f" * 64)]
d_gpt = sl.batch_diversity(conn, reg_syn, gpt_batch, NOW)
check("P3-GPT-example-fails", d_gpt["passes"] is False
      and d_gpt["counts"].get("g-a") == 2, f"{d_gpt['counts']}")
# 3 qualified + 1 unknown must NOT pass; rebuild passes; original unpublishable.
mixed = three + [("trojan", "203.0.113.115", 443, "0" * 64)]
d_mix = sl.batch_diversity(conn, reg_syn, mixed, NOW)
check("P3-3plus1unknown-fails", d_mix["passes"] is False
      and len(d_mix["rejected"]) == 1)
rebuilt = sl.rebuild_batch(d_mix)
d_re = sl.batch_diversity(conn, reg_syn, rebuilt, NOW)
check("P3-rebuilt-passes-original-not-publishable",
      d_re["passes"] is True and d_mix["publishable"] is False)
# Future-dated evidence rejected; older valid still qualifies.
fut = {"protocol": "trojan", "host": "203.0.113.120", "port": 443,
       "source": "syn-a", "name_hint": "", "password": "syn-pw-fut",
       "t_type": "tcp", "sni": None, "ws": False, "ws_path": "/",
       "ws_host": None, "skip_verify": False}
fp_fut = sl.config_fingerprint(la.canonical_config(fut), KEY)
sl.record_sighting(conn, "trojan", "203.0.113.120", 443, fp_fut, "syn-a",
                   NOW + 3600, evidence="i02-future", event_id="i02-fut-1")
sl.record_sighting(conn, "trojan", "203.0.113.120", 443, fp_fut, "syn-c",
                   NOW - 60, evidence="i02-scrape-1", event_id="i02-fut-2")
conn.commit()
check("P3-future-skipped-older-qualifies",
      sl.qualified_source_group(conn, reg_syn, "trojan", "203.0.113.120",
                                443, fp_fut, NOW) == "g-c")
fut2 = {"protocol": "trojan", "host": "203.0.113.121", "port": 443,
        "source": "syn-a", "name_hint": "", "password": "syn-pw-fut2",
        "t_type": "tcp", "sni": None, "ws": False, "ws_path": "/",
        "ws_host": None, "skip_verify": False}
fp_fut2 = sl.config_fingerprint(la.canonical_config(fut2), KEY)
sl.record_sighting(conn, "trojan", "203.0.113.121", 443, fp_fut2, "syn-a",
                   NOW + 3600, evidence="i02-future", event_id="i02-fut-3")
conn.commit()
check("P3-only-future-no-group",
      sl.qualified_source_group(conn, reg_syn, "trojan", "203.0.113.121",
                                443, fp_fut2, NOW) is None)
conn.close()
print(f"  [Part 1-3 done: {len(PASSED)} passed, {len(FAILED)} failed so far]")

if FAILED:
    print(f"\nFAILED CHECKS ({len(FAILED)}): {FAILED}")
    sys.exit(1)
print("  [Part 1-3 done: all passed; continuing to Parts 4-7]")

# ===========================================================================
# Part 4: O1 vmess net whitelist (scrape-layer admission)
# ===========================================================================
print("=== Part 4: O1 net whitelist ===")
conn4 = fresh_conn()
rec4 = la.LineageRecorder(conn4, KEY, reg_syn, "i02-o1", NOW - 60)


def vmess_rec(host, net, uuid="aaaaaaaa-1111-2222-3333-444444444444"):
    return {"protocol": "vmess", "host": host, "port": 443, "source": "syn-a",
            "name_hint": "", "uuid": uuid, "security": "auto", "net": net,
            "tls": True, "ws_path": "/", "ws_host": None, "sni": None,
            "skip_verify": False}


for net in ("ws", "tcp", ""):
    r = rec4.observe(vmess_rec(f"203.0.113.13{len(net)}", net))
    check(f"P4-net-{net or 'empty'}-admitted", r.get("accepted") is True,
          f"{r}")
for net in ("grpc", "raw", "http", "xhttp", "h2", "none", "tcp,udp",
            "tcp#frag@junk"):
    r = rec4.observe(vmess_rec("203.0.113.140", net))
    check(f"P4-net-{net}-audited-not-recorded",
          r.get("recorded") is False and r.get("reason") == "unsupported-transport",
          f"{r}")
conn4.commit()
audit = rec4.summary()["skipped"]
check("P4-audit-counts-by-net",
      audit.get("unsupported-transport", {}).get("grpc") == 1
      and audit.get("unsupported-transport", {}).get("tcp,udp") == 1
      and audit.get("unsupported-transport", {}).get("tcp#frag@junk") == 1,
      f"{audit}")
check("P4-no-lineage-for-unknown-nets",
      conn4.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0] == 3,
      "only ws/tcp/'' admitted")
# O1 v2 (GPT 7121245603): the gate is now the full support matrix, not
# vmess-net-only. Trojan grpc + ss non-AEAD are judged leg by leg and
# rejected because a leg of the chain actually breaks -- NOT by name:
# the tester refuses both, and the Surge line drops trojan grpc
# silently (round-trip loss). The ss line CAN carry a non-AEAD method
# in text (round-trip matches; see the v2 test Part 12), but the
# tester will not verify it, so it still cannot be admitted.
trojan_grpc = {"protocol": "trojan", "host": "203.0.113.141", "port": 443,
               "source": "syn-a", "name_hint": "", "password": "syn-pw-g",
               "t_type": "grpc", "sni": None, "ws": False, "ws_path": "/",
               "ws_host": None, "skip_verify": False}
r = rec4.observe(trojan_grpc)
check("P4-trojan-grpc-gated-by-O1-v2",
      r.get("recorded") is False
      and r.get("reason") == "unsupported-transport",
      f"{r}")
ss_rc4 = {"protocol": "ss", "host": "203.0.113.142", "port": 8388,
          "source": "syn-a", "name_hint": "", "method": "rc4-md5",
          "password": "syn-pw-rc4", "plugin": None}
r = rec4.observe(ss_rc4)
check("P4-ss-nonaead-gated-by-O1-v2",
      r.get("recorded") is False and r.get("reason") == "ss-method",
      f"{r}")
check("P4-prefilter-still-bars-those",
      pre_filter(dict(trojan_grpc, host="grpc.example.invalid"), PRIVATE)
      == (False, "unsupported-transport")
      and pre_filter(dict(ss_rc4, host="rc4.example.invalid"), PRIVATE)
      == (False, "ss-method"))
# v2 matrix rows (direct gate assertions; the full per-combination
# table lives in the v2 test script Part 11).
check("P4-vmess-nontls-gated",
      la.admission_gate(dict(vmess_rec("203.0.113.143", "tcp"), tls=False))
      == (False, "vmess-non-tls", ""))
for sec in ("aes-128-gcm", "chacha20-poly1305", "none"):
    check(f"P4-vmess-security-{sec}-admitted",
          la.admission_gate(dict(vmess_rec("203.0.113.144", "ws"),
                                 security=sec)) == (True, "", ""))
check("P4-vmess-security-unknown-gated",
      la.admission_gate(dict(vmess_rec("203.0.113.145", "ws"),
                             security="aes-256-gcm"))
      == (False, "unsupported-security", "aes-256-gcm"))
check("P4-vmess-security-uppercase-gated",
      la.admission_gate(dict(vmess_rec("203.0.113.146", "ws"),
                             security="AES-128-GCM"))
      == (False, "unsupported-security", "AES-128-GCM"))
check("P4-ss-plugin-gated",
      la.admission_gate({"protocol": "ss", "host": "203.0.113.147",
                         "port": 8388, "source": "syn-a", "name_hint": "",
                         "method": "aes-256-gcm", "password": "syn-pw-p",
                         "plugin": "v2ray-plugin;tls"})
      == (False, "ss-plugin", "present"))
check("P4-vmess-missing-uuid-gated",
      la.admission_gate(dict(vmess_rec("203.0.113.148", "ws"), uuid=""))
      == (False, "missing-uuid", ""))
check("P4-trojan-missing-password-gated",
      la.admission_gate({"protocol": "trojan", "host": "203.0.113.149",
                         "port": 443, "source": "syn-a", "name_hint": "",
                         "password": "", "t_type": "tcp", "sni": None,
                         "ws": False, "ws_path": "/", "ws_host": None,
                         "skip_verify": False})
      == (False, "missing-password", ""))
check("P4-unknown-protocol-fail-closed",
      la.admission_gate({"protocol": "vless", "host": "203.0.113.150",
                         "port": 443})
      == (False, "unknown-protocol", "vless"))
# B10 does NOT gate lineage (v2 re-asserted): comma / malformed
# credentials are still recorded; only publish refuses them.
check("P4-comma-password-still-gets-lineage-v2",
      la.admission_gate({"protocol": "trojan", "host": "203.0.113.151",
                         "port": 443, "source": "syn-a", "name_hint": "",
                         "password": "syn-pw,001", "t_type": "tcp",
                         "sni": None, "ws": False, "ws_path": "/",
                         "ws_host": None, "skip_verify": False})
      == (True, "", ""))
check("P4-invalid-uuid-still-gets-lineage-v2",
      la.admission_gate(dict(vmess_rec("203.0.113.152", "ws"),
                             uuid="not-a-uuid"))
      == (True, "", ""))
conn4.close()

# ===========================================================================
# Part 5: B10 comma passwords (publish rejection; lineage unaffected)
# ===========================================================================
print("=== Part 5: B10 comma passwords ===")


def trojan_rec(pw, host="203.0.113.150"):
    return {"protocol": "trojan", "host": host, "port": 443, "source": "syn-a",
            "name_hint": "", "password": pw, "t_type": "tcp", "sni": None,
            "ws": False, "ws_path": "/", "ws_host": None, "skip_verify": False}


def ss_rec(pw, host="203.0.113.151"):
    return {"protocol": "ss", "host": host, "port": 8388, "source": "syn-a",
            "name_hint": "", "method": "aes-256-gcm", "password": pw,
            "plugin": None}


for pw in ("syn-pw,001", "syn-pw, 002"):
    check(f"P5-trojan-comma-prefilter-{pw!r}",
          pre_filter(dict(trojan_rec(pw), host="c.example.invalid"), PRIVATE)
          == (False, "comma-password"))
    check(f"P5-ss-comma-prefilter-{pw!r}",
          pre_filter(dict(ss_rec(pw), host="c.example.invalid"), PRIVATE)
          == (False, "comma-password"))
    for rec in (trojan_rec(pw), ss_rec(pw)):
        try:
            build_surge_line(rec, "X")
            check(f"P5-build-refuses-{pw!r}", False, "no error raised")
        except ValueError:
            check(f"P5-build-refuses-{pw!r}", True)
check("P5-clean-password-passes",
      pre_filter(dict(trojan_rec("syn-pw-003"), host="c.example.invalid"),
                 PRIVATE) == (True, "")
      and pre_filter(dict(ss_rec("syn-pw-004"), host="c.example.invalid"),
                     PRIVATE) == (True, ""))
check("P5-whitespace-still-bad-password",
      pre_filter(dict(trojan_rec(" syn-pw-005 "), host="c.example.invalid"),
                 PRIVATE) == (False, "bad-password"))
# vmess uuid comma (B10-EXTENSION, same defect class).
vu_bad = vmess_rec("203.0.113.152", "ws", uuid="aaaaaaaa-1111,2222-3333")
vu_bad = dict(vu_bad, host="u.example.invalid")
check("P5-uuid-comma-prefilter",
      pre_filter(vu_bad, PRIVATE) == (False, "comma-uuid"),
      f"{pre_filter(vu_bad, PRIVATE)}")
try:
    build_surge_line(vu_bad, "X")
    check("P5-uuid-comma-build-refuses", False, "no error raised")
except ValueError:
    check("P5-uuid-comma-build-refuses", True)
vu_ok = vmess_rec("203.0.113.153", "ws")
vu_ok = dict(vu_ok, host="u.example.invalid")
check("P5-uuid-clean-passes",
      pre_filter(vu_ok, PRIVATE) == (True, ""))
# B10-EXTENSION v2 (GPT 7121245603): UUID format check -- standard
# 8-4-4-4-12 hex shape only; version/variant nibbles are NOT policed.
for good_uuid in ("11111111-2222-3333-4444-555555555555",
                  "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                  "aAbB1234-5678-90aB-cDeF-0123456789ab"):
    vu = dict(vmess_rec("203.0.113.154", "ws"), uuid=good_uuid,
              host="u.example.invalid")
    check(f"P5-uuid-format-valid-{good_uuid[:8]}",
          is_valid_uuid(good_uuid) is True
          and pre_filter(vu, PRIVATE) == (True, ""))
    try:
        build_surge_line(vu, "X")
        check(f"P5-uuid-format-build-ok-{good_uuid[:8]}", True)
    except ValueError:
        check(f"P5-uuid-format-build-ok-{good_uuid[:8]}", False,
              "valid uuid refused by build")
for bad_uuid, why in (
        ("not-a-uuid", "not-uuid"),
        ("11111111-2222-3333-4444-55555555555", "short-last-group"),
        ("11111111-2222-3333-4444555555555555", "missing-dash"),
        ("11111111-2222-3333-4444-55555555555g", "non-hex"),
        ("11111111-2222-3333-4444", "too-short"),
        ("11111111-2222-3333-4444-555555555555-extra", "extra-group"),
        (" 11111111-2222-3333-4444-555555555555", "leading-space"),
        ("11111111-2222-3333-4444-555555555555 ", "trailing-space")):
    vu = dict(vmess_rec("203.0.113.155", "ws"), uuid=bad_uuid,
              host="u.example.invalid")
    check(f"P5-uuid-format-invalid-{why}",
          is_valid_uuid(bad_uuid) is False
          and pre_filter(vu, PRIVATE) == (False, "invalid-uuid"),
          f"{pre_filter(vu, PRIVATE)}")
    try:
        build_surge_line(vu, "X")
        check(f"P5-uuid-format-build-refuses-{why}", False, "no error raised")
    except ValueError:
        check(f"P5-uuid-format-build-refuses-{why}", True)
# Comma takes precedence over format (v1 behaviour preserved): a
# comma uuid is "comma-uuid", not "invalid-uuid".
vu_comma = dict(vmess_rec("203.0.113.156", "ws"),
                uuid="aaaaaaaa-1111,2222-3333", host="u.example.invalid")
check("P5-uuid-comma-beats-format",
      pre_filter(vu_comma, PRIVATE) == (False, "comma-uuid"))
# Missing uuid is still "missing-uuid" (checked before format).
vu_missing = dict(vmess_rec("203.0.113.157", "ws"), uuid="",
                  host="u.example.invalid")
check("P5-uuid-missing-beats-format",
      pre_filter(vu_missing, PRIVATE) == (False, "missing-uuid"))
# B10 gates PUBLISH, not lineage: a comma-password node still gets lineage.
conn5 = fresh_conn()
rec5 = la.LineageRecorder(conn5, KEY, reg_syn, "i02-b10", NOW - 60)
r = rec5.observe(trojan_rec("syn-pw,009"))
check("P5-comma-password-still-gets-lineage", r.get("accepted") is True,
      f"{r}")
conn5.close()

# ===========================================================================
# Part 6: cmd_crawl end-to-end (real subprocess, synthetic base dir)
# ===========================================================================
print("=== Part 6: cmd_crawl end-to-end ===")
MIGRATE = os.path.join(POOL, "migrate_node_sources.py")
BASE6 = os.path.join(HERE, "crawl-base")
shutil.rmtree(BASE6, ignore_errors=True)
os.makedirs(os.path.join(BASE6, "data"), exist_ok=True)
shutil.copy(os.path.join(WORK, "sources.yaml"),
            os.path.join(BASE6, "sources.yaml"))
with open(os.path.join(BASE6, "source_groups.json"), "w") as f:
    json.dump({"groups": {"g-a": ["syn-a", "syn-d"], "g-b": ["syn-b"],
                          "g-c": ["syn-c"]},
               "paused": []}, f)
DB6 = os.path.join(BASE6, "data", "pool.db")
# The crawl subprocess needs `import pool.cli`: PYTHONPATH must be the
# directory CONTAINING the pool package (harness: HERE; PR: tests/..).
POOL_PARENT = os.path.dirname(os.path.abspath(POOL))
ENV6 = dict(os.environ, PYTHONPATH=POOL_PARENT, POOL_LINEAGE_HMAC_KEY="i02-e2e-key")


def run_cli_crawl(extra_args=(), env_extra=None, cwd=BASE6):
    env = dict(ENV6)
    if env_extra:
        env.update(env_extra)
    r = subprocess.run(
        [sys.executable, "-m", "pool.cli", "crawl", *extra_args],
        cwd=cwd, env=env, capture_output=True, text=True, timeout=120)
    try:
        # cmd_crawl prints one pretty-printed JSON document.
        out = json.loads(r.stdout) if r.stdout.strip() else {}
    except Exception:
        try:
            out = json.loads(r.stdout.strip().splitlines()[-1])
        except Exception:
            out = {"_raw": r.stdout, "_stderr": r.stderr}
    return r.returncode, out, r


def migrate_db(db_path, *args):
    r = subprocess.run([sys.executable, MIGRATE, db_path, *args],
                       capture_output=True, text=True, timeout=120)
    try:
        rep = json.loads(r.stdout) if r.stdout.strip() else {}
    except Exception:
        try:
            rep = json.loads(r.stdout.strip().splitlines()[-1])
        except Exception:
            rep = {"_raw": r.stdout, "_stderr": r.stderr}
    return r.returncode, rep


# 6a: no migration yet -> lineage disabled (schema_not_migrated), crawl OK.
rc, out, _ = run_cli_crawl(env_extra={"POOL_LINEAGE_HMAC_KEY": "i02-e2e-key"})
check("P6-schema-not-migrated-disables-lineage",
      out.get("lineage", {}).get("reason") == "schema_not_migrated",
      f"{out.get('lineage')}")
check("P6-crawl-still-succeeds-without-lineage", rc == 0
      and out.get("unique") == 7, f"rc={rc} unique={out.get('unique')}")
# 6b: migrate, then crawl with key -> lineage recorded.
# The v4 migrate fail-closes on the production schema shape: it requires
# a phone_failures table (created on live by the phone-observation
# importer). The synthetic DB lacks it, so the test setup creates the
# empty table first -- test fixture only, no code change.
c6 = sqlite3.connect(DB6)
c6.execute("CREATE TABLE IF NOT EXISTS phone_failures"
           " (protocol TEXT, host TEXT, port INTEGER)")
c6.commit()
c6.close()
rc_m, rep_m = migrate_db(DB6, "--backup-dir", os.path.join(BASE6, "backups"))
check("P6-migrate-ok", rc_m == 0 and rep_m.get("ok") is True,
      f"rc={rc_m} backfilled={rep_m.get('backfilled_rows')}")
rc, out, _ = run_cli_crawl()
lin = out.get("lineage", {})
check("P6-lineage-enabled", lin.get("enabled") is True, f"{lin}")
check("P6-lineage-recorded-12", lin.get("recorded") == 12,
      f"recorded={lin.get('recorded')}")
check("P6-lineage-variants-9", lin.get("variants") == 9,
      f"variants={lin.get('variants')}")
check("P6-lineage-evidence-format",
      isinstance(lin.get("evidence"), str)
      and lin["evidence"].startswith("crawl:"),
      f"{lin.get('evidence')}")
conn6 = sqlite3.connect(DB6)
check("P6-db-sighting-events-12",
      conn6.execute("SELECT COUNT(*) FROM sighting_events").fetchone()[0] == 12)
# 7 legacy variant rows from the backfill (fingerprint='legacy') + 9 real.
check("P6-db-node-variants-7legacy-plus-9real",
      conn6.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0] == 16
      and conn6.execute("SELECT COUNT(*) FROM node_variants"
                        " WHERE fingerprint != 'legacy'").fetchone()[0] == 9)
check("P6-db-nodes-7",
      conn6.execute("SELECT COUNT(*) FROM nodes").fetchone()[0] == 7)
ev1 = lin["evidence"]
# 6c: second crawl run -> new events (one per line per run), variants stay 9.
time.sleep(1.1)
rc, out2, _ = run_cli_crawl()
lin2 = out2.get("lineage", {})
check("P6-run2-enabled", lin2.get("enabled") is True)
check("P6-run2-new-evidence", lin2.get("evidence") != ev1,
      f"{ev1} vs {lin2.get('evidence')}")
check("P6-run2-recorded-12-again", lin2.get("recorded") == 12)
check("P6-run2-variants-still-9", lin2.get("variants") == 9)
check("P6-db-sighting-events-24",
      conn6.execute("SELECT COUNT(*) FROM sighting_events").fetchone()[0] == 24)
check("P6-db-node-variants-still-16",
      conn6.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0] == 16
      and conn6.execute("SELECT COUNT(*) FROM node_variants"
                        " WHERE fingerprint != 'legacy'").fetchone()[0] == 9)
# Same event_id replay is a no-op (v4 dedup): re-record run 1's sighting.
row = conn6.execute(
    "SELECT event_id, protocol, host, port, fingerprint, source, ts, evidence"
    " FROM sighting_events LIMIT 1").fetchone()
r = sl.record_sighting(conn6, row[1], row[2], row[3], row[4], row[5], row[6],
                       evidence=row[7], event_id=row[0])
check("P6-same-event-id-noop", r == {"accepted": False, "reason": "duplicate_event"},
      f"{r}")
# 6d: no key -> lineage disabled, crawl still succeeds, no new sightings.
env_clean = {k: v for k, v in os.environ.items()
             if k != "POOL_LINEAGE_HMAC_KEY"}
env_clean["PYTHONPATH"] = POOL_PARENT
r = subprocess.run([sys.executable, "-m", "pool.cli", "crawl"], cwd=BASE6,
                   env=env_clean, capture_output=True, text=True, timeout=120)
out3 = json.loads(r.stdout)  # pretty-printed JSON document, same as 6a
check("P6-nokey-lineage-disabled",
      out3.get("lineage", {}) == {"enabled": False, "reason": "no_key"},
      f"{out3.get('lineage')}")
check("P6-nokey-crawl-succeeds", r.returncode == 0
      and out3.get("unique") == 7)
check("P6-nokey-no-new-sightings",
      conn6.execute("SELECT COUNT(*) FROM sighting_events").fetchone()[0] == 24)
# 6e: --no-lineage flag.
rc, out4, _ = run_cli_crawl(extra_args=("--no-lineage",))
check("P6-flag-disables-lineage",
      out4.get("lineage", {}) == {"enabled": False, "reason": "disabled_by_flag"},
      f"{out4.get('lineage')}")
check("P6-flag-crawl-succeeds", rc == 0)
# 6f: missing registry file -> lineage disabled.
os.rename(os.path.join(BASE6, "source_groups.json"),
          os.path.join(BASE6, "source_groups.json.bak"))
rc, out5, _ = run_cli_crawl()
check("P6-no-registry-disables-lineage",
      out5.get("lineage", {}).get("reason") == "no_registry",
      f"{out5.get('lineage')}")
os.rename(os.path.join(BASE6, "source_groups.json.bak"),
          os.path.join(BASE6, "source_groups.json"))
check("P6-runs-logged",
      conn6.execute("SELECT COUNT(*) FROM runs WHERE kind='crawl'").fetchone()[0] >= 5)
conn6.close()

# ===========================================================================
# Part 7: latest-batch binding
# ===========================================================================
print("=== Part 7: latest-batch binding ===")
conn7 = sqlite3.connect(DB6)
evs = [r[0] for r in conn7.execute(
    "SELECT DISTINCT evidence FROM sighting_events ORDER BY evidence").fetchall()]
check("P7-two-distinct-run-evidences", len(evs) == 2, f"{evs}")
latest = evs[-1]
# Only real-fingerprint rows carry crawl evidence; legacy backfill rows do not.
check("P7-last-evidence-is-latest-run",
      all(r[0] == latest for r in conn7.execute(
          "SELECT last_evidence FROM node_sources"
          " WHERE fingerprint != 'legacy'").fetchall()),
      f"latest={latest}")
now7 = int(time.time())
fp101 = conn7.execute(
    "SELECT fingerprint FROM node_variants WHERE protocol='trojan'"
    " AND host='203.0.113.101' AND port=443 AND fingerprint != 'legacy'"
    " LIMIT 1").fetchone()[0]
reg7 = sl.SourceRegistry(
    groups={"g-a": ["syn-a", "syn-d"], "g-b": ["syn-b"], "g-c": ["syn-c"]},
    status={"syn-a": "active", "syn-b": "active",
            "syn-c": "active", "syn-d": "active"})
check("P7-qualified-group-traces-to-latest-run",
      sl.qualified_source_group(conn7, reg7, "trojan", "203.0.113.101", 443,
                                fp101, now7) in ("g-a", "g-b", "g-c"))
conn7.close()

if FAILED:
    print(f"\nFAILED CHECKS ({len(FAILED)}): {FAILED}")
    sys.exit(1)
print(f"\nPARTS 1-7 DONE: {len(PASSED)} passed, 0 failed")
print("PARTS 8-9 run as separate scripts; see below.")
