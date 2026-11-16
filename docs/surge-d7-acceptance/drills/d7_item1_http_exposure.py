#!/usr/bin/env python3
"""D7 item-1 drill (Issue #73, GPT D6 review 6904538782, item 1).

HTTP exposure surface: prove the served file and served/.quarantine
are NOT directly readable from the public/internal subscription
entry. Two evidence layers:

  R (real, checked-in): the live nginx audit + live HTTP probes
    captured 2026-11-16 16:37 CST (docs/d7-live-probes.json,
    desensitised: no hostnames, no subscription URLs, no node
    lines, no credentials, no random path tokens; SHA prefixes
    only). The drill VALIDATES the table: the entry SHA equals
    the on-disk bridge SHA, every served-path probe is refused,
    and no probe body equals the served bytes. The audit part
    records: exactly ONE static alias in the live config (the
    bridge dir), zero roots/aliases pointing at the served or
    publish dirs, zero autoindex, nginx -t OK.
  S (sandbox, re-runnable in both environments): a static server
    replicating the live mapping (alias <STATIC_PREFIX> -> bridge
    dir; everything else 404) is probed with the same path set;
    a NEGATIVE CONTROL server adds an independent alias pointing
    at the served dir and proves the gate-sync.sh realpath guard
    does NOT catch it (guard returns "ok"), while the probe DOES
    return the served bytes (200) -- i.e. detection relies on the
    audit + probes, never on the guard alone.

Engine: real nginx when available (VPS), else a Python
http.server emulation of the same routing (local sandbox has no
nginx). The engine is recorded in the log; both engines must give
the same verdicts.

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object; --out writes it.

Usage: python3 drills/d7_item1_http_exposure.py
       [--out docs/d7-item1-drill-log.json]
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def guard_result(served_dir, bridge_dir):
    """The exact realpath expression from systemd/gate-sync.sh."""
    s = os.path.realpath(served_dir)
    b = os.path.realpath(bridge_dir)
    return "exposed" if s == b or s.startswith(b + os.sep) else "ok"


def http_get(url, timeout=10):
    """Returns (status, body_bytes). Never raises."""
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read()
        except Exception:
            return e.code, b""
    except Exception as e:
        return 0, ("error:%s" % type(e).__name__).encode()


# ---------------- Python fallback server (nginx emulation) ----------------

def _resolve_within(base, rel):
    """Resolve rel (URL-decoded) inside base. Returns the absolute
    path, or None if it escapes base. Dot segments are walked
    manually (normpath would silently collapse a leading ".." at
    the root and hide the escape); a ".." that would pop past the
    base root is an escape -> None (fail-closed, like nginx
    normalising the traversal out of the aliased location)."""
    rel = urllib.parse.unquote(rel)
    parts = []
    for seg in rel.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if not parts:
                return None
            parts.pop()
            continue
        parts.append(seg)
    cand = os.path.join(base, *parts) if parts else base
    real = os.path.realpath(cand)
    if real != os.path.realpath(base) and not real.startswith(
            os.path.realpath(base) + os.sep):
        return None
    return real


def make_handler(bridge_dir, served_dir, alias_served):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def do_GET(self):
            raw = self.path.split("?", 1)[0]
            target = None
            if raw.startswith("/m/"):
                target = _resolve_within(bridge_dir, raw[3:])
            elif alias_served and raw.startswith("/alias-served/"):
                target = _resolve_within(served_dir, raw[len("/alias-served/"):])
            if target is None or not os.path.isfile(target or ""):
                body = b"404 Not Found\n"
                self.send_response(404)
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            with open(target, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    return H


class SandboxServer:
    """Context manager: real nginx if available, else the Python
    emulation. Both expose the same two origins: good (alias /m/ ->
    bridge only) and control (extra independent alias -> served)."""

    def __init__(self, root, bridge_dir, served_dir):
        self.root = root
        self.bridge_dir = bridge_dir
        self.served_dir = served_dir
        self.engine = "python-emulation"
        self.good_port = 18091
        self.ctrl_port = 18092
        self._httpd = None
        self._nginx_prefix = None

    def __enter__(self):
        nginx = shutil.which("nginx")
        if nginx:
            try:
                self._start_nginx(nginx)
                self.engine = "nginx"
                return self
            except Exception as e:
                self.engine = "python-emulation (nginx start failed: %s)" % type(e).__name__
        handler = make_handler(self.bridge_dir, self.served_dir, False)
        self._httpd = ThreadingHTTPServer(("127.0.0.1", self.good_port), handler)
        threading.Thread(target=self._httpd.serve_forever, daemon=True).start()
        handler2 = make_handler(self.bridge_dir, self.served_dir, True)
        self._httpd2 = ThreadingHTTPServer(("127.0.0.1", self.ctrl_port), handler2)
        threading.Thread(target=self._httpd2.serve_forever, daemon=True).start()
        return self

    def _start_nginx(self, nginx):
        prefix = os.path.join(self.root, "nginx")
        os.makedirs(prefix + "/logs", exist_ok=True)
        for d in (self.bridge_dir, self.served_dir):
            os.chmod(d, 0o755)
            for f in os.listdir(d):
                p = os.path.join(d, f)
                if os.path.isfile(p):
                    os.chmod(p, 0o644)
        conf = """user root;
