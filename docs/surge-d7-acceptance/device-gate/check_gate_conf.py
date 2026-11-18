"""Static auditor for device-gate-test.conf (P0-E).

Parses the conf for real (sections, [Script], [Rule], [Proxy],
[Proxy Group]) and proves the structural properties the device gate
depends on — no eyeballing:

  * the SCRIPT gate rule is the FIRST and ONLY non-FINAL rule, and its
    policy is exactly the gated select group;
  * FINAL,REJECT is present and last; no DIRECT anywhere (rules, groups,
    general); no other policy group is referenced by any rule;
  * no bypass rule types (RULE-SET, GEOIP, IP-CIDR, DOMAIN*, ...) — only
    SCRIPT + FINAL are allowed in this test profile;
  * the gated group is `select, REJECT, <test proxies>` with REJECT
    first and no nested group members;
  * every test proxy is in TEST-NET 192.0.2.0/24 with password test123
    and sni test.invalid; nothing else that looks like a real node;
  * the [Script] section declares the rule script, all three event
    scripts (engine-started / network-changed / profile-reloaded) and
    the cron sweep, all engine=jsc, and the cron fires at most 10
    times/hour (manual battery-warning threshold);
  * no external subscription / MITM / module references.

Usage:
    python3 check_gate_conf.py device-gate-test.conf
Exit 0 = all checks pass; exit 1 = violations listed on stdout.
Stdlib only. No network, no device, no production access.
"""

from __future__ import annotations

import ipaddress
import re
import sys
from urllib.parse import urlsplit

GATE_GROUP = "测试安全出口"
GATE_RULE_SCRIPT = "gate-rule"
GATE_EVENTS_SCRIPT = "gate-events.js"
GATE_SWEEP_SCRIPT = "gate-sweep.js"
EXPECTED_CRON_MAX_PER_HOUR = 10
TEST_NET = ipaddress.ip_network("192.0.2.0/24")
TEST_PROXIES = {"Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"}
# Isolation-only test URLs. This is deliberately NOT a production trust
# model: temporary muse.ai downloads expire and are not content-addressed.
_SCRIPT_FILES = {
    "gate-rule": "gate-script.js",
    "gate-events-boot": "gate-events.js",
    "gate-events-net": "gate-events.js",
    "gate-events-profile": "gate-events.js",
    "gate-sweep": "gate-sweep.js",
}


def script_path_matches(value: str, filename: str) -> bool:
    """Only exact local files or the limited HTTPS isolation download path."""
    if value == filename:
        return True
    if not isinstance(value, str):
        return False
    try:
        u = urlsplit(value)
        return bool(
            u.scheme == "https"
            and u.hostname == "muse.ai"
            and u.username is None
            and u.password is None
            and u.port is None
            and not u.query
            and not u.fragment
            and re.fullmatch(
                r"/files/[0-9]+/[0-9]+/[a-z0-9]+/" + re.escape(filename),
                u.path,
            )
        )
    except ValueError:
        return False


def parse_conf(text: str) -> dict[str, list[str]]:
    """Return {SECTION: [stripped non-empty, non-comment lines]}."""
    sections: dict[str, list[str]] = {}
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        m = re.match(r"^\[(.+)\]$", line)
        if m:
            current = m.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is None:
            raise ValueError(f"line outside any section: {raw!r}")
        sections[current].append(line)
    return sections


def parse_kv(line: str) -> tuple[str, dict[str, str]]:
    """Parse `name = k=v,k2=v2` into (name, {k: v})."""
    if "=" not in line:
        return line, {}
    name, rest = line.split("=", 1)
    params: dict[str, str] = {}
    for part in rest.split(","):
        part = part.strip()
        if "=" in part:
            k, v = part.split("=", 1)
            params[k.strip()] = v.strip().strip('"')
        elif part:
            params[part] = ""
    return name.strip(), params


def cron_runs_per_hour(cronexp: str) -> int | None:
    """Runs/hour for the simple expressions used here; None if complex."""
    fields = cronexp.strip().strip('"').split()
    if len(fields) != 5:
        return None
    minute = fields[0]
    if minute == "*":
        return 60
    m = re.fullmatch(r"\*/(\d+)", minute)
    if m:
        step = int(m.group(1))
        return 60 // step if 60 % step == 0 else None
    if re.fullmatch(r"\d+", minute):
        return 1
    if "," in minute and all(p.isdigit() for p in minute.split(",")):
        return len(minute.split(","))
    return None


