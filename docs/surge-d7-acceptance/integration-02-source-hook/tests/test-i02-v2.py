#!/usr/bin/env python3
"""Integration-02 v2 isolation tests (GPT 7121245603):
B10-EXTENSION retained + UUID format check; O1 expanded to the
protocol / transport / encryption support matrix; no_module
fail-closed form triggered in isolation.

Layout: runs the v1 suite (Parts 1-9) as subprocesses for regression,
then runs new Parts 10-13 inline. All samples are SYNTHETIC
(TEST-NET 203.0.113.0/24, synthetic passwords/uuids). No real
credentials, no real subscription lines, no real node identity.
No live files, no live DB (Part 13 uses a synthetic base dir only).

Exit 0 = every numbered check passed. Exit 1 = a check failed.
"""
import base64
import json
import os
import shutil
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
POOL = (os.path.join(HERE, "pool") if os.path.exists(os.path.join(HERE, "pool", "crawler.py"))
        else os.path.join(HERE, "..", "pool"))
sys.path.insert(0, HERE)
sys.path.insert(0, POOL)
sys.path.insert(0, os.path.dirname(os.path.abspath(POOL)))
from pool.crawler import crawl_records, parse_record  # noqa: E402
from pool.rules import build_surge_line, is_valid_uuid, pre_filter  # noqa: E402
from pool.cli import surge_line_to_record  # noqa: E402
from pool.tester import _filter_reason, build_config  # noqa: E402
from pool import source_lineage as sl  # noqa: E402
from pool import lineage_adapter as la  # noqa: E402

KEY = b"i02-v2-test-key-do-not-use-in-production"
NOW = 1795498000  # fixed synthetic "now" (2026-11-24 ~12:30 CST)
WORK = os.path.join(HERE, "v2-work")
os.makedirs(WORK, exist_ok=True)
PRIVATE = set()

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


def vmess_rec(host, net="ws", tls="tls", scy="auto",
              uuid="11111111-2222-3333-4444-555555555555"):
    return {"protocol": "vmess", "host": host, "port": 443, "source": "syn-a",
            "name_hint": "", "uuid": uuid, "security": scy, "net": net,
            "tls": (tls in ("tls", True)), "ws_path": "/",
            "ws_host": None, "sni": None, "skip_verify": False}


def trojan_rec(host, t_type="tcp", pw="syn-pw-v2"):
    return {"protocol": "trojan", "host": host, "port": 443, "source": "syn-a",
            "name_hint": "", "password": pw, "t_type": t_type, "sni": None,
            "ws": t_type == "ws", "ws_path": "/",
            "ws_host": None, "skip_verify": False}


def ss_rec(host, method="aes-256-gcm", pw="syn-pw-v2", plugin=None):
    return {"protocol": "ss", "host": host, "port": 8388, "source": "syn-a",
            "name_hint": "", "method": method, "password": pw,
            "plugin": plugin}


