"""Static checker for safe-egress-test.conf (A1).

Parses the conf file with real Python (configparser-style section scan,
not eyeballing) and verifies:
  * the select group "测试安全出口" exists, is a `select` group,
    and its FIRST member is REJECT;
  * no DIRECT token appears anywhere (proxy / group / rule);
  * no nested group type appears (smart / fallback / url-test / load-balance);
  * every group member is either the built-in REJECT or a [Proxy] defined
    in this file;
  * every rule references an existing group (or built-in REJECT);
  * FINAL is REJECT;
  * every test proxy host is inside TEST-NET 192.0.2.0/24.

Usage:  python3 check_conf.py [path-to-conf]
Exit 0 = all checks pass; exit 1 = violations printed.
"""

from __future__ import annotations

import ipaddress
import re
import sys

GROUP_NAME = "测试安全出口"
TEST_NET = ipaddress.ip_network("192.0.2.0/24")
FORBIDDEN_GROUP_TYPES = {"smart", "fallback", "url-test", "load-balance"}
BUILTINS = {"REJECT", "DIRECT"}  # DIRECT is forbidden; listed only to detect it.


def parse_conf(text: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            current = m.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)
    return sections


def _split_top_level(line: str) -> list[str]:
    return [p.strip() for p in line.split(",") if p.strip()]


def check_conf(path: str) -> list[str]:
    errors: list[str] = []
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    sections = parse_conf(text)

    # --- no DIRECT anywhere (token match, case-insensitive) ---
    for section, lines in sections.items():
        for line in lines:
            tokens = re.split(r"[,\s=]+", line)
            if any(t.upper() == "DIRECT" for t in tokens):
                errors.append(f"DIRECT forbidden: [{section}] {line}")

    # --- [Proxy]: hosts must be TEST-NET only ---
    proxies: dict[str, str] = {}
    for line in sections.get("Proxy", []):
        if "=" not in line:
            errors.append(f"malformed proxy line: {line}")
            continue
        name, rest = line.split("=", 1)
        name = name.strip()
        proxies[name] = rest.strip()
        parts = _split_top_level(rest)
        if len(parts) < 3:
            errors.append(f"proxy {name}: too few fields: {line}")
            continue
        try:
            host = ipaddress.ip_address(parts[1])
        except ValueError:
            errors.append(f"proxy {name}: host is not an IP: {parts[1]}")
            continue
        if host not in TEST_NET:
            errors.append(
                f"proxy {name}: host {host} outside TEST-NET 192.0.2.0/24"
            )

    # --- [Proxy Group]: the test egress group ---
    groups: dict[str, list[str]] = {}
    for line in sections.get("Proxy Group", []):
        if "=" not in line:
            errors.append(f"malformed group line: {line}")
            continue
        name, rest = line.split("=", 1)
        name = name.strip()
        parts = _split_top_level(rest)
        groups[name] = parts
        if not parts:
            errors.append(f"group {name}: empty")
            continue
        gtype = parts[0].lower()
        if gtype in FORBIDDEN_GROUP_TYPES:
            errors.append(f"group {name}: nested group type forbidden: {gtype}")
        if gtype != "select":
            errors.append(
                f"group {name}: type must be select, got {gtype!r}"
            )

    if GROUP_NAME not in groups:
        errors.append(f'missing group "{GROUP_NAME}"')
        return errors
    members = groups[GROUP_NAME][1:]
    if not members:
        errors.append(f'group "{GROUP_NAME}" has no members')
    elif members[0] != "REJECT":
        errors.append(
            f'group "{GROUP_NAME}" first member must be REJECT, got {members[0]!r}'
        )
    for member in members:
        if member == "REJECT":
            continue
        if member not in proxies:
            errors.append(
                f'group "{GROUP_NAME}" member {member!r} is not a [Proxy] '
                "defined in this file"
            )
    # No other group may exist in this test profile (defence against
    # smuggled nested groups).
    for name in groups:
        if name != GROUP_NAME:
            errors.append(f"unexpected extra group: {name!r}")

    # --- [Rule]: references must exist; FINAL must be REJECT ---
    final_seen = False
    for line in sections.get("Rule", []):
        parts = _split_top_level(line)
        if not parts:
            continue
        if parts[0].upper() == "FINAL":
            final_seen = True
            if len(parts) < 2 or parts[1] != "REJECT":
                errors.append(f"FINAL must be REJECT, got: {line}")
            continue
        target = parts[-1]
        if target not in groups and target != "REJECT":
            errors.append(f"rule references unknown group/policy: {line}")
    if not final_seen:
        errors.append("missing FINAL rule")

    return errors


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "safe-egress-test.conf"
    errors = check_conf(path)
    if errors:
        print(f"FAIL: {path} — {len(errors)} violation(s):")
        for err in errors:
            print(f"  - {err}")
        return 1
    print(f"PASS: {path} — select group, REJECT first, no DIRECT, "
          "no nested groups, FINAL=REJECT, TEST-NET only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
