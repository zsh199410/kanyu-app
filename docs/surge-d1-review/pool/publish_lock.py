"""D1 isolation: shared flock publish lock + timestamped snapshots + 8-step rollback.

D1 builds on D0 (/opt/p2p3-d0/pool/publish_lock.py, copied verbatim, SHA256
02e840513ff686d1ac00ba64ec4aea80136bc1faaace6c3eb924a5a51b44ab98) for GPT
Issue #73 decision 6875033415 item 4: publish and sync MUST share one
flock, pinned has NO exemption, and the gate MUST span publish / sync /
rollback. "Atomic rename alone" is not accepted as a substitute for
mutual exclusion and gating.

D1 changes over D0 (all inside this file, marked D1):
  1. _atomic_write_inner(): the lock-free inner write (snapshot + tmp +
     fsync + rename + verify) so publish / sync / rollback can all run
     their gate checks INSIDE one held lock (no TOCTOU between gate and
     write). atomic_publish_locked() now wraps it.
  2. Snapshot sidecar meta: every snapshot and every published file gets
     a .meta.json sidecar carrying its source_version_sha (the
     subscription version the native evidence was measured on), so a
     rollback target can be gate-checked against the native record for
     ITS OWN version.
  3. write_version_meta() / read_version_meta() helpers for those sidecars.

This module never touches production paths by itself: every path is passed
in by the caller, and the drill defaults all live under /opt/p2p3-d1/.

Design (from safe_state_and_lock_plan.md section 2 + GPT 6875033415 item 4):
  1. One flock file lock shared by publish / sync / rollback. Acquired with
     fcntl.flock, non-blocking retries + timeout, owner record (pid, owner
     name, acquired_at) written into the lock file while the lock is held.
     If the holder dies, the kernel releases the flock: the next acquirer
     proceeds (crash recovery is a property of flock, verified by drill).
  2. .prev protection: every publish first copies the current file to
     history/pool-new-<unix-ts>.txt and keeps the newest 3 snapshots, so a
     rollback anchor never depends on the single .prev file. .prev is still
     maintained for compatibility with production publish.rollback().
  3. Rollback is the plan's 8 steps, as code (see rollback_eight_steps).

Logging discipline: every log/record carries only line counts, SHA256
prefixes (first 12 hex), timestamps and step names. No node lines, hosts,
passwords, URIs, tokens or subscription URLs are ever written.
"""

import fcntl
import hashlib
import json
import os
import shutil
import time

HISTORY_KEEP_DEFAULT = 3
LOCK_TIMEOUT_DEFAULT = 30
SHA_PREFIX_LEN = 12


class LockTimeout(Exception):
    """Raised when the flock could not be acquired within the timeout."""


class PublishRefused(Exception):
    """Raised when a publish/rollback is refused fail-closed."""


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sha_prefix(path, n=SHA_PREFIX_LEN):
    try:
        return sha256_file(path)[:n]
    except OSError:
        return ""


def file_manifest(path):
    """Desensitised manifest of a publish file, or None if absent."""
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        data = f.read()
    lines = [l for l in data.decode("utf-8", errors="ignore").splitlines()
             if l.strip()]
    return {
        "exists": True,
        "lines": len(lines),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "sha_prefix": hashlib.sha256(data).hexdigest()[:SHA_PREFIX_LEN],
        "mtime": int(os.path.getmtime(path)),
    }


def _iso(ts=None):
    return time.strftime("%Y-%m-%d %H:%M:%S %Z", time.localtime(ts or time.time()))


