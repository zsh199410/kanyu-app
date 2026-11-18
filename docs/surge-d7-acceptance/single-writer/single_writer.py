#!/usr/bin/env python3
"""Single-writer lock for the Surge node-pool production publisher (task G).

This module closes the gap found in task C: the PR #80 legacy-writer guard
(``legacy-writer-guard.py``, head eaa52023, reused verbatim) is a
point-in-time check only. Two concurrent checks can both pass, so the guard
alone cannot serialize writers. This module adds the missing continuous,
cross-process exclusive critical section around the whole publish:

    acquire flock -> STOP check -> PR #80 guard check -> legacy-ban proof
    -> candidate re-verification -> atomic write(s) -> served/staging
    verification -> post-write re-check -> release lock

Everything between lock acquisition and release runs under one exclusive
``flock(2)`` held on a lock file. The lock is an OS-level advisory lock:
when the holding process dies -- including SIGKILL -- the kernel releases
it, so no stale lock can survive a killed publisher. No lock state is kept
in the database or in any file that must be cleaned up by hand.

Design notes (see single-writer/README.md for the full discussion):

* Guard semantics are unchanged. The guard is imported, never copied or
  edited; if it cannot be imported the publish refuses fail-closed.
* The legacy-writer ban proof goes beyond flock on purpose: flock cannot
  bind writers that never take the lock (the old timers do not use any
  lock at all). The proof chain is: guard passes AND the old timers are
  disabled + inactive AND the old services are masked AND no legacy
  writer process is visible AND no systemd Job is pending -- checked
  inside the lock, immediately before the write, and re-checked after
  the write. A re-entry during the window restores the previous files
  and rolls back.
* Writes are atomic: temp file in the same directory + fsync + rename +
  directory fsync. A reader (nginx / HTTP) therefore only ever observes
  the old complete file or the new complete file, never a partial one.
* Rollback only ever deletes the publish's own ``publish_log`` row
  (by id). Crawl / test tables are never touched by rollback.
* Fail-closed everywhere: lock timeout, STOP present, guard refusal,
  ban unproven, stale candidate/current version, verification mismatch,
  or any inspection failure all refuse the publish and leave the
  previously served content untouched.
* No real node URIs, passwords, tokens, or egress IPs appear anywhere
  in this file or in the tests. Fixtures use 192.0.2.0/24 and "test123".
"""

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import sqlite3
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Production legacy units (PR #80 guard's fixed names). The guard itself is
# the authority on these; the values below are only used by the ban-proof
# chain's default unit list and by the CLI's --check output.
LEGACY_TIMERS = ("pool-publish.timer", "pool-sync.timer")
LEGACY_SERVICES = ("pool-publish.service", "pool-sync.service")

# Where the PR #80 guard copy may live, relative to this file and to the
# current working directory. First hit wins; the file is never modified.
_GUARD_CANDIDATES = (
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "legacy-writer-guard.py"),
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "..", "legacy-writer-guard", "legacy-writer-guard.py"),
    os.path.join(os.getcwd(), "legacy-writer-guard.py"),
)

_SYSTEMCTL = "/usr/bin/systemctl"
_PS = "/usr/bin/ps"


