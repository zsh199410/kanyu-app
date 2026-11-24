#!/usr/bin/env python3
"""Integration-02 v2 live prevalence (GPT 7121245603).
Runs ON THE VPS. Parses the 10 live subscriptions with the LIVE
crawler, then classifies every parsed line with the v2
pre_filter / admission_gate / UUID format check.

Two denominators, both reported (never one masquerading as the other):
  * LINE view  -- every parsed subscription line (cross-source
    duplicates included), each line labelled with its own source.
  * TRIPLE view -- de-duplicated by (protocol, host, port), first
    occurrence wins (same rule as the crawler's own de-duplication).

Gate-rejected rows are NOT deleted: they stay as audit-only raw
source counts (part a). B10-rejected rows (comma / invalid uuid)
are lineage-recorded but publish-refused (part b). The report keeps
(a) and (b) separate.

READ-ONLY: fetches the 10 public subscriptions, prints aggregates
only. No IPs, no credentials, no URIs. No live files are written.
"""
import collections
import sys

sys.path.insert(0, "/tmp/i02v2")
sys.path.insert(0, "/opt/free-node-program/pool")
from crawler import load_sources, fetch, decode_body, parse_record  # noqa: E402
from pool import lineage_adapter as la  # noqa: E402
from pool.rules import is_valid_uuid, pre_filter  # noqa: E402

# v1 gate, re-implemented inline for the v1-vs-v2 delta (v1 O1 scope was
# vmess net only; everything else was admitted to lineage).
V1_VMESS_NET_OK = {"ws", "tcp", ""}


def v1_gate(rec):
    if rec["protocol"] == "vmess":
        net = (rec.get("net") or "").strip().lower()
        if net not in V1_VMESS_NET_OK:
            return (False, "unsupported-net")
    return (True, "")


def uuid_class(rec):
    """vmess only: comma > missing > invalid > valid (pre_filter order)."""
    u = rec.get("uuid")
    if u is None:
        return "missing"
    if "," in u:
        return "comma"
    if u == "":
        return "missing"
    return "valid" if is_valid_uuid(u) else "invalid"


def classify(rec):
    """Return the per-record classification dict."""
    gate_ok, gate_reason, _ = la.admission_gate(rec)
    pf_ok, pf_reason = pre_filter(rec, set())
    v1_ok, v1_reason = v1_gate(rec)
    out = {
        "gate": (gate_ok, gate_reason),
        "prefilter": (pf_ok, pf_reason),
        "v1_gate": (v1_ok, v1_reason),
    }
    if rec["protocol"] == "vmess":
        out["uuid_class"] = uuid_class(rec)
    return out


sources = load_sources("/opt/free-node-program/sources.yaml")
print("sources:", len(sources))

line = collections.Counter()
triple = collections.Counter()
gate_line = collections.Counter()
gate_triple = collections.Counter()
pf_line = collections.Counter()
pf_triple = collections.Counter()
v1v2_delta_line = collections.Counter()
v1v2_delta_triple = collections.Counter()
uuid_line = collections.Counter()
uuid_triple = collections.Counter()
vmess_sec = collections.Counter()
vmess_net = collections.Counter()
vmess_tls = collections.Counter()
ss_methods = collections.Counter()
trojan_ttype = collections.Counter()
ss_plugin = 0
comma_pw = 0
comma_pw_space = 0
other = collections.Counter()
unparsed = 0
per_src_lines = collections.Counter()
by_src = collections.defaultdict(set)
seen_triples = set()

for s in sources:
    name = s["name"]
    try:
        text = fetch(s["url"])
    except Exception as e:
        print(f"fetch FAILED {name}: {type(e).__name__}")
        continue
    lines = decode_body(text)
    per_src_lines[name] = len(lines)
    for raw in lines:
        line["all"] += 1
        r = parse_record(raw, name)
        if isinstance(r, tuple):
            other[r[1]] += 1
            continue
        if r is None:
            unparsed += 1
            continue
        p = r["protocol"]
        line["parsed"] += 1
        line[f"proto_{p}"] += 1
        by_src[name].add((p, r["host"], r["port"]))
        c = classify(r)
        gate_line[("admitted" if c["gate"][0] else c["gate"][1])] += 1
        pf_line[("admitted" if c["prefilter"][0] else c["prefilter"][1])] += 1
        if c["v1_gate"][0] and not c["gate"][0]:
            v1v2_delta_line[c["gate"][1]] += 1
        if p == "vmess":
            uuid_line[c["uuid_class"]] += 1
            vmess_sec[r.get("security")] += 1
            vmess_net[r.get("net")] += 1
            vmess_tls[r.get("tls")] += 1
        elif p == "trojan":
            trojan_ttype[r.get("t_type")] += 1
        elif p == "ss":
            ss_methods[r.get("method")] += 1
            if r.get("plugin"):
                ss_plugin += 1
        pw = r.get("password") or ""
        if "," in pw:
            comma_pw += 1
        if ", " in pw:
            comma_pw_space += 1
        # TRIPLE view: first occurrence wins.
        key = (p, r["host"], r["port"])
        if key in seen_triples:
            continue
        seen_triples.add(key)
        triple["parsed"] += 1
        triple[f"proto_{p}"] += 1
        gate_triple[("admitted" if c["gate"][0] else c["gate"][1])] += 1
        pf_triple[("admitted" if c["prefilter"][0] else c["prefilter"][1])] += 1
        if c["v1_gate"][0] and not c["gate"][0]:
            v1v2_delta_triple[c["gate"][1]] += 1
        if p == "vmess":
            uuid_triple[c["uuid_class"]] += 1

union = set()
for s in by_src.values():
    union |= s

print("all_lines:", line["all"])
print("unparsed_or_other:", unparsed, dict(other))
print("LINE parsed:", line["parsed"], "by_proto:",
      {k[6:]: v for k, v in line.items() if k.startswith("proto_")})
print("TRIPLE parsed (union):", triple["parsed"], len(union),
      "by_proto:",
      {k[6:]: v for k, v in triple.items() if k.startswith("proto_")})
print("LINE gate_v2:", dict(gate_line))
print("TRIPLE gate_v2:", dict(gate_triple))
print("LINE prefilter_v2:", dict(pf_line))
print("TRIPLE prefilter_v2:", dict(pf_triple))
print("LINE v1-admitted-but-v2-rejected (delta):", dict(v1v2_delta_line),
      "total:", sum(v1v2_delta_line.values()))
print("TRIPLE v1-admitted-but-v2-rejected (delta):",
      dict(v1v2_delta_triple), "total:", sum(v1v2_delta_triple.values()))
print("LINE uuid_class:", dict(uuid_line))
print("TRIPLE uuid_class:", dict(uuid_triple))
vmess_n = sum(vmess_sec.values())
print("vmess_security:", dict(vmess_sec),
      f"(non-auto {vmess_n - vmess_sec.get('auto', 0)}/{vmess_n})")
print("vmess_net:", dict(vmess_net))
print("vmess_tls:", dict(vmess_tls))
print("trojan_t_type:", dict(trojan_ttype))
print("ss_methods:", dict(ss_methods))
print("ss_plugin_nonempty:", ss_plugin)
print("password_contains_comma:", comma_pw,
      "password_contains_comma_space:", comma_pw_space)
print("per_source_lines:", dict(per_src_lines))
for n in sorted(by_src):
    print(f"source_size {n}: {len(by_src[n])}")