def run_script(path, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    r = subprocess.run([sys.executable, path], capture_output=True,
                       text=True, timeout=300, env=env)
    return r


# ===========================================================================
# Regression: v1 Parts 1-9 as subprocesses (must stay green)
# ===========================================================================
print("=== v2 regression: v1 Parts 1-9 ===")
# Rollback re-runs against the FRESH v2 snapshot (12:36 CST, 7798 nodes),
# not the v1 snapshot -- same assertions, current data.
FRESH_SNAP = os.path.join(
    os.path.dirname(os.path.dirname(HERE)), "work", "pool-snapshot-v2.db")
assert os.path.exists(FRESH_SNAP), FRESH_SNAP
for script, label, env_extra in (
        ("test-i02-source-hook.py", "Parts 1-7 (updated Part 4/5)", None),
        ("test-i02-rollback.py", "Part 8 (rollback, fresh snapshot)",
         {"I02_POOL_SNAPSHOT": FRESH_SNAP}),
        ("test-i02-perf.py", "Part 9 (perf)", None)):
    r = run_script(os.path.join(HERE, script), env_extra=env_extra)
    tail = (r.stdout.strip().splitlines() or [""]) [-1]
    check(f"REG-{label}", r.returncode == 0, f"rc={r.returncode} :: {tail}")
    if r.returncode != 0:
        print(r.stdout[-2000:])
        print(r.stderr[-2000:])

# ===========================================================================
# Part 10: UUID format matrix (B10-EXTENSION v2)
# ===========================================================================
print("=== Part 10: UUID format matrix ===")
VALID_UUIDS = [
    "11111111-2222-3333-4444-555555555555",
    "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
    "aAbB1234-5678-90aB-cDeF-0123456789ab",
    "00000000-0000-0000-0000-000000000000",
    "ffffffff-ffff-ffff-ffff-ffffffffffff",
]
for u in VALID_UUIDS:
    check(f"P10-uuid-valid-{u[:8]}", is_valid_uuid(u) is True)
    rec = dict(vmess_rec("203.0.113.160", "ws"), uuid=u,
               host="u.example.invalid")
    check(f"P10-uuid-valid-prefilter-{u[:8]}",
          pre_filter(rec, PRIVATE) == (True, ""))
INVALID_UUIDS = [
    ("", "empty-string"),
    ("not-a-uuid", "not-uuid"),
    ("11111111-2222-3333-4444-55555555555", "short-last-group"),
    ("11111111-2222-3333-4444-5555555555555", "long-last-group"),
    ("11111111-2222-3333-4444555555555555", "missing-dash"),
    ("11111111-2222-3333-4444-55555555555g", "non-hex"),
    ("11111111-2222-3333-4444", "too-short"),
    ("11111111-2222-3333-4444-555555555555-extra", "extra-group"),
    ("11111111_2222_3333_4444_555555555555", "underscores"),
    (" 11111111-2222-3333-4444-555555555555", "leading-space"),
    ("11111111-2222-3333-4444-555555555555 ", "trailing-space"),
    ("11111111222233334444555555555555", "no-dashes"),
    ("{11111111-2222-3333-4444-555555555555}", "braces"),
]
for u, why in INVALID_UUIDS:
    check(f"P10-uuid-invalid-{why}", is_valid_uuid(u) is False)
    rec = dict(vmess_rec("203.0.113.161", "ws"), uuid=u,
               host="u.example.invalid")
    if u == "":
        check(f"P10-uuid-invalid-prefilter-{why}",
              pre_filter(rec, PRIVATE) == (False, "missing-uuid"),
              "empty uuid is missing-uuid, not invalid-uuid")
    else:
        check(f"P10-uuid-invalid-prefilter-{why}",
              pre_filter(rec, PRIVATE) == (False, "invalid-uuid"),
              f"{pre_filter(rec, PRIVATE)}")
        try:
            build_surge_line(rec, "X")
            check(f"P10-uuid-invalid-build-{why}", False, "no error raised")
        except ValueError:
            check(f"P10-uuid-invalid-build-{why}", True)
# Non-string uuid input never reaches pre_filter (parse_record coerces
# to str), but is_valid_uuid must not raise on it.
check("P10-uuid-nonstring", is_valid_uuid(None) is False
      and is_valid_uuid(12345) is False)
# The format check is shape-only: version/variant nibbles are NOT policed.
check("P10-uuid-shape-only-version-nibble",
      is_valid_uuid("11111111-2222-9999-4444-555555555555") is True)
check("P10-uuid-shape-only-variant-nibble",
      is_valid_uuid("11111111-2222-3333-0999-555555555555") is True)

# ===========================================================================
# Part 11: support matrix completeness (gate vs SUPPORT_MATRIX, row by row)
# ===========================================================================
print("=== Part 11: support matrix completeness ===")
MATRIX_CASES = [
    # (label, record, expected gate result)
    ("vmess tcp auto tls", vmess_rec("203.0.113.170", "tcp"), (True, "", "")),
    ("vmess ws auto tls", vmess_rec("203.0.113.171", "ws"), (True, "", "")),
    ("vmess empty-net auto tls", vmess_rec("203.0.113.172", ""),
     (True, "", "")),
    ("vmess tcp aes-128-gcm tls",
     vmess_rec("203.0.113.173", "tcp", scy="aes-128-gcm"), (True, "", "")),
    ("vmess ws chacha20-poly1305 tls",
     vmess_rec("203.0.113.174", "ws", scy="chacha20-poly1305"), (True, "", "")),
    ("vmess tcp none tls",
     vmess_rec("203.0.113.175", "tcp", scy="none"), (True, "", "")),
    ("vmess net grpc", vmess_rec("203.0.113.176", "grpc"),
     (False, "unsupported-transport", "grpc")),
    ("vmess net raw", vmess_rec("203.0.113.177", "raw"),
     (False, "unsupported-transport", "raw")),
    ("vmess net http", vmess_rec("203.0.113.178", "http"),
     (False, "unsupported-transport", "http")),
    ("vmess net xhttp", vmess_rec("203.0.113.179", "xhttp"),
     (False, "unsupported-transport", "xhttp")),
    ("vmess net h2", vmess_rec("203.0.113.180", "h2"),
     (False, "unsupported-transport", "h2")),
    ("vmess net none", vmess_rec("203.0.113.181", "none"),
     (False, "unsupported-transport", "none")),
    ("vmess net tcp,udp", vmess_rec("203.0.113.182", "tcp,udp"),
     (False, "unsupported-transport", "tcp,udp")),
    ("vmess net malformed", vmess_rec("203.0.113.183", "tcp#frag@junk"),
     (False, "unsupported-transport", "tcp#frag@junk")),
    ("vmess no TLS", vmess_rec("203.0.113.184", "tcp", tls=""),
     (False, "vmess-non-tls", "")),
    ("vmess security aes-256-gcm",
     vmess_rec("203.0.113.185", "ws", scy="aes-256-gcm"),
     (False, "unsupported-security", "aes-256-gcm")),
    ("vmess security zero",
     vmess_rec("203.0.113.186", "ws", scy="zero"),
     (False, "unsupported-security", "zero")),
    ("vmess security AES-128-GCM uppercase",
     vmess_rec("203.0.113.187", "ws", scy="AES-128-GCM"),
     (False, "unsupported-security", "AES-128-GCM")),
    ("vmess uuid missing",
     dict(vmess_rec("203.0.113.188", "ws"), uuid=""),
     (False, "missing-uuid", "")),
    ("trojan tcp", trojan_rec("203.0.113.190", "tcp"), (True, "", "")),
    ("trojan ws", trojan_rec("203.0.113.191", "ws"), (True, "", "")),
    ("trojan empty t_type", trojan_rec("203.0.113.192", ""),
     (True, "", "")),
    ("trojan grpc", trojan_rec("203.0.113.193", "grpc"),
     (False, "unsupported-transport", "grpc")),
    ("trojan t_type h2", trojan_rec("203.0.113.194", "h2"),
     (False, "unsupported-transport", "h2")),
    ("trojan password missing",
     trojan_rec("203.0.113.195", "tcp", pw=""), (False, "missing-password", "")),
    ("ss aes-256-gcm", ss_rec("203.0.113.200"), (True, "", "")),
    ("ss aes-128-gcm", ss_rec("203.0.113.201", method="aes-128-gcm"),
     (True, "", "")),
    ("ss chacha20-ietf-poly1305",
     ss_rec("203.0.113.202", method="chacha20-ietf-poly1305"), (True, "", "")),
    ("ss rc4-md5", ss_rec("203.0.113.203", method="rc4-md5"),
     (False, "ss-method", "rc4-md5")),
    ("ss aes-128-cfb", ss_rec("203.0.113.204", method="aes-128-cfb"),
     (False, "ss-method", "aes-128-cfb")),
    ("ss plain", ss_rec("203.0.113.205", method="plain"),
     (False, "ss-method", "plain")),
    ("ss unknown method", ss_rec("203.0.113.206", method="made-up-method"),
     (False, "ss-method", "made-up-method")),
    ("ss plugin present",
     ss_rec("203.0.113.207", plugin="v2ray-plugin;tls;host=example.com"),
     (False, "ss-plugin", "present")),
    ("ss password missing",
     ss_rec("203.0.113.208", pw=""), (False, "missing-password", "")),
    ("unknown protocol vless",
     {"protocol": "vless", "host": "203.0.113.209", "port": 443},
     (False, "unknown-protocol", "vless")),
    ("unknown protocol hysteria2",
     {"protocol": "hysteria2", "host": "203.0.113.210", "port": 443},
     (False, "unknown-protocol", "hysteria2")),
    ("unknown protocol empty",
     {"protocol": "", "host": "203.0.113.211", "port": 443},
     (False, "unknown-protocol", "")),
]
for label, rec, expected in MATRIX_CASES:
    got = la.admission_gate(rec)
    check(f"P11-matrix-{label}", got == expected, f"got={got}")
# Precedence (multi-defect records): the gate mirrors live pre_filter's
# order (tls before net before uuid), so the first reason agrees.
check("P11-precedence-tls-beats-net",
      la.admission_gate(dict(vmess_rec("203.0.113.212", "grpc"), tls=False))
      == (False, "vmess-non-tls", ""))
check("P11-precedence-net-beats-uuid",
      la.admission_gate(dict(vmess_rec("203.0.113.213", "grpc"),
                             uuid="not-a-uuid"))
      == (False, "unsupported-transport", "grpc"))
check("P11-precedence-tls-beats-uuid",
      la.admission_gate(dict(vmess_rec("203.0.113.214", "ws"),
                             uuid="not-a-uuid", tls=False))
      == (False, "vmess-non-tls", ""))
# B10 does not gate lineage: a malformed (but present) uuid is NOT a
# gate reason -- the gate passes it to the security check, which is
# the first gate leg that fails here.
check("P11-precedence-uuid-format-not-a-gate-reason",
      la.admission_gate(dict(vmess_rec("203.0.113.215", "ws"),
                             uuid="not-a-uuid", security="aes-256-gcm"))
      == (False, "unsupported-security", "aes-256-gcm"))
check("P11-precedence-malformed-uuid-admitted-when-clean",
      la.admission_gate(dict(vmess_rec("203.0.113.216", "ws"),
                             uuid="not-a-uuid"))
      == (True, "", ""))
# Matrix documentation completeness: 16 rows; every row's reason is in
# GATE_REASONS (or "" when admitted); every GATE_REASONS member appears.
check("P11-matrix-row-count", len(la.SUPPORT_MATRIX) == 16,
      f"rows={len(la.SUPPORT_MATRIX)}")
row_reasons = {r["reason"] for r in la.SUPPORT_MATRIX if r["reason"]}
check("P11-matrix-reasons-known",
      row_reasons <= set(la.GATE_REASONS), f"{row_reasons}")
check("P11-matrix-reasons-complete",
      row_reasons == set(la.GATE_REASONS),
      f"missing={set(la.GATE_REASONS) - row_reasons}")
check("P11-matrix-admitted-rows-have-no-reason",
      all(r["reason"] == "" for r in la.SUPPORT_MATRIX if r["admitted"]))
check("P11-matrix-rejected-rows-have-reason",
      all(r["reason"] != "" for r in la.SUPPORT_MATRIX if not r["admitted"]))

# ===========================================================================
# Part 12: round-trip negatives (where exactly the chain breaks)
# ===========================================================================
print("=== Part 12: round-trip negatives ===")


def roundtrip_fps(rec):
    """(fp_parsed, fp_after_surge_line_or_None, build_error_or_None)."""
    ca = la.canonical_config(rec)
    fp_a = sl.config_fingerprint(ca, KEY)
    try:
        line = build_surge_line(rec, "合成-1")
    except ValueError as e:
        return (fp_a, None, str(e))
    rec_b = surge_line_to_record(line)
    assert rec_b is not None
    fp_b = sl.config_fingerprint(la.canonical_config(rec_b), KEY)
    return (fp_a, fp_b, None)


# Trojan grpc: the Surge line drops t_type; round-trip returns tcp.
rec = trojan_rec("203.0.113.220", "grpc")
fp_a, fp_b, err = roundtrip_fps(rec)
check("P12-trojan-grpc-roundtrip-loses-transport",
      err is None and fp_a != fp_b, "grpc must not survive the Surge line")
check("P12-trojan-grpc-tester-refuses",
      _filter_reason(rec) == "unsupported-transport")
check("P12-trojan-grpc-prefilter-refuses",
      pre_filter(dict(rec, host="grpc.example.invalid"), PRIVATE)
      == (False, "unsupported-transport"))
# Vmess grpc / httpupgrade: same loss (net falls back to tcp).
for net in ("grpc", "httpupgrade"):
    rec = vmess_rec("203.0.113.221", net)
    fp_a, fp_b, err = roundtrip_fps(rec)
    check(f"P12-vmess-{net}-roundtrip-loses-net",
          err is None and fp_a != fp_b, f"net={net}")
    check(f"P12-vmess-{net}-tester-refuses",
          _filter_reason(rec) == "unsupported-transport")
# Vmess security aes-128-gcm: round-trip diverges ONLY on security
# (D2-accepted); the tester preserves it (no fold).
rec = vmess_rec("203.0.113.222", "ws", scy="aes-128-gcm")
fp_a, fp_b, err = roundtrip_fps(rec)
ca = la.canonical_config(rec)
line = build_surge_line(rec, "合成-1")
cb = la.canonical_config(surge_line_to_record(line))
check("P12-vmess-security-roundtrip-diverges",
      err is None and fp_a != fp_b)
check("P12-vmess-security-only-security-differs",
      {k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k)} == {"security"})