def check_conf(path: str) -> list[str]:
    """Return a list of violations (empty = pass)."""
    problems: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        return [f"cannot read conf: {exc}"]
    try:
        sections = parse_conf(text)
    except ValueError as exc:
        return [str(exc)]

    # Only declared/validated gate resources may contain a remote URL.
    trusted_lines = set()
    for line in sections.get("Script", []):
        name, params = parse_kv(line)
        expected = _SCRIPT_FILES.get(name)
        if expected and script_path_matches(params.get("script-path", ""), expected):
            trusted_lines.add(line)

    # --- no DIRECT / no real egress anywhere in the raw text -----------
    for i, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("#"):
            continue
        if re.search(r"\bDIRECT\b", line):
            problems.append(f"line {i}: DIRECT present: {line.strip()!r}")
        if "://" in line and "test.invalid" not in line and line.strip() not in trusted_lines:
            problems.append(f"line {i}: URL-like content: {line.strip()!r}")

    # --- [Proxy]: only TEST-NET test proxies ----------------------------
    proxies = sections.get("Proxy", [])
    seen: set[str] = set()
    for line in proxies:
        name, params = parse_kv(line)
        seen.add(name)
        host = params.get("trojan") or ""
        # trojan line form: `trojan, 192.0.2.1, 443, password=..., sni=...`
        # parse_kv splits on commas, so positional fields land as keys
        # with empty values; recover them from the raw line instead.
        m = re.match(
            r"^[^=]+=\s*trojan,\s*([^,]+),\s*(\d+),\s*password=([^,]+),\s*sni=([^\s,]+)",
            line,
        )
        if not m:
            problems.append(f"[Proxy] unparsable test proxy line: {line!r}")
            continue
        host, _port, password, sni = m.groups()
        try:
            if ipaddress.ip_address(host.strip()) not in TEST_NET:
                problems.append(f"[Proxy] {name} host {host} not in TEST-NET")
        except ValueError:
            problems.append(f"[Proxy] {name} host {host!r} is not an IP")
        if password.strip() != "test123":
            problems.append(f"[Proxy] {name} password is not test123")
        if sni.strip() != "test.invalid":
            problems.append(f"[Proxy] {name} sni is not test.invalid")
    if seen != TEST_PROXIES:
        problems.append(f"[Proxy] members {sorted(seen)} != {sorted(TEST_PROXIES)}")

    # --- [Proxy Group]: exactly one select group, REJECT first ---------
    groups = sections.get("Proxy Group", [])
    if len(groups) != 1:
        problems.append(f"[Proxy Group] expected 1 group, found {len(groups)}")
    for line in groups:
        name, rest = line.split("=", 1)
        members = [p.strip() for p in rest.split(",")]
        if name.strip() != GATE_GROUP:
            problems.append(f"[Proxy Group] unexpected group {name.strip()!r}")
        if not members or members[0] != "select":
            problems.append(f"[Proxy Group] {name.strip()} is not a select group")
        elif members[1:] != ["REJECT"] + sorted(TEST_PROXIES):
            problems.append(
                f"[Proxy Group] members {members[1:]} != REJECT + test proxies"
            )

    # --- [Script]: rule + 3 events + cron ------------------------------
    scripts = sections.get("Script", [])
    decls: dict[str, dict[str, str]] = {}
    for line in scripts:
        name, params = parse_kv(line)
        decls[name] = params
    if set(decls) != set(_SCRIPT_FILES):
        problems.append("[Script] unexpected/missing scripts: "
                        + repr(sorted(set(decls) ^ set(_SCRIPT_FILES))))
    rule = decls.get(GATE_RULE_SCRIPT)
    if rule is None:
        problems.append(f"[Script] missing rule script {GATE_RULE_SCRIPT!r}")
    else:
        if rule.get("type") != "rule":
            problems.append("[Script] gate-rule type is not 'rule'")
        if not script_path_matches(rule.get("script-path", ""), "gate-script.js"):
            problems.append("[Script] gate-rule script-path is not gate-script.js (bare file or https URL ending in /gate-script.js)")
        if rule.get("engine") != "jsc":
            problems.append("[Script] gate-rule engine is not jsc")
    events = {
        name: params
        for name, params in decls.items()
        if params.get("type") == "event"
    }
    want_events = {"engine-started", "network-changed", "profile-reloaded"}
    got_events = {p.get("event-name") for p in events.values()}
    if got_events != want_events:
        problems.append(f"[Script] event-names {sorted(got_events)} != {sorted(want_events)}")
    for name, params in events.items():
        if not script_path_matches(params.get("script-path", ""), GATE_EVENTS_SCRIPT):
            problems.append(f"[Script] event {name} script-path is not {GATE_EVENTS_SCRIPT} (bare file or https URL ending in /{GATE_EVENTS_SCRIPT})")
        if params.get("engine") != "jsc":
            problems.append(f"[Script] event {name} engine is not jsc")
    crons = {
        name: params
        for name, params in decls.items()
        if params.get("type") == "cron"
    }
    if len(crons) != 1 or "gate-sweep" not in crons:
        problems.append("[Script] expected exactly one cron script 'gate-sweep'")
    else:
        sweep = crons["gate-sweep"]
        if not script_path_matches(sweep.get("script-path", ""), GATE_SWEEP_SCRIPT):
            problems.append(f"[Script] gate-sweep script-path is not gate-sweep.js (bare file or https URL ending in /{GATE_SWEEP_SCRIPT})")
        if sweep.get("engine") != "jsc":
            problems.append("[Script] gate-sweep engine is not jsc")
        runs = cron_runs_per_hour(sweep.get("cronexp", ""))
        if runs is None:
            problems.append("[Script] gate-sweep cronexp not understood; cannot bound runs/hour")
        elif runs > EXPECTED_CRON_MAX_PER_HOUR:
            problems.append(
                f"[Script] gate-sweep fires {runs}/hour > {EXPECTED_CRON_MAX_PER_HOUR}/hour battery threshold"
            )

    # --- [Rule]: SCRIPT gate first, FINAL,REJECT last, nothing else -----
    rules = sections.get("Rule", [])
    if not rules:
        problems.append("[Rule] empty rule list")
    else:
        first = rules[0]
        if first != f"SCRIPT,{GATE_RULE_SCRIPT},{GATE_GROUP}":
            problems.append(f"[Rule] first rule is not the gate: {first!r}")
        for line in rules[1:-1]:
            problems.append(f"[Rule] unexpected middle rule (bypass?): {line!r}")
        last = rules[-1]
        if last != "FINAL,REJECT":
            problems.append(f"[Rule] last rule is not FINAL,REJECT: {last!r}")
        for line in rules:
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 3 and parts[2] not in (GATE_GROUP, "REJECT"):
                problems.append(f"[Rule] rule references unexpected policy: {line!r}")
            if parts[0] not in ("SCRIPT", "FINAL"):
                problems.append(f"[Rule] unexpected rule type (bypass?): {line!r}")

    # --- [General]: no subscription / MITM ------------------------------
    general = sections.get("General", [])
    for line in general:
        key = line.split("=")[0].strip().lower()
        if key in ("subscription", "mitm", "module", "rule-set"):
            problems.append(f"[General] unexpected {key} line: {line!r}")
        if key == "http-api":
            # P1 (GPT review 2026-11-18): the test profile's HTTP API
            # is test-only by design (public key test123, LAN listener).
            # It must never carry a real credential: only the test key
            # is allowed here, so a production key can never be baked
            # into this file by accident.
            value = line.split("=", 1)[1].strip() if "=" in line else ""
            if not value.startswith("test123@"):
                problems.append(
                    f"[General] http-api must use the test key test123: {line!r}"
                )
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python3 check_gate_conf.py <device-gate-test.conf>")
        return 2
    problems = check_conf(argv[1])
    if problems:
        print(f"FAIL: {len(problems)} violation(s) in {argv[1]}:")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"PASS: {argv[1]} — gate structure verified (SCRIPT first, FINAL,REJECT, no DIRECT, no bypass)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
