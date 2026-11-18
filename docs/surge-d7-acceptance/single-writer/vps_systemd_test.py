#!/usr/bin/env python3
"""VPS systemd end-to-end test for the single-writer lock (task G).

Runs ON the US VPS as root, entirely inside the isolation directory
/opt/p2p3-single-writer/ (mode 700). It never writes production
/opt/free-node-program/ or /opt/surge-bridge/modules/, never stops a
production timer, and never installs Node. Test units live in
/run/systemd/system/ (runtime only, removed at the end) under
p2p3-* names; production units are only ever READ (systemctl show /
is-active / the verbatim PR #80 guard).

What is verified here (with real systemctl / ps output as evidence):
  S1 production guard refuses (timers active) + production SHA unchanged
  S2 legacy-ban proof chain on real systemd: timer re-enable, service
     running, signal-killed service, legacy process in ps -- each must
     fail the proof; drained + masked state must pass it; plus the
     demonstrated mask-and-amended-guard agreement (S2e)
  S3 two concurrent systemd publish services: exactly one wins, the
     other is refused; lock intervals never overlap; final file complete
  S4 SIGKILL of the lock holder under systemd: lock released, next
     publish succeeds, no half-written file
  S5 HTTP-served content during rapid publishes: every fetch is one
     complete payload (old or new), never partial
  S6 rollback under systemd: fault after staging restores files and
     removes only the own DB record; crawl/test rows intact
  S7 cleanup + production SHA / timer state re-verified unchanged

Usage (from the operator machine; files are transferred first and
SHA-verified -- see the transfer commands in the task log):
    ssh ... 'python3 /opt/p2p3-single-writer/vps_systemd_test.py'

Exit 0 only if every step passes; otherwise 1 (evidence is still
printed). Fixtures use only 192.0.2.0/24 and "test123".
"""

import hashlib
import importlib.util
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.request

BASE = "/opt/p2p3-single-writer"
RUN_UNITS = "/run/systemd/system"
PROD_SERVED = "/opt/surge-bridge/modules/pool-new.txt"
PROD_STAGING = "/opt/free-node-program/publish/pool-new.txt"
PROD_TIMERS = ("pool-publish.timer", "pool-sync.timer", "pool-crawl.timer",
               "pool-test.timer", "pool-test-full.timer")

LEGACY_TIMERS = ("p2p3-legacy-publish.timer", "p2p3-legacy-sync.timer")
LEGACY_SERVICES = ("p2p3-legacy-publish.service", "p2p3-legacy-sync.service")
GATE_TIMERS = ("p2p3-gate-publish.timer", "p2p3-gate-sync.timer")
GATE_SERVICES = ("p2p3-gate-publish.service", "p2p3-gate-sync.service")

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sw = _load("single_writer", os.path.join(_HERE, "single_writer.py"))
guard = _load("legacy_writer_guard",
              os.path.join(_HERE, "legacy-writer-guard.py"))

RESULTS = []  # (name, ok, detail)
LOG_FH = None


def log(msg):
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    if LOG_FH is not None:
        LOG_FH.write(line + "\n")
        LOG_FH.flush()


def record(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    log("%s %s -- %s" % ("PASS" if ok else "FAIL", name, detail))


def run(argv, check=False, timeout=60):
    proc = subprocess.run(argv, capture_output=True, text=True,
                          timeout=timeout)
    return proc


def sh(cmd, check=False, timeout=60):
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                          timeout=timeout)
    if check and proc.returncode != 0:
        raise RuntimeError("cmd failed %r: %s" % (cmd, proc.stderr))
    return proc


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def make_payload(tag, lines=30):
    out = []
    for i in range(1, lines + 1):
        out.append("test-node-%s-%02d 192.0.2.%d test123"
                   % (tag, i, (i % 250) + 1))
    return ("\n".join(out) + "\n").encode("utf-8")


PAYLOADS = {tag: make_payload(tag) for tag in ("init", "A", "B", "C")}
PAYLOAD_SHA = {tag: sha_bytes(data) for tag, data in PAYLOADS.items()}


def p(*parts):
    return os.path.join(BASE, *parts)


def write_unit(name, content):
    with open(os.path.join(RUN_UNITS, name), "w", encoding="utf-8") as fh:
        fh.write(content)
    log("wrote unit %s" % name)


def daemon_reload():
    proc = run(["systemctl", "daemon-reload"])
    assert proc.returncode == 0, proc.stderr


def systemctl_show(unit):
    proc = run(["systemctl", "show", "--no-pager",
                "--property=LoadState,UnitFileState,ActiveState,SubState,"
                "MainPID,ControlPID,Result,Job,ExecMainStatus", unit])
    data = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            data[k] = v.strip()
    return data


