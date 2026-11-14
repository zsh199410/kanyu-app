"""Red->green demo for the D3 P0 (GPT D2 review 6884522235).

Same scenario on D2 code vs D3 code:
  seed clean 14, then DELETE the recovery-state file and publish again.
D2 has no gate: publish succeeds (rc=0) -> the fail-open defect
reproduced (RED). D3 refuses (rc=1, recovery_state_missing) and the
publish file is unchanged (GREEN).

Usage: python3 redgreen_d3_demo.py <tree_dir>
  tree_dir = p2p3-d2 (red) or p2p3-d3 (green)
"""

import json
import os
import sys
import tempfile

TREE = sys.argv[1]
sys.path.insert(0, TREE)
FIX = os.environ.get("FIXDIR", os.path.join(TREE, "fixtures"))

from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402

try:
    from pool.recovery import OWNER_ACK_INIT, init_recovery_state
    HAS_D3 = True
except ImportError:
    HAS_D3 = False


def read_lines(p):
    with open(p, encoding="utf-8") as f:
        return [ln.rstrip("\n") for ln in f if ln.strip()]


def main():
    workdir = tempfile.mkdtemp(prefix="redgreen-d3-")
    clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
    record_path = os.path.join(FIX, "native_results_fixture.json")
    probe_db = os.path.join(FIX, "p0_fixture.db")
    with open(record_path) as f:
        record = json.load(f)
    version_sha = record["runs"][0]["version_sha"]
    now = record["runs"][0]["tested_at"] + 3600
    pool44_path = os.path.join(FIX, "pool_44_fixture.txt")
    target = os.path.join(workdir, "publish", "pool-new.txt")
    state_path = os.path.join(workdir, "recovery-state.json")

    if HAS_D3:
        rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
        print("init rc=%s %s" % (rc, out.get("mode", out.get("error"))))
        assert rc == 0, out
    rc, res = run_publish(workdir, clean14, record_path, version_sha,
                          probe_db=probe_db, now=now,
                          source_file=pool44_path)
    print("seed rc=%s ok=%s" % (rc, res.get("ok")))
    assert rc == 0, res
    before = file_manifest(target)["sha256"]
    print("state file exists after seed: %s" % os.path.exists(state_path))

    if os.path.exists(state_path):
        os.unlink(state_path)
    print("state file deleted; publish again...")
    rc, res = run_publish(workdir, clean14, record_path, version_sha,
                          probe_db=probe_db, now=now,
                          source_file=pool44_path)
    after = file_manifest(target)["sha256"]
    print("attack rc=%s error=%s target_unchanged=%s"
          % (rc, res.get("error"), after == before))
    print("VERDICT: %s" % ("RED-defect-reproduced"
                            if rc == 0 else "GREEN-refused"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
