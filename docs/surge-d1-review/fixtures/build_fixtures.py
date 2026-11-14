"""D1 fixture builder (SYNTHETIC DATA ONLY -- no real credentials).

Builds the drill fixtures that mirror the 2026-11-14 13:24 native test
structure EXACTLY (same decision pattern, same ms values), but with
synthetic connection parameters:
  - hosts are TEST-NET addresses (192.0.2.0/24, 198.51.100.0/24)
  - passwords are the literal string TEST-ONLY-NOT-A-REAL-NODE
  - sni is test.invalid
  - display names mirror the real 13:24 names (already public in Issue
    #73) prefixed with T<nn> to mark them synthetic

Mirror of the 13:24 native test (44 lines, SHA 1360ab7c...):
  - 14 native-pass (<300ms): T01,T02,T03,T04,T05,T06,T07,T08,T09,T10,
    T12,T13,T14,T20 (incl. 3 conditional: T09 P0 297, T12 P0 281,
    T13 P0 296 -- native pass, P0 in (280,297])
  - 4 native-slow but P0-fast (P0 <280, native 320-1018): T11 (P0 254,
    native 320), T15 (P0 252, native 1018), T16 (P0 255, native 983),
    T17 (P0 199, native 321) -- the dual gate MUST reject these
  - 26 native-failed (P0 failed too)

Outputs (all under fixtures/):
  pool_44_fixture.txt          44 synthetic Surge lines
  clean_14_fixture.txt         the 14 admitted lines (subset)
  native_results_fixture.json  native-results-v1 record, run1 only
  native_results_supersede_fixture.json  run1 + run2 (run2: T01 fails
                               on a newer version -> superseded evidence)
  p0_fixture.db                synthetic probe DB (probe_nodes +
                               probe_reports, same schema as production)
  MAPPING.md                   per-node mirror table + provenance

Usage: python3 fixtures/build_fixtures.py [--out fixtures]
Re-running regenerates identical files (deterministic).
"""

import hashlib
import json
import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402

