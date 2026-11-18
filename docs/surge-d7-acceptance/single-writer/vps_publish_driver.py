#!/usr/bin/env python3
"""VPS driver for the single-writer systemd tests (task G).

Runs on the VPS inside /opt/p2p3-single-writer/ only. It wires the
verbatim PR #80 guard and the ban proof to ISOLATION-named units
(p2p3-gate-*) via environment variables, so the real guard logic and
the real flock critical section are exercised under real systemd
services without ever touching the production timers (which keep
running, and whose guard therefore keeps refusing -- as expected).

Modes:
  publish --candidate-file F --expected-sha SHA --event-log-file F
      [--fault-after-staging]
      Runs single_writer.publish() with the isolation gate and writes
      the lock event log (lock_acquired / published / lock_released,
      monotonic timestamps) as JSON lines for overlap analysis.
  hold --hold-seconds N --pid-file F
      Acquires the same lock and holds it (for the SIGKILL test).

Environment:
  SINGLE_WRITER_GATE_TIMERS   comma-separated timer units (default:
                              p2p3-gate-publish.timer,p2p3-gate-sync.timer)
  SINGLE_WRITER_GATE_SERVICES comma-separated service units (default:
                              p2p3-gate-publish.service,p2p3-gate-sync.service)
  SINGLE_WRITER_BASE          base dir (default /opt/p2p3-single-writer)

Exit codes: 0 published, 2 publish refused (fail-closed), 1 error.
"""

import importlib.util
import json
import os
import sys
import time

BASE = os.environ.get("SINGLE_WRITER_BASE", "/opt/p2p3-single-writer")
_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sw = _load("single_writer", os.path.join(_HERE, "single_writer.py"))
guard = _load("legacy_writer_guard",
              os.path.join(_HERE, "legacy-writer-guard.py"))

GATE_TIMERS = tuple(
    u for u in os.environ.get(
        "SINGLE_WRITER_GATE_TIMERS",
        "p2p3-gate-publish.timer,p2p3-gate-sync.timer").split(",") if u)
GATE_SERVICES = tuple(
    u for u in os.environ.get(
        "SINGLE_WRITER_GATE_SERVICES",
        "p2p3-gate-publish.service,p2p3-gate-sync.service").split(",")
    if u)


def gate_guard_check():
    """The verbatim PR #80 guard logic, pointed at isolation units.

    guard.check() reads the module globals TIMERS / SERVICES, so
    pointing it at the isolation units exercises the identical code
    path (same checks, same fail-closed reasons) without touching
    production units.
    """
    guard.TIMERS = GATE_TIMERS
    guard.SERVICES = GATE_SERVICES
    return guard.check()


def gate_ban_proof():
    # Default chain (services masked): the strongest bar. The amended
    # guard accepts masked services, so mask and guard pass together.
    return sw.legacy_ban_proof(timers=GATE_TIMERS, services=GATE_SERVICES)


def paths():
    return {
        "lock": os.path.join(BASE, "lock", "pool.lock"),
        "served": os.path.join(BASE, "served", "pool-new.txt"),
        "staging": os.path.join(BASE, "staging", "pool-new.txt"),
        "db": os.path.join(BASE, "pool.sqlite3"),
    }


def do_publish(args):
    p = paths()
    with open(args.candidate_file, "rb") as fh:
        candidate = fh.read()
    events = []
    try:
        receipt = sw.publish(
            lock_path=p["lock"], served_path=p["served"],
            staging_path=p["staging"], candidate_bytes=candidate,
            expected_current_sha=args.expected_sha, db_path=p["db"],
            guard_check=gate_guard_check, ban_proof_fn=gate_ban_proof,
            stop_check=lambda: False, lock_timeout=30.0,
            fault_after_staging=args.fault_after_staging,
            event_log=events)
    except sw.PublishRefused as exc:
        _write_events(args.event_log_file, events, refused=exc.reason)
        print(json.dumps({"ok": False, "reason": exc.reason,
                          "subject": exc.subject}, ensure_ascii=True))
        return 2
    except RuntimeError as exc:
        # The injected test fault (fault_after_staging) raises inside
        # publish() after its own rollback; surface it as a refusal
        # (exit 2, "no publish happened") rather than a crash (exit 1),
        # so the service exit code carries the same meaning as a
        # PublishRefused. Any other unexpected error still exits 1.
        if "injected_fault_after_staging" in str(exc):
            _write_events(args.event_log_file, events,
                          refused="injected_fault_after_staging")
            print(json.dumps({"ok": False,
                              "reason": "injected_fault_after_staging",
                              "subject": "staging"}, ensure_ascii=True))
            return 2
        raise
    _write_events(args.event_log_file, events)
    print(json.dumps(receipt, ensure_ascii=True))
    return 0


def _write_events(path, events, refused=None):
    if not path:
        return
    with open(path, "a", encoding="utf-8") as fh:
        for event, ts in events:
            fh.write(json.dumps({"event": event, "ts": ts,
                                 "pid": os.getpid(),
                                 "refused": refused}) + "\n")


def do_hold(args):
    p = paths()
    lock = sw.SingleWriterLock(p["lock"], timeout=30.0)
    lock.acquire()
    try:
        with open(args.pid_file, "w", encoding="utf-8") as fh:
            fh.write("%d\n" % os.getpid())
        print(json.dumps({"holding": True, "pid": os.getpid()}),
              flush=True)
        time.sleep(args.hold_seconds)
    finally:
        lock.release()
    return 0


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description="VPS single-writer driver")
    sub = parser.add_subparsers(dest="mode", required=True)
    pub = sub.add_parser("publish")
    pub.add_argument("--candidate-file", required=True)
    pub.add_argument("--expected-sha", required=True)
    pub.add_argument("--event-log-file", default="")
    pub.add_argument("--fault-after-staging", action="store_true")
    hold = sub.add_parser("hold")
    hold.add_argument("--hold-seconds", type=float, default=60.0)
    hold.add_argument("--pid-file", required=True)
    args = parser.parse_args(argv)
    if args.mode == "publish":
        return do_publish(args)
    return do_hold(args)


if __name__ == "__main__":
    sys.exit(main())
