#!/usr/bin/env python3
"""Integration-02 live prevalence, LINE-LEVEL (P1-1 population).
Same population as P1-1: every parsed subscription line, cross-source
duplicates included, each line labelled with its own source.
READ-ONLY: fetches the 10 public subscriptions, prints aggregates only.
No IPs, no credentials, no URIs.
"""
import collections
import sys

sys.path.insert(0, "/opt/free-node-program/pool")
from crawler import load_sources, fetch, decode_body, parse_record  # noqa: E402

sources = load_sources("/opt/free-node-program/sources.yaml")
print("sources:", len(sources))

all_lines = 0
unparsed = 0
other = collections.Counter()
by_proto = collections.Counter()
sec = collections.Counter()
net = collections.Counter()
tls = collections.Counter()
comma_pw = 0
comma_pw_space = 0
comma_uuid = 0
ss_plugin = 0
ss_methods = collections.Counter()
trojan_ttype = collections.Counter()
nonws_path = 0
nonws_host = 0
trojan_nonws_path = 0
by_src = collections.defaultdict(set)
per_src_lines = collections.Counter()

for s in sources:
    name = s["name"]
    try:
        text = fetch(s["url"])
    except Exception as e:
        print(f"fetch FAILED {name}: {type(e).__name__}")
        continue
    lines = decode_body(text)
    per_src_lines[name] = len(lines)
    for line in lines:
        all_lines += 1
        r = parse_record(line, name)
        if isinstance(r, tuple):
            # ("other", scheme): known non-whitelisted protocol, not unparsable.
            other[r[1]] += 1
            continue
        if r is None:
            unparsed += 1
            continue
        p = r["protocol"]
        by_proto[p] += 1
        by_src[name].add((p, r["host"], r["port"]))
        if p == "vmess":
            sec[r.get("security")] += 1
            net[r.get("net")] += 1
            tls[r.get("tls")] += 1
            if r.get("net") != "ws" and r.get("ws_path") not in ("/", None, ""):
                nonws_path += 1
            if r.get("net") != "ws" and r.get("ws_host"):
                nonws_host += 1
            if "," in (r.get("uuid") or ""):
                comma_uuid += 1
        elif p == "trojan":
            trojan_ttype[r.get("t_type")] += 1
            if r.get("ws") is False and r.get("ws_path") not in ("/", None, ""):
                trojan_nonws_path += 1
        elif p == "ss":
            ss_methods[r.get("method")] += 1
            if r.get("plugin"):
                ss_plugin += 1
        pw = r.get("password") or ""
        if "," in pw:
            comma_pw += 1
        if ", " in pw:
            comma_pw_space += 1

print("all_lines:", all_lines)
print("unparsed_or_other:", unparsed, dict(other))
print("by_protocol:", dict(by_proto))
vmess_n = sum(sec.values())
ss_n = sum(ss_methods.values())
print("vmess_security:", dict(sec),
      f"(non-auto {vmess_n - sec.get('auto', 0)}/{vmess_n})")
print("vmess_net:", dict(net))
print("vmess_tls:", dict(tls))
print("vmess_non_ws_with_path:", nonws_path,
      "non_ws_with_host:", nonws_host)
print("trojan_t_type:", dict(trojan_ttype),
      "trojan_nonws_path:", trojan_nonws_path)
print("ss_methods:", dict(ss_methods))
print("ss_plugin_nonempty:", f"{ss_plugin}/{ss_n}")
print("password_contains_comma:", comma_pw,
      "password_contains_comma_space:", comma_pw_space)
print("uuid_contains_comma:", comma_uuid)
print("per_source_lines:", dict(per_src_lines))

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
