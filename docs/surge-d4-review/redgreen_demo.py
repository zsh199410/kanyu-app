"""Red->green demo for D2 blocker 1 (GPT attack scenario).

Same scenario on D1 code vs D2 code:
  seed clean 14, then publish clean14 while claiming source_version_sha
  of the ORIGINAL pool44 but pointing at a file with one byte changed.
D1 trusts the caller SHA and publishes (rc=0) -> defect reproduced (RED).
D2 verifies sha256(actual bytes) and refuses (rc=1) -> fixed (GREEN).

Usage: python3 redgreen_demo.py <tree_dir>   # tree_dir = p2p3-d1 or p2p3-d2
"""
import hashlib
import json
import os
import sys
import tempfile

TREE = sys.argv[1]
sys.path.insert(0, TREE)
FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
# fixtures live next to this script's tree; allow override
FIX = os.environ.get("FIXDIR", os.path.join(TREE, "fixtures"))

from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402


def read_lines(p):
    with open(p, encoding="utf-8") as f:
        return [ln.rstrip("\n") for ln in f if ln.strip()]


def main():
    workdir = tempfile.mkdtemp(prefix="redgreen-")
    pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
    clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
    record_path = os.path.join(FIX, "native_results_fixture.json")
    probe_db = os.path.join(FIX, "p0_fixture.db")
    with open(record_path) as f:
        record = json.load(f)
    version_sha = record["runs"][0]["version_sha"]
    now = record["runs"][0]["tested_at"] + 3600
    pool44_path = os.path.join(FIX, "pool_44_fixture.txt")
    target = os.path.join(workdir, "publish", "pool-new.txt")

    kwargs = {"probe_db": probe_db, "now": now}
    if "p2p3-d2" in TREE:
        kwargs["source_file"] = pool44_path
    rc, res = run_publish(workdir, clean14, record_path, version_sha, **kwargs)
    print("seed rc=%s ok=%s" % (rc, res.get("ok")))
    assert rc == 0, res
    before = file_manifest(target)["sha256"]

    mod_lines = list(pool44)
    mod_lines[0] = mod_lines[0].replace(
        "TEST-ONLY-NOT-A-REAL-NODE", "TEST-ONLY-CHANGED")
    mod_path = os.path.join(workdir, "modified.txt")
    with open(mod_path, "w", encoding="utf-8") as f:
        f.write("\n".join(mod_lines) + "\n")
    print("modified file sha=%s (claimed version_sha=%s)"
          % (hashlib.sha256(open(mod_path, "rb").read()).hexdigest()[:12],
             version_sha[:12]))

    kwargs2 = {"probe_db": probe_db, "now": now}
    if "p2p3-d2" in TREE:
        kwargs2["source_file"] = mod_path
    rc, res = run_publish(workdir, clean14, record_path, version_sha, **kwargs2)
    after = file_manifest(target)["sha256"]
    print("attack rc=%s error=%s target_unchanged=%s"
          % (rc, res.get("error"), after == before))
    print("VERDICT: %s" % ("RED-defect-reproduced"
                            if rc == 0 else "GREEN-refused"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
