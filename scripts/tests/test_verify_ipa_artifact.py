"""Tests for the offline artifact verifier; run with python -m unittest discover -s scripts/tests."""
import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_ipa_artifact import inspect


class ArtifactIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def make_zip(self, name, entries):
        path = self.root / name
        with zipfile.ZipFile(path, "w") as archive:
            for key, value in entries.items():
                archive.writestr(key, value)
        return path

    def test_valid_ipa_and_digest(self):
        path = self.make_zip("test.ipa", {"Payload/Test.app/Info.plist": b"plist"})
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        result = inspect(path, expected)
        self.assertEqual(result["kind"], "ipa")
        self.assertFalse(result["source_commit_verified"])
        self.assertFalse(result["device_tested"])

    def test_digest_mismatch(self):
        path = self.make_zip("test.ipa", {"Payload/Test.app/Info.plist": b"plist"})
        with self.assertRaisesRegex(ValueError, "mismatch"):
            inspect(path, "0" * 64)

    def test_missing_app(self):
        path = self.make_zip("test.ipa", {"README": b"no app"})
        with self.assertRaisesRegex(ValueError, "Payload"):
            inspect(path)

    def test_two_apps(self):
        path = self.make_zip("test.ipa", {"Payload/A.app/Info.plist": b"a", "Payload/B.app/Info.plist": b"b"})
        with self.assertRaisesRegex(ValueError, "exactly one"):
            inspect(path)

    def test_artifact_with_inner_ipa(self):
        ipa = self.make_zip("inner.ipa", {"Payload/Test.app/Info.plist": b"plist"})
        outer = self.make_zip("artifact.zip", {"inner.ipa": ipa.read_bytes()})
        self.assertEqual(inspect(outer)["kind"], "artifact-zip")

    def test_reject_non_zip(self):
        path = self.root / "bad.ipa"
        path.write_bytes(b"not zip")
        with self.assertRaisesRegex(ValueError, "not a ZIP"):
            inspect(path)


if __name__ == "__main__":
    unittest.main()