check("P12-vmess-security-tester-preserves",
      build_config(rec)["outbounds"][0]["security"] == "aes-128-gcm")
# Vmess security unknown / uppercase: the tester folds to auto (lossy).
for sec in ("aes-256-gcm", "AES-128-GCM", "zero"):
    rec = vmess_rec("203.0.113.223", "ws", scy=sec)
    check(f"P12-vmess-security-{sec}-tester-folds-to-auto",
          build_config(rec)["outbounds"][0]["security"] == "auto")
    check(f"P12-vmess-security-{sec}-gate-refuses",
          la.admission_gate(rec) == (False, "unsupported-security", sec))
# SS non-AEAD: the Surge line CAN carry the method losslessly in text
# (round-trip fingerprints MATCH) -- the break is at the tester, which
# refuses to verify it. Judged by the chain, not by the name.
rec = ss_rec("203.0.113.224", method="rc4-md5")
fp_a, fp_b, err = roundtrip_fps(rec)
check("P12-ss-nonaead-roundtrip-text-lossless",
      err is None and fp_a == fp_b,
      "the line carries encrypt-method; the tester is the breaking leg")
check("P12-ss-nonaead-tester-refuses",
      _filter_reason(rec) == "ss-method")
check("P12-ss-nonaead-prefilter-refuses",
      pre_filter(dict(rec, host="rc4.example.invalid"), PRIVATE)
      == (False, "ss-method"))
