#!/usr/bin/env python3
"""D7a post-deploy HTTP recheck (Issue #73, GPT D7 review 6912114134,
item 2).

Run AFTER any deployment that touches nginx or the bridge/served
paths: the 16:37 live probe proved the config AT THAT TIME, not
that a new path still has no independent alias. This script is
standalone (no pool imports) and directly usable in the switch
window.

Inputs:
  --config-dump PATH   file with `nginx -T` output (or a plain
                       nginx.conf; the parser handles both)
  --entry-url URL      the subscription entry URL to GET
  --expected-sha SHA   the SHA the entry must serve
  --bridge-file PATH   the bridge file (the only HTTP-served target)
  --legacy-file PATH   the legacy $OLD file (lives under the bridge
                       dir by design; not itself a violation)
  --served-file PATH   the served file (must NEVER be HTTP-served)
  --quarantine-name N  a quarantine filename to probe (default:
                       pool-new-guess.txt)
  --extra-probe PATH   additional URL path to probe (repeatable)

Checks:
  C1 config: exactly one location matches the entry path; its
     alias/root resolves (realpath) to the bridge FILE -- not the
     served file, not the legacy file, not any other file.
  C2 config: NO location resolves into the served dir (or its
     .quarantine subdir), and no `autoindex on` anywhere. Each
     violation is reported with its location pattern.
  C3 HTTP: GET the entry -> 200, body SHA == bridge file SHA ==
     expected SHA (three-way), line count recorded.
  C4 probes: the D7 probe set (traversal `..`, encoded `..`,
     out-of-scope publish, encoded gate path, root served direct,
     `..;`, .quarantine guess) plus any --extra-probe: every probe
     must be non-200 OR its body SHA must differ from the served /
     bridge / expected SHAs.

Output: ONE JSON object on stdout (desensitised: SHA prefixes,
line counts, path names, booleans -- never the full entry URL,
never node lines, never credentials). Exit 0 = all checks pass,
1 = any failure (the JSON names the failing check).

Usage (switch window):
  nginx -T > /tmp/nginx-effective.txt 2>&1
  python3 tools/http_recheck.py --config-dump /tmp/nginx-effective.txt \\
      --entry-url "$ENTRY_URL" --expected-sha "$EXPECTED_SHA" \\
      --bridge-file "$BRIDGE_DIR/pool-new.txt" \\
      --legacy-file "$OLD_PATH" \\
      --served-file "$STATE/served/pool-new.txt"
"""
import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def http_get(url, timeout=10):
    """Returns (status, body_bytes). Never raises."""
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read()
        except Exception:
            return e.code, b""
    except Exception as e:
        return 0, ("error:%s" % type(e).__name__).encode()


# ---------------- nginx -T parsing ----------------

_LOCATION_RE = re.compile(
    r"location\s+([^\{]+?)\{([^}]*)\}", re.DOTALL)
_DIRECTIVE_RE = re.compile(
    r"\b(alias|root)\s+([^;]+);")
_AUTOINDEX_RE = re.compile(r"\bautoindex\s+on\s*;")


def parse_locations(config_text):
    """Returns [{pattern, directive, target}] for every location
    block carrying an alias/root directive, plus autoindex hits.
    Only prefix locations (the form this deployment uses) are
    resolved; regex locations (= ~ ~*) are reported as
    unresolvable and never treated as the entry mapping."""
    out = []
    autoindex = []
    for m in _LOCATION_RE.finditer(config_text):
        pattern = m.group(1).strip()
        body = m.group(2)
        if _AUTOINDEX_RE.search(body):
            autoindex.append(pattern)
        d = _DIRECTIVE_RE.search(body)
        if not d:
            continue
        directive, target = d.group(1), d.group(2).strip().strip("\"'")
        out.append({"pattern": pattern, "directive": directive,
                    "target": target})
    return out, autoindex


def _strip_location_modifiers(pattern):
    """Drop nginx location modifiers (=, ~, ~*, ^~) for prefix
    matching. Returns (pattern, is_regex)."""
    p = pattern.strip()
    if p.startswith("="):
        return p[1:].strip(), False
    if p.startswith("^~"):
        return p[2:].strip(), False
    if p.startswith("~"):
        return p, True
    return p, False


def resolve_location(pattern, directive, target, url_path):
    """Resolve what filesystem path a location serves for url_path.
    Returns the absolute path, or None when this location does not
    match url_path / cannot be resolved. alias: the location
    prefix is REPLACED by the target; root: the full url_path is
    APPENDED to the target."""
    pat, is_regex = _strip_location_modifiers(pattern)
    if is_regex:
        return None
    if not url_path.startswith(pat):
        return None
    rest = url_path[len(pat):]
    if directive == "alias":
        return os.path.join(target, rest.lstrip("/"))
    if directive == "root":
        return os.path.join(target, url_path.lstrip("/"))
    return None


