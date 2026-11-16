#!/usr/bin/env python3
"""D7a item-2 drill (Issue #73, GPT D7 review 6912114134, item 2).

tools/http_recheck.py must catch, AFTER a deployment, what the
16:37 snapshot cannot prove: a NEW independent HTTP alias pointing
at the served dir. Three runs against the D7 sandbox servers
(real nginx on the VPS, Python emulation locally):

  H healthy: good-only config dump + good origin -> rc=0, entry
    200 with SHA == bridge == expected, all 7 D7 probes refused.
  V violation: the dump gains an independent alias
    (/alias-served/ -> served dir, the D7-proven guard blind
    spot) and the entry URL moves to the control origin ->
    rc=1, the violation names /alias-served/, and the extra probe
    of the alias path returns served bytes (200, SHA == served).
  F fixed: back to the good dump + good origin -> rc=0 again.

When real nginx is available the dump is genuine `nginx -T`
output (proving the parser handles it); otherwise the conf file
itself is the dump. The config text is the evidence; the HTTP
probes are the second layer.

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object; --out writes it.

Usage: python3 drills/d7a_item2_http_recheck.py
       [--out docs/d7a-item2-drill-log.json]
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

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "drills"))

import d7_item1_http_exposure as item1  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    root = tempfile.mkdtemp(prefix="d7a-item2-")
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

    def run_recheck(dump_path, entry_url, extra_probes=()):
        cmd = [sys.executable,
               os.path.join(HERE, "tools", "http_recheck.py"),
               "--config-dump", dump_path,
               "--entry-url", entry_url,
               "--expected-sha", clean_sha,
               "--bridge-file", bridge_dir + "/pool-new.txt",
               "--legacy-file", bridge_dir + "/old-pool.txt",
               "--served-file", served_dir + "/pool-new.txt",
               "--quarantine-name", qname]
        for p in extra_probes:
            cmd += ["--extra-probe", p]
        p = subprocess.run(cmd, capture_output=True, text=True,
                           cwd=HERE, timeout=120)
        try:
            return p.returncode, json.loads(p.stdout.strip() or "{}")
        except ValueError:
            return p.returncode, {"raw": (p.stdout + p.stderr)[:400]}

    try:
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean_sha = sha_bytes(("\n".join(clean14) + "\n").encode("utf-8"))
        polluted = clean14 + [l for l in pool44 if l not in clean14][:1]
        polluted_sha = sha_bytes(
            ("\n".join(polluted) + "\n").encode("utf-8"))
        qname = "pool-new-20261116-000000-abcdef123456.txt"

        bridge_dir = os.path.join(root, "bridge")
        served_dir = os.path.join(root, "served")
        qdir = os.path.join(served_dir, ".quarantine")
        os.makedirs(bridge_dir)
        os.makedirs(qdir)
        write_lines(bridge_dir + "/pool-new.txt", clean14)
        write_lines(bridge_dir + "/old-pool.txt", clean14)
        write_lines(served_dir + "/pool-new.txt", clean14)
        write_lines(qdir + "/" + qname, polluted)

        good_conf = """events { worker_connections 16; }