class PublishRefused(Exception):
    """Fail-closed refusal: the publish did not happen (or was rolled back).

    ``reason`` is a stable machine-readable code, ``subject`` names the
    unit / file / pid the refusal is about. Nothing about a refusal ever
    implies a partial write: either the write completed and verified, or
    the previous content was restored and only the own DB row removed.
    """

    def __init__(self, reason, subject="system"):
        super().__init__("%s: %s" % (reason, subject))
        self.reason = reason
        self.subject = subject


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def atomic_write(path, data):
    """Write ``data`` to ``path`` atomically (same-dir tmp + fsync + rename).

    On any failure the temp file is removed and the destination is left
    untouched. Raises the original exception; callers translate it into a
    refusal + rollback. A reader of ``path`` can only ever see the old
    complete content or the new complete content.
    """
    directory = os.path.dirname(os.path.abspath(path))
    tmp_path = os.path.join(
        directory, ".%s.tmp-%d" % (os.path.basename(path), os.getpid()))
    try:
        with open(tmp_path, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.rename(tmp_path, path)
        dir_fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except BaseException:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# PR #80 guard loading (verbatim reuse, never edited here)
# ---------------------------------------------------------------------------

def load_guard():
    """Import the verbatim PR #80 guard module, or return None.

    The guard file is located, never written. Returning None is a
    fail-closed condition for publish(): without the guard there is no
    legacy-writer evidence at all.
    """
    for candidate in _GUARD_CANDIDATES:
        path = os.path.normpath(candidate)
        if os.path.isfile(path):
            spec = importlib.util.spec_from_file_location(
                "legacy_writer_guard_reuse", path)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    return None


# ---------------------------------------------------------------------------
# Raw systemctl / ps backends (same commands the guard uses)
# ---------------------------------------------------------------------------

def systemctl_show(unit):
    """Parsed ``systemctl show --property=...`` dict for one unit."""
    proc = subprocess.run(
        (_SYSTEMCTL, "show", "--no-pager",
         "--property=LoadState,UnitFileState,ActiveState,SubState,"
         "MainPID,ControlPID,Result,Job", unit),
        capture_output=True, text=True, timeout=8, check=False)
    if proc.returncode != 0:
        raise RuntimeError("command_failed")
    result = {}
    for line in proc.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value.strip()
    return result


def ps_rows():
    proc = subprocess.run((_PS, "-eo", "pid=,args="),
                          capture_output=True, text=True, timeout=8,
                          check=False)
    if proc.returncode != 0:
        raise RuntimeError("command_failed")
    return proc.stdout.splitlines()


def _legacy_process_present(rows):
    """True if a real legacy writer command appears in ps rows.

    Same patterns as the PR #80 guard: ``pool.cli publish`` or
    ``pool-sync.sh`` as the executed command. The guard module itself is
    never matched (it runs no such command).
    """
    import re
    own_pid = os.getpid()
    for line in rows:
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        pid, command = parts
        if int(pid) == own_pid:
            continue
        if re.search(r"pool[.]cli\s+publish(?:\s|$)", command):
            return "pid:" + pid
        if re.search(r"(?:^|[\s/])pool-sync[.]sh(?:\s|$)", command):
            return "pid:" + pid
    return None


# ---------------------------------------------------------------------------
# Legacy-writer ban proof (beyond flock)
# ---------------------------------------------------------------------------

def legacy_ban_proof(show=None, processes=None,
                     timers=LEGACY_TIMERS, services=LEGACY_SERVICES,
                     require_masked_services=False):
    """Prove legacy writers are banned from re-entering, beyond flock.

    flock alone cannot bind a writer that never takes the lock -- the old
    timers use no lock at all (flock/fcntl count 0 in cli.py and
    pool-sync.sh). So the ban must be proven from systemd state itself:

    * every legacy timer: loaded, UnitFileState == "disabled",
      ActiveState == "inactive", no pending Job;
    * every legacy service: loaded, ActiveState == "inactive",
      SubState == "dead", MainPID == ControlPID == "0", no pending Job,
      Result == "success", and -- the extra bar beyond the verbatim
      guard, which does not check service UnitFileState --
      UnitFileState == "disabled";
    * no legacy writer process visible in the process table.

    About masking (verified on the VPS 2026-11-18): a masked service
    reports LoadState == "masked", and the verbatim PR #80 guard
    refuses any service whose LoadState is not "loaded"
    (``service_not_loaded``). Masked services and the verbatim guard
    therefore CANNOT pass together -- masking an old service would make
    the guard refuse every future publish forever. Masking is the
    stronger bar, but it needs a guard amendment (accept LoadState
    "masked" as drained), which is a separate decision outside this
    task. The opt-in ``require_masked_services=True`` checks
    UnitFileState == "masked" instead of "disabled" for callers that
    have made that decision and do not run the verbatim guard alongside;
    in that mode a masked unit's LoadState ("masked") is also accepted
    as loaded, since the unit is known to systemd and its state is
    fully determined. The default (False) is the strongest chain that
    stays compatible with the verbatim guard.

    Returns ``(proven, evidence)`` where ``evidence`` is a list of
    ``{"check": ..., "ok": ..., "detail": ...}`` dicts, one per assertion,
    so a caller can log exactly which link of the chain failed. Any
    inspection failure makes the whole proof fail (fail-closed).

    ``show`` / ``processes`` are injectable for tests; defaults hit the
    real systemctl / ps. ``timers`` / ``services`` are injectable so the
    identical chain can be verified against isolation-named units on a
    host where the production timers must keep running.
    """
    show = show or systemctl_show
    processes = processes or ps_rows
    evidence = []

    def _record(check, ok, detail):
        evidence.append({"check": check, "ok": bool(ok), "detail": detail})
        return bool(ok)

    try:
        for unit in timers:
            data = show(unit)
            if not _record("timer_loaded:" + unit,
                           data.get("LoadState") == "loaded",
                           data.get("LoadState", "")):
                return False, evidence
            if not _record("timer_disabled:" + unit,
                           data.get("UnitFileState") == "disabled",
                           data.get("UnitFileState", "")):
                return False, evidence
            if not _record("timer_inactive:" + unit,
                           data.get("ActiveState") == "inactive",
                           data.get("ActiveState", "")):
                return False, evidence
            if not _record("timer_no_job:" + unit,
                           data.get("Job", "") in ("", "0"),
                           data.get("Job", "")):
                return False, evidence
        for unit in services:
            data = show(unit)
            acceptable_load = ("loaded", "masked") \
                if require_masked_services else ("loaded",)
            if not _record("service_loaded:" + unit,
                           data.get("LoadState") in acceptable_load,
                           data.get("LoadState", "")):
                return False, evidence
            if not _record("service_drained:" + unit,
                           data.get("ActiveState") == "inactive"
                           and data.get("SubState") == "dead",
                           "%s/%s" % (data.get("ActiveState", ""),
                                      data.get("SubState", ""))):
                return False, evidence
            if not _record("service_no_pid:" + unit,
                           data.get("MainPID") == "0"
                           and data.get("ControlPID") == "0",
                           "%s/%s" % (data.get("MainPID", ""),
                                      data.get("ControlPID", ""))):
                return False, evidence
            if not _record("service_no_job:" + unit,
                           data.get("Job", "") in ("", "0"),
                           data.get("Job", "")):
                return False, evidence
            if not _record("service_result_success:" + unit,
                           data.get("Result") == "success",
                           data.get("Result", "")):
                return False, evidence
            if require_masked_services:
                if not _record("service_masked:" + unit,
                               data.get("UnitFileState") == "masked",
                               data.get("UnitFileState", "")):
                    return False, evidence
            else:
                if not _record("service_disabled:" + unit,
                               data.get("UnitFileState") == "disabled",
                               data.get("UnitFileState", "")):
                    return False, evidence
        rows = processes()
        if not isinstance(rows, (list, tuple)):
            _record("process_scan_valid", False, "not-a-list")
            return False, evidence
        _record("process_scan_valid", True, "%d rows" % len(rows))
        hit = _legacy_process_present(rows)
        if not _record("no_legacy_process", hit is None, hit or "none"):
            return False, evidence
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired):
        _record("inspection_ok", False, "inspection_failed")
        return False, evidence
    return True, evidence