# SS plugin: the line drops the plugin (lossy); tester refuses too.
rec = ss_rec("203.0.113.225", plugin="v2ray-plugin;tls;host=example.com")
fp_a, fp_b, err = roundtrip_fps(rec)
check("P12-ss-plugin-roundtrip-loses-plugin",
      err is None and fp_a != fp_b)
check("P12-ss-plugin-tester-refuses",
      _filter_reason(rec) == "ss-plugin")
# Vmess no-TLS: the Surge line expresses it (round-trip MATCHES) -- the
# break is at the tester, which refuses to verify it.
rec = vmess_rec("203.0.113.226", "tcp", tls="")
fp_a, fp_b, err = roundtrip_fps(rec)
check("P12-vmess-nontls-roundtrip-matches",
      err is None and fp_a == fp_b,
      "Surge expresses plain vmess; the tester is the breaking leg")
check("P12-vmess-nontls-tester-refuses",
      _filter_reason(rec) == "vmess-non-tls")
# Positive controls: supported combos round-trip cleanly.
for label, rec in (
        ("trojan ws", trojan_rec("203.0.113.227", "ws")),
        ("vmess ws auto tls", vmess_rec("203.0.113.228", "ws")),
        ("ss aes-256-gcm", ss_rec("203.0.113.229"))):
    fp_a, fp_b, err = roundtrip_fps(rec)
    check(f"P12-roundtrip-clean-{label}", err is None and fp_a == fp_b)

