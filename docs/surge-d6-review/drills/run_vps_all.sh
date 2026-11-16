#!/bin/bash
# D6 VPS full verification runner (run on the VPS as root).
# Runs: full unittest suite (root), full suite as d5test (non-root),
# and every drill. Each step prints a one-line PASS/FAIL summary.
# Logs land in docs/*-log-vps.json under /opt/p2p3-d6.
set -u
cd /opt/p2p3-d6 || exit 1
echo "=== env: python $(python3 --version 2>&1) user $(whoami) ==="
ls -d /opt/p2p3-d5 /opt/p2p3-d4 2>&1

echo "=== 1. full suite, root ==="
python3 -m unittest discover -s tests 2>&1 | tail -3

echo "=== 2. full suite, non-root (d5test) ==="
bash drills/run_nonroot_tests.sh --log docs/nonroot-test-log-vps.json 2>&1 | tail -3

echo "=== 3. cross-cycle drill ==="
python3 drills/cross_cycle_drill.py --out docs/cross-cycle-drill-log-vps.json 2>&1 | tail -1
python3 -c "import json; l=json.load(open('docs/cross-cycle-drill-log-vps.json')); print('cross-cycle:', l['passed'], '/', l['total'], 'ok:', l['ok'])"

echo "=== 4. crash-window drill N=20 ==="
python3 drills/crash_window_drill.py --iterations 20 --out docs/crash-window-drill-log-vps.json 2>&1 | tail -1
python3 -c "import json; l=json.load(open('docs/crash-window-drill-log-vps.json')); print('crash-window:', l.get('summary'), 'all_pass:', l.get('all_pass'))"

echo "=== 5. backup-restore drill ==="
python3 drills/backup_restore_drill.py --log docs/backup-restore-drill-log-vps.json 2>&1 | tail -1
python3 -c "import json; l=json.load(open('docs/backup-restore-drill-log-vps.json')); print('backup-restore: passed', l['passed'], 'failed', l['failed'], 'informational', l['informational'], 'ok:', l['ok'])"

echo "=== 6. cross-cycle redgreen (D4 vs D6) ==="
python3 drills/cross_cycle_redgreen.py --d4-root /opt/p2p3-d4 --out docs/cross-cycle-redgreen-log-vps.json 2>&1 | tail -1
python3 -c "import json; l=json.load(open('docs/cross-cycle-redgreen-log-vps.json')); print('cc-redgreen:', l['passed'], '/', l['total'], 'ok:', l['ok'])"

echo "=== 7. d6 item drills ==="
for n in 1 2 3; do
  python3 drills/d6_item${n}_*.py --out docs/d6-item${n}-drill-log-vps.json > /tmp/d6-item${n}-vps.out 2>&1
  echo "item${n} rc=$?"
  python3 -c "import json; l=json.load(open('/tmp/d6-item${n}-vps.out')); print('item${n}:', l['passed'], '/', l['total'], 'ok:', l['ok'])"
done

echo "=== 8. d6 redgreen (D5 vs D6) ==="
python3 drills/d6_redgreen.py --d5-root /opt/p2p3-d5 --out docs/d6-redgreen-log-vps.json 2>&1 | tail -1
python3 -c "import json; l=json.load(open('docs/d6-redgreen-log-vps.json')); print('d6-redgreen:', l['passed'], '/', l['total'], 'ok:', l['ok'])"

echo "=== done ==="
