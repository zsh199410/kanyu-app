#!/usr/bin/env python3
"""D7 stop -> restore -> start drill (Issue #73, GPT D6 review
6904538782, item 3 -- pre-launch checklist, "real stop->restore->
start").

The PROCEDURE, in isolation (synthetic live dir, fake service).
Production execution stays UNVERIFIED -- pending the switch
window (see docs/D7_CHECKLIST.md). What this drill closes:
the stop/restore/start sequence itself, with SHA evidence at
every step, using the same snapshot+manifest shape as
backup-drill/PROCEDURE.md (snapshot dir 700, files 600, manifest
with per-file SHA256 + DB counts).

Sequence:
  1. Build synthetic live dir (publish file clean14, small
     sqlite DB, config.yaml, unit files) + snapshot it with a
     manifest (SHA per file + DB row counts).
  2. START a fake service (python http.server rooted at the live
     publish dir); GET returns the live SHA (clean14).
  3. Simulate loss: delete the live publish file, corrupt the DB.
  4. STOP the service (terminate; port must refuse connections).
  5. RESTORE from the snapshot; every restored file SHA must
     equal the manifest; the DB must open with matching counts.
  6. START the service again; GET returns clean14 SHA.
  7. A second loss+restore round proves the procedure is
     repeatable (no leftover state breaks it).

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object; --out writes it.

Usage: python3 drills/d7_stop_restore_start.py
       [--out docs/d7-stop-restore-log.json]
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")


def sha_file(path):
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


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def http_get_sha(url, timeout=10):
    """Returns (status, sha_prefix_or_None). Never raises."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            body = r.read()
            return r.status, hashlib.sha256(body).hexdigest()[:12]
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception:
        return 0, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    root = tempfile.mkdtemp(prefix="d7-stop-restore-")
    steps = []
    checks = []
    server = None

    def step(name, detail, **kw):
        rec = {"step": name, "detail": str(detail)}
        rec.update(kw)
        steps.append(rec)
        return rec

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    def sha_of(path):
        return sha_file(path)[:12] if os.path.exists(path) else ""

    def build_live(live):
        os.makedirs(live + "/publish", exist_ok=True)
        os.makedirs(live + "/data", exist_ok=True)
        os.makedirs(live + "/config", exist_ok=True)
        os.makedirs(live + "/units", exist_ok=True)
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        write_lines(live + "/publish/pool-new.txt", clean14)
        db = sqlite3.connect(live + "/data/pool.db")
        db.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)")
        db.execute("CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT)")
        for i in range(5):
            db.execute("INSERT INTO nodes (name) VALUES (?)",
                       ("node-%d" % i,))
        db.execute("INSERT INTO meta VALUES ('pinned', '2')")
        db.execute("INSERT INTO meta VALUES ('version', 'v1')")
        db.commit()
        db.close()
        with open(live + "/config.yaml", "w") as f:
            f.write("pinned_protected: false\npublish_limit: 150\n")
        for name in ("gate-publish.sh", "gate-sync.sh"):
            shutil.copy(os.path.join(HERE, "systemd", name),
                        live + "/units/" + name)
        return sha_lines(clean14)

    def snapshot(live, snap):
        os.makedirs(snap, exist_ok=True)
        os.chmod(snap, 0o700)
        manifest = {"files": {}, "db_counts": {}}
        for rel in ("publish/pool-new.txt", "data/pool.db",
                    "config.yaml", "units/gate-publish.sh",
                    "units/gate-sync.sh"):
            src = os.path.join(live, rel)
            dst = os.path.join(snap, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            os.chmod(dst, 0o600)
            manifest["files"][rel] = {
                "sha256": sha_file(dst),
                "bytes": os.path.getsize(dst)}
        db = sqlite3.connect("file:%s?mode=ro" % os.path.join(
            snap, "data/pool.db"), uri=True)
        manifest["db_counts"]["nodes"] = db.execute(
            "SELECT COUNT(*) FROM nodes").fetchone()[0]
        manifest["db_counts"]["meta"] = db.execute(
            "SELECT COUNT(*) FROM meta").fetchone()[0]
        db.close()
        with open(snap + "/manifest.json", "w") as f:
            json.dump(manifest, f, indent=1)
        os.chmod(snap + "/manifest.json", 0o600)
        return manifest

    def restore(snap, live):
        manifest = json.load(open(snap + "/manifest.json"))
        mismatches = []
        for rel, meta in manifest["files"].items():
            src = os.path.join(snap, rel)
            dst = os.path.join(live, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            if sha_file(dst) != meta["sha256"]:
                mismatches.append(rel)
        return manifest, mismatches

    def db_counts(path):
        db = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        try:
            return {"nodes": db.execute("SELECT COUNT(*) FROM nodes").fetchone()[0],
                    "meta": db.execute("SELECT COUNT(*) FROM meta").fetchone()[0]}
        finally:
            db.close()

    def start_server(pub_dir, port):
        proc = subprocess.Popen(
            [sys.executable, "-m", "http.server", str(port),
             "--bind", "127.0.0.1", "--directory", pub_dir],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            code, _sha = http_get_sha(
                "http://127.0.0.1:%d/pool-new.txt" % port)
            if code == 200:
                return proc
            time.sleep(0.1)
        raise RuntimeError("fake service did not come up")

    def stop_server(proc):
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=10)

    try:
        live = os.path.join(root, "live")
        snap = os.path.join(root, "snapshot")
        clean_sha = build_live(live)
        manifest = snapshot(live, snap)
        check("snapshot_manifest_complete",
              len(manifest["files"]) == 5
              and manifest["db_counts"] == {"nodes": 5, "meta": 2},
              "files=%d counts=%s"
              % (len(manifest["files"]), manifest["db_counts"]))
        check("snapshot_perms_700_600",
              (oct(os.stat(snap).st_mode & 0o777) == "0o700")
              and all((os.stat(os.path.join(snap, rel)).st_mode & 0o777) == 0o600
                      for rel in manifest["files"]),
              "dir 700, files 600 (D4 procedure)")
        step("snapshot taken",
             "5 files + manifest (SHA per file + DB counts)",
             clean_sha=clean_sha[:12], error="")

        port = free_port()
        url = "http://127.0.0.1:%d/pool-new.txt" % port
        server = start_server(live + "/publish", port)
        code, sha = http_get_sha(url)
        check("service_serves_live_sha",
              code == 200 and sha == clean_sha[:12],
              "http=%s sha=%s" % (code, sha))
        step("service started", "GET returns live SHA clean14",
             sha=sha, error="")

        # ---- Round 1: loss -> stop -> restore -> start ----
        os.unlink(live + "/publish/pool-new.txt")
        with open(live + "/data/pool.db", "wb") as f:
            f.write(b"garbage, not a database")
        check("loss_simulated",
              not os.path.exists(live + "/publish/pool-new.txt"),
              "publish file deleted, DB corrupted")
        stop_server(server)
        server = None
        code, _sha = http_get_sha(url)
        check("service_stopped_port_refuses",
              code == 0, "GET after stop -> connection refused (code 0)")
        step("service stopped", "port refuses connections",
             error="")
        _man, mismatches = restore(snap, live)
        check("restore_sha_matches_manifest", not mismatches,
              "mismatches=%s" % mismatches)
        check("restored_db_counts_match",
              db_counts(live + "/data/pool.db") == {"nodes": 5, "meta": 2},
              "counts=%s" % db_counts(live + "/data/pool.db"))
        check("restored_publish_is_clean14",
              sha_of(live + "/publish/pool-new.txt") == clean_sha[:12],
              "sha=%s" % sha_of(live + "/publish/pool-new.txt"))
        step("restored from snapshot",
             "all 5 files SHA == manifest; DB counts match",
             error="")
        server = start_server(live + "/publish", port)
        code, sha = http_get_sha(url)
        check("service_restarted_serves_restored_sha",
              code == 200 and sha == clean_sha[:12],
              "http=%s sha=%s" % (code, sha))
        step("service restarted",
             "GET returns restored SHA clean14 (round 1 complete)",
             sha=sha, error="")

        # ---- Round 2: repeat to prove no leftover state breaks it ----
        os.unlink(live + "/publish/pool-new.txt")
        stop_server(server)
        server = None
        code, _sha = http_get_sha(url)
        check("round2_service_stopped", code == 0, "port refuses")
        _man, mismatches = restore(snap, live)
        check("round2_restore_sha_matches", not mismatches,
              "mismatches=%s" % mismatches)
        server = start_server(live + "/publish", port)
        code, sha = http_get_sha(url)
        check("round2_service_serves_restored_sha",
              code == 200 and sha == clean_sha[:12],
              "http=%s sha=%s" % (code, sha))
        step("round 2 complete",
             "loss -> stop -> restore -> start repeats cleanly",
             sha=sha, error="")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7_stop_restore_start",
               "sha": {"clean14": clean_sha[:12]},
               "steps": steps, "checks": checks,
               "passed": sum(1 for c in checks if c["ok"]),
               "total": len(checks), "ok": ok}
        print(json.dumps(log, indent=1, ensure_ascii=False))
        if args.out:
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(log, f, indent=1, ensure_ascii=False)
        return 0 if ok else 1
    finally:
        if server is not None:
            try:
                stop_server(server)
            except Exception:
                pass
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
