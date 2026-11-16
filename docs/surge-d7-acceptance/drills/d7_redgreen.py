#!/usr/bin/env python3
"""D7 red -> green (Issue #73, GPT D6 review 6904538782, item 2).

The D7 item-2 additions (post-rename hooks, post-bridge crash
hook, verify_targets) do not exist on the D6 tree. This drill
proves the red and the green by running the SAME drill
(drills/d7_item2_legacy_postwrite.py) against both trees:

  R1 RED:  --code-root <D6 tree> -> the drill fails (ImportError:
    verify_targets does not exist on D6; the new hook kwargs
    would also raise TypeError). The D6 code cannot express the
    GPT D6 item-2 evidence.
  R2 GREEN: --code-root <D7 tree> -> the drill passes 15/15.
  R3 API surface: on D6, `from pool.bridge_sync import
    verify_targets` raises ImportError and inspect.signature of
    run_bridge_sync has no post_bridge_hook; on D7 both exist.

The D6 tree is only READ (never modified); --code-root points
the drill at it. --d6-root defaults to the sibling p2p3-d6 tree
(local ~/workspace/p2p3-d6, VPS /opt/p2p3-d6).

Usage: python3 drills/d7_redgreen.py
       [--out docs/d7-redgreen-log.json] [--d6-root PATH]
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
    ap.add_argument("--d6-root",
                    default=os.path.join(os.path.dirname(HERE), "p2p3-d6"))
    args = ap.parse_args()
    d6_root = os.path.abspath(args.d6_root)
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

    drill = os.path.join(HERE, "drills", "d7_item2_legacy_postwrite.py")

    # ---- R1: RED on D6 ----
    p = subprocess.run([sys.executable, drill, "--code-root", d6_root],
                       capture_output=True, text=True, cwd=HERE, timeout=180)
    tail = (p.stderr + p.stdout).strip().splitlines()
    tail = tail[-1][:200] if tail else ""
    check("r1_red_on_d6",
          p.returncode != 0
          and ("verify_targets" in (p.stderr + p.stdout)
               or "TypeError" in (p.stderr + p.stdout)
               or "ImportError" in (p.stderr + p.stdout)),
          "rc=%d tail=%s" % (p.returncode, tail))
    step("R1 red on D6",
         "d7 item-2 drill against the D6 tree fails: the D6 API has "
         "no verify_targets / post-rename hooks",
         rc=p.returncode, error="ImportError/TypeError")

    # ---- R2: GREEN on D7 ----
    p = subprocess.run([sys.executable, drill, "--code-root", HERE],
                       capture_output=True, text=True, cwd=HERE, timeout=180)
    green = {}
    try:
        green = json.loads(p.stdout)
    except Exception:
        green = {}
    check("r2_green_on_d7",
          p.returncode == 0 and green.get("ok") is True
          and green.get("passed") == 15,
          "rc=%d passed=%s/15" % (p.returncode, green.get("passed")))
    step("R2 green on D7",
         "same drill against the D7 tree passes 15/15",
         rc=p.returncode, error="")

    # ---- R3: API surface ----
    probe = (
        "import sys, inspect, json\n"
        "sys.path.insert(0, sys.argv[1])\n"
        "out = {}\n"
        "try:\n"
        "    from pool.bridge_sync import verify_targets\n"
        "    out['verify_targets'] = True\n"
        "except ImportError as e:\n"
        "    out['verify_targets'] = False\n"
        "    out['import_error'] = str(e)[:120]\n"
        "from pool.bridge_sync import run_bridge_sync\n"
        "params = list(inspect.signature(run_bridge_sync).parameters)\n"
        "out['has_post_bridge_hook'] = 'post_bridge_hook' in params\n"
        "out['has_legacy_post_rename_hook'] = "
        "'legacy_post_rename_hook' in params\n"
        "out['has_bridge_post_rename_hook'] = "
        "'bridge_post_rename_hook' in params\n"
        "print(json.dumps(out))\n")
    for label, root, want in (("d6", d6_root, False), ("d7", HERE, True)):
        p = subprocess.run([sys.executable, "-c", probe, root],
                           capture_output=True, text=True, timeout=60)
        try:
            res = json.loads(p.stdout.strip())
        except ValueError:
            res = {"raw": (p.stdout + p.stderr)[:200]}
        ok = (res.get("verify_targets") is want
              and res.get("has_post_bridge_hook") is want
              and res.get("has_legacy_post_rename_hook") is want
              and res.get("has_bridge_post_rename_hook") is want)
        check("r3_api_surface_%s" % label, ok, json.dumps(res)[:200])
    step("R3 API surface",
         "D6 lacks verify_targets + the three D7 hooks; D7 has them",
         error="")

    ok = all(c["ok"] for c in checks)
    log = {"drill": "d7_redgreen", "d6_root": d6_root, "d7_root": HERE,
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
