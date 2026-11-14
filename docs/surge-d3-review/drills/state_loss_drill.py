"""D3 state-loss drill (GPT D2 review 6884522235, P0).

Persistence drill: kill -9 mid-write, truncate, chmod 000 / directory
replacement -- each must leave publish/sync/rollback refusing (or,
for the kill-mid-write case, the OLD state intact because the atomic
rename never happened, so the gate still works on the old state).

Recovery drill: STOP -> delete the state file -> publish/sync/rollback
refused (a STOP is still on record in the anchor) -> init refuses ->
manual restore with the confirmation string -> fresh native evidence
required to return to ok -> publish works again.

Usage (run from the D3 root):
  python3 drills/state_loss_drill.py
    [--workdir DIR] [--record PATH] [--probe-db PATH]
    [--clean14 PATH] [--pool44 PATH] [--version-sha SHA] [--now SECONDS]
    [--out LOG.json]
Exit 0 only when every scenario produced the expected refusal (or the
expected success for the kill-mid-write intact-state case and the
recovered publish). Writes a JSON log (stdout + --out file).

Honest boundary: fixtures are SYNTHETIC (fixtures/build_fixtures.py).
The "fresh native evidence" here is a fixture record, not a real phone
measurement.
"""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

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

from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_INIT, OWNER_ACK_RESTORE, clear_stop,
    enter_degraded, init_recovery_state, manual_restore, read_state)