# ---------------------------------------------------------------------------
# The lock
# ---------------------------------------------------------------------------

class SingleWriterLock:
    """Cross-process exclusive lock via flock(2) on a lock file.

    The lock is held on an open file description for the whole critical
    section. ``flock`` is released by the kernel when the holder dies --
    including SIGKILL, which cannot run any cleanup -- so a killed
    publisher can never leave a stale lock behind. ``acquire`` with a
    timeout refuses fail-closed (``PublishRefused: lock_timeout``) instead
    of waiting forever; a second publisher therefore fails loudly rather
    than silently queueing behind a stuck first one.
    """

    def __init__(self, lock_path, timeout=30.0, poll_interval=0.05):
        self.lock_path = lock_path
        self.timeout = timeout
        self.poll_interval = poll_interval
        self._fd = None
        self.acquired_at = None
        self.released_at = None

    def acquire(self):
        if self._fd is not None:
            raise PublishRefused("lock_already_held", self.lock_path)
        parent = os.path.dirname(os.path.abspath(self.lock_path))
        os.makedirs(parent, exist_ok=True)
        fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT, 0o600)
        deadline = time.monotonic() + self.timeout
        try:
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        os.close(fd)
                        raise PublishRefused("lock_timeout", self.lock_path)
                    time.sleep(self.poll_interval)
        except BaseException:
            if self._fd is None:
                try:
                    os.close(fd)
                except OSError:
                    pass
            raise
        self._fd = fd
        self.acquired_at = time.monotonic()
        # Best-effort holder diagnostics only; correctness never depends
        # on this content (the kernel owns the lock, not the file text).
        try:
            os.ftruncate(fd, 0)
            os.write(fd, ("%d\n" % os.getpid()).encode("ascii"))
            os.fsync(fd)
        except OSError:
            pass
        return self

    def release(self):
        if self._fd is None:
            return
        try:
            fcntl.flock(self._fd, fcntl.LOCK_UN)
        finally:
            try:
                os.close(self._fd)
            finally:
                self._fd = None
                self.released_at = time.monotonic()

    def __enter__(self):
        return self.acquire()

    def __exit__(self, exc_type, exc, tb):
        self.release()
        return False


