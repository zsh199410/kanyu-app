"""Isolation-only end-to-end tests of release-bound deploy and rollback.

Fake nginx/systemctl/curl commands operate on a temporary test root. Nothing
contacts a real VPS or changes production. Real SQLite backup API is exercised.
"""
import hashlib
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
DEPLOY = ROOT / "tools" / "deploy_dual.sh"
ROLLBACK = ROOT / "tools" / "rollback_dual.sh"
JS = ROOT / "script" / "probe-task-dual.js"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class ReleaseManifestTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="surge-dual-release-"))
        self.base = self.tmp / "probe"
        self.conf = self.base / "config"
        self.data = self.base / "data"
        self.conf.mkdir(parents=True)
        self.data.mkdir(parents=True)
        self.commands = self.tmp / "mock-bin"
        self.commands.mkdir()
        self.script_dst = self.tmp / "live-probe.js"
        self.service_dst = self.tmp / "live-service.py"
        self.nginx = self.tmp / "probe.conf"
        self.script_dst.write_text("OLD_SCRIPT_ORIGINAL\n")
        self.service_dst.write_text("OLD_SERVICE_ORIGINAL\n")
        self.nginx.write_text(
            "server {\n location = /testseg12345678 { proxy_pass http://127.0.0.1:18081; }\n}\n"
        )
        (self.conf / "probe-path.txt").write_text("testseg12345678")
        (self.conf / "deploy-render.conf").write_text(
            "PROBE_HOST=probe.example\nNGINX_CONF=" + str(self.nginx) + "\n"
        )
        self.db = self.data / "probe.db"
        c = sqlite3.connect(self.db)
        c.execute("PRAGMA journal_mode=WAL")
        c.execute("CREATE TABLE probe_reports(id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE probe_nodes(id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE probe_reports_wifi(id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("CREATE TABLE probe_nodes_wifi(id INTEGER PRIMARY KEY, name TEXT)")
        c.execute("INSERT INTO probe_reports VALUES (1,'cell')")
        c.execute("INSERT INTO probe_reports_wifi VALUES (1,'wifi')")
        c.commit()
        c.close()
        for cmd in ("nginx", "systemctl"):
            shim = self.commands / cmd
            shim.write_text("#!/bin/sh\nexit 0\n")
            shim.chmod(0o755)
        curl = self.commands / "curl"
        curl.write_text(
            "#!/usr/bin/env python3\n"
            "import os,sys\n"
            "a=sys.argv[1:]\n"
            "headers=[a[i+1] for i,v in enumerate(a[:-1]) if v=='-H']\n"
            "uri=a[-1]\n"
            "if '-wifi' in uri:\n"
            "    valid='Host: probe.example' in headers\n"
            "    if 'X-Probe-Network: cellular' in headers: status='400'\n"
            "    elif os.environ.get('MOCK_WIFI_STATE')=='new' and valid: status='200'\n"
            "    else: status='404'\n"
            "else: status='200'\n"
            "if '-w' in a: sys.stdout.write(status)\n"
        )
        curl.chmod(0o755)
        self.env = dict(os.environ)
        self.env.update({
            "PATH": str(self.commands) + os.pathsep + os.environ.get("PATH", ""),
            "PROBE_BASE": str(self.base),
            "SERVICE_DST": str(self.service_dst),
            "SCRIPT_DST": str(self.script_dst),
            "DEPLOY_RENDER_CONF": str(self.conf / "deploy-render.conf"),
            "MOCK_WIFI_STATE": "new",
        })
        self.new_service = self.tmp / "candidate_service.py"
        self.new_service.write_text("NEW_SERVICE_PATCHED\n")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_shell(self, path, *args, env=None):
        return subprocess.run(
            ["bash", str(path), *map(str, args)],
            env=env or self.env,
            text=True,
            capture_output=True,
            timeout=30,
        )

    def stage2(self):
        p = self.run_shell(DEPLOY, 2, self.new_service, sha(self.new_service))
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return self.conf / "dual-release.manifest"

    def test_stage2_pins_all_original_backups(self):
        originals = (sha(self.script_dst), sha(self.nginx))
        manifest = self.stage2()
        self.assertTrue(manifest.exists())
        self.assertEqual(manifest.stat().st_mode & 0o777, 0o600)
        body = manifest.read_text()
        self.assertIn("SCRIPT_SHA=" + originals[0], body)
        self.assertIn("NGINX_SHA=" + originals[1], body)
        self.assertIn("SERVICE_SHA=", body)
        self.assertIn("DB_SHA=", body)
        self.assertNotIn("<probe-host>", body)
        p = self.run_shell(DEPLOY, 2, self.new_service, sha(self.new_service))
        self.assertNotEqual(p.returncode, 0, "a second release must refuse overlap")

    def test_mismatched_backup_refuses_before_any_restore(self):
        manifest = self.stage2()
        self.service_dst.write_text("MODIFIED_SERVICE\n")
        self.script_dst.write_text("MODIFIED_SCRIPT\n")
        self.nginx.write_text("MODIFIED_NGINX\n")
        text = manifest.read_text()
        text = text.replace("SCRIPT_SHA=", "SCRIPT_SHA=" + "0" * 64 + " #", 1)
        manifest.write_text(text)
        p = self.run_shell(ROLLBACK)
        self.assertNotEqual(p.returncode, 0, p.stdout)
        self.assertEqual(self.script_dst.read_text(), "MODIFIED_SCRIPT\n")
        self.assertEqual(self.nginx.read_text(), "MODIFIED_NGINX\n")
        self.assertEqual(self.service_dst.read_text(), "MODIFIED_SERVICE\n")

    def test_sequential_stages_real_host_header_and_reverse_rollback(self):
        orig_script = self.script_dst.read_bytes()
        orig_nginx = self.nginx.read_bytes()
        orig_service = self.service_dst.read_bytes()
        manifest = self.stage2()
        self.assertEqual(self.service_dst.read_text(), "NEW_SERVICE_PATCHED\n")
        for stage in (3, 4):
            p = self.run_shell(DEPLOY, stage)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            self.assertIn("wifi", p.stdout.lower())
        p = self.run_shell(DEPLOY, 5, JS, sha(JS))
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        rendered = self.script_dst.read_text()
        self.assertIn("https://probe.example:8443/testseg12345678", rendered)
        self.assertNotIn("<random-path>", rendered)
        self.assertNotEqual(self.script_dst.read_bytes(), orig_script)
        rollback_env = dict(self.env, MOCK_WIFI_STATE="old")
        p = self.run_shell(ROLLBACK, env=rollback_env)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(self.script_dst.read_bytes(), orig_script)
        self.assertEqual(self.nginx.read_bytes(), orig_nginx)
        self.assertEqual(self.service_dst.read_bytes(), orig_service)
        self.assertFalse(manifest.exists())
        self.assertEqual(len(list(self.conf.glob("dual-release.manifest.rolledback-*"))), 1)
        c = sqlite3.connect(self.db)
        self.assertEqual(c.execute("SELECT count(*) FROM probe_reports_wifi").fetchone()[0], 1)
        c.close()


if __name__ == "__main__":
    unittest.main()