# ===========================================================================
# Part 13: no_module fail-closed form, triggered in isolation
# ===========================================================================
print("=== Part 13: no_module triggered in isolation ===")
NM_POOL = os.path.join(WORK, "nomodule", "pool")
NM_BASE = os.path.join(WORK, "nomodule-base")
shutil.rmtree(os.path.join(WORK, "nomodule"), ignore_errors=True)
shutil.rmtree(NM_BASE, ignore_errors=True)
shutil.copytree(POOL, NM_POOL)
os.remove(os.path.join(NM_POOL, "lineage_adapter.py"))
assert not os.path.exists(os.path.join(NM_POOL, "lineage_adapter.py"))
# Synthetic base: the same 4 synthetic sources as the v1 Part 2 set.
NM_SRC = {
    "syn-a": [
        "trojan://syn-pw-a1@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1",
        "trojan://syn-pw-a2@203.0.113.102:443?sni=cdn.example.com#n2",
        "vmess://" + base64.b64encode(json.dumps(
            {"v": "2", "ps": "syn", "add": "203.0.113.103", "port": 443,
             "id": "aaaaaaaa-1111-2222-3333-444444444444", "aid": "0",
             "scy": "auto", "net": "ws", "tls": "tls"},
            separators=(",", ":")).encode()).decode(),
    ],
    "syn-b": [
        "trojan://syn-pw-b1@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1-mirror",
        "trojan://syn-pw-b2@203.0.113.104:443?sni=cdn.example.com#n4",
        "ss://YWVzLTI1Ni1nY206c3luLXB3LWI1@203.0.113.105:8388#n5",
    ],
    "syn-c": [
        "vmess://" + base64.b64encode(json.dumps(
            {"v": "2", "ps": "syn", "add": "203.0.113.103", "port": 443,
             "id": "aaaaaaaa-1111-2222-3333-444444444444", "aid": "0",
             "scy": "auto", "net": "ws", "tls": "tls"},
            separators=(",", ":")).encode()).decode(),
        "trojan://syn-pw-c1@203.0.113.106:443?sni=cdn.example.com#n6",
        "trojan://syn-pw-c2@203.0.113.107:443?sni=cdn.example.com#n7",
    ],
    "syn-d": [
        "trojan://syn-pw-a1@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1",
        "vmess://" + base64.b64encode(json.dumps(
            {"v": "2", "ps": "syn", "add": "203.0.113.103", "port": 443,
             "id": "aaaaaaaa-1111-2222-3333-444444444444", "aid": "0",
             "scy": "auto", "net": "ws", "tls": "tls"},
            separators=(",", ":")).encode()).decode(),
    ],
}
NM_SRC["syn-c"].append(
    "trojan://syn-pw-OTHER@203.0.113.101:443?sni=cdn.example.com&type=ws&path=%2Fws#n1-altpw")