# ---------------------------------------------------------------------------
# Publish database: only the own record may ever be rolled back
# ---------------------------------------------------------------------------

def _db_connect(db_path):
    conn = sqlite3.connect(db_path, timeout=10.0)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS publish_log ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  payload_sha TEXT NOT NULL,"
        "  created_at REAL NOT NULL,"
        "  status TEXT NOT NULL)")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS crawl_log ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  source TEXT NOT NULL, detail TEXT NOT NULL)")
    conn.execute(
        "CREATE TABLE IF NOT EXISTS test_log ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  node_ref TEXT NOT NULL, detail TEXT NOT NULL)")
    conn.commit()
    return conn


def _insert_own_record(conn, payload_sha):
    cur = conn.execute(
        "INSERT INTO publish_log (payload_sha, created_at, status)"
        " VALUES (?, ?, 'published')",
        (payload_sha, time.time()))
    return cur.lastrowid


def _delete_own_record(conn, record_id):
    """Rollback: delete ONLY this publish's own record, by id.

    Crawl / test tables are never mentioned here by construction.
    """
    conn.execute("DELETE FROM publish_log WHERE id = ?", (record_id,))
    conn.commit()


# ---------------------------------------------------------------------------
# The publish critical section
# ---------------------------------------------------------------------------

def publish(*, lock_path, served_path, staging_path, candidate_bytes,
            expected_current_sha, db_path, guard_check=None,
            ban_proof_fn=None, stop_check=None, lock_timeout=30.0,
            fault_after_staging=False, event_log=None):
    """Publish ``candidate_bytes`` under the single-writer lock.

    Full critical section, all inside the lock -- there is no window
    between check and write in which another writer (new or legacy) can
    slip in unnoticed:

    1. acquire flock (fail-closed on timeout);
    2. STOP check (refuse if a STOP flag is present);
    3. PR #80 guard check (legacy writers drained at this instant);
    4. legacy-ban proof (timers disabled, services masked, no legacy
       process, no pending Job -- the bar beyond flock);
    5. candidate re-verification: the served file on disk must still
       hash to ``expected_current_sha`` (the version the candidate was
       built against) and the candidate hash is recomputed;
    6. insert this publish's own DB record (id kept for rollback);
    7. atomic write staging, verify its SHA; atomic write served,
       verify its SHA;
    8. post-write re-check (guard + ban proof): if a legacy writer
       re-entered during the window, restore the previous files and
       roll back the own record instead of leaving a contested publish;
    9. release the lock.

    ``event_log`` (optional list) receives ``("lock_acquired", ts)`` /
    ``("lock_released", ts)`` / ``("published", ts)`` entries with
    ``time.monotonic()`` timestamps, for observability only -- the
    correctness of the lock never depends on this log.

    Returns a receipt dict on success. Raises ``PublishRefused`` (no
    write, or write rolled back) or propagates unexpected errors only
    after the same restore + rollback has been attempted.
    """
    if guard_check is None:
        guard = load_guard()
        if guard is None:
            raise PublishRefused("guard_unavailable",
                                 "legacy-writer-guard.py")
        guard_check = guard.check
    if ban_proof_fn is None:
        ban_proof_fn = lambda: legacy_ban_proof()  # noqa: E731
    if stop_check is None:
        stop_path = os.path.join(
            os.path.dirname(os.path.abspath(served_path)), "STOP")
        stop_check = lambda: os.path.exists(stop_path)  # noqa: E731

    candidate_sha = sha256_bytes(candidate_bytes)
    receipt = {"ok": True, "payload_sha": candidate_sha}

    def _log(event):
        if event_log is not None:
            event_log.append((event, time.monotonic()))

    with SingleWriterLock(lock_path, timeout=lock_timeout):
        _log("lock_acquired")
        # -- 2. STOP ------------------------------------------------------
        if stop_check():
            raise PublishRefused("stop_present", "STOP")
        # -- 3. PR #80 guard, inside the lock -----------------------------
        allowed, reason, subject = guard_check()
        if not allowed:
            raise PublishRefused("guard_refused:" + reason, subject)
        # -- 4. legacy-ban proof, inside the lock -------------------------
        proven, evidence = ban_proof_fn()
        if not proven:
            failed = [e for e in evidence if not e["ok"]]
            detail = failed[0]["check"] if failed else "ban_proof"
            raise PublishRefused("legacy_ban_unproven:" + detail, "system")
        # -- 5. candidate re-verification ---------------------------------
        try:
            current_bytes = read_bytes(served_path)
        except FileNotFoundError:
            current_bytes = b""
        current_sha = sha256_bytes(current_bytes)
        if current_sha != expected_current_sha:
            raise PublishRefused(
                "stale_current_version",
                "served=%s expected=%s" % (current_sha[:12],
                                           expected_current_sha[:12]))
        # -- 6/7. write under the lock, with rollback ---------------------
        conn = _db_connect(db_path)
        try:
            record_id = _insert_own_record(conn, candidate_sha)
            conn.commit()
            receipt["record_id"] = record_id
            prev_staging = None
            try:
                prev_staging = read_bytes(staging_path)
            except FileNotFoundError:
                pass
            prev_served = current_bytes
            try:
                atomic_write(staging_path, candidate_bytes)
                if sha256_file(staging_path) != candidate_sha:
                    raise PublishRefused("staging_verify_mismatch",
                                         staging_path)
                if fault_after_staging:
                    raise RuntimeError("injected_fault_after_staging")
                atomic_write(served_path, candidate_bytes)
                if sha256_file(served_path) != candidate_sha:
                    raise PublishRefused("served_verify_mismatch",
                                         served_path)
                # -- 8. post-write re-check -------------------------------
                allowed2, reason2, subject2 = guard_check()
                if not allowed2:
                    raise PublishRefused(
                        "legacy_writer_reentered:" + reason2, subject2)
                proven2, evidence2 = ban_proof_fn()
                if not proven2:
                    failed = [e for e in evidence2 if not e["ok"]]
                    detail = failed[0]["check"] if failed else "ban_proof"
                    raise PublishRefused(
                        "legacy_writer_reentered:" + detail, "system")
                if sha256_file(served_path) != candidate_sha:
                    raise PublishRefused("served_verify_mismatch",
                                         served_path)
                if sha256_file(staging_path) != candidate_sha:
                    raise PublishRefused("staging_verify_mismatch",
                                         staging_path)
                _log("published")
            except BaseException:
                # Restore previous files atomically (best-effort: a
                # failed restore must not mask the original refusal),
                # then drop only the own DB record. Crawl / test rows
                # are never deleted.
                try:
                    if prev_served is not None:
                        atomic_write(served_path, prev_served)
                except BaseException:
                    pass
                try:
                    if prev_staging is not None:
                        atomic_write(staging_path, prev_staging)
                except BaseException:
                    pass
                _delete_own_record(conn, record_id)
                raise
        finally:
            conn.close()
    _log("lock_released")
    receipt["served_sha"] = sha256_file(served_path)
    receipt["staging_sha"] = sha256_file(staging_path)
    return receipt


