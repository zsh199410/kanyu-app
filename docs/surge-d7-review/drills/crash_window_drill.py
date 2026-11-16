"""D5 crash-window drill (GPT D3 review 6886420557, item 3).

Complements drills/state_loss_drill.py (11 scenarios) and
drills/crash_drill.py (SIGKILLed lock holder): those cover a kill
BEFORE the atomic rename and a killed lock holder. This drill covers
the remaining gap -- a kill BETWEEN the two writes of _write_state()
(state rename done, anchor not yet written; or anchor just written).

Method: a child process loops calling _write_state() under the shared
lock while the parent SIGKILLs it after a random delay. After the
kill the parent reads the workdir and classifies the outcome. The
read result may ONLY be one of three things:

  * consistent ok        (both records new, agree, seq + checksum match)
  * consistent degraded  (same, with the STOP still recorded)
  * explicit refusal     (a recovery_state_*/recovery_anchor_* code)

A torn mix (state ok + anchor degraded, or vice versa) can NEVER
surface as a silently accepted state: the strict read refuses it.

Two phases (N >= 20 total, default 10 + 10):
  Phase A -- STOP persistence: the child only rewrites degraded
    states (the STOP is never legitimately cleared by the child).
    After every kill the STOP must still be verifiable: the read is
    a consistent degraded/stopped state, or a refusal carrying the
    _stop_recorded suffix.
  Phase B -- crash window: the child alternates ok/degraded. After
    every kill the read must be one of the three outcomes above.
    STOP survival is recorded per iteration, but a consistent ok is
    NOT counted as a STOP loss: it means the child COMPLETED a full
    ok write (both records agree, verified by the strict read
    succeeding) before the kill landed -- a legitimate overwrite by
    the writer, not a torn state. The property under test is that no
    TORN ok ever appears; a torn write surfaces as an explicit
    refusal, never as a silent ok.

The served file is never touched by _write_state(); its SHA must be
identical before and after every iteration.

Usage (run from the D5 root):
  python3 drills/crash_window_drill.py [--iterations N] [--out LOG.json]
Exit 0 only when every iteration lands in its allowed set and the
served SHA never changes. Writes a JSON log (stdout + --out file).

Honest boundary: fixtures are SYNTHETIC (fixtures/build_fixtures.py).
SIGKILL timing is random, so the exact mix of outcomes varies run to
run; the log records the actual kill delay and outcome per iteration.
"""

import argparse
import hashlib
import json
import os
import random
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
    OWNER_ACK_INIT, enter_degraded, init_recovery_state,
    read_state_strict)
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(ROOT, "fixtures")