class PublishLock:
    """One flock lock shared by publish / sync / rollback.

    Usage:
        with PublishLock(lock_path, owner="publish", timeout=30):
            ... critical section ...
    The lock file is never unlinked (unlinking a flock file while another
    process has it open creates two distinct locks). The owner record is
    written while the lock is held, so a stale-looking record always means
    "holder is alive or died holding it" -- and a dead holder's flock is
    released by the kernel, so the next acquirer simply overwrites it.
    """

    def __init__(self, lock_path, owner, timeout=LOCK_TIMEOUT_DEFAULT):
        self.lock_path = lock_path
        self.owner = owner
        self.timeout = timeout
        self.fd = None
        self.acquired_at = None

    def acquire(self):
        os.makedirs(os.path.dirname(self.lock_path) or ".", exist_ok=True)
        self.fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT, 0o600)
        deadline = time.time() + self.timeout
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() >= deadline:
                    os.close(self.fd)
                    self.fd = None
                    raise LockTimeout(
                        "lock busy after %.1fs: %s" % (self.timeout, self.lock_path))
                time.sleep(0.1)
        self.acquired_at = int(time.time())
        record = {
            "owner": self.owner,
            "pid": os.getpid(),
            "acquired_at": self.acquired_at,
            "acquired_at_iso": _iso(self.acquired_at),
        }
        os.ftruncate(self.fd, 0)
        os.lseek(self.fd, 0, os.SEEK_SET)
        os.write(self.fd, (json.dumps(record) + "\n").encode("utf-8"))
        os.fsync(self.fd)
        return self

    def release(self):
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            finally:
                os.close(self.fd)
                self.fd = None

    def owner_record(self):
        try:
            with open(self.lock_path) as f:
                return json.loads(f.read().strip() or "{}")
        except (OSError, ValueError):
            return {}

    def __enter__(self):
        return self.acquire()

    def __exit__(self, *exc):
        self.release()
        return False


