#!/bin/bash
# D5 non-root test runner (GPT D3 review 6886420557, item 1).
#
# test_d3.py's chmod-000 test SKIPS under root (the kernel lets root
# read through chmod 000), so the unreadable-file/dir cases were never
# actually run green. This script runs the D5 suite
# (tests/test_d5_d3.py) plus tests/test_d3.py as a dedicated non-root
# user (d5test, no sudo), where chmod 000 really blocks reads.
#
# What it does (idempotent, safe to re-run):
#   1. Creates user d5test (home /home/d5test, no sudo) if missing.
#   2. Gives d5test traverse (o+x) on the ancestor dirs of the D5
#      tree and read+traverse (a+rX) on the tree itself, so the test
#      user can read the code and the synthetic fixtures. It does NOT
#      change ownership and does NOT touch anything outside the D5
#      tree (or its ancestor dirs' traverse bit).
#   3. Prepares a scratch dir /tmp/d5-nonroot owned by d5test (the
#      tests create their temp workdirs under /tmp).
#   4. Runs the suites as d5test via runuser, collects a JSON log
#      (counts, per-test outcome, skip reasons, euid, exit code)
#      and copies it to the --log path (default
#      docs/nonroot-test-log.json; on the VPS pass
#      docs/nonroot-test-log-vps.json).
#
# Usage (as root, from anywhere):
#   drills/run_nonroot_tests.sh [--root DIR] [--log FILE]
# Exit code: the test suites' exit code (0 = all non-skipped green).
# Production is never touched: only this D5 tree and /tmp/d5-nonroot.
set -u

D5_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$D5_ROOT/docs/nonroot-test-log.json"
USER="d5test"
SCRATCH="/tmp/d5-nonroot"

while [ $# -gt 0 ]; do
    case "$1" in
        --root) D5_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
        --log)  LOG="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
case "$LOG" in
    /*) : ;;
    *)  LOG="$D5_ROOT/$LOG" ;;
esac

# 1. Test user (no sudo).
if ! id -u "$USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$USER"
    echo "created user $USER"
fi
echo "test user: $(id "$USER")"

# 2. Read access to the tree: traverse on every ancestor dir, a+rX
#    on the tree itself.
dir="$D5_ROOT"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    chmod o+x "$dir"
    dir="$(dirname "$dir")"
done
chmod -R a+rX "$D5_ROOT"

# 3. Scratch dir for the test user.
mkdir -p "$SCRATCH"
chown "$USER:$USER" "$SCRATCH"
chmod 700 "$SCRATCH"

# 4. Run the suites as the non-root user; the inline runner writes a
#    JSON log to the scratch dir (d5test cannot write docs/ directly).
SCRATCH_LOG="$SCRATCH/nonroot-test-log.json"
runuser -u "$USER" -- python3 - "$D5_ROOT" "$SCRATCH_LOG" <<'PYEOF'
import json, os, sys, time, unittest
root, out_path = sys.argv[1], sys.argv[2]
sys.path.insert(0, root)
os.chdir(root)

class Rec(unittest.TestResult):
    def __init__(self):
        super().__init__()
        self.records = []
    def _rec(self, test, status, detail=""):
        self.records.append({"test": str(test), "status": status,
                             "detail": detail})
    def addSuccess(self, test):
        super().addSuccess(test)
        self._rec(test, "pass")
    def addFailure(self, test, err):
        super().addFailure(test, err)
        self._rec(test, "fail", self._exc_info_to_string(err, test))
    def addError(self, test, err):
        super().addError(test, err)
        self._rec(test, "error", self._exc_info_to_string(err, test))
    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self._rec(test, "skipped", reason)

loader = unittest.TestLoader()
suite = loader.loadTestsFromNames(["tests.test_d5_d3", "tests.test_d3"])
result = Rec()
t0 = time.time()
suite.run(result)
dt = round(time.time() - t0, 3)
passed = sum(1 for r in result.records if r["status"] == "pass")
failed = sum(1 for r in result.records if r["status"] in ("fail", "error"))
skipped = sum(1 for r in result.records if r["status"] == "skipped")
log = {
    "suite": ["tests.test_d5_d3", "tests.test_d3"],
    "run_as": {"euid": os.geteuid(), "user": os.environ.get("USER", ""),
               "uid": os.getuid()},
    "python": sys.version.split()[0],
    "root": root,
    "duration_s": dt,
    "total": len(result.records),
    "passed": passed,
    "failed": failed,
    "skipped": skipped,
    "skip_reasons": sorted({r["detail"] for r in result.records
                            if r["status"] == "skipped"}),
    "exit_code": 0 if failed == 0 else 1,
    "tests": result.records,
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(log, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("total=%d passed=%d failed=%d skipped=%d euid=%d exit=%d"
      % (log["total"], passed, failed, skipped,
         log["run_as"]["euid"], log["exit_code"]))
sys.exit(log["exit_code"])
PYEOF
RC=$?

# 5. Publish the log where the task expects it.
mkdir -p "$(dirname "$LOG")"
cp "$SCRATCH_LOG" "$LOG"
chmod 644 "$LOG"
echo "log: $LOG"
exit $RC