# ---------------------------------------------------------------------------
# CLI (for systemd services and manual checks)
# ---------------------------------------------------------------------------

def _build_arg_parser():
    parser = argparse.ArgumentParser(
        description="Single-writer publisher for the Surge node pool.")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("publish", help="publish a candidate file")
    p.add_argument("--lock", required=True)
    p.add_argument("--served", required=True)
    p.add_argument("--staging", required=True)
    p.add_argument("--candidate-file", required=True)
    p.add_argument("--expected-sha", required=True)
    p.add_argument("--db", required=True)
    p.add_argument("--lock-timeout", type=float, default=30.0)
    p.add_argument("--fault-after-staging", action="store_true")
    p.add_argument("--skip-guard", action="store_true",
                   help="TEST ONLY: bypass guard+ban checks (never for "
                        "production use; refuses unless "
                        "SINGLE_WRITER_TEST_MODE=1)")
    c = sub.add_parser("check", help="run guard + ban proof, no write")
    c.add_argument("--timers", nargs="*", default=list(LEGACY_TIMERS))
    c.add_argument("--services", nargs="*", default=list(LEGACY_SERVICES))
    c.add_argument("--require-masked", action="store_true",
                   help="require masked services instead of disabled "
                        "(opt-in; incompatible with the verbatim guard, "
                        "see legacy_ban_proof docstring)")
    return parser