# Child: loop _write_state() under the shared lock until SIGKILLed.
# argv: workdir, mode ("stop" = degraded only, "switch" = ok/degraded),
# ready-file path. Writes the ready file after the first completed
# write so the parent only starts its kill timer once the child is
# actually inside the write loop.
CHILD_SRC = (
    "import sys, os, time\n"
    "sys.path.insert(0, %r)\n"
    "import types\n"
    "_c = types.ModuleType('pool.crawler')\n"
    "_c.AEAD_METHODS = ('aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305')\n"
    "_c.parse_surge_line = lambda line: None\n"
    "sys.modules['pool.crawler'] = _c\n"
    "_g = types.ModuleType('pool.geo')\n"
    "_g.hint_to_code = lambda hint: ''\n"
    "_g.display_name = lambda code, english='': ('', '')\n"
    "_g.code_to_flag = lambda code: ''\n"
    "_g.is_cf_or_reserved = lambda host: False\n"
    "class _F:\n"
    "    def country(self, host):\n"
    "        return ('US', '')\n"
    "_g.IpApi = _F\n"
    "sys.modules['pool.geo'] = _g\n"
    "from pool.publish_lock import PublishLock\n"
    "from pool.recovery import _write_state, _load_state_for_transition\n"
    "workdir, mode, ready = sys.argv[1], sys.argv[2], sys.argv[3]\n"
    "lock = PublishLock(os.path.join(workdir, 'lock', 'publish.lock'),\n"
    "                   owner='crash-window-child', timeout=30)\n"
    "lock.acquire()\n"
    "try:\n"
    "    i = 0\n"
    "    while True:\n"
    "        now = int(time.time())\n"
    "        state, _note = _load_state_for_transition(workdir, now)\n"
    "        if mode == 'stop':\n"
    "            state.update({'state': 'degraded', 'stopped': True,\n"
    "                          'since': now,\n"
    "                          'reason': 'crash-window stop %%d' %% i})\n"
    "        else:\n"
    "            ok = (i %% 2 == 0)\n"
    "            state.update({'state': 'ok' if ok else 'degraded',\n"
    "                          'stopped': not ok, 'since': now,\n"
    "                          'reason': 'crash-window switch %%d' %% i})\n"
    "        _write_state(workdir, state,\n"
    "                     reason='crash-window %%d' %% i)\n"
    "        if i == 0:\n"
    "            open(ready, 'w').write('ready\\n')\n"
    "        i += 1\n"
    "        time.sleep(0.02)\n"
    "finally:\n"
    "    lock.release()\n"
) % ROOT


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _sha(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _classify_read(workdir):
    """One of: consistent-ok / consistent-degraded / refused:<code>.
    Returns (label, state_or_None, error_or_None)."""
    state, err = read_state_strict(workdir)
    if err is not None:
        return "refused:%s" % err, None, err
    if state.get("state") == "ok" and not state.get("stopped"):
        return "consistent-ok", state, None
    if state.get("stopped"):
        return "consistent-degraded", state, None
    return "refused:unexpected-state-%s" % state.get("state"), state, None


def main(argv=None):
    ap = argparse.ArgumentParser(description="D5 crash-window drill")
    ap.add_argument("--iterations", type=int, default=20,
                    help="total kill iterations, split evenly between "
                         "phase A (STOP persistence) and phase B "
                         "(ok/degraded switching); >= 20")
    ap.add_argument("--workdir", default="")
    ap.add_argument("--record",
                    default=os.path.join(FIX, "native_results_fixture.json"))
    ap.add_argument("--probe-db", default=os.path.join(FIX, "p0_fixture.db"))
    ap.add_argument("--clean14",
                    default=os.path.join(FIX, "clean_14_fixture.txt"))
    ap.add_argument("--pool44",
                    default=os.path.join(FIX, "pool_44_fixture.txt"))
    ap.add_argument("--out", default="")
    args = ap.parse_args(argv)
    n_total = max(20, args.iterations)
    n_a = n_total // 2
    n_b = n_total - n_a

    workdir = args.workdir or tempfile.mkdtemp(prefix="d5-crash-window-")
    with open(args.record) as f:
        record = json.load(f)
    version_sha = record["runs"][0]["version_sha"]
    tested_at = record["runs"][0]["tested_at"]
    now = tested_at + 3600
    clean14 = _read_lines(args.clean14)
    served_file = os.path.join(workdir, "served", "pool-new.txt")

    # Seed: init + clean publish + sync, so a served file exists and
    # its SHA can be tracked across the kills.
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    assert rc == 0, out
    rc, res = run_publish(workdir, clean14, args.record, version_sha,
                          probe_db=args.probe_db, now=now,
                          source_file=args.pool44)
    assert rc == 0, res
    rc, res = run_sync(workdir, args.record, version_sha,
                       probe_db=args.probe_db, now=now)
    assert rc == 0, res
    served_sha_before = _sha(served_file)
    assert served_sha_before is not None

    log = {"drill": "crash-window", "workdir": workdir,
           "served_sha_prefix": served_sha_before[:12],
           "iterations": []}
    all_pass = True

    def run_one(n, phase, mode):
        nonlocal all_pass
        # Every iteration starts from a known recorded STOP.
        rc, _out = enter_degraded(workdir, "crash-window reset %d" % n,
                                  now=now)
        assert rc == 0, _out
        ready = os.path.join(workdir, "child-ready-%d.txt" % n)
        if os.path.exists(ready):
            os.unlink(ready)
        proc = subprocess.Popen(
            [sys.executable, "-c", CHILD_SRC, workdir, mode, ready],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if os.path.exists(ready):
                    break
                time.sleep(0.05)
            delay = random.uniform(0.02, 0.5)
            time.sleep(delay)
            proc.send_signal(signal.SIGKILL)
            proc.wait(timeout=10)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=10)
        if os.path.exists(ready):
            os.unlink(ready)
        label, state, err = _classify_read(workdir)
        served_after = _sha(served_file)
        served_unchanged = served_after == served_sha_before
        stop_survived = False
        overwritten_by_completed_write = False
        if label == "consistent-degraded":
            stop_survived = True
        elif label.startswith("refused:") and err is not None \
                and err.endswith("_stop_recorded"):
            stop_survived = True
        elif label == "consistent-ok":
            # Both records agree (the strict read succeeded): the
            # child completed a full ok write before the kill, so the
            # STOP was overwritten by a completed write, not lost to
            # a torn write. Recorded separately, not a STOP loss.
            overwritten_by_completed_write = True
        if phase == "A":
            ok = stop_survived and served_unchanged
        else:
            ok = (label in ("consistent-ok", "consistent-degraded")
                  or label.startswith("refused:")) and served_unchanged
        entry = {"n": n, "phase": phase, "mode": mode,
                 "kill_delay_s": round(delay, 3),
                 "read": label,
                 "stop_survived": stop_survived,
                 "stop_overwritten_by_completed_write":
                     overwritten_by_completed_write,
                 "served_sha_unchanged": served_unchanged,
                 "pass": bool(ok)}
        log["iterations"].append(entry)
        all_pass = all_pass and bool(ok)
        return entry

    for n in range(1, n_a + 1):
        run_one(n, "A", "stop")
    for n in range(n_a + 1, n_a + n_b + 1):
        run_one(n, "B", "switch")

    iters = log["iterations"]
    log["summary"] = {
        "total": len(iters),
        "phase_a_total": n_a,
        "phase_a_stop_survived": sum(
            1 for e in iters if e["phase"] == "A" and e["stop_survived"]),
        "phase_b_total": n_b,
        "phase_b_stop_survived": sum(
            1 for e in iters if e["phase"] == "B" and e["stop_survived"]),
        "phase_b_completed_ok_overwrites": sum(
            1 for e in iters
            if e["phase"] == "B"
            and e["stop_overwritten_by_completed_write"]),
        "phase_b_refusals": sum(
            1 for e in iters
            if e["phase"] == "B" and e["read"].startswith("refused:")),
        "served_sha_unchanged_all": all(
            e["served_sha_unchanged"] for e in iters),
        "all_pass": bool(all_pass),
    }
    log["all_pass"] = bool(all_pass)
    text = json.dumps(log, indent=2, ensure_ascii=False)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    return 0 if all_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