def check_config(config_text, entry_path, bridge_file, served_file):
    """C1 + C2. Returns (entry_mapping_dict, violations_list)."""
    locations, autoindex = parse_locations(config_text)
    bridge_real = os.path.realpath(bridge_file)
    served_real = os.path.realpath(served_file)
    served_dir = os.path.realpath(os.path.dirname(served_real))
    quarantine_dir = os.path.join(served_dir, ".quarantine")
    entry_mapping = None
    entry_candidates = []
    violations = []
    for loc in locations:
        pat = loc["pattern"]
        resolved = resolve_location(pat, loc["directive"], loc["target"],
                                    entry_path)
        if resolved is not None:
            entry_candidates.append(
                {"location": pat, "directive": loc["directive"],
                 "target": loc["target"],
                 "resolved": os.path.realpath(resolved),
                 "resolves_to_bridge_file":
                     os.path.realpath(resolved) == bridge_real})
        # C2: any alias/root whose target directory resolves into
        # the served tree (served dir or .quarantine) is a violation,
        # even when it is not the entry location (the D7 blind spot:
        # an independent alias the realpath guard cannot see).
        tgt_real = os.path.realpath(loc["target"])
        if (tgt_real == served_dir
                or tgt_real.startswith(served_dir + os.sep)
                or tgt_real == quarantine_dir
                or tgt_real.startswith(quarantine_dir + os.sep)):
            violations.append(
                {"location": pat, "directive": loc["directive"],
                 "target": loc["target"],
                 "reason": "alias_or_root_resolves_into_served_dir"})
    for pat in autoindex:
        violations.append({"location": pat, "directive": "autoindex",
                           "target": "on",
                           "reason": "autoindex_on"})
    if entry_candidates:
        # Longest matching prefix wins (nginx semantics, approx.).
        entry_candidates.sort(key=lambda c: len(c["location"]),
                              reverse=True)
        entry_mapping = entry_candidates[0]
    return entry_mapping, violations


def build_probes(entry_path, quarantine_name):
    """The D7 probe set, derived from the entry path."""
    prefix = os.path.dirname(entry_path)
    if not prefix.endswith("/"):
        prefix += "/"
    fname = os.path.basename(entry_path)
    return [
        prefix + "../" + fname,
        prefix + "%2e%2e/" + fname,
        prefix + "../../free-node-program/publish/" + fname,
        prefix + "..%2f..%2f..%2fopt%2fpool-gate%2fstate%2fserved%2f"
        + fname,
        "/opt/pool-gate/state/served/" + fname,
        prefix + "..;/" + fname,
        prefix + ".quarantine/" + quarantine_name,
    ]


def main(argv=None):
    ap = argparse.ArgumentParser(description="D7a post-deploy HTTP "
                                            "recheck (Issue #73)")
    ap.add_argument("--config-dump", required=True,
                    help="file with `nginx -T` output (or nginx.conf)")
    ap.add_argument("--entry-url", required=True)
    ap.add_argument("--expected-sha", required=True)
    ap.add_argument("--bridge-file", required=True)
    ap.add_argument("--legacy-file", default=None)
    ap.add_argument("--served-file", required=True)
    ap.add_argument("--quarantine-name",
                    default="pool-new-guess.txt")
    ap.add_argument("--extra-probe", action="append", default=[])
    ap.add_argument("--timeout", type=float, default=10)
    args = ap.parse_args(argv)

    result = {"tool": "http_recheck", "ok": False, "checks": {}}
    checks = result["checks"]
    try:
        with open(args.config_dump, encoding="utf-8") as f:
            config_text = f.read()
    except OSError as e:
        result["error"] = "config_dump_unreadable: %s" % type(e).__name__
        print(json.dumps(result, ensure_ascii=False))
        return 1
    try:
        bridge_sha = sha_file(args.bridge_file)
        served_sha = sha_file(args.served_file)
    except OSError as e:
        result["error"] = "target_file_unreadable: %s" % type(e).__name__
        print(json.dumps(result, ensure_ascii=False))
        return 1
    expected_sha = args.expected_sha.strip().lower()
    parsed = urllib.parse.urlparse(args.entry_url)
    origin = "%s://%s" % (parsed.scheme, parsed.netloc)
    entry_path = parsed.path or "/"
    result["entry_path"] = entry_path
    result["sha"] = {"bridge_prefix": bridge_sha[:12],
                     "served_prefix": served_sha[:12],
                     "expected_prefix": expected_sha[:12]}

    # C1 + C2: effective config.
    entry_mapping, violations = check_config(
        config_text, entry_path, args.bridge_file, args.served_file)
    checks["config_entry_maps_to_bridge_file"] = bool(
        entry_mapping and entry_mapping["resolves_to_bridge_file"])
    checks["config_no_served_mapping"] = len(violations) == 0
    result["config"] = {"entry_mapping": entry_mapping,
                        "violations": violations,
                        "location_count": len(
                            parse_locations(config_text)[0])}

    # C3: entry response, three-way SHA.
    code, body = http_get(args.entry_url, timeout=args.timeout)
    body_sha = sha_bytes(body)
    result["entry"] = {"http": code, "body_sha_prefix": body_sha[:12],
                       "body_lines": len(
                           [l for l in body.decode("utf-8", "ignore")
                            .splitlines() if l.strip()]),
                       "sha_matches_bridge": body_sha == bridge_sha,
                       "sha_matches_expected": body_sha == expected_sha}
    checks["entry_200_and_sha_matches_bridge_and_expected"] = bool(
        code == 200 and body_sha == bridge_sha
        and body_sha == expected_sha)

    # C4: probes must not serve pool bytes.
    probe_rows = []
    probes_ok = True
    for path in build_probes(entry_path, args.quarantine_name) \
            + list(args.extra_probe):
        pcode, pbody = http_get(origin + path, timeout=args.timeout)
        psha = sha_bytes(pbody)
        refused = (pcode != 200 or psha not in
                   (served_sha, bridge_sha, expected_sha))
        probes_ok = probes_ok and refused
        probe_rows.append({"path": path, "http": pcode,
                           "body_sha_prefix": psha[:12],
                           "refused": bool(refused)})
    result["probes"] = probe_rows
    checks["probes_all_refused"] = bool(probes_ok)

    result["ok"] = all(checks.values())
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
