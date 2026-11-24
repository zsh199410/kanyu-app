#!/usr/bin/env python3
"""Integration-02 live prevalence re-verification (READ-ONLY).
Runs the live crawler's fresh parse over all 10 subscriptions and
prints AGGREGATE counts only: no IPs, no credentials, no URIs.
Also re-verifies the 10-source pairwise triple overlap and the live
disabled_sources value. Run on the VPS via stdin; writes nothing.
"""
import collections
import sqlite3
import sys

sys.path.insert(0, "/opt/free-node-program/pool")
from crawler import crawl_records  # noqa: E402

records, counts = crawl_records("/opt/free-node-program/sources.yaml",
                                skip=set())
print("total_lines:", counts["total"])
print("unparsed:", counts["unparsed"])
print("other_protocol:", dict(counts["other_protocol"]))
print("by_protocol:", dict(counts["by_protocol"]))
print("unique_triples:", counts["unique"])
print("sources_ok:", counts["sources_ok"], "of", counts["sources"])
print("vmess_tls:", counts["vmess_tls"],
      "vmess_non_tls:", counts["vmess_non_tls"])

# Field-level prevalence over parsed records.
sec = collections.Counter()
net = collections.Counter()
tls = collections.Counter()
comma_pw = 0
comma_uuid = 0
comma_pw_space = 0
ss_plugin = 0
ss_methods = collections.Counter()
trojan_ttype = collections.Counter()
nonws_path = 0
nonws_host = 0
for r in records:
    p = r["protocol"]
    if p == "vmess":
        sec[r.get("security")] += 1
        net[r.get("net")] += 1
        tls[r.get("tls")] += 1
        if r.get("net") != "ws" and r.get("ws_path") not in ("/", None, ""):
            nonws_path += 1
        if r.get("net") != "ws" and r.get("ws_host"):
            nonws_host += 1
        u = r.get("uuid") or ""
        if "," in u:
            comma_uuid += 1
    elif p == "trojan":
        trojan_ttype[r.get("t_type")] += 1
        if r.get("ws") is False and r.get("ws_path") not in ("/", None, ""):
            nonws_path += 1
    elif p == "ss":
        ss_methods[r.get("method")] += 1
        if r.get("plugin"):
            ss_plugin += 1
    pw = r.get("password") or ""
    if "," in pw:
        comma_pw += 1
    if ", " in pw:
        comma_pw_space += 1

vmess_n = sum(sec.values())
ss_n = sum(ss_methods.values())
print("vmess_security:", dict(sec), f"(non-auto {vmess_n - sec.get('auto', 0)}/{vmess_n})")
print("vmess_net:", dict(net))
print("vmess_tls:", dict(tls))
print("vmess_non_ws_with_path:", nonws_path, "non_ws_with_host:", nonws_host)
print("trojan_t_type:", dict(trojan_ttype))
print("ss_methods:", dict(ss_methods))
print("ss_plugin_nonempty:", f"{ss_plugin}/{ss_n}")
print("password_contains_comma:", comma_pw,
      "password_contains_comma_space:", comma_pw_space)
print("uuid_contains_comma:", comma_uuid)

# Per-source triple sets -> pairwise overlap (union + Jaccard-style).
by_src = collections.defaultdict(set)
for r in records:
    by_src[r["source"]].add((r["protocol"], r["host"], r["port"]))
names = sorted(by_src)
union = set()
for s in by_src.values():
    union |= s
print("union_triples:", len(union))
for a in names:
    for b in names:
        if a < b:
            inter = len(by_src[a] & by_src[b])
            if inter:
                print(f"overlap {a} x {b}: {inter} "
                      f"({inter}/{len(by_src[a])} of {a}, "
                      f"{inter}/{len(by_src[b])} of {b})")
for n in names:
    print(f"source_size {n}: {len(by_src[n])}")

# Live DB read-only facts.
c = sqlite3.connect("file:/opt/free-node-program/data/pool.db?mode=ro",
                    uri=True)
print("db_nodes:", c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0])
print("db_node_tests:", c.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0])
print("db_disabled_sources:",
      c.execute("SELECT value FROM config WHERE key='disabled_sources'").fetchone()[0])
print("db_sources:", c.execute(
    "SELECT name, last_count FROM sources ORDER BY name").fetchall())
print("db_sources_last_success:",
      c.execute("SELECT MAX(last_success) FROM sources").fetchone()[0])