http {
  access_log off;
  server {
    listen 127.0.0.1:18091;
    location /m/ { alias %s/; default_type text/plain; }
    location / { return 404; }
  }
}
""" % bridge_dir
        bad_conf = """events { worker_connections 16; }
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
""" % (bridge_dir, bridge_dir, served_dir)
        good_path = os.path.join(root, "good.conf")
        bad_path = os.path.join(root, "bad.conf")
        with open(good_path, "w") as f:
            f.write(good_conf)
        with open(bad_path, "w") as f:
            f.write(bad_conf)

        nginx = shutil.which("nginx")
        dump_kind = "conf-file"
        good_dump, bad_dump = good_path, bad_path
        if nginx:
            # Genuine `nginx -T` output (the parser must handle the
            # "# configuration file ..." headers and test lines).
            for src, dst in ((good_path, "good-T.txt"),
                             (bad_path, "bad-T.txt")):
                p = subprocess.run(
                    [nginx, "-T", "-c", src, "-p", root + "/"],
                    capture_output=True, text=True, timeout=30)
                if p.returncode == 0:
                    with open(os.path.join(root, dst), "w") as f:
                        f.write(p.stdout + p.stderr)
                    if dst.startswith("good"):
                        good_dump = os.path.join(root, dst)
                    else:
                        bad_dump = os.path.join(root, dst)
                    dump_kind = "nginx -T output"
        step("dump prepared",
             "kind=%s (nginx=%s)" % (dump_kind, bool(nginx)), error="")

        with item1.SandboxServer(root, bridge_dir, served_dir) as srv:
            engine = srv.engine
            step("sandbox servers up",
                 "engine=%s" % engine, engine=engine, error="")

            # ---- H: healthy ----
            rc, out = run_recheck(
                good_dump, "http://127.0.0.1:18091/m/pool-new.txt")
            check("h_rc0", rc == 0, "rc=%d" % rc)
            check("h_ok_true", out.get("ok") is True,
                  "ok=%s" % out.get("ok"))
            check("h_entry_sha_matches_bridge_and_expected",
                  out.get("entry", {}).get("http") == 200
                  and out.get("entry", {}).get("sha_matches_bridge") is True
                  and out.get("entry", {}).get(
                      "sha_matches_expected") is True,
                  "entry=%s" % out.get("entry"))
            check("h_probes_all_refused",
                  out.get("checks", {}).get("probes_all_refused") is True
                  and len(out.get("probes", [])) == 7,
                  "probes=%d refused=%s"
                  % (len(out.get("probes", [])),
                     out.get("checks", {}).get("probes_all_refused")))
            check("h_no_violations",
                  out.get("checks", {}).get("config_no_served_mapping")
                  is True and out.get("config", {}).get("violations") == [],
                  "violations=%s"
                  % out.get("config", {}).get("violations"))
            step("H healthy",
                 "rc=0, entry 200 + SHA == bridge == expected, 7 "
                 "probes refused, no config violations",
                 engine=engine, error="")

            # ---- V: independent alias at served (guard blind spot) ----
            rc, out = run_recheck(
                bad_dump, "http://127.0.0.1:18092/m/pool-new.txt",
                extra_probes=["/alias-served/pool-new.txt"])
            check("v_rc1", rc == 1, "rc=%d" % rc)
            vlocs = [v.get("location")
                     for v in out.get("config", {}).get("violations", [])]
            check("v_violation_names_alias_served",
                  "/alias-served/" in vlocs,
                  "violations=%s" % vlocs)
            alias_probe = [p for p in out.get("probes", [])
                           if p.get("path") == "/alias-served/pool-new.txt"]
            check("v_alias_probe_serves_served_bytes",
                  len(alias_probe) == 1
                  and alias_probe[0].get("http") == 200
                  and alias_probe[0].get("refused") is False
                  and alias_probe[0].get("body_sha_prefix")
                  == out.get("sha", {}).get("served_prefix"),
                  "probe=%s" % alias_probe)
            check("v_entry_still_matches",
                  out.get("entry", {}).get("sha_matches_bridge") is True,
                  "entry on the control origin still serves the "
                  "verified bridge bytes -- the failure is the alias, "
                  "not the entry")
            step("V independent alias at served",
                 "rc=1; violation names /alias-served/; the alias path "
                 "probe returns served bytes (200)",
                 engine=engine, error="")

            # ---- F: fixed ----
            rc, out = run_recheck(
                good_dump, "http://127.0.0.1:18091/m/pool-new.txt")
            check("f_rc0_after_fix", rc == 0, "rc=%d" % rc)
            check("f_ok_true_after_fix", out.get("ok") is True,
                  "ok=%s" % out.get("ok"))
            step("F fixed",
                 "back to the good dump + good origin: rc=0 again",
                 engine=engine, error="")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7a_item2_http_recheck",
               "engine": engine, "dump_kind": dump_kind,
               "sha": {"clean14": clean_sha[:12],
                       "polluted": polluted_sha[:12]},
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
