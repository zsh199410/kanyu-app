"""Regression: a no-op publish must not destroy the last distinct rollback anchor.

Runs entirely in a temporary directory; never accesses real subscriptions.
Usage: python3 -m unittest discover -s tests -p 'test_distinct_rollback_anchor.py' -v
"""
import json
import os
import tempfile
import unittest

from pool.publish_lock import atomic_publish_locked, sha256_file


class DistinctRollbackAnchorTests(unittest.TestCase):
    def test_repeated_identical_publish_keeps_previous_different_version(self):
        a = ["Test A = ss, 192.0.2.1, 443"]
        b = ["Test B = ss, 192.0.2.2, 443"]
        c = ["Test C = ss, 192.0.2.3, 443"]
        with tempfile.TemporaryDirectory() as root:
            pub = os.path.join(root, "publish")
            lock = os.path.join(root, "lock", "publish.lock")
            target = os.path.join(pub, "pool-new.txt")
            prev = target + ".prev"

            def publish(lines, version):
                return atomic_publish_locked(
                    pub, "pool-new.txt", lines, lock,
                    source_version_sha=version * 64)

            publish(a, "a")
            sha_a = sha256_file(target)
            publish(b, "b")
            sha_b = sha256_file(target)
            self.assertNotEqual(sha_a, sha_b)
            self.assertEqual(sha256_file(prev), sha_a)

            for _ in range(6):  # Simulate repeated hourly same-byte writes.
                result = publish(b, "b")
                self.assertIsNone(result["snapshot_path"])
                self.assertEqual(sha256_file(target), sha_b)
                self.assertEqual(sha256_file(prev), sha_a)
                with open(prev + ".meta.json", encoding="utf-8") as fp:
                    self.assertEqual(json.load(fp)["source_version_sha"], "a" * 64)

            history = os.path.join(pub, "history")
            snaps = [name for name in os.listdir(history)
                     if name.endswith(".txt")]
            self.assertEqual(len(snaps), 1)
            self.assertEqual(sha256_file(os.path.join(history, snaps[0])), sha_a)

            publish(c, "c")
            self.assertEqual(sha256_file(prev), sha_b)
            snaps = [name for name in os.listdir(history)
                     if name.endswith(".txt")]
            self.assertEqual(
                {sha256_file(os.path.join(history, name)) for name in snaps},
                {sha_a, sha_b})


if __name__ == "__main__":
    unittest.main()
