"""Hard-gated production-cycle unit tests. Zero real services or writes."""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest

from test_production_cycle import make_env, prod


class ProductionCycleGates(unittest.TestCase):
    def fixture(self, directory, **extra):
        db, served, staging = make_env(directory)
        stop = Path(directory) / "stop-status"
        stop.write_text("RUNNING", encoding="utf-8")
        release = Path(directory) / "release-ready"
        release.write_text("PR93_APPROVED_SAME_BYTES_ONLY", encoding="utf-8")
        env = {
            "P2P3_POOL_DB": str(db),
            "P2P3_POOL_SERVED": str(served),
            "P2P3_POOL_STAGING": str(staging),
            "P2P3_STOP_STATE_FILE": str(stop),
            "P2P3_RELEASE_MARKER": str(release),
            "P2P3_ENABLE_PRODUCTION": "YES_EXPLICITLY",
            "P2P3_WRITER_DB": str(Path(directory) / "writer.db"),
            "P2P3_WRITER_LOCK": str(Path(directory) / "lock"),
            "P2P3_LEGACY_ROOT": directory,
            **extra
        }
        return env, served, staging, stop, release

    @staticmethod
    def preview_same(db, current, root, now):
        return {
            "proposed_bytes": current, "proposed_count": len(current.splitlines()),
            "production_write_authorized": False,
        }, {
            "decision":"HOLD_NO_CHANGE",
            "production_delete_authorized":False,
        }

    @staticmethod
    def preview_changed(db, current, root, now):
        return {
            "proposed_bytes": current + b"#changed\n",
            "proposed_count": len(current.splitlines()),
            "production_write_authorized":False,
        }, {
            "decision":"HOLD_UNVERIFIED_CHANGE",
            "production_delete_authorized":False,
        }

    def test_preview_no_writes(self):
        with tempfile.TemporaryDirectory() as d:
            env, served, staging, _, _ = self.fixture(d)
            before = served.read_bytes()
            status = prod.run_cycle(env=env,mode="preview",
                                     previewer=self.preview_same)
            self.assertEqual(status["decision"],"PREVIEW_ONLY")
            self.assertEqual(served.read_bytes(), before)
            self.assertEqual(staging.read_bytes(), before)

    def test_live_writer_without_release_gate_refused_before_preview(self):
        with tempfile.TemporaryDirectory() as d:
            env, served, staging, _, release = self.fixture(d)
            release.unlink()
            called=[]
            with self.assertRaisesRegex(prod.CycleRefused, "release_marker_missing"):
                prod.run_cycle(env=env,mode="publish",
                    previewer=lambda *a:called.append("CALLED"))
            self.assertEqual(called,[])

    def test_live_writer_without_explicit_env_refused(self):
        with tempfile.TemporaryDirectory() as d:
            env, _, _, _, _ = self.fixture(d)
            env["P2P3_ENABLE_PRODUCTION"] = "NO"
            with self.assertRaisesRegex(prod.CycleRefused,"production_not_enabled"):
                prod.run_cycle(env=env,mode="publish",
                               previewer=self.preview_same)

    def test_missing_or_stop_state_refused_before_fetch(self):
        with tempfile.TemporaryDirectory() as d:
            env, _, _, stop, _ = self.fixture(d)
            for state in ("STOP", "UNKNOWN", "RUNNING\nCORRUPT"):
                with self.subTest(state=state):
                    stop.write_text(state)
                    with self.assertRaisesRegex(prod.CycleRefused,"stop_or_unknown_state"):
                        prod.run_cycle(env=env,mode="publish",
                                       previewer=self.preview_same)
            stop.unlink()
            with self.assertRaisesRegex(prod.CycleRefused,"stop_state_unavailable"):
                prod.run_cycle(env=env,mode="publish",
                               previewer=self.preview_same)

    def test_same_bytes_calls_single_writer_with_guard_default(self):
        with tempfile.TemporaryDirectory() as d:
            env, served, staging, stop, _ = self.fixture(d)
            original = served.read_bytes()
            calls=[]
            def dummy_publisher(**kwargs):
                calls.append(kwargs)
                self.assertNotIn("guard_check",kwargs)
                self.assertNotIn("ban_proof_fn",kwargs)
                self.assertFalse(kwargs["stop_check"]())
                self.assertEqual(kwargs["candidate_bytes"],original)
                self.assertEqual(kwargs["expected_current_sha"],
                                 hashlib.sha256(original).hexdigest())
                return {"ok":True}
            status=prod.run_cycle(env=env,mode="publish",
                    previewer=self.preview_same,publisher=dummy_publisher)
            self.assertEqual(status["decision"],"SAME_BYTES_PUBLISHED")
            self.assertEqual(len(calls),1)
            self.assertEqual(served.read_bytes(),original)
            stop.write_text("STOP")
            self.assertTrue(calls[0]["stop_check"]())

    def test_changed_candidate_is_held_even_with_release_marker(self):
        with tempfile.TemporaryDirectory() as d:
            env, served, staging, _, _ = self.fixture(d)
            before=served.read_bytes()
            def cannot_publish(**kwargs):
                raise AssertionError("unsafe changed candidate published")
            x=prod.run_cycle(env=env,mode="publish",
                            previewer=self.preview_changed,
                            publisher=cannot_publish)
            self.assertEqual(x["decision"],"HOLD_UNVERIFIED_CHANGE")
            self.assertFalse(x["production_changed"])
            self.assertFalse(x["ok"])
            self.assertEqual(served.read_bytes(),before)
            self.assertEqual(staging.read_bytes(),before)

    def test_invalid_writer_receipt_refused(self):
        with tempfile.TemporaryDirectory() as d:
            env, _, _, _, _ = self.fixture(d)
            with self.assertRaisesRegex(prod.CycleRefused,"writer_receipt_invalid"):
                prod.run_cycle(env=env,mode="publish",
                    previewer=self.preview_same,publisher=lambda **k:{"ok":False})

    def test_cannot_trust_preview_own_release_claim(self):
        with tempfile.TemporaryDirectory() as d:
            env, _, _, _, _ = self.fixture(d)
            def malicious(db, current, root, now):
                p,a = self.preview_same(db,current,root,now)
                p["production_write_authorized"] = True
                return p,a
            with self.assertRaisesRegex(prod.CycleRefused,"unsafe_candidate_claim"):
                prod.run_cycle(env=env,mode="publish",previewer=malicious)

    def test_invalid_source_inputs_refuse_no_mutations(self):
        with tempfile.TemporaryDirectory() as d:
            env, served, staging, _, _ = self.fixture(d)
            staging.write_bytes(b"bad")
            with self.assertRaisesRegex(prod.CycleRefused,"served_staging_differ"):
                prod.run_cycle(env=env,mode="preview",
                               previewer=self.preview_same)
            self.assertEqual(staging.read_bytes(), b"bad")

    def test_readonly_inspect_works_with_no_release_flag(self):
        with tempfile.TemporaryDirectory() as d:
            env, served, staging, _, release = self.fixture(d)
            release.unlink()
            x=prod.run_cycle(env=env,mode="inspect-only")
            self.assertTrue(x["ok"])
            self.assertEqual(x["canonical_pin_count"],21)


if __name__=="__main__":
    unittest.main()
