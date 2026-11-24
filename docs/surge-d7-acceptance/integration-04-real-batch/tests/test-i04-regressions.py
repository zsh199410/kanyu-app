#!/usr/bin/env python3
"""Integration-04 regression runner: v1/v2 baselines + merged layout.

Runs, in order:
  B1  #126 v2 suite in its own package (baseline, expect 67/67)
  B2  #127 v2 suite files in their own package (baseline, expect 152 + 133)
  B3  #128 v2 suite files in their own package (baseline, expect 81 + 155)
  N   the new #04 suite in the merged layout (expect 157/157)
  M1  #126 v2 suite against the MERGED layout (I01_SRC = #04 pr-source)
  M2  #127 v2 suite files copied into the merged layout's tests/
  M3  #128 v2 suite files copied into the merged layout's tests/

Superseded assertions (patched ONLY in scratch copies, never in the
original suite files):
  * #126 A18a: "-> READY" -> "-> PHONE_EVIDENCE_READY" (Review 6034204978
    point 1 renamed the verdict; the old token must not appear).
  * #128 K7 first half: the merged rules.py INTENTIONALLY contains both
    the N3 strict check AND #127's comma-uuid (documented merge, not an
    overwrite). The scratch copy asserts both are present.
  * #127 P1 no-SNI vmess (V2/V3/V4/V5): with #128 N3 merged into
    build_surge_line, vmess+tls nodes with an IP dial host and no SNI
    are BUILD_REFUSED (vmess-no-sni) -- N3 has no net condition (#128's
    own K4 asserts the refusal with default net=tcp). The canonical
    round-trip / divergence comparisons can no longer run on these
    nodes. The scratch copy asserts the refusals instead and drops
    V2/V5 from the expected-consistent list; D2 (security is not
    normalized) is covered by the #04 N-section tests (N3.8/N4.6/N6.5),
    and the V4 prefilter/gate refusal checks are untouched (they pass).
  * #127 P12 grpc/httpupgrade round-trip: same N3 refusal at build
    (verified: build raises vmess-no-sni; pre_filter/tester still
    refuse the transport). The scratch copy asserts the refusal
    instead of the net loss. The P12 security round-trip keeps its D2
    substance by adding an SNI so the node builds (verified:
    canonical diff is still exactly {"security"}); the clean vmess
    positive control gets the same SNI treatment (verified: fingerprints
    still match after the round-trip).
  * #128 Part L: the suite applies pool-db-source.patch from the package
    root and reads the production chain from WORK/prod-chain; neither
    exists in the #04 package. The runner stages both in for the M3 run
    and removes the patch file afterwards (fixtures, not #04 files).
  * #128 Part I harness: the merged rules.py/tester.py import the new
    normalize module, which the suite's fixed harness copy list omits.
    The scratch copy adds "normalize.py" to that list (same pattern as
    the M1 phone_evidence.py seed); the original suite file is untouched.
Any other failure in M1/M2/M3 is a real regression.

Merged-layout staging:
  * M1 seeds phone_evidence.py into the #126 ISO dir before running
    (the suite's fixed copy list does not include it; without the seed
    auto_prune falls back to pre-#04 G10 behaviour instead of crashing).
  * M2/M3 stage the suite files into the merged layout's tests/ and
    remove them (plus their generated work dirs) afterwards.
  * M2 also copies the #127 v2 snapshot fixture into the merged work/
    (pool-snapshot-v2.db) so the staged v2 test's relative FRESH_SNAP
    resolves; rollback runs get I02_POOL_SNAPSHOT explicitly (the suite
    default ~/workspace/... does not exist on the VPS, HOME=/root).
  * M3 needs the #128 work fixtures in the merged layout's work/
    (pool-snapshot.db, crawl fixture, live/, cli-patched.py) -- copied
    once from the #128 v2 package; they are test inputs, not PR files.
Exit 0 iff every run passes.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

WS = Path(os.environ.get(
    "I04_WS", os.path.expanduser("~/workspace/tester-diag-pr")))
I04 = WS / "pr128-integration-04" / "pr-source"
I01V2 = WS / "pr126-integration-01-v2" / "pr-source"
I01V1 = WS / "pr126-integration-01" / "pr-source"
I02V2 = WS / "pr127-integration-02-v2" / "pr-source"
I03V2 = WS / "pr128-integration-03-v2" / "pr-source"
I04_WORK = WS / "pr128-integration-04" / "work"
I03_WORK = WS / "pr128-integration-03-v2" / "work"
I02V2_WORK = WS / "pr127-integration-02-v2" / "work"
I02V1_WORK = WS / "pr127-integration-02" / "work"
I02_SNAP = I02V1_WORK / "pool-snapshot.db"
# VPS /tmp is a 484M tmpfs and was already full from other rounds' leftovers
# (2026-11-24): route all tempfile traffic to the big disk. The #126 suite's
# fixed ISO path (/tmp/i01v2-isolation, ~1.2M) still needs a little /tmp free;
# free it by deleting this round's own /tmp leftovers only, never others'.
TMP = WS / "pr128-integration-04" / "tmp"
ISO126 = Path("/tmp/i01v2-isolation")
SCRATCH = TMP / "scratch"

RESULTS = []

BASE_ENV = {"TMPDIR": str(TMP)}


def run(name, cmd, cwd, env_extra=None, timeout=900):
    env = dict(os.environ)
    env.update(BASE_ENV)
    if env_extra:
        env.update(env_extra)
    print("=" * 70)
    print("RUN:", name)
    print("  cmd:", " ".join(str(c) for c in cmd))
    print("  cwd:", cwd)
    try:
        proc = subprocess.run(cmd, cwd=str(cwd), env=env,
                              capture_output=True, text=True, timeout=timeout)
        out = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired:
        print("  TIMEOUT after %ss" % timeout)
        RESULTS.append((name, False, "timeout"))
        return
    tail = "\n".join(out.strip().splitlines()[-6:])
    print("  rc=%d" % proc.returncode)
    for line in tail.splitlines():
        print("   |", line[:200])
    ok = proc.returncode == 0
    RESULTS.append((name, ok, "rc=%d" % proc.returncode))


def parse_total(out, pattern):
    m = re.search(pattern, out)
    return m.group(0) if m else None


def main():
    TMP.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)

    # ---- Baselines (own packages) ----
    # NOTE: the suites' ~/workspace defaults do not exist on the VPS
    # (HOME=/root); pass the VPS paths explicitly. TMPDIR routes tempfile
    # off the full 484M /tmp tmpfs onto the big disk.
    run("B1 #126 v2 baseline (own package)",
        [sys.executable, str(I01V2 / "test-i01-control-v2.py")], I01V2,
        env_extra={"I01_SRC": str(I01V2), "I01_V1_SRC": str(I01V1)},
        timeout=1200)
    for f in ("test-i02-source-hook.py", "test-i02-v2.py",
              "test-i02-rollback.py", "test-i02-perf.py"):
        extra = ({"I02_POOL_SNAPSHOT": str(I02_SNAP)}
                 if f == "test-i02-rollback.py" else None)
        run("B2 #127 v2 baseline %s" % f,
            [sys.executable, str(I02V2 / "tests" / f)], I02V2 / "tests",
            env_extra=extra, timeout=900)
    for f in ("test_integration_03.py", "test_integration_03_v2.py"):
        run("B3 #128 v2 baseline %s" % f,
            [sys.executable, str(I03V2 / "tests" / f)], I03V2 / "tests",
            timeout=900)

    # ---- New #04 suite (merged layout) ----
    run("N #04 new suite (merged layout)",
        [sys.executable, str(I04 / "tests" / "test_integration_04.py")], I04,
        timeout=900)

    # ---- M1: #126 v2 suite against the merged layout ----
    try:
        scratch126 = SCRATCH / "test-i01-control-v2.py"
        text = (I01V2 / "test-i01-control-v2.py").read_text(encoding="utf-8")
        old_a18a = '"-> READY" in out.stdout'
        assert text.count(old_a18a) == 1, "A18a assertion not found exactly once"
        text = text.replace(old_a18a, '"-> PHONE_EVIDENCE_READY" in out.stdout')
        scratch126.write_text(text, encoding="utf-8")
        if ISO126.exists():
            shutil.rmtree(ISO126)
        ISO126.mkdir(parents=True)
        # Seed the classifier: the suite's fixed copy list omits it.
        shutil.copy2(I04 / "phone_evidence.py", ISO126 / "phone_evidence.py")
        run("M1 #126 v2 merged layout (A18a patched in scratch copy only)",
            [sys.executable, str(scratch126)], SCRATCH,
            env_extra={"I01_SRC": str(I04), "I01_V1_SRC": str(I01V1)},
            timeout=1200)
    except Exception as exc:  # setup failure must not kill the whole run
        print("M1 SETUP FAILED:", repr(exc))
        RESULTS.append(("M1 #126 v2 merged layout (setup)", False, repr(exc)))

    # ---- M2: #127 v2 suite files staged into the merged layout ----
    # The staged v2 test resolves its fresh snapshot relative to the merged
    # work dir (I04/work/pool-snapshot-v2.db); copy the #127 v2 fixture in.
    snap_v2_src = I02V2_WORK / "pool-snapshot-v2.db"
    snap_v2_dst = I04_WORK / "pool-snapshot-v2.db"
    if not snap_v2_dst.exists():
        shutil.copy2(snap_v2_src, snap_v2_dst)
    staged127 = []
    try:
        for f in ("test-i02-source-hook.py", "test-i02-v2.py",
                  "test-i02-rollback.py", "test-i02-perf.py"):
            dst = I04 / "tests" / f
            text = (I02V2 / "tests" / f).read_text(encoding="utf-8")
            if f == "test-i02-source-hook.py":
                old_list = (
                    '# Expected consistent (canonical match): T1-T4, V1, V2, V5,'
                    ' V6, S1, S3, S5.\n'
                    'for lbl in ["T1 trojan ws+sni+path+host", "T2 trojan tcp plain",\n'
                    '            "T3 trojan sni via peer", "T4 trojan path set but no ws",\n'
                    '            "V1 vmess ws+tls+sni+path+host", "V2 vmess tcp+tls",\n'
                    '            "V5 vmess net=tcp but path+host set", "V6 vmess tls=false tcp",\n')
                assert text.count(old_list) == 1, "P1 consistent list not found exactly once"
                text = text.replace(old_list,
                    '# Expected consistent (canonical match): T1-T4, V1, V6, S1, S3, S5.\n'
                    '# (i04-superseded: V2/V5 are BUILD_REFUSED by merged N3.)\n'
                    'for lbl in ["T1 trojan ws+sni+path+host", "T2 trojan tcp plain",\n'
                    '            "T3 trojan sni via peer", "T4 trojan path set but no ws",\n'
                    '            "V1 vmess ws+tls+sni+path+host", "V6 vmess tls=false tcp",\n')
                old_t6 = (
                    'check("P1-T6-refused", results["T6 trojan password with %2C%20"]'
                    '[0] == "BUILD_REFUSED")\n')
                assert text.count(old_t6) == 1, "P1-T6 line not found exactly once"
                text = text.replace(old_t6, old_t6 +
                    '# V2/V5: i04-superseded -- vmess+tls with an IP dial host\n'
                    '# and no SNI is BUILD_REFUSED by merged N3 (same as V3).\n'
                    'for _lbl in ("V2 vmess tcp+tls",\n'
                    '             "V5 vmess net=tcp but path+host set"):\n'
                    '    _st = results[_lbl]\n'
                    '    check(f"P1-{_lbl.split()[0]}-N3-refuses-no-sni",\n'
                    '          _st[0] == "BUILD_REFUSED"\n'
                    '          and "vmess-no-sni" in _st[1], f"st={_st}")\n')
                old_v3 = (
                    '# V3: D2 -- canonical mismatch, and the ONLY differing'
                    ' canonical field is security.\n'
                    'st = results["V3 vmess scy=aes-128-gcm"]\n'
                    'check("P1-V3-D2-diverges", st[0] == "OK" and st[2] is False,'
                    ' f"canon_match={st[2]}")\n'
                    'ca, cb = st[4], st[5]\n'
                    'check("P1-V3-only-security-differs",\n'
                    '      {k for k in set(ca) | set(cb) if ca.get(k) != cb.get(k)}'
                    ' == {"security"},\n'
                    '      f"diff_keys={[k for k in set(ca)|set(cb)'
                    ' if ca.get(k)!=cb.get(k)]}")\n')
                assert text.count(old_v3) == 1, "P1-V3 block not found exactly once"
                text = text.replace(old_v3,
                    '# V3: i04-superseded -- with #128 N3 merged into\n'
                    '# build_surge_line, a vmess+tls node with an IP dial host\n'
                    '# and no SNI is BUILD_REFUSED (vmess-no-sni); the D2\n'
                    '# canonical-divergence comparison can no longer run on\n'
                    '# this node. D2 is covered by the #04 N-section tests.\n'
                    'st = results["V3 vmess scy=aes-128-gcm"]\n'
                    'check("P1-V3-N3-refuses-no-sni", st[0] == "BUILD_REFUSED"\n'
                    '      and "vmess-no-sni" in st[1], f"st={st}")\n')
                old_v4 = (
                    'check("P1-V4-diverges", st[0] == "OK" and st[2] is False)\n')
                assert text.count(old_v4) == 1, "P1-V4 line not found exactly once"
                text = text.replace(old_v4,
                    '# P1-V4-diverges is i04-superseded (same N3 refusal as V3).\n'
                    'check("P1-V4-N3-refuses-no-sni", st[0] == "BUILD_REFUSED"\n'
                    '      and "vmess-no-sni" in st[1], f"st={st}")\n')
            if f == "test-i02-v2.py":
                # P12 grpc/httpupgrade round-trip: N3 refuses the node at
                # build before the net loss can happen (verified: build
                # raises vmess-no-sni; pre_filter/tester still refuse the
                # transport). The security round-trip keeps its D2 substance
                # by adding an SNI so the node builds (verified: canonical
                # diff is still exactly {"security"}).
                old_p12 = (
                    '    check(f"P12-vmess-{net}-roundtrip-loses-net",\n'
                    '          err is None and fp_a != fp_b, f"net={net}")\n')
                assert text.count(old_p12) == 1, "P12 grpc loop not found exactly once"
                text = text.replace(old_p12,
                    '    check(f"P12-vmess-{net}-build-refuses-no-sni",\n'
                    '          err == "vmess-no-sni", f"net={net} err={err}")\n')
                old_sec = (
                    'rec = vmess_rec("203.0.113.222", "ws", scy="aes-128-gcm")\n')
                assert text.count(old_sec) == 1, "P12 security rec not found exactly once"
                text = text.replace(old_sec,
                    '# i04: SNI added so the node builds under merged N3;\n'
                    '# the D2 substance (diverges ONLY on security) is unchanged.\n'
                    'rec = dict(vmess_rec("203.0.113.222", "ws", scy="aes-128-gcm"),\n'
                    '           sni="cdn.example.com")\n')
                old_clean = (
                    '        ("vmess ws auto tls", vmess_rec("203.0.113.228", "ws")),\n')
                assert text.count(old_clean) == 1, "P12 clean control not found exactly once"
                text = text.replace(old_clean,
                    '        # i04: SNI added so the positive control builds under merged N3.\n'
                    '        ("vmess ws auto tls", dict(vmess_rec("203.0.113.228", "ws"),\n'
                    '                                   sni="cdn.example.com")),\n')
            dst.write_text(text, encoding="utf-8")
            staged127.append(dst)
        for f in staged127:
            extra = ({"I02_POOL_SNAPSHOT": str(I02_SNAP)}
                     if f.name == "test-i02-rollback.py" else None)
            run("M2 #127 v2 merged layout %s" % f.name,
                [sys.executable, str(f)], I04 / "tests",
                env_extra=extra, timeout=900)
    finally:
        for f in staged127:
            if f.exists():
                f.unlink()
        for d in ("v2-work", "scrape-work", "crawl-base", "rollback-work",
                  "perf-work"):
            p = I04 / "tests" / d
            if p.exists():
                shutil.rmtree(p, ignore_errors=True)

    # ---- M3: #128 v2 suite files staged into the merged layout ----
    for f in ("pool-snapshot.db", "pool-snapshot.db-wal",
              "pool-snapshot.db-shm", "crawl-20261124-desensitized.json",
              "cli-patched.py"):
        src, dst = I03_WORK / f, I04_WORK / f
        if not dst.exists():
            shutil.copy2(src, dst)
    if not (I04_WORK / "live").exists():
        shutil.copytree(I03_WORK / "live", I04_WORK / "live")
    # Part L reads the production chain from WORK/prod-chain.
    if not (I04_WORK / "prod-chain").exists():
        shutil.copytree(I03_WORK / "prod-chain", I04_WORK / "prod-chain")
    # Part L applies pool-db-source.patch from the package root: stage the
    # #128 v2 file in, remove it afterwards (test fixture, not a #04 file).
    patch_dst = I04 / "pool-db-source.patch"
    patch_staged = False
    if not patch_dst.exists():
        shutil.copy2(I03V2 / "pool-db-source.patch", patch_dst)
        patch_staged = True
    staged128 = []
    try:
        for f in ("test_integration_03.py", "test_integration_03_v2.py"):
            dst = I04 / "tests" / f
            text = (I03V2 / "tests" / f).read_text(encoding="utf-8")
            if f == "test_integration_03_v2.py":
                old_k7 = ('"comma-uuid" not in v2_rules_text')
                assert text.count(old_k7) == 1, "K7 assertion not found exactly once"
                # NOTE: no trailing '#...' comment here -- a comment would
                # swallow the closing paren of the check() call (the K7
                # assertion spans two lines) and break the scratch copy.
                text = text.replace(
                    old_k7, '"comma-uuid" in v2_rules_text')
                old_harness = (
                    '    for f in ("__init__.py", "db.py", "crawler.py", "geo.py", "rules.py",\n'
                    '              "tester.py", "screening.py", "blocklist_common.py"):\n')
                assert text.count(old_harness) == 1, "Part I harness list not found exactly once"
                text = text.replace(old_harness,
                    '    for f in ("__init__.py", "db.py", "crawler.py", "geo.py", "rules.py",\n'
                    '              "tester.py", "screening.py", "blocklist_common.py",\n'
                    '              "normalize.py"):  # i04: merged rules/tester import it\n')
            dst.write_text(text, encoding="utf-8")
            staged128.append(dst)
        for f in staged128:
            run("M3 #128 v2 merged layout %s" % f.name,
                [sys.executable, str(f)], I04 / "tests", timeout=900)
    finally:
        for f in staged128:
            if f.exists():
                f.unlink()
        if patch_staged and patch_dst.exists():
            patch_dst.unlink()

    print("=" * 70)
    failed = [r for r in RESULTS if not r[1]]
    print("REGRESSIONS: %d passed, %d failed, %d total"
          % (len(RESULTS) - len(failed), len(failed), len(RESULTS)))
    for name, ok, detail in RESULTS:
        print(("PASS " if ok else "FAIL ") + name + " :: " + detail)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
