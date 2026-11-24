#!/usr/bin/env python3
"""Part 9 (integration-02): hook performance -- 2000 synthetic subscription
lines (4 sources x 500, trojan/vmess/ss mix, TEST-NET hosts) through the
real crawl_records + LineageRecorder path, in-memory DB. Reports wall
time and ms per 1000 observations; the only hard bound is a generous
60 s sanity cap (a slower result would mean something is pathologically
wrong, not a tuned threshold).
"""
import base64
import json
import os
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
POOL = (os.path.join(HERE, "pool") if os.path.exists(os.path.join(HERE, "pool", "crawler.py"))
        else os.path.join(HERE, "..", "pool"))
WORK = os.path.join(HERE, "perf-work")

sys.path.insert(0, POOL)
sys.path.insert(0, HERE)
# `import pool.xxx` needs the directory CONTAINING the pool package.
sys.path.insert(0, os.path.dirname(os.path.abspath(POOL)))
from pool.crawler import crawl_records  # noqa: E402
import pool.lineage_adapter as la  # noqa: E402
import pool.source_lineage as sl  # noqa: E402

KEY = b"i02-perf-key-do-not-use-in-production"
N_PER_SOURCE = 500


def vmess_uri(host, port, uuid, ps="perf"):
    obj = {"v": "2", "ps": ps, "add": host, "port": port, "id": uuid,
           "aid": "0", "scy": "auto", "net": "ws", "tls": "tls"}
    return "vmess://" + base64.b64encode(
        json.dumps(obj, separators=(",", ":")).encode()).decode()


def build_sources():
    os.makedirs(WORK, exist_ok=True)
    sources = {}
    for s in range(4):
        lines = []
        for i in range(N_PER_SOURCE):
            # TEST-NET hosts; unique triple per line.
            host = f"203.0.113.{s * 50 + (i % 50) + 1}"
            port = 4000 + (i // 50)
            proto = ("trojan", "vmess", "ss")[i % 3]
            if proto == "trojan":
                lines.append(
                    f"trojan://perf-pw-{s}-{i}@{host}:{port}"
                    f"?sni=cdn.example.com&type=ws&path=%2Fws#perf-{s}-{i}")
            elif proto == "vmess":
                lines.append(vmess_uri(
                    host, port, f"aaaaaaaa-{s:04d}-2222-3333-{i:012d}",
                    ps=f"perf-{s}-{i}"))
            else:
                cred = base64.b64encode(
                    f"aes-256-gcm:perf-pw-{s}-{i}".encode()).decode()
                lines.append(f"ss://{cred}@{host}:{port}#perf-{s}-{i}")
        path = os.path.join(WORK, f"perf-src-{s}.txt")
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        sources[f"perf-{s}"] = {"url": f"file://{path}"}
    yaml_path = os.path.join(WORK, "sources.yaml")
    with open(yaml_path, "w") as f:
        for name, spec in sources.items():
            f.write(f"- name: {name}\n  url: {spec['url']}\n"
                    f"  protocols: [trojan, vmess, ss]\n")
    return yaml_path


def main():
    yaml_path = build_sources()
    # Perf registry: all four perf sources in one group (grouping is not
    # what is being measured here).
    reg = sl.SourceRegistry(
        groups={"g-perf": ["perf-0", "perf-1", "perf-2", "perf-3"]},
        status={f"perf-{s}": "active" for s in range(4)})
    conn = sqlite3.connect(":memory:")
    sl.ensure_schema(conn)
    rec = la.LineageRecorder(conn, KEY, reg, "i02-perf",
                             int(time.time()) - 60)

    t0 = time.monotonic()
    records, counts = crawl_records(yaml_path, skip=set(),
                                    on_observation=rec.observe)
    t1 = time.monotonic()
    conn.commit()
    summ = rec.summary()
    total = counts["total"]
    elapsed_ms = (t1 - t0) * 1000.0
    print(f"lines parsed: {total} (expected {4 * N_PER_SOURCE})")
    print(f"unique triples: {counts['unique']}")
    print(f"observations recorded: {summ['recorded']}")
    print(f"variants: {summ['variants']}")
    print(f"errors: {summ['errors']}")
    print(f"wall time: {elapsed_ms:.1f} ms")
    print(f"rate: {elapsed_ms / max(total, 1) * 1000:.1f} ms / 1000 observations")
    assert total == 4 * N_PER_SOURCE, f"total {total}"
    assert summ["recorded"] == total, f"recorded {summ['recorded']}"
    assert summ["errors"] == 0, f"errors {summ['errors']}"
    assert elapsed_ms < 60_000, f"too slow: {elapsed_ms:.1f} ms"
    print("\nPERF CHECK PASSED")


if __name__ == "__main__":
    main()