from pool.rollback import run_rollback  # noqa: E402
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(ROOT, "fixtures")


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _sha(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _latest_history(workdir):
    hist = os.path.join(workdir, "publish", "history")
    snaps = sorted(f for f in os.listdir(hist) if f.endswith(".txt"))
    return os.path.join(hist, snaps[-1]) if snaps else None


def main():
    ap = argparse.ArgumentParser(description="D3 state-loss drill")
    ap.add_argument("--workdir", default="")
    ap.add_argument("--record", default=os.path.join(FIX, "native_results_fixture.json"))
    ap.add_argument("--probe-db", default=os.path.join(FIX, "p0_fixture.db"))
    ap.add_argument("--clean14", default=os.path.join(FIX, "clean_14_fixture.txt"))
    ap.add_argument("--pool44", default=os.path.join(FIX, "pool_44_fixture.txt"))
    ap.add_argument("--version-sha", default="")
    ap.add_argument("--now", type=int, default=0)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    workdir = args.workdir or tempfile.mkdtemp(prefix="d3-state-loss-")
    with open(args.record) as f:
        record = json.load(f)
    version_sha = args.version_sha or record["runs"][0]["version_sha"]
    tested_at = record["runs"][0]["tested_at"]
    now = args.now or tested_at + 3600
    clean14 = _read_lines(args.clean14)
    pool44_path = args.pool44
    probe_db = args.probe_db

    state_path = os.path.join(workdir, "recovery-state.json")
    anchor_path = os.path.join(workdir, "recovery-anchor.json")
    tmp_path = state_path + ".tmp"
    publish_file = os.path.join(workdir, "publish", "pool-new.txt")
    served_file = os.path.join(workdir, "served", "pool-new.txt")

    log = {"scenarios": [], "workdir": workdir}
    ok = True

    def attempt_all(tag, expect_error=None, expect_ok=False):
        """Run publish/sync/rollback; record rc + error for each."""
        entry = {"scenario": tag, "attempts": {}}
        rc, res = run_publish(workdir, clean14, args.record, version_sha,
                              probe_db=probe_db, now=now,
                              source_file=pool44_path)
        entry["attempts"]["publish"] = {"rc": rc,
                                        "error": res.get("error")}
        rc, res = run_sync(workdir, args.record, version_sha,
                           probe_db=probe_db, now=now)
        entry["attempts"]["sync"] = {"rc": rc, "error": res.get("error")}
        rc, res = run_rollback(workdir, "latest-history", args.record,
                               probe_db=probe_db, now=now)
        entry["attempts"]["rollback"] = {"rc": rc,
                                         "error": res.get("error")}
        if expect_ok:
            entry["pass"] = all(a["rc"] == 0
                                for a in entry["attempts"].values())
        else:
            entry["pass"] = all(a["rc"] == 1
                                and a["error"] == expect_error
                                for a in entry["attempts"].values())
        entry["expected_error"] = expect_error
        log["scenarios"].append(entry)
        return entry["pass"]

    # ---- seed: init + clean publish + sync -------------------------
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    assert rc == 0, out
    rc, res = run_publish(workdir, clean14, args.record, version_sha,
                          probe_db=probe_db, now=now,
                          source_file=pool44_path)
    assert rc == 0, res
    rc, res = run_sync(workdir, args.record, version_sha,
                       probe_db=probe_db, now=now)
    assert rc == 0, res
    log["seed"] = {"publish_sha": _sha(publish_file),
                   "served_sha": _sha(served_file)}

    # ---- S1: kill -9 mid-write --------------------------------------
    # A writer child opens the state .tmp, writes partial JSON, and
    # sleeps; SIGKILL it. The rename never happens, so the OLD state
    # file must be intact and the gate must still work on it.
    state_sha_before = _sha(state_path)
    child_src = (
        "import time\n"
        "p = %r\n"
        "with open(p, 'w') as f:\n"
        "    f.write('{\"state\": \"ok\", \"stopped\": fa')\n"
        "    f.flush()\n"
        "    time.sleep(30)\n" % tmp_path)
    child_path = os.path.join(workdir, "kill_child.py")
    with open(child_path, "w", encoding="utf-8") as f:
        f.write(child_src)
    proc = subprocess.Popen([sys.executable, child_path])
    time.sleep(0.5)
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    s1 = {"scenario": "S1 kill -9 mid-write",
          "tmp_leftover": os.path.exists(tmp_path),
          "state_sha_unchanged": _sha(state_path) == state_sha_before}
    # Gate on the intact old state: publish must still succeed.
    rc, res = run_publish(workdir, clean14, args.record, version_sha,
                          probe_db=probe_db, now=now,
                          source_file=pool44_path)
    s1["publish_rc"] = rc
    s1["pass"] = (s1["tmp_leftover"] and s1["state_sha_unchanged"]
                  and rc == 0)
    log["scenarios"].append(s1)
    ok = ok and s1["pass"]
    # Now the torn-write combination: state file gone, .tmp left.
    os.unlink(state_path)
    ok = attempt_all("S1b torn write (state missing + .tmp present)",
                     expect_error="recovery_state_write_interrupted") and ok
    # Clean up the .tmp and rebuild from the anchor.
    os.unlink(tmp_path)
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    assert rc == 0, out

    # ---- S2: truncate the state file --------------------------------
    with open(state_path, "w", encoding="utf-8") as f:
        f.truncate(0)
    ok = attempt_all("S2 truncate state file (0 bytes)",
                     expect_error="recovery_state_corrupt") and ok
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    # init refuses a corrupt state file: the operator must remove it
    # deliberately first; then the anchor governs the rebuild.
    log["scenarios"].append(
        {"scenario": "S2b init refuses corrupt state file",
         "init_rc": rc, "init_error": out.get("error"),
         "pass": rc == 1
         and out.get("error") == "init_refused_unreadable_state"})
    ok = ok and log["scenarios"][-1]["pass"]
    os.unlink(state_path)
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    assert rc == 0, out

    # ---- S3: unreadable state file ----------------------------------
    # chmod 000 only blocks reads for non-root; as root the kernel
    # lets root read through it, so use directory replacement there.
    if os.geteuid() == 0:
        os.unlink(state_path)
        os.mkdir(state_path)
        method = "directory replacement (root: chmod 000 is not a block)"
        ok = attempt_all("S3 unreadable state file (%s)" % method,
                         expect_error="recovery_state_unreadable") and ok
        os.rmdir(state_path)
    else:
        os.chmod(state_path, 0)
        try:
            ok = attempt_all("S3 unreadable state file (chmod 000)",
                             expect_error="recovery_state_unreadable") and ok
        finally:
            os.chmod(state_path, 0o600)
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    assert rc == 0, out

    # ---- S4: recovery drill ------------------------------------------
    # STOP -> delete the state file -> attempts refused -> init refused
    # -> manual restore with confirmation string -> fresh native
    # evidence -> clear_stop -> ok -> publish works.
    rc, _out = enter_degraded(workdir, "drill stop", now=now)
    assert rc == 0
    os.unlink(state_path)
    ok = attempt_all(
        "S4 STOP + state file deleted",
        expect_error="recovery_state_missing_stop_recorded") and ok
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    log["scenarios"].append(
        {"scenario": "S4b init cannot launder STOP",
         "init_rc": rc, "init_error": out.get("error"),
         "pass": rc == 1
         and out.get("error") == "init_refused_stop_recorded"})
    ok = ok and log["scenarios"][-1]["pass"]
    rc, out = manual_restore(workdir, _latest_history(workdir),
                             args.record, OWNER_ACK_RESTORE,
                             probe_db=probe_db, now=now)
    log["scenarios"].append(
        {"scenario": "S4c manual restore (confirmation string)",
         "rc": rc, "pass": rc == 0})
    ok = ok and log["scenarios"][-1]["pass"]
    # Fresh native evidence (fixture record, same version, now) then
    # clear_stop returns the gate to ok.
    rc, out = clear_stop(workdir, OWNER_ACK_CLEAR, args.record,
                         probe_db=probe_db, now=now + 60)
    log["scenarios"].append(
        {"scenario": "S4d clear_stop with fresh native evidence",
         "rc": rc, "pass": rc == 0})
    ok = ok and log["scenarios"][-1]["pass"]
    state = read_state(workdir)
    log["scenarios"].append(
        {"scenario": "S4e gate back to ok, publish works",
         "state": state.get("state"),
         "pass": state.get("state") == "ok"})
    ok = ok and log["scenarios"][-1]["pass"]
    ok = attempt_all("S4f publish/sync/rollback after recovery",
                     expect_ok=True) and ok

    log["all_pass"] = bool(ok)
    text = json.dumps(log, indent=2, ensure_ascii=False)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