os.makedirs(os.path.join(NM_BASE, "data"), exist_ok=True)
for name, lines in NM_SRC.items():
    with open(os.path.join(NM_BASE, f"{name}.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
with open(os.path.join(NM_BASE, "sources.yaml"), "w") as f:
    for name in NM_SRC:
        f.write(f"- name: {name}\n")
        f.write(f"  url: file://{NM_BASE}/{name}.txt\n")
        f.write("  protocols: [trojan, vmess, ss]\n")
with open(os.path.join(NM_BASE, "source_groups.json"), "w") as f:
    json.dump({"groups": {"g-a": ["syn-a", "syn-d"], "g-b": ["syn-b"],
                          "g-c": ["syn-c"]},
               "paused": []}, f)
env_nm = dict(os.environ, PYTHONPATH=os.path.join(WORK, "nomodule"),
              POOL_LINEAGE_HMAC_KEY="i02-v2-nomodule-key")
r = subprocess.run([sys.executable, "-m", "pool.cli", "crawl"], cwd=NM_BASE,
                   env=env_nm, capture_output=True, text=True, timeout=120)
try:
    out_nm = json.loads(r.stdout) if r.stdout.strip() else {}
except Exception:
    out_nm = {"_raw": r.stdout, "_stderr": r.stderr}
check("P13-nomodule-lineage-disabled",
      out_nm.get("lineage", {}).get("reason") == "no_module",
      f"{out_nm.get('lineage')}")
check("P13-nomodule-crawl-succeeds", r.returncode == 0
      and out_nm.get("unique") == 7,
      f"rc={r.returncode} unique={out_nm.get('unique')}")
check("P13-nomodule-key-present-but-irrelevant",
      "i02-v2-nomodule-key" not in json.dumps(out_nm),
      "the key must never appear in crawl output")
conn_nm = sqlite3.connect(os.path.join(NM_BASE, "data", "pool.db"))
check("P13-nomodule-nodes-7",
      conn_nm.execute("SELECT COUNT(*) FROM nodes").fetchone()[0] == 7)
check("P13-nomodule-no-lineage-tables",
      conn_nm.execute(
          "SELECT COUNT(*) FROM sqlite_master"
          " WHERE name IN ('node_variants', 'node_sources',"
          " 'sighting_events')").fetchone()[0] == 0)
check("P13-nomodule-run-logged",
      conn_nm.execute(
          "SELECT COUNT(*) FROM runs WHERE kind='crawl'").fetchone()[0] >= 1)
conn_nm.close()

if FAILED:
    print(f"\nFAILED CHECKS ({len(FAILED)}): {FAILED}")
    sys.exit(1)
print(f"\nV2 PARTS 10-13 DONE: {len(PASSED)} passed, 0 failed")