pid %s/nginx.pid;
error_log %s/logs/error.log;
events { worker_connections 16; }
http {
  access_log off;
  server {
    listen 127.0.0.1:18091;
    location /m/ { alias %s/; default_type text/plain; }
    location / { return 404; }
  }
  server {
    listen 127.0.0.1:18092;
    location /m/ { alias %s/; default_type text/plain; }
    location /alias-served/ { alias %s/; default_type text/plain; }
    location / { return 404; }
  }
}
""" % (prefix, prefix, self.bridge_dir, self.bridge_dir, self.served_dir)
        conf_path = os.path.join(prefix, "nginx.conf")
        with open(conf_path, "w") as f:
            f.write(conf)
        subprocess.run([nginx, "-c", conf_path, "-p", prefix + "/",
                        "-g", "daemon on;"],
                       capture_output=True, timeout=30, check=True)
        self._nginx_prefix = prefix
        self._nginx_conf = conf_path
        # Wait until the good origin answers.
        for _ in range(50):
            code, _ = http_get("http://127.0.0.1:18091/m/pool-new.txt")
            if code in (200, 404):
                return
            import time
            time.sleep(0.1)
        raise RuntimeError("nginx did not come up")

    def __exit__(self, *exc):
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd2.shutdown()
            self._httpd2.server_close()
        if self._nginx_prefix:
            nginx = shutil.which("nginx")
            subprocess.run([nginx, "-c", self._nginx_conf,
                            "-p", self._nginx_prefix + "/",
                            "-s", "stop"],
                           capture_output=True, timeout=30)
        return False

    def good(self, path):
        return http_get("http://127.0.0.1:%d%s" % (self.good_port, path))

    def ctrl(self, path):
        return http_get("http://127.0.0.1:%d%s" % (self.ctrl_port, path))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    root = tempfile.mkdtemp(prefix="d7-item1-")
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

    try:
        live = json.load(open(os.path.join(HERE, "docs",
                                           "d7-live-probes.json")))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean_sha = sha_bytes(("\n".join(clean14) + "\n").encode("utf-8"))
        polluted = clean14 + [l for l in pool44 if l not in clean14][:1]
        polluted_sha = sha_bytes(("\n".join(polluted) + "\n").encode("utf-8"))

        # ---- R: validate the checked-in live evidence table ----
        probes = {p["name"]: p for p in live["probes"]}
        disk = live["disk"]
        audit = live["audit"]
        check("r_entry_sha_matches_disk_bridge",
              probes["P1-entry"]["body_sha_prefix"]
              == disk["bridge_file_sha_prefix"]
              == disk["production_publish_sha_prefix"],
              "http=%s lines=%s sha=%s"
              % (probes["P1-entry"]["http"],
                 probes["P1-entry"]["body_lines"],
                 probes["P1-entry"]["body_sha_prefix"]))
        check("r_entry_is_only_200",
              probes["P1-entry"]["http"] == 200
              and all(p["http"] != 200 for k, p in probes.items()
                      if k != "P1-entry"),
              "non-entry: " + ",".join(
                  "%s=%s" % (k, p["http"]) for k, p in probes.items()
                  if k != "P1-entry"))
        check("r_no_probe_body_is_pool_bytes",
              all(p["body_sha_prefix"]
                  != disk["bridge_file_sha_prefix"]
                  for k, p in probes.items() if k != "P1-entry"),
              "served-path body SHAs: " + ",".join(
                  sorted({p["body_sha_prefix"] for k, p in probes.items()
                          if k != "P1-entry"})))
        check("r_quarantine_path_404",
              probes["P4-quarantine"]["http"] == 404,
              "http=%s" % probes["P4-quarantine"]["http"])
        check("r_audit_one_static_alias_bridge_only",
              audit["static_alias_count"] == 1
              and audit["static_alias_target_token"] == "<BRIDGE_DIR>"
              and audit["roots_or_aliases_pointing_at_served_or_publish"] == 0
              and audit["autoindex_on"] == 0,
              "aliases=%s served_mappings=%s autoindex=%s nginx=%s"
              % (audit["static_alias_count"],
                 audit["roots_or_aliases_pointing_at_served_or_publish"],
                 audit["autoindex_on"], audit["nginx_syntax"]))
        check("r_gate_state_not_yet_deployed",
              disk["gate_state_dir_exists"] is False,
              "gate state dir absent pre-switch (served path does not "
              "exist yet; the check binds the FUTURE path)")
        step("R live evidence table validated",
             "entry 200 + SHA == disk bridge == production publish; "
             "7 served-path probes refused; audit: 1 static alias "
             "(bridge only), 0 served/publish mappings, 0 autoindex",
             entry_sha=probes["P1-entry"]["body_sha_prefix"],
             refused=7, error="")

        # ---- S: sandbox servers with the same mapping ----
        bridge_dir = os.path.join(root, "bridge")
        served_dir = os.path.join(root, "served")
        qdir = os.path.join(served_dir, ".quarantine")
        os.makedirs(bridge_dir)
        os.makedirs(qdir)
        write_lines(bridge_dir + "/pool-new.txt", clean14)
        write_lines(served_dir + "/pool-new.txt", clean14)
        write_lines(qdir + "/pool-new-20261116-000000-abcdef123456.txt",
                    polluted)
        with SandboxServer(root, bridge_dir, served_dir) as srv:
            code, body = srv.good("/m/pool-new.txt")
            check("s_entry_200_sha_match",
                  code == 200 and sha_bytes(body) == clean_sha,
                  "http=%s sha=%s" % (code, sha_bytes(body)[:12]))
            trav = ["/m/../pool-new.txt",
                    "/m/%2e%2e/pool-new.txt",
                    "/m/../../free-node-program/publish/pool-new.txt",
                    "/m/..%2f..%2f..%2fopt%2fpool-gate%2fstate%2fserved%2fpool-new.txt",
                    "/opt/pool-gate/state/served/pool-new.txt",
                    "/m/..;/pool-new.txt"]
            trav_ok = True
            trav_detail = []
            for path in trav:
                code, body = srv.good(path)
                ok = code != 200 and sha_bytes(body) != clean_sha
                trav_ok = trav_ok and ok
                trav_detail.append("%s=%s" % (path.split("/")[-1][:18], code))
            check("s_traversal_all_refused", trav_ok, ",".join(trav_detail))
            code, body = srv.good("/m/.quarantine/pool-new-20261116-000000-abcdef123456.txt")
            check("s_quarantine_404",
                  code == 404 and sha_bytes(body) != polluted_sha,
                  "http=%s" % code)
            step("S sandbox good mapping",
                 "engine=%s; entry 200 + SHA match; 6 traversal paths "
                 "refused; quarantine 404" % srv.engine,
                 engine=srv.engine, error="")
            # Guard pins.
            check("s_guard_served_inside_bridge_exposed",
                  guard_result(os.path.join(bridge_dir, "served"),
                               bridge_dir) == "exposed",
                  "nested served -> exposed")
            check("s_guard_independent_alias_returns_ok",
                  guard_result(served_dir, bridge_dir) == "ok",
                  "served outside bridge -> ok (the documented limit)")
            # Negative control: independent alias DOES serve it.
            code, body = srv.ctrl("/alias-served/pool-new.txt")
            check("s_alias_control_serves_served_200",
                  code == 200 and sha_bytes(body) == clean_sha,
                  "http=%s sha=%s (served bytes readable via alias)"
                  % (code, sha_bytes(body)[:12]))
            check("s_gap_guard_ok_but_probe_200",
                  guard_result(served_dir, bridge_dir) == "ok"
                  and code == 200,
                  "guard blind to the alias; only the audit + probe "
                  "catch it (GPT D6 item 1 limit, proven live here)")
            step("S negative control (independent alias)",
                 "guard=ok AND probe=200 with served SHA: the realpath "
                 "guard cannot cover an independent HTTP alias; the "
                 "pre-switch audit + probes are the control",
                 engine=srv.engine, error="")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7_item1_http_exposure",
               "live_captured_cst": live["probed_at_cst"],
               "sha": {"clean14": clean_sha[:12],
                       "polluted": polluted_sha[:12],
                       "live_entry": probes["P1-entry"]["body_sha_prefix"]},
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