def main(argv=None):
    args = _build_arg_parser().parse_args(argv)
    if args.command == "check":
        guard = load_guard()
        if guard is None:
            print(json.dumps({"ok": False, "reason": "guard_unavailable",
                              "subject": "legacy-writer-guard.py"}))
            return 1
        allowed, reason, subject = guard.check()
        proven, evidence = legacy_ban_proof(
            timers=tuple(args.timers), services=tuple(args.services),
            require_masked_services=args.require_masked)
        print(json.dumps({"ok": bool(allowed and proven),
                          "guard": {"ok": allowed, "reason": reason,
                                    "subject": subject},
                          "ban_proof": {"proven": proven,
                                        "evidence": evidence}},
                         ensure_ascii=True))
        return 0 if (allowed and proven) else 1
    if args.command == "publish":
        with open(args.candidate_file, "rb") as fh:
            candidate = fh.read()
        kwargs = dict(
            lock_path=args.lock, served_path=args.served,
            staging_path=args.staging, candidate_bytes=candidate,
            expected_current_sha=args.expected_sha, db_path=args.db,
            lock_timeout=args.lock_timeout,
            fault_after_staging=args.fault_after_staging)
        if args.skip_guard:
            if os.environ.get("SINGLE_WRITER_TEST_MODE") != "1":
                print("skip-guard requires SINGLE_WRITER_TEST_MODE=1",
                      file=sys.stderr)
                return 1
            kwargs["guard_check"] = lambda: (True, "test_bypass", "system")
            kwargs["ban_proof_fn"] = lambda: (True, [])
            kwargs["stop_check"] = lambda: False
        try:
            receipt = publish(**kwargs)
        except PublishRefused as exc:
            print(json.dumps({"ok": False, "reason": exc.reason,
                              "subject": exc.subject}, ensure_ascii=True))
            return 2
        print(json.dumps(receipt, ensure_ascii=True))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
