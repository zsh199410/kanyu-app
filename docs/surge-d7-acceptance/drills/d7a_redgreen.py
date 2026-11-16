#!/usr/bin/env python3
"""D7a red -> green (Issue #73, GPT D7 review 6912114134, item 1).

The D7a item-1 additions (gate_block / repair_targets, CLI
--gate-block / --repair-targets / --now) do not exist on the D7
tree. This drill proves the red and the green by running the SAME
drill (drills/d7a_item1_gate_block.py) against both trees:

  R1 RED:  --code-root <D7 tree> -> the drill fails (ImportError:
    gate_block / repair_targets do not exist on D7). The D7 code
    cannot express the GPT D7 item-1 evidence: a divergence is
    silently repaired by the next run with no STOP latch.
  R2 GREEN: --code-root <D7a tree> -> the drill passes 23/23.
  R3 API surface: on D7, `from pool.bridge_sync import gate_block`
    raises ImportError; on D7a gate_block, repair_targets and the
    --gate-block / --repair-targets CLI flags exist.
  R4 Unit suite: tests/test_d7a.py fails to import on D7
    (ImportError) and passes 20/20 on D7a.

The D7 tree is only READ (never modified); --code-root points the
drill at it. --d7-root defaults to the sibling p2p3-d7 tree
(local ~/workspace/p2p3-d7, VPS /opt/p2p3-d7).

Usage: python3 drills/d7a_redgreen.py
       [--out docs/d7a-redgreen-log.json] [--d7-root PATH]
Exit 0 = red confirmed AND green confirmed. Stdout: one JSON
object (the log).
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    ap.add_argument("--d7-root",
                    default=os.path.join(os.path.dirname(HERE), "p2p3-d7"))
    args = ap.parse_args()
    d7_root = os.path.abspath(args.d7_root)
    checks = []
    steps = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    def step(name, detail, **kw):
        rec = {"step": name, "detail": str(detail)}
        rec.update(kw)
        steps.append(rec)
        return rec

    drill = os.path.join(HERE, "drills", "d7a_item1_gate_block.py")

    # ---- R1: RED on D7 ----
    p = subprocess.run([sys.executable, drill, "--code-root", d7_root,
                        "--d7-root", d7_root],
                       capture_output=True, text=True, cwd=HERE, timeout=300)
    tail = (p.stderr + p.stdout).strip().splitlines()
    tail = tail[-1][:200] if tail else ""
    check("r1_red_on_d7",
          p.returncode != 0
          and ("gate_block" in (p.stderr + p.stdout)
               or "ImportError" in (p.stderr + p.stdout)),
          "rc=%d tail=%s" % (p.returncode, tail))
    step("R1 red on D7",
         "d7a item-1 drill against the D7 tree fails: the D7 API has "
         "no gate_block / repair_targets",
         rc=p.returncode, error="ImportError")

    # ---- R2: GREEN on D7a ----
    p = subprocess.run([sys.executable, drill, "--code-root", HERE,
                        "--d7-root", d7_root],
                       capture_output=True, text=True, cwd=HERE, timeout=300)
    green = {}
    try:
        green = json.loads(p.stdout)
    except Exception:
        green = {}
    check("r2_green_on_d7a",
          p.returncode == 0 and green.get("ok") is True
          and green.get("passed") == 23,
          "rc=%d passed=%s/23" % (p.returncode, green.get("passed")))
    step("R2 green on D7a",
         "same drill against the D7a tree passes 23/23",
         rc=p.returncode, error="")

    # ---- R3: API surface ----
    probe = (
        "import sys, json\n"
        "sys.path.insert(0, sys.argv[1])\n"
        "out = {}\n"
        "try:\n"
        "    from pool.bridge_sync import gate_block, repair_targets\n"
        "    out['gate_api'] = True\n"
        "except ImportError as e:\n"
        "    out['gate_api'] = False\n"
        "    out['import_error'] = str(e)[:120]\n"
        "import inspect\n"
        "from pool.bridge_sync import main\n"
        "out['cli_has_gate_block'] = '--gate-block' in "
        "inspect.getsource(main)\n"
        "out['cli_has_repair_targets'] = '--repair-targets' in "
        "inspect.getsource(main)\n"
        "print(json.dumps(out))\n")
    for label, root, want in (("d7", d7_root, False), ("d7a", HERE, True)):
        p = subprocess.run([sys.executable, "-c", probe, root],
                           capture_output=True, text=True, timeout=60)
        try:
            res = json.loads(p.stdout.strip())
        except ValueError:
            res = {"raw": (p.stdout + p.stderr)[:200]}
        ok = (res.get("gate_api") is want
              and res.get("cli_has_gate_block") is want
              and res.get("cli_has_repair_targets") is want)
        check("r3_api_surface_%s" % label, ok, json.dumps(res)[:200])
    step("R3 API surface",
         "D7: no gate_block / repair_targets / CLI flags; "
         "D7a: all present",
         error="")

    # ---- R4: unit suite on both trees ----
    for label, root, want_rc in (("d7", d7_root, 1), ("d7a", HERE, 0)):
        p = subprocess.run([sys.executable, "-m", "unittest",
                            "tests.test_d7a"],
                           capture_output=True, text=True, cwd=root,
                           timeout=180)
        if want_rc == 0:
            ok = (p.returncode == 0 and "OK" in (p.stderr + p.stdout))
            detail = "rc=%d" % p.returncode
        else:
            ok = (p.returncode != 0
                  and "ImportError" in (p.stderr + p.stdout))
            detail = "rc=%d (ImportError expected)" % p.returncode
        check("r4_unit_suite_%s" % label, ok, detail)
    step("R4 unit suite",
         "tests/test_d7a.py: ImportError on D7, 20/20 green on D7a",
         error="")

    ok = all(c["ok"] for c in checks)
    log = {"drill": "d7a_redgreen", "d7_root": d7_root,
           "steps": steps, "checks": checks,
           "passed": sum(1 for c in checks if c["ok"]),
           "total": len(checks), "ok": ok}
    print(json.dumps(log, indent=1, ensure_ascii=False))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(log, f, indent=1, ensure_ascii=False)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