def write_version_meta(publish_dir, filename, source_version_sha, extra=None):
    """D1: write a <file>.meta.json sidecar for the current publish file.

    Carries the source_version_sha the file's lines were gated against,
    so a later rollback can gate-check the anchor against the native
    record for ITS OWN version. Never contains node lines or secrets.
    Returns the sidecar path.
    """
    target = os.path.join(publish_dir, filename)
    meta = {
        "source_version_sha": source_version_sha,
        "manifest": file_manifest(target),
        "written_at": int(time.time()),
        "written_at_iso": _iso(),
    }
    if extra:
        meta.update(extra)
    sidecar = target + ".meta.json"
    with open(sidecar, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    try:
        os.chmod(sidecar, 0o600)
    except OSError:
        pass
    return sidecar


def read_version_meta(publish_dir, filename):
    """D1: read a <file>.meta.json sidecar, or None if absent/unparsable."""
    sidecar = os.path.join(publish_dir, filename) + ".meta.json"
    try:
        with open(sidecar, encoding="utf-8") as f:
            meta = json.load(f)
        if isinstance(meta, dict) and meta.get("source_version_sha"):
            return meta
    except (OSError, ValueError):
        pass
    return None


def snapshot_current(publish_dir, filename, keep=HISTORY_KEEP_DEFAULT,
                     source_version_sha=None):
    """Copy the current publish file to history/pool-new-<ts>.txt.

    Returns (snapshot_path, snapshot_manifest) or (None, None) when there
    is no current file yet. Prunes history to the newest `keep` snapshots.
    D1: when source_version_sha is given, a sidecar <snap>.meta.json is
    written so the snapshot stays gate-checkable after its .prev is gone.
    """
    target = os.path.join(publish_dir, filename)
    if not os.path.exists(target):
        return None, None
    hist_dir = os.path.join(publish_dir, "history")
    os.makedirs(hist_dir, exist_ok=True)
    ts = int(time.time())
    snap = os.path.join(hist_dir, "pool-new-%d.txt" % ts)
    n = 0
    while os.path.exists(snap):
        n += 1
        snap = os.path.join(hist_dir, "pool-new-%d-%d.txt" % (ts, n))
    shutil.copyfile(target, snap)
    os.chmod(snap, 0o600)
    if source_version_sha:
        meta = {
            "source_version_sha": source_version_sha,
            "manifest": file_manifest(snap),
            "written_at": int(time.time()),
            "written_at_iso": _iso(),
        }
        with open(snap + ".meta.json", "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        try:
            os.chmod(snap + ".meta.json", 0o600)
        except OSError:
            pass
    snaps = sorted(
        (os.path.join(hist_dir, f) for f in os.listdir(hist_dir)
         if f.startswith("pool-new-") and f.endswith(".txt")),
        key=lambda p: os.path.getmtime(p))
    pruned = []
    while len(snaps) > keep:
        victim = snaps.pop(0)
        try:
            os.unlink(victim)
            pruned.append(os.path.basename(victim))
            try:
                os.unlink(victim + ".meta.json")
            except OSError:
                pass
        except OSError:
            pass
    return snap, file_manifest(snap)


def _fsync_dir(path):
    try:
        dfd = os.open(path, os.O_DIRECTORY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except OSError:
        pass


def _atomic_write_inner(publish_dir, filename, lines, keep=HISTORY_KEEP_DEFAULT,
                        source_version_sha=None):
    """D1: lock-free inner write. CALLER MUST HOLD THE SHARED LOCK.

    Snapshot + tmp + fsync + rename + verify, identical to the body of
    the D0 atomic_publish_locked, but without acquiring the lock itself.
    This lets publish / sync / rollback run their gate checks INSIDE one
    held lock (no TOCTOU between gate evaluation and the write).
    When source_version_sha is given, the new file and the snapshot get
    .meta.json sidecars carrying it.
    Returns the same desensitised result dict as atomic_publish_locked
    (minus lock_owner, which the caller adds).
    """
    if not lines:
        raise PublishRefused("empty publish refused")
    expected = ("\n".join(lines) + "\n").encode("utf-8")
    expected_sha = hashlib.sha256(expected).hexdigest()
    os.makedirs(publish_dir, exist_ok=True)
    target = os.path.join(publish_dir, filename)
    prev = target + ".prev"
    tmp = target + ".tmp"
    # Snapshot the CURRENT file before overwriting, with its own version
    # meta (read from the current file's sidecar, if any).
    current_meta = read_version_meta(publish_dir, filename)
    snap_path, snap_manifest = snapshot_current(
        publish_dir, filename, keep=keep,
        source_version_sha=(current_meta or {}).get("source_version_sha"))
    prev_manifest_before = file_manifest(prev)
    with open(tmp, "w", encoding="utf-8") as f:
        for line in lines:
            f.write(line + "\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp, 0o600)
    if os.path.exists(target):
        shutil.copyfile(target, prev)
        try:
            os.chmod(prev, 0o600)
        except OSError:
            pass
        # .prev inherits the current file's version meta.
        if current_meta:
            with open(prev + ".meta.json", "w", encoding="utf-8") as f:
                json.dump(current_meta, f, ensure_ascii=False, indent=2)
            try:
                os.chmod(prev + ".meta.json", 0o600)
            except OSError:
                pass
    os.rename(tmp, target)
    _fsync_dir(publish_dir)
    got = file_manifest(target)
    if got is None or got["sha256"] != expected_sha or got["lines"] != len(lines):
        raise PublishRefused(
            "post-publish verification failed: lines=%s sha_prefix=%s"
            % (got["lines"] if got else None,
               got["sha_prefix"] if got else ""))
    if source_version_sha:
        write_version_meta(publish_dir, filename, source_version_sha)
    return {
        "ok": True,
        "target": target,
        "manifest": got,
        "snapshot_path": snap_path,
        "snapshot_manifest": snap_manifest,
        "prev_manifest_before": prev_manifest_before,
        "prev_manifest_after": file_manifest(prev),
    }


def atomic_publish_locked(publish_dir, filename, lines, lock_path,
                          owner="publish", timeout=LOCK_TIMEOUT_DEFAULT,
                          keep=HISTORY_KEEP_DEFAULT,
                          source_version_sha=None):
    """Publish under the shared lock, with snapshot + .prev + verification.

    Refuses empty input fail-closed (no file is written). Returns a
    desensitised result dict: new manifest, snapshot path/manifest, .prev
    manifest, lock owner. D1: delegates the write to _atomic_write_inner
    and accepts source_version_sha for the .meta.json sidecars.
    """
    with PublishLock(lock_path, owner=owner, timeout=timeout) as lock:
        result = _atomic_write_inner(
            publish_dir, filename, lines, keep=keep,
            source_version_sha=source_version_sha)
        result["lock_owner"] = lock.owner_record()
        return result


def rollback_eight_steps(publish_dir, filename, lock_path, owner="rollback",
                         sync_dir=None, timeout=LOCK_TIMEOUT_DEFAULT,
                         log_path=None):
    """The plan's 8 rollback steps, as code. Returns a desensitised result.

    Steps: 1 record bad manifest; 2 take the write lock; 3 restore from
    .prev, or the newest history snapshot if .prev is missing; 4 verify the
    restored file equals the anchor (SHA + lines); 5 sync (copy to sync_dir
    and verify SHA there, or record "pending next pool-sync cycle <=15 min
    or manual trigger"); 6 phone refresh is MANUAL (cannot be done from
    the VPS -- recorded as pending, never claimed done); 7 release the lock
    and write the rollback log; 8 if still bad, record "stop
    pool-publish.timer -- REQUIRES owner authorisation" (never executed
    here: stopping a production timer is a production change).
    """
    target = os.path.join(publish_dir, filename)
    prev = target + ".prev"
    steps = []
    result = {"ok": False, "steps": steps, "bad_manifest": file_manifest(target)}

    def _step(name, detail):
        steps.append({"step": name, "at": _iso(), "ts": int(time.time()),
                      "detail": detail})

    _step("1-record-bad-version",
          "bad lines=%s sha_prefix=%s" % (
              result["bad_manifest"]["lines"] if result["bad_manifest"] else None,
              result["bad_manifest"]["sha_prefix"] if result["bad_manifest"] else ""))
    lock = PublishLock(lock_path, owner=owner, timeout=timeout)
    try:
        lock.acquire()
    except LockTimeout as e:
        _step("2-acquire-write-lock", "FAILED: %s" % e)
        result["error"] = "lock_timeout"
        return result
    try:
        _step("2-acquire-write-lock",
              "held by %s pid=%s" % (owner, os.getpid()))
        anchor = None
        anchor_kind = None
        if os.path.exists(prev):
            anchor, anchor_kind = prev, ".prev"
        else:
            hist_dir = os.path.join(publish_dir, "history")
            if os.path.isdir(hist_dir):
                snaps = sorted(
                    (os.path.join(hist_dir, f) for f in os.listdir(hist_dir)
                     if f.startswith("pool-new-") and f.endswith(".txt")),
                    key=lambda p: os.path.getmtime(p))
                if snaps:
                    anchor, anchor_kind = snaps[-1], "history-snapshot"
        if anchor is None:
            _step("3-restore-anchor", "FAILED: no .prev and no history snapshot")
            result["error"] = "no_rollback_anchor"
            return result
        anchor_manifest = file_manifest(anchor)
        _step("3-restore-anchor",
              "anchor%s lines=%s sha_prefix=%s" % (
                   anchor_kind, anchor_manifest["lines"],
                  anchor_manifest["sha_prefix"]))
        tmp = target + ".tmp"
        shutil.copyfile(anchor, tmp)
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.rename(tmp, target)
        _fsync_dir(publish_dir)
        got = file_manifest(target)
        if (got is None or got["sha256"] != anchor_manifest["sha256"]
                or got["lines"] != anchor_manifest["lines"]):
            _step("4-verify-restored",
                  "FAILED: restored lines=%s sha_prefix=%s" % (
                      got["lines"] if got else None,
                      got["sha_prefix"] if got else ""))
            result["error"] = "rollback_verify_failed"
            result["restored_manifest"] = got
            return result
        _step("4-verify-restored",
              "restored lines=%s sha_prefix=%s matches anchor" % (
                  got["lines"], got["sha_prefix"]))
        result["restored_manifest"] = got
        result["anchor_kind"] = anchor_kind
        result["anchor_manifest"] = anchor_manifest
        if sync_dir:
            os.makedirs(sync_dir, exist_ok=True)
            staged = os.path.join(sync_dir, filename + ".tmp")
            final = os.path.join(sync_dir, filename)
            shutil.copyfile(target, staged)
            os.rename(staged, final)
            synced = file_manifest(final)
            if synced and synced["sha256"] == got["sha256"]:
                _step("5-sync-verify",
                      "synced to staging dir lines=%s sha_prefix=%s match" % (
                          synced["lines"], synced["sha_prefix"]))
            else:
                _step("5-sync-verify", "FAILED: staged sha mismatch")
                result["error"] = "sync_verify_failed"
                return result
        else:
            _step("5-sync-verify",
                  "PENDING: next pool-sync cycle (<=15 min) or manual sync "
                  "trigger; then verify hosted SHA equals restored SHA")
        _step("6-phone-refresh",
              "MANUAL (not done from VPS): refresh the free pool on the "
              "phone and check member count equals restored lines=%s"
              % got["lines"])
        result["ok"] = True
    finally:
        lock.release()
        _step("7-release-lock-and-log",
              "lock released; rollback log written")
        if log_path is None:
            log_path = os.path.join(
                publish_dir, "rollback-%d.json" % int(time.time()))
        with open(log_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        try:
            os.chmod(log_path, 0o600)
        except OSError:
            pass
        result["rollback_log"] = log_path
    if not result["ok"]:
        _step("8-stop-publish-timer-if-still-bad",
              "RECORDED ONLY (not executed): stop pool-publish.timer "
              "requires owner authorisation; rollback failed with "
              "error=%s" % result.get("error"))
    else:
        _step("8-stop-publish-timer-if-still-bad",
              "not needed: rollback verified ok")
    return result