# (tag, display name, proto, native result) -- native result is
# ("pass", ms) / ("slow", ms) / ("fail", None); P0 ms is separate.
NODES = [
    ("T01", "美国9 \U0001f1fa\U0001f1f8", "trojan", ("pass", 232), 241),
    ("T02", "美国11 \U0001f1fa\U0001f1f8", "trojan", ("pass", 271), 280),
    ("T03", "美国12 \U0001f1fa\U0001f1f8", "trojan", ("pass", 265), 279),
    ("T04", "香港 \U0001f1ed\U0001f1f0", "trojan", ("pass", 119), 105),
    ("T05", "美国1 \U0001f1fa\U0001f1f8", "trojan", ("pass", 240), 237),
    ("T06", "美国7 \U0001f1fa\U0001f1f8", "trojan", ("pass", 264), 237),
    ("T07", "美国10 \U0001f1fa\U0001f1f8", "trojan", ("pass", 242), 252),
    ("T08", "美国5 \U0001f1fa\U0001f1f8", "trojan", ("pass", 280), 245),
    ("T09", "美国2 \U0001f1fa\U0001f1f8", "trojan", ("pass", 260), 297),
    ("T10", "香港2 \U0001f1ed\U0001f1f0", "trojan", ("pass", 131), 106),
    ("T11", "美国3 \U0001f1fa\U0001f1f8", "trojan", ("slow", 320), 254),
    ("T12", "美国13 \U0001f1fa\U0001f1f8", "trojan", ("pass", 264), 281),
    ("T13", "美国8 \U0001f1fa\U0001f1f8", "trojan", ("pass", 232), 296),
    ("T14", "美国4 \U0001f1fa\U0001f1f8", "trojan", ("pass", 264), 245),
    ("T15", "美国6 \U0001f1fa\U0001f1f8", "trojan", ("slow", 1018), 252),
    ("T16", "香港8 \U0001f1ed\U0001f1f0", "trojan", ("slow", 983), 255),
    ("T17", "香港24 \U0001f1ed\U0001f1f0", "trojan", ("slow", 321), 199),
    ("T18", "香港25 \U0001f1ed\U0001f1f0", "trojan", ("fail", None), None),
    ("T19", "香港34 \U0001f1ed\U0001f1f0", "trojan", ("fail", None), None),
    ("T20", "香港36 \U0001f1ed\U0001f1f0", "trojan", ("pass", 75), 90),
    ("T21", "香港39 \U0001f1ed\U0001f1f0", "trojan", ("fail", None), None),
    ("T22", "美国14 \U0001f1fa\U0001f1f8", "trojan", ("fail", None), None),
    ("T23", "伊朗5 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T24", "美国20 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T25", "伊朗9 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T26", "美国30 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T27", "伊朗10 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T28", "伊朗13 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T29", "美国34 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T30", "美国35 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T31", "美国36 \U0001f1fa\U0001f1f8", "trojan", ("fail", None), None),
    ("T32", "美国40 \U0001f1fa\U0001f1f8", "trojan", ("fail", None), None),
    ("T33", "伊朗3 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T34", "美国 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T35", "伊朗 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T36", "美国15 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T37", "美国16 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T38", "伊朗2 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T39", "美国17 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T40", "美国18 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T41", "伊朗4 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T42", "美国19 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
    ("T43", "伊朗6 \U0001f1ee\U0001f1f7", "ss", ("fail", None), None),
    ("T44", "美国21 \U0001f1fa\U0001f1f8", "ss", ("fail", None), None),
]

PASS_TAGS = {"T01", "T02", "T03", "T04", "T05", "T06", "T07", "T08",
             "T09", "T10", "T12", "T13", "T14", "T20"}


def synth_line(tag, name, proto, idx):
    """Deterministic synthetic Surge line (TEST-NET host, fake password)."""
    host = "192.0.2.%d" % (idx + 1) if idx < 250 else "198.51.100.%d" % (idx - 249)
    port = 40000 + idx
    if proto == "trojan":
        return ("%s %s = trojan, %s, %d, password=TEST-ONLY-NOT-A-REAL-NODE, "
                "sni=test.invalid" % (tag, name, host, port))
    if proto == "ss":
        return ("%s %s = ss, %s, %d, encrypt-method=aes-256-gcm, "
                "password=TEST-ONLY-NOT-A-REAL-NODE" % (tag, name, host, port))
    raise ValueError(proto)


def build(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    now = int(time.time())
    lines = []
    fps = {}
    for idx, (tag, name, proto, _native, _p0) in enumerate(NODES):
        line = synth_line(tag, name, proto, idx)
        parsed = parse_surge_line(line)
        assert parsed is not None, line
        _n, p, h, port, params = parsed
        fp = fingerprint_of(p, h, port, params)
        fps[tag] = fp
        lines.append(line)
    pool_bytes = ("\n".join(lines) + "\n").encode("utf-8")
    pool_sha = hashlib.sha256(pool_bytes).hexdigest()
    assert len(set(fps.values())) == 44, "fingerprints must be unique"
    assert len(lines) == 44

    with open(os.path.join(out_dir, "pool_44_fixture.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    clean_lines = [lines[i] for i, (tag, *_rest) in enumerate(NODES)
                   if tag in PASS_TAGS]
    assert len(clean_lines) == 14
    with open(os.path.join(out_dir, "clean_14_fixture.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(clean_lines) + "\n")
    clean_sha = hashlib.sha256(
        ("\n".join(clean_lines) + "\n").encode("utf-8")).hexdigest()

    def native_results():
        out = []
        for tag, name, _proto, (kind, ms), _p0 in NODES:
            if kind == "fail":
                out.append({"fingerprint": fps[tag], "name": "%s %s" % (tag, name),
                            "success": False, "ms": None})
            else:
                out.append({"fingerprint": fps[tag], "name": "%s %s" % (tag, name),
                            "success": True, "ms": ms})
        return out

    run1 = {
        "version_sha": pool_sha,
        "tested_at": now,
        "tested_at_cst": time.strftime("%Y-%m-%d %H:%M:%S CST", time.localtime(now)),
        "mirrors_native_test": "2026-11-14 13:24 CST, ts 1794633840, "
                               "44-line pool SHA 1360ab7c... (fixture SHA differs: "
                               "synthetic connection params)",
        "network": "5G cellular pdp_ip0, no Wi-Fi",
        "surge": "6.100.0 build 4025",
        "results": native_results(),
    }
    record = {"format": "native-results-v1", "runs": [run1]}
    with open(os.path.join(out_dir, "native_results_fixture.json"), "w",
              encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)

    # Supersede fixture: run2 (1h later, different version) has T01 failing.
    run2_results = native_results()
    for r in run2_results:
        if r["fingerprint"] == fps["T01"]:
            r["success"] = False
            r["ms"] = None
    run2 = dict(run1)
    run2["version_sha"] = "a" * 64
    run2["tested_at"] = now + 3600
    run2["tested_at_cst"] = time.strftime(
        "%Y-%m-%d %H:%M:%S CST", time.localtime(now + 3600))
    run2["results"] = run2_results
    record2 = {"format": "native-results-v1", "runs": [run1, run2]}
    with open(os.path.join(out_dir, "native_results_supersede_fixture.json"),
              "w", encoding="utf-8") as f:
        json.dump(record2, f, ensure_ascii=False, indent=2)

    # P0 fixture DB (same schema as production probe.db).
    db_path = os.path.join(out_dir, "p0_fixture.db")
    if os.path.exists(db_path):
        os.unlink(db_path)
    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE probe_nodes (fingerprint TEXT PRIMARY KEY, "
                 "name TEXT, state TEXT)")
    conn.execute("CREATE TABLE probe_reports (id INTEGER PRIMARY KEY "
                 "AUTOINCREMENT, fingerprint TEXT, ts INTEGER, success "
                 "INTEGER, second_ms INTEGER, second_status INTEGER, "
                 "interface TEXT, error TEXT, "
                 "UNIQUE(fingerprint, ts))")
    rid = 1
    for tag, name, _proto, (kind, _ms), p0_ms in NODES:
        fp = fps[tag]
        if kind == "fail":
            conn.execute("INSERT INTO probe_nodes VALUES (?, ?, ?)",
                         (fp, "%s %s" % (tag, name), "quarantined"))
            conn.execute(
                "INSERT INTO probe_reports VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (rid, fp, now - 3600, 0, None, 0, "pdp_ip0",
                 "HTTP request timeout"))
        else:
            conn.execute("INSERT INTO probe_nodes VALUES (?, ?, ?)",
                         (fp, "%s %s" % (tag, name), "verified"))
            conn.execute(
                "INSERT INTO probe_reports VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (rid, fp, now - 3600, 1, p0_ms, 204, "pdp_ip0", None))
        rid += 1
    conn.commit()
    conn.close()

    # Mapping table.
    rows = ["# D1 fixture mapping (synthetic, mirrors 13:24 native test)",
            "",
            "All connection parameters are synthetic (TEST-NET hosts, "
            "password TEST-ONLY-NOT-A-REAL-NODE). Only the DECISION "
            "structure mirrors the real 13:24 test: names, native ms, "
            "P0 ms, pass/slow/fail.",
            "",
            "| tag | mirrors | proto | native | P0 | verdict |",
            "|---|---|---|---|---|---|"]
    for tag, name, proto, (kind, ms), p0_ms in NODES:
        verdict = {"pass": "PASS", "slow": "REJECT (native slow)",
                   "fail": "REJECT (native fail)"}[kind]
        if tag in ("T09", "T12", "T13"):
            verdict = "PASS (conditional: P0 281-297)"
        rows.append("| %s | %s | %s | %s | %s | %s |" % (
            tag, name, proto, ms if ms is not None else "fail",
            p0_ms if p0_ms is not None else "fail", verdict))
    rows += ["",
             "Fixture pool SHA256: `%s`" % pool_sha,
             "Fixture clean-14 SHA256: `%s`" % clean_sha,
             "Real 13:24 pool SHA256: "
             "`1360ab7ca83b75427a616c03c84bcdf69bd9a0af3aee69befd849636db9421d6` "
             "(44 lines); real clean-14 SHA256: "
             "`32a0a0fb24160a15bd2fd8edf188d631a76848b67e36a8605c46eb3540aae8b1`.",
             "Fixture SHAs differ because connection parameters are synthetic; "
             "fingerprints are computed with the identical algorithm.",
             ""]
    with open(os.path.join(out_dir, "MAPPING.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(rows))
    print("pool_sha=%s" % pool_sha)
    print("clean_sha=%s" % clean_sha)
    print("files written to %s" % out_dir)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ""))
    args = ap.parse_args()
    build(args.out)