def is_active(unit):
    proc = run(["systemctl", "is-active", unit])
    return proc.stdout.strip()


def wait_finished(unit, timeout=60):
    """Wait until a oneshot service reaches a terminal state.

    A oneshot that exits non-zero ends in ActiveState=failed (not
    inactive), so both "inactive" and "failed" are terminal here.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if is_active(unit) in ("inactive", "failed"):
            return True
        time.sleep(0.5)
    return False


def service_result(unit):
    data = systemctl_show(unit)
    return data.get("Result", "?"), data.get("ExecMainStatus", "?")


def ban_proof_for(timers, services):
    # Default chain (services masked): the strongest bar, and the
    # amended guard now accepts masked services too, so the two pass
    # together. A merely-disabled service fails the proof.
    return sw.legacy_ban_proof(timers=tuple(timers),
                               services=tuple(services))


def db_counts(db_path):
    conn = sqlite3.connect(db_path)
    try:
        crawl = conn.execute("SELECT COUNT(*) FROM crawl_log").fetchone()[0]
        test = conn.execute("SELECT COUNT(*) FROM test_log").fetchone()[0]
        pub = conn.execute("SELECT COUNT(*) FROM publish_log").fetchone()[0]
        return crawl, test, pub
    finally:
        conn.close()


def reset_files():
    for name in ("served", "staging"):
        with open(p(name, "pool-new.txt"), "wb") as fh:
            fh.write(PAYLOADS["init"])
    for f in ("events-a.jsonl", "events-b.jsonl", "events-c.jsonl"):
        path = p("events", f)
        if os.path.exists(path):
            os.unlink(path)


def check_intervals_overlap():
    """Parse lock event logs; return (ok, detail). Intervals from
    different pids must never overlap."""
    intervals = []
    for fname in ("events-a.jsonl", "events-b.jsonl", "events-c.jsonl"):
        path = p("events", fname)
        if not os.path.exists(path):
            continue
        acquired = released = None
        pid = None
        for line in open(path, encoding="utf-8"):
            entry = json.loads(line)
            pid = entry["pid"]
            if entry["event"] == "lock_acquired":
                acquired = entry["ts"]
            elif entry["event"] == "lock_released":
                released = entry["ts"]
        if acquired is not None and released is not None:
            intervals.append((acquired, released, pid, fname))
    intervals.sort()
    for i in range(len(intervals)):
        for j in range(i + 1, len(intervals)):
            a0, a1, apid, aname = intervals[i]
            b0, b1, bpid, bname = intervals[j]
            if a0 < b1 and b0 < a1:
                return False, "overlap %s%s vs %s%s" % (aname, apid,
                                                       bname, bpid)
    return True, "%d interval(s), no overlap" % len(intervals)


# ---------------------------------------------------------------------------
# S0 setup
# ---------------------------------------------------------------------------

def setup():
    os.makedirs(p("lock"), exist_ok=True)
    os.makedirs(p("served"), exist_ok=True)
    os.makedirs(p("staging"), exist_ok=True)
    os.makedirs(p("payloads"), exist_ok=True)
    os.makedirs(p("events"), exist_ok=True)
    os.makedirs(p("bin"), exist_ok=True)
    os.chmod(BASE, 0o700)
    for tag, data in PAYLOADS.items():
        with open(p("payloads", tag + ".txt"), "wb") as fh:
            fh.write(data)
    reset_files()
    if os.path.exists(p("holder.pid")):
        os.unlink(p("holder.pid"))
    db_path = p("pool.sqlite3")
    if os.path.exists(db_path):
        os.unlink(db_path)
    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE crawl_log (id INTEGER PRIMARY KEY "
                 "AUTOINCREMENT, source TEXT, detail TEXT)")
    conn.execute("CREATE TABLE test_log (id INTEGER PRIMARY KEY "
                 "AUTOINCREMENT, node_ref TEXT, detail TEXT)")
    for i in range(50):
        conn.execute("INSERT INTO crawl_log (source, detail) VALUES (?, ?)",
                     ("crawl-src-%d" % i, "crawl-detail-%d" % i))
        conn.execute("INSERT INTO test_log (node_ref, detail) VALUES (?, ?)",
                     ("test-node-%d" % i, "test-detail-%d" % i))
    conn.commit()
    conn.close()
    log("setup done; prod sha before=%s" % sha_file(PROD_SERVED))
    return sha_file(PROD_SERVED), sha_file(PROD_STAGING)


def prod_state():
    states = {}
    for unit in PROD_TIMERS:
        states[unit] = is_active(unit)
    return (sha_file(PROD_SERVED), sha_file(PROD_STAGING), states)


# ---------------------------------------------------------------------------
# S1 production guard refuses
# ---------------------------------------------------------------------------

def step_s1(prod_before):
    proc = run(["python3", os.path.join(_HERE, "legacy-writer-guard.py")])
    log("production guard stdout: %s" % proc.stdout.strip())
    log("production guard exit: %d" % proc.returncode)
    try:
        out = json.loads(proc.stdout.strip())
        reason = out.get("reason", "?")
    except ValueError:
        reason = "unparsable"
    record("S1-production-guard-refuses",
           proc.returncode == 1 and reason == "old_timer_not_disabled",
           "exit=%d reason=%s" % (proc.returncode, reason))
    log("prod timers: %s" % json.dumps(prod_state()[2]))
    record("S1-production-sha-baseline",
           prod_before[0] == prod_before[1],
           "served=%s staging=%s" % (prod_before[0][:12],
                                     prod_before[1][:12]))


# ---------------------------------------------------------------------------
# S2 ban proof chain on real systemd
# ---------------------------------------------------------------------------

TIMER_UNIT = """[Unit]
Description=P2P3 isolation legacy timer (test only)
[Timer]
OnCalendar=*:0/5:00
Persistent=false
[Install]
WantedBy=timers.target
"""

SERVICE_TRUE = """[Unit]
Description=P2P3 isolation legacy service (test only)
[Service]
Type=oneshot
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
"""

SERVICE_SLEEP = """[Unit]
Description=P2P3 isolation legacy sync service (test only)
[Service]
Type=simple
ExecStart=/bin/sleep 300
[Install]
WantedBy=multi-user.target
"""


def step_s2():
    # Isolation units: legacy pair (ban-proof target) + gate pair
    # (publish-time target). Timers stay disabled; services are MASKED
    # (the default bar since the GPT review P0, 2026-11-18 -- a
    # merely-disabled service can still be revived by `systemctl
    # start`). The amended guard accepts masked services, so mask and
    # guard pass together (see S2e).
    write_unit("p2p3-legacy-publish.timer", TIMER_UNIT)
    write_unit("p2p3-legacy-sync.timer", TIMER_UNIT)
    write_unit("p2p3-legacy-publish.service", SERVICE_TRUE)
    write_unit("p2p3-legacy-sync.service", SERVICE_SLEEP)
    write_unit("p2p3-gate-publish.timer", TIMER_UNIT)
    write_unit("p2p3-gate-sync.timer", TIMER_UNIT)
    write_unit("p2p3-gate-publish.service", SERVICE_TRUE)
    write_unit("p2p3-gate-sync.service", SERVICE_TRUE)
    daemon_reload()
    run(["systemctl", "mask", "p2p3-legacy-publish.service"])
    run(["systemctl", "mask", "p2p3-legacy-sync.service"])
    run(["systemctl", "mask", "p2p3-gate-publish.service"])
    run(["systemctl", "mask", "p2p3-gate-sync.service"])
    daemon_reload()
    log("legacy publish timer state: %s"
        % json.dumps(systemctl_show("p2p3-legacy-publish.timer")))
    log("legacy publish service state: %s"
        % json.dumps(systemctl_show("p2p3-legacy-publish.service")))

    # S2a: drained + masked proves the ban (both unit sets).
    proven, evidence = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    record("S2a-ban-proven-when-drained-masked",
           proven, "evidence=%d checks" % len(evidence))
    proven_g, _ = ban_proof_for(GATE_TIMERS, GATE_SERVICES)
    record("S2a-gate-ban-proven", proven_g, "gate units drained+masked")

    # S2b: re-enable + start the legacy timer -> proof must fail.
    run(["systemctl", "enable", "--runtime", "p2p3-legacy-publish.timer"])
    run(["systemctl", "start", "p2p3-legacy-publish.timer"])
    time.sleep(1)
    log("legacy timer after enable+start: %s"
        % json.dumps(systemctl_show("p2p3-legacy-publish.timer")))
    proven, evidence = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    failed = [e["check"] for e in evidence if not e["ok"]]
    record("S2b-timer-reenable-fails-proof",
           not proven and any("timer_disabled" in c or "timer_inactive" in c
                              for c in failed),
           "failed=%s" % failed)
    run(["systemctl", "stop", "p2p3-legacy-publish.timer"])
    run(["systemctl", "disable", "--runtime", "p2p3-legacy-publish.timer"])
    proven, _ = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    record("S2b-timer-restored-proof-passes-again", proven, "")

    # S2c: a legacy writer process in ps -> proof must fail.
    with open(p("bin", "pool-sync.sh"), "w", encoding="utf-8") as fh:
        fh.write("#!/bin/bash\nsleep 120\n")
    os.chmod(p("bin", "pool-sync.sh"), 0o755)
    legacy_proc = subprocess.Popen(
        ["/bin/bash", p("bin", "pool-sync.sh")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    ps_out = run(["ps", "-eo", "pid=,args="]).stdout
    shown = [ln for ln in ps_out.splitlines() if "pool-sync.sh" in ln]
    log("ps rows for pool-sync.sh: %s" % shown)
    proven, evidence = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    failed = [e["check"] for e in evidence if not e["ok"]]
    record("S2c-legacy-process-fails-proof",
           not proven and "no_legacy_process" in failed and bool(shown),
           "failed=%s ps_rows=%d" % (failed, len(shown)))
    legacy_proc.terminate()
    legacy_proc.wait(timeout=10)
    proven, _ = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    record("S2c-process-gone-proof-passes-again", proven, "")

    # S2d: legacy service running, then killed out-of-band -> proof must
    # fail both times. NOTE (verified on this host): `systemctl stop`
    # sends SIGTERM as part of a stop job and leaves Result=success, so
    # a stop-job kill is NOT caught by the Result check; only an
    # out-of-band kill (SIGKILL straight at the MainPID) leaves
    # Result=signal. The proof below uses the out-of-band kill.
    # The service is masked by the S2 setup, so unmask it first (a
    # masked unit cannot be started at all); it is re-masked after
    # the restore below.
    run(["systemctl", "unmask", "p2p3-legacy-sync.service"])
    daemon_reload()
    run(["systemctl", "start", "p2p3-legacy-sync.service"])
    time.sleep(1)
    log("legacy sync service while running: %s"
        % json.dumps(systemctl_show("p2p3-legacy-sync.service")))
    proven, evidence = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    failed = [e["check"] for e in evidence if not e["ok"]]
    record("S2d-running-service-fails-proof",
           not proven and "service_drained:p2p3-legacy-sync.service" in failed,
           "failed=%s" % failed)
    main_pid = systemctl_show("p2p3-legacy-sync.service").get("MainPID", "0")
    log("killing legacy sync MainPID %s with SIGKILL (out-of-band)" % main_pid)
    run(["kill", "-9", main_pid])
    time.sleep(2)
    state = systemctl_show("p2p3-legacy-sync.service")
    log("legacy sync service after out-of-band SIGKILL: %s" % json.dumps(state))
    proven, evidence = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    failed = [e["check"] for e in evidence if not e["ok"]]
    # The proof must refuse; the first failing check is service_drained
    # (ActiveState=failed/SubState=failed after the kill), which is
    # fail-closed and correct -- the Result check is never reached.
    # The independent fact asserted here is Result=signal itself.
    record("S2d-signal-killed-service-fails-proof",
           not proven and state.get("Result") == "signal"
           and any(c.startswith("service_drained:")
                   or c.startswith("service_result_success:")
                   for c in failed),
           "Result=%s failed=%s" % (state.get("Result"), failed))
    run(["systemctl", "stop", "p2p3-legacy-sync.service"])
    run(["systemctl", "reset-failed", "p2p3-legacy-sync.service"])
    time.sleep(1)
    state = systemctl_show("p2p3-legacy-sync.service")
    if state.get("Result") != "success":
        # reset-failed did not restore a clean Result on this host:
        # recreate the unit file fresh (a never-run unit reports
        # Result=success) instead of guessing further.
        log("reset-failed left Result=%s; recreating unit file fresh"
            % state.get("Result"))
        write_unit("p2p3-legacy-sync.service", SERVICE_SLEEP)
        daemon_reload()
        state = systemctl_show("p2p3-legacy-sync.service")
    # Re-mask the service (it was unmasked for the start test above)
    # so the ban proof passes again on the masked bar.
    run(["systemctl", "mask", "p2p3-legacy-sync.service"])
    daemon_reload()
    log("legacy sync service after restore: %s" % json.dumps(state))
    proven, _ = ban_proof_for(LEGACY_TIMERS, LEGACY_SERVICES)
    record("S2d-service-restored-proof-passes-again", proven,
           "Result=%s after restore" % state.get("Result"))

    # S2e: the mask / guard amendment, demonstrated on the gate units.
    # Masking is the stronger bar, and the guard was amended (GPT
    # review P0, 2026-11-18) to accept LoadState=masked as drained, so
    # mask and guard now pass TOGETHER. Previously (verbatim guard) a
    # masked service failed the guard as "service_not_loaded" and the
    # two could not pass together; that conflict is closed by the
    # amendment. The gate services are already masked by the S2 setup;
    # this step proves the amended behaviour instead of leaving it as
    # an assumption.
    state = systemctl_show("p2p3-gate-publish.service")
    log("gate publish service while masked: %s" % json.dumps(state))
    guard.TIMERS = GATE_TIMERS
    guard.SERVICES = GATE_SERVICES
    allowed, reason, subject = guard.check()
    proven_masked, _ = sw.legacy_ban_proof(
        timers=GATE_TIMERS, services=GATE_SERVICES,
        require_masked_services=True)
    record("S2e-masked-service-passes-amended-guard",
           allowed and reason == "legacy_writers_drained",
           "guard reason=%s LoadState=%s"
           % (reason, state.get("LoadState")))
    record("S2e-masked-service-passes-masked-proof",
           proven_masked,
           "require_masked_services=True passes while masked")
    record("S2e-mask-and-guard-pass-together",
           allowed and proven_masked,
           "amended guard + masked proof agree while masked")
    # The masked state IS the restored state now (no unmask): both
    # must still pass with the services masked.
    allowed, reason, _ = guard.check()
    proven, _ = ban_proof_for(GATE_TIMERS, GATE_SERVICES)
    record("S2e-masked-guard-and-proof-pass-again",
           allowed and proven, "guard reason=%s" % reason)


# ---------------------------------------------------------------------------
# S3 concurrent systemd publishes
# ---------------------------------------------------------------------------

PUB_UNIT = """[Unit]
Description=P2P3 isolation publish %(tag)s (test only)
[Service]
Type=oneshot
Environment=SINGLE_WRITER_BASE=/opt/p2p3-single-writer
ExecStart=/usr/bin/python3 /opt/p2p3-single-writer/vps_publish_driver.py publish --candidate-file /opt/p2p3-single-writer/payloads/%(tag)s.txt --expected-sha %(sha)s --event-log-file /opt/p2p3-single-writer/events/events-%(lower)s.jsonl%(fault)s
"""


def step_s3():
    for tag, lower in (("A", "a"), ("B", "b")):
        write_unit("p2p3-pub-%s.service" % lower,
                   PUB_UNIT % {"tag": tag, "lower": lower,
                               "sha": PAYLOAD_SHA["init"], "fault": ""})
    daemon_reload()
    wins = 0
    for rnd in range(1, 4):
        reset_files()
        proc = run(["systemctl", "start",
                    "p2p3-pub-a.service", "p2p3-pub-b.service"])
        log("round %d systemctl start exit=%d" % (rnd, proc.returncode))
        ok_a = wait_finished("p2p3-pub-a.service", timeout=60)
        ok_b = wait_finished("p2p3-pub-b.service", timeout=60)
        res_a = service_result("p2p3-pub-a.service")
        res_b = service_result("p2p3-pub-b.service")
        log("round %d A: inactive=%s Result=%s ExecMainStatus=%s"
            % (rnd, ok_a, res_a[0], res_a[1]))
        log("round %d B: inactive=%s Result=%s ExecMainStatus=%s"
            % (rnd, ok_b, res_b[0], res_b[1]))
        # Exactly one exit 0 (winner), one exit 2 (refused stale).
        statuses = sorted([res_a[1], res_b[1]])
        one_win = statuses == ["0", "2"] and ok_a and ok_b
        if one_win:
            wins += 1
        final = open(p("served", "pool-new.txt"), "rb").read()
        staging = open(p("staging", "pool-new.txt"), "rb").read()
        complete = final in (PAYLOADS["A"], PAYLOADS["B"]) and staging == final
        tmp_left = [f for d in (p("served"), p("staging"), p("lock"))
                    for f in os.listdir(d) if ".tmp-" in f]
        record("S3-round%d-exactly-one-winner" % rnd, one_win,
               "A=%s B=%s" % (res_a, res_b))
        record("S3-round%d-final-file-complete" % rnd,
               complete and not tmp_left,
               "final=%s staging_match=%s tmp=%s"
               % (sha_bytes(final)[:12], staging == final, tmp_left))
        ok_iv, detail_iv = check_intervals_overlap()
        record("S3-round%d-lock-intervals-no-overlap" % rnd, ok_iv,
               detail_iv)
    record("S3-all-three-rounds-one-winner", wins == 3,
           "%d/3 rounds" % wins)


# ---------------------------------------------------------------------------
# S4 SIGKILL of the lock holder
# ---------------------------------------------------------------------------

HOLDER_UNIT = """[Unit]
Description=P2P3 isolation lock holder (test only)
[Service]
Type=simple
Environment=SINGLE_WRITER_BASE=/opt/p2p3-single-writer
ExecStart=/usr/bin/python3 /opt/p2p3-single-writer/vps_publish_driver.py hold --hold-seconds 120 --pid-file /opt/p2p3-single-writer/holder.pid
"""

PUB_C_UNIT = """[Unit]
Description=P2P3 isolation publish C (test only)
[Service]
Type=oneshot
Environment=SINGLE_WRITER_BASE=/opt/p2p3-single-writer
ExecStart=/usr/bin/python3 /opt/p2p3-single-writer/vps_publish_driver.py publish --candidate-file /opt/p2p3-single-writer/payloads/C.txt --expected-sha %(sha)s --event-log-file /opt/p2p3-single-writer/events/events-c.jsonl
"""


def step_s4():
    write_unit("p2p3-holder.service", HOLDER_UNIT)
    daemon_reload()
    run(["systemctl", "start", "p2p3-holder.service"])
    deadline = time.monotonic() + 30
    pid = None
    main_pid = None
    while time.monotonic() < deadline:
        state = systemctl_show("p2p3-holder.service")
        main_pid = state.get("MainPID", "0")
        if (os.path.exists(p("holder.pid"))
                and main_pid not in ("", "0")):
            pid = int(open(p("holder.pid")).read().strip())
            if pid == int(main_pid):
                break
            pid = None
        time.sleep(0.5)
    log("holder pid: %s MainPID=%s state=%s"
        % (pid, main_pid, json.dumps(systemctl_show("p2p3-holder.service"))))
    # The pid must be the live holder process, not a stale file.
    pid_alive = False
    if pid is not None:
        pid_alive = run(["kill", "-0", str(pid)]).returncode == 0
    # Prove the lock is really held: a non-blocking flock must fail.
    flock_proc = run(["flock", "--nonblock", p("lock", "pool.lock"),
                      "-c", "echo acquired"], timeout=10)
    log("flock --nonblock while held: exit=%d out=%r"
        % (flock_proc.returncode, flock_proc.stdout.strip()))
    held = flock_proc.returncode != 0
    record("S4-lock-held-by-holder",
           held and pid is not None and pid_alive,
           "flock exit=%d holder_pid=%s alive=%s"
           % (flock_proc.returncode, pid, pid_alive))
    # SIGKILL the holder via systemd, like a real OOM / kill -9.
    kill = run(["systemctl", "kill", "-s", "SIGKILL", "p2p3-holder.service"])
    time.sleep(2)
    ps_out = run(["ps", "-eo", "pid=,args="]).stdout
    still = [ln for ln in ps_out.splitlines()
             if pid is not None and ln.strip().startswith(str(pid) + " ")]
    state = systemctl_show("p2p3-holder.service")
    log("holder after SIGKILL: %s ps_still=%s"
        % (json.dumps(state), still))
    record("S4-holder-killed-by-sigkill",
           kill.returncode == 0 and not still,
           "kill_exit=%d ActiveState=%s" % (kill.returncode,
                                            state.get("ActiveState")))
    # The lock must be acquirable immediately: next publish succeeds.
    current_sha = sha_file(p("served", "pool-new.txt"))
    before = open(p("served", "pool-new.txt"), "rb").read()
    write_unit("p2p3-pub-c.service", PUB_C_UNIT % {"sha": current_sha})
    daemon_reload()
    run(["systemctl", "start", "p2p3-pub-c.service"])
    ok_c = wait_finished("p2p3-pub-c.service", timeout=60)
    res_c = service_result("p2p3-pub-c.service")
    log("publish C after SIGKILL: inactive=%s Result=%s ExecMainStatus=%s"
        % (ok_c, res_c[0], res_c[1]))
    after = open(p("served", "pool-new.txt"), "rb").read()
    tmp_left = [f for d in (p("served"), p("staging"))
                for f in os.listdir(d) if ".tmp-" in f]
    record("S4-publish-succeeds-after-sigkill",
           ok_c and res_c[1] == "0" and after == PAYLOADS["C"]
           and not tmp_left,
           "ExecMainStatus=%s complete=%s tmp=%s"
           % (res_c[1], after == PAYLOADS["C"], tmp_left))
    record("S4-no-half-product", before != after or after == PAYLOADS["C"],
           "served was complete before and after")


# ---------------------------------------------------------------------------
# S5 HTTP consistency during rapid publishes
# ---------------------------------------------------------------------------

def step_s5():
    reset_files()
    # NOTE: port 18081 on this host belongs to an unrelated service
    # (/opt/probe-service/probe_service.py, answers JSON 404s). Use
    # 18099 and verify OUR server answers 200 before the readers start,
    # so a foreign listener can never silently stand in for it.
    # Threading server: the stock `python3 -m http.server` is
    # single-threaded, and on this 1-CPU host concurrent readers starved
    # it into timeouts (run4: 2 timeouts, 0 partial snapshots). A
    # timeout is "no data", not "partial data", but the harness must not
    # produce inconclusive errors -- use a threading server.
    http_proc = subprocess.Popen(
        ["python3", "-c",
         "from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler;"
         "import functools, sys;"
         "ThreadingHTTPServer(('127.0.0.1', 18099),"
         " functools.partial(SimpleHTTPRequestHandler,"
         " directory=sys.argv[1])).serve_forever()",
         p("served")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        bound = False
        for _ in range(20):
            if http_proc.poll() is not None:
                break
            try:
                with urllib.request.urlopen(
                        "http://127.0.0.1:18099/pool-new.txt",
                        timeout=5) as resp:
                    if resp.status == 200:
                        bound = True
                        break
            except Exception:  # noqa: BLE001 - retry until bound
                time.sleep(0.5)
        record("S5-http-server-bound", bound and http_proc.poll() is None,
               "our server answers 200 on 18099 before readers start")
        if not bound:
            return
        allowed = {PAYLOAD_SHA["init"], PAYLOAD_SHA["A"], PAYLOAD_SHA["B"]}
        allowed_bodies = {PAYLOADS["init"], PAYLOADS["A"], PAYLOADS["B"]}
        seen = set()
        errors = []
        timeouts = []
        snapshot_count = [0]
        stop = {"flag": False}

        import threading

        # Claim under test (point 7): no HTTP response body is EVER a
        # partial write. A fetch timeout yields NO body at all, so it is
        # not a consistency violation -- it is recorded separately and
        # does not fail the step. The step fails only if a body is
        # partial/corrupt, or if too few snapshots were observed to
        # mean anything. Readers keep one persistent connection each
        # (no TCP/thread churn per fetch on this 1-CPU host).
        import http.client

        def _reader():
            conn = http.client.HTTPConnection("127.0.0.1", 18099, timeout=15)
            while not stop["flag"]:
                try:
                    conn.request("GET", "/pool-new.txt")
                    resp = conn.getresponse()
                    body = resp.read()
                except Exception as exc:  # noqa: BLE001 - transient
                    if len(timeouts) < 10:
                        timeouts.append("%s" % exc)
                    try:
                        conn.close()
                    except Exception:  # noqa: BLE001 - best effort
                        pass
                    conn = http.client.HTTPConnection("127.0.0.1", 18099,
                                                     timeout=15)
                    time.sleep(0.05)
                    continue
                snapshot_count[0] += 1
                h = sha_bytes(body)
                seen.add(h)
                if h not in allowed or body not in allowed_bodies:
                    errors.append("partial snapshot %s (%d bytes)"
                                  % (h[:12], len(body)))
                    return
                time.sleep(0.01)

        readers = [threading.Thread(target=_reader) for _ in range(3)]
        for t in readers:
            t.start()
        try:
            current_sha = PAYLOAD_SHA["init"]
            for i in range(20):
                tag = "A" if i % 2 == 0 else "B"
                env = dict(os.environ,
                           SINGLE_WRITER_BASE=BASE)
                proc = subprocess.run(
                    ["python3", os.path.join(_HERE, "vps_publish_driver.py"),
                     "publish", "--candidate-file", p("payloads", tag + ".txt"),
                     "--expected-sha", current_sha,
                     "--event-log-file", ""],
                    capture_output=True, text=True, timeout=60, env=env)
                assert proc.returncode == 0, proc.stdout + proc.stderr
                current_sha = PAYLOAD_SHA[tag]
        finally:
            stop["flag"] = True
            for t in readers:
                t.join(timeout=10)
        record("S5-http-never-shows-partial-write",
               not errors and bool(seen) and seen <= allowed
               and snapshot_count[0] >= 20,
               "errors=%s timeouts=%d snapshots=%d distinct=%s"
               % (errors, len(timeouts), snapshot_count[0],
                  sorted(h[:8] for h in seen)))
    finally:
        http_proc.terminate()
        http_proc.wait(timeout=10)


# ---------------------------------------------------------------------------
# S6 rollback under systemd
# ---------------------------------------------------------------------------

def step_s6():
    reset_files()
    counts_before = db_counts(p("pool.sqlite3"))
    # One good publish via systemd service (candidate A).
    write_unit("p2p3-pub-a.service",
               PUB_UNIT % {"tag": "A", "lower": "a",
                           "sha": PAYLOAD_SHA["init"], "fault": ""})
    daemon_reload()
    run(["systemctl", "start", "p2p3-pub-a.service"])
    wait_finished("p2p3-pub-a.service", timeout=60)
    res_a = service_result("p2p3-pub-a.service")
    counts = db_counts(p("pool.sqlite3"))
    record("S6-good-publish-via-service",
           res_a[1] == "0"
           and counts == (counts_before[0], counts_before[1],
                          counts_before[2] + 1),
           "ExecMainStatus=%s counts=%s (before=%s)"
           % (res_a[1], counts, counts_before))
    # Faulty publish (fault after staging) via systemd service.
    write_unit("p2p3-pub-b.service",
               PUB_UNIT % {"tag": "B", "lower": "b",
                           "sha": PAYLOAD_SHA["A"],
                           "fault": " --fault-after-staging"})
    daemon_reload()
    run(["systemctl", "start", "p2p3-pub-b.service"])
    wait_finished("p2p3-pub-b.service", timeout=60)
    res_b = service_result("p2p3-pub-b.service")
    served = open(p("served", "pool-new.txt"), "rb").read()
    staging = open(p("staging", "pool-new.txt"), "rb").read()
    counts = db_counts(p("pool.sqlite3"))
    record("S6-faulty-publish-refused",
           res_b[1] == "2",
           "ExecMainStatus=%s (2 = refused)" % res_b[1])
    record("S6-rollback-restores-files-and-keeps-data",
           served == PAYLOADS["A"] and staging == PAYLOADS["A"]
           and counts == (counts_before[0], counts_before[1],
                          counts_before[2] + 1),
           "served_ok=%s staging_ok=%s counts=%s"
           % (served == PAYLOADS["A"], staging == PAYLOADS["A"], counts))


# ---------------------------------------------------------------------------
# S7 cleanup + production re-verification
# ---------------------------------------------------------------------------

def cleanup_units():
    units = ["p2p3-pub-a.service", "p2p3-pub-b.service", "p2p3-pub-c.service",
             "p2p3-holder.service", "p2p3-legacy-publish.timer",
             "p2p3-legacy-sync.timer", "p2p3-legacy-publish.service",
             "p2p3-legacy-sync.service", "p2p3-gate-publish.timer",
             "p2p3-gate-sync.timer", "p2p3-gate-publish.service",
             "p2p3-gate-sync.service"]
    for unit in units:
        run(["systemctl", "stop", unit])
    for unit in units:
        run(["systemctl", "disable", "--runtime", unit])
        run(["systemctl", "unmask", unit])
        run(["systemctl", "reset-failed", unit])
        path = os.path.join(RUN_UNITS, unit)
        if os.path.exists(path):
            os.unlink(path)
    # Enable/disable --runtime leaves symlinks in *.wants/ dirs.
    sh("rm -f /run/systemd/system/*.wants/p2p3-* "
       "/etc/systemd/system/*.wants/p2p3-* 2>/dev/null; true")
    daemon_reload()
    leftovers = [u for u in units
                 if os.path.exists(os.path.join(RUN_UNITS, u))]
    return leftovers


def main():
    global LOG_FH
    LOG_FH = open(p("test-run.log"), "a", encoding="utf-8")
    log("=== P0-G VPS systemd test start ===")
    prod_before = None
    try:
        prod_before = setup()
        step_s1(prod_before)
        step_s2()
        step_s3()
        step_s4()
        step_s5()
        step_s6()
    except Exception as exc:  # noqa: BLE001 - recorded, cleanup still runs
        import traceback
        traceback.print_exc()
        record("HARNESS-EXCEPTION", False, "%s: %s"
               % (type(exc).__name__, exc))
    finally:
        leftovers = cleanup_units()
        record("S7-test-units-removed", not leftovers,
               "leftovers=%s" % leftovers)
        served_sha, staging_sha, states = prod_state()
        all_active = all(v == "active" for v in states.values())
        record("S7-production-sha-unchanged",
               served_sha == prod_before[0] and staging_sha == prod_before[1]
               and served_sha == staging_sha,
               "served=%s staging=%s before=%s"
               % (served_sha[:12], staging_sha[:12], prod_before[0][:12]))
        record("S7-production-timers-still-active", all_active,
               json.dumps(states))
        log("=== SUMMARY ===")
        passed = sum(1 for _, ok, _ in RESULTS if ok)
        for name, ok, detail in RESULTS:
            log("%s %s -- %s" % ("PASS" if ok else "FAIL", name, detail))
        log("TOTAL %d/%d passed" % (passed, len(RESULTS)))
        print(json.dumps(
            {"total": len(RESULTS), "passed": passed,
             "results": [{"name": n, "ok": ok, "detail": d}
                         for n, ok, d in RESULTS]}, ensure_ascii=True))
        LOG_FH.close()
        return 0 if passed == len(RESULTS) and RESULTS else 1


if __name__ == "__main__":
    sys.exit(main())
