#!/usr/bin/env python3
"""D7 :07/:15 cycle drill (Issue #73, GPT D6 review 6904538782,
item 3 -- pre-launch checklist, ":07/:15 consecutive cycles and
rollback SHA").

In-process sequence with explicit :07 (gate-publish) / :15
(gate-sync + bridge_sync) labels, on synthetic fixtures:

  P1 cycle N:   :07 publish v1 (gated) -> :15 sync + bridge serve
    clean14; served / bridge / legacy all clean14; chain
    source_sha == v1.
  P1 cycle N+1: :07 publish v2 (gated, new source) -> :15 sync +
    bridge; served bytes still clean14 (same admitted subset),
    chain source_sha moves v1 -> v2; bridge SHA unchanged
    (last good bytes, correctly re-served).
  P2 cycle N+2: :07 publish v3 (UNTESTED source, no native run)
    -> gate REFUSES (rc=1); :15 sync still serves v2 clean14,
    bridge SHA unchanged -- an ungated version never reaches the
    bridge.
  P3 (fresh workdir): :15 sync with served tampered post-copy ->
    rc=1, served quarantined + restored to clean14, bridge keeps
    its pre-run SHA (rollback SHA), pool STOP until manual
    recovery.

This is the cycle-level companion to drills/cross_cycle_drill.py
(wrapper-based, 32/32): same invariants, labelled by the real
timer slots. The wrapper exit-code semantics (0/1/2, health.json)
are covered by drills/d6_item3_publish_exit.py (17/17).

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object; --out writes it.

Usage: python3 drills/d7_cycles_0715.py
       [--out docs/d7-cycles-drill-log.json]
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")
sys.path.insert(0, HERE)

import types  # noqa: E402

_crawler = types.ModuleType("pool.crawler")
_crawler.AEAD_METHODS = ("aes-128-gcm", "aes-256-gcm", "chacha20-poly1305")
_crawler.parse_surge_line = lambda line: None
sys.modules["pool.crawler"] = _crawler

_geo = types.ModuleType("pool.geo")
_CN = {"US": ("美国", "\U0001f1fa\U0001f1f8"),
       "HK": ("香港", "\U0001f1ed\U0001f1f0"),
       "IR": ("伊朗", "\U0001f1ee\U0001f1f7")}


def _hint_to_code(hint):
    for cn, code in (("美国", "US"), ("香港", "HK"), ("伊朗", "IR")):
        if cn in (hint or ""):
            return code
    return ""


_geo.hint_to_code = _hint_to_code
_geo.display_name = lambda code, english="": _CN.get(code, ("未知", ""))
_geo.code_to_flag = lambda code: _CN.get(code, ("", ""))[1]
_geo.is_cf_or_reserved = lambda host: False


class _FakeIpApi:
    def country(self, host):
        return ("US", "")


_geo.IpApi = _FakeIpApi
sys.modules["pool.geo"] = _geo

from pool.bridge_sync import run_bridge_sync, verify_targets  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, gate_check, init_recovery_state  # noqa: E402
from pool.sync import run_sync  # noqa: E402
from pool.version_chain import read_chain_sidecar  # noqa: E402


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sha_lines(lines):
    return hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def fp_of_line(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    root = tempfile.mkdtemp(prefix="d7-cycles-")
    steps = []
    checks = []

    def step(name, detail, **kw):
        rec = {"step": name, "detail": str(detail)}
        rec.update(kw)
        steps.append(rec)
        return rec

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    def sha_of(path):
        return sha256_file(path)[:12] if os.path.exists(path) else ""

    try:
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        clean_sha = sha_lines(clean14)
        failed_lines = [l for l in pool44 if fp_of_line(l) not in clean_fps]
        v2_lines = [l for l in pool44 if l != failed_lines[0]]
        v3_lines = [l for l in pool44 if l != failed_lines[1]]
        sha1 = sha_lines(pool44)
        sha2 = sha_lines(v2_lines)
        sha3 = sha_lines(v3_lines)
        record_path = os.path.join(FIX, "native_results_fixture.json")
        probe_db = os.path.join(FIX, "p0_fixture.db")
        record = json.load(open(record_path))
        v1_results = record["runs"][0]["results"]
        now = record["runs"][0]["tested_at"] + 3600

        def make_record(path):
            rec = {"format": "native-results-v1", "runs": [
                {"version_sha": sha1, "tested_at": now - 3600,
                 "tested_at_cst": "", "network": "5G cellular",
                 "surge": "6.100.0 build 4025", "results": v1_results},
                {"version_sha": sha2, "tested_at": now - 3600,
                 "tested_at_cst": "", "network": "5G cellular",
                 "surge": "6.100.0 build 4025", "results": v1_results}]}
            with open(path, "w") as f:
                json.dump(rec, f)
            return path

        def chain_source(workdir):
            _meta, chain = read_chain_sidecar(
                os.path.join(workdir, "publish"), "pool-new.txt")
            return (chain or {}).get("source_sha", "")

        # ================= P1: cycles N and N+1 =================
        wd = os.path.join(root, "wd")
        os.makedirs(wd, exist_ok=True)
        rec2 = make_record(os.path.join(root, "record-v1v2.json"))
        v1_file = os.path.join(FIX, "pool_44_fixture.txt")
        v2_file = os.path.join(root, "v2.txt")
        write_lines(v2_file, v2_lines)
        bridge = os.path.join(root, "bridge")
        os.makedirs(bridge, exist_ok=True)
        old_path = os.path.join(bridge, "old-pool.txt")
        rc, out = init_recovery_state(wd, OWNER_ACK_INIT)
        check("p1_init_rc0", rc == 0, str(out)[:100])

        rc, res = run_publish(wd, clean14, rec2, sha1, probe_db=probe_db,
                              now=now, source_file=v1_file)
        check("p1_n_07_publish_v1_rc0", rc == 0, str(res.get("error")))
        check("p1_n_07_chain_source_v1",
              chain_source(wd) == sha1, chain_source(wd)[:12])
        rc, res = run_sync(wd, rec2, sha1, probe_db=probe_db, now=now)
        check("p1_n_15_sync_rc0", rc == 0, str(res.get("error")))
        rc, res = run_bridge_sync(wd, bridge, old_path=old_path,
                                  native_record_path=rec2, probe_db=probe_db,
                                  now=now)
        check("p1_n_15_bridge_rc0", rc == 0, str(res.get("error")))
        check("p1_n_targets_clean14",
              sha_of(wd + "/served/pool-new.txt") == clean_sha[:12]
              and sha_of(bridge + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_path) == clean_sha[:12],
              "served=%s bridge=%s legacy=%s"
              % (sha_of(wd + "/served/pool-new.txt"),
                 sha_of(bridge + "/pool-new.txt"), sha_of(old_path)))
        vt = verify_targets(wd, bridge, old_path=old_path)
        check("p1_n_verify_targets_consistent", vt["consistent"],
              vt["detail"])
        step("P1 cycle N :07+:15",
             ":07 publish v1 gated, :15 sync + bridge serve clean14",
             served_sha=sha_of(wd + "/served/pool-new.txt"),
             bridge_sha=sha_of(bridge + "/pool-new.txt"), rc=rc, error="")

        rc, res = run_publish(wd, clean14, rec2, sha2, probe_db=probe_db,
                              now=now, source_file=v2_file)
        check("p1_n1_07_publish_v2_rc0", rc == 0, str(res.get("error")))
        check("p1_n1_07_chain_source_v2",
              chain_source(wd) == sha2, chain_source(wd)[:12])
        rc, res = run_sync(wd, rec2, sha2, probe_db=probe_db, now=now)
        check("p1_n1_15_sync_rc0", rc == 0, str(res.get("error")))
        rc, res = run_bridge_sync(wd, bridge, old_path=old_path,
                                  native_record_path=rec2, probe_db=probe_db,
                                  now=now)
        check("p1_n1_15_bridge_rc0", rc == 0, str(res.get("error")))
        check("p1_n1_targets_still_clean14",
              sha_of(wd + "/served/pool-new.txt") == clean_sha[:12]
              and sha_of(bridge + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_path) == clean_sha[:12],
              "source moved v1->v2, served bytes stay clean14")
        vt = verify_targets(wd, bridge, old_path=old_path)
        check("p1_n1_verify_targets_consistent", vt["consistent"],
              vt["detail"])
        step("P1 cycle N+1 :07+:15",
             ":07 publish v2 gated (source v1->v2), :15 re-serves "
             "clean14; bridge SHA unchanged (last good bytes)",
             served_sha=sha_of(wd + "/served/pool-new.txt"),
             bridge_sha=sha_of(bridge + "/pool-new.txt"), rc=rc, error="")

        # ================= P2: untested v3 refused =================
        v3_file = os.path.join(root, "v3.txt")
        write_lines(v3_file, v3_lines)
        rc, res = run_publish(wd, clean14, rec2, sha3, probe_db=probe_db,
                              now=now, source_file=v3_file)
        check("p2_n2_07_publish_v3_refused", rc == 1,
              "rc=%d error=%s" % (rc, res.get("error")))
        check("p2_n2_07_chain_still_v2",
              chain_source(wd) == sha2, chain_source(wd)[:12])
        rc, res = run_sync(wd, rec2, sha2, probe_db=probe_db, now=now)
        check("p2_n2_15_sync_still_serves_v2", rc == 0,
              str(res.get("error")))
        rc, res = run_bridge_sync(wd, bridge, old_path=old_path,
                                  native_record_path=rec2, probe_db=probe_db,
                                  now=now)
        check("p2_n2_15_bridge_still_v2_clean",
              rc == 0
              and sha_of(bridge + "/pool-new.txt") == clean_sha[:12],
              "rc=%d bridge=%s" % (rc, sha_of(bridge + "/pool-new.txt")))
        step("P2 cycle N+2 :07+:15 (untested v3)",
             ":07 gate refuses v3; :15 keeps serving v2 clean14; "
             "bridge SHA unchanged",
             served_sha=sha_of(wd + "/served/pool-new.txt"),
             bridge_sha=sha_of(bridge + "/pool-new.txt"), rc=rc, error="")

        # ================= P3: :15 tamper -> refuse + restore =================
        wd3 = os.path.join(root, "wd3")
        os.makedirs(wd3, exist_ok=True)
        bridge3 = os.path.join(root, "bridge3")
        os.makedirs(bridge3, exist_ok=True)
        old3 = os.path.join(bridge3, "old-pool.txt")
        rc, out = init_recovery_state(wd3, OWNER_ACK_INIT)
        assert rc == 0, out
        rc, res = run_publish(wd3, clean14, rec2, sha1, probe_db=probe_db,
                              now=now, source_file=v1_file)
        assert rc == 0, res
        rc, res = run_sync(wd3, rec2, sha1, probe_db=probe_db, now=now)
        assert rc == 0, res
        rc, res = run_bridge_sync(wd3, bridge3, old_path=old3,
                                  native_record_path=rec2, probe_db=probe_db,
                                  now=now)
        assert rc == 0, res

        def _tamper(served_path):
            with open(served_path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc, res = run_sync(wd3, rec2, sha1, probe_db=probe_db, now=now,
                           post_copy_hook=_tamper)
        check("p3_15_tamper_sync_refuses", rc == 1,
              "rc=%d error=%s" % (rc, res.get("error")))
        check("p3_15_served_restored_clean14",
              sha_of(wd3 + "/served/pool-new.txt") == clean_sha[:12]
              and res.get("served_restored") is True,
              "served=%s restored=%s"
              % (sha_of(wd3 + "/served/pool-new.txt"),
                 res.get("served_restored")))
        check("p3_15_bridge_rollback_sha_unchanged",
              sha_of(bridge3 + "/pool-new.txt") == clean_sha[:12],
              "bridge=%s (last good, untouched by the tamper)"
              % sha_of(bridge3 + "/pool-new.txt"))
        allowed, err, _st = gate_check(wd3)
        check("p3_15_pool_stopped_after_tamper",
              not allowed and err == "pool_stopped", "err=%s" % err)
        step("P3 :15 tamper -> refuse + restore",
             "served tampered post-copy: sync rc=1, served restored "
             "clean14, bridge keeps last good SHA, pool STOP",
             served_sha=sha_of(wd3 + "/served/pool-new.txt"),
             bridge_sha=sha_of(bridge3 + "/pool-new.txt"), rc=rc,
             error=res.get("error", ""))

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7_cycles_0715",
               "sha": {"clean14": clean_sha[:12], "v1": sha1[:12],
                       "v2": sha2[:12], "v3_untested": sha3[:12]},
               "steps": steps, "checks": checks,
               "passed": sum(1 for c in checks if c["ok"]),
               "total": len(checks), "ok": ok}
        print(json.dumps(log, indent=1, ensure_ascii=False))
        if args.out:
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(log, f, indent=1, ensure_ascii=False)
        return 0 if ok else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
