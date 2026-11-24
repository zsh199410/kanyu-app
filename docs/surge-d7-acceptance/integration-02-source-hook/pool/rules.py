"""优选规则引擎：纯规则、可审计；排序按稳定性，VPS 延迟绝不作手机排名。"""

import ipaddress

from .crawler import AEAD_METHODS, parse_surge_line
from .geo import IpApi, code_to_flag, display_name, hint_to_code, is_cf_or_reserved


def load_private_hosts(path):
    hosts = set()
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                hosts.add(line.lower())
    except OSError:
        pass
    return hosts


def is_private(host, private_hosts):
    host = host.lower()
    if host in private_hosts:
        return True
    try:
        ip = ipaddress.ip_address(host)
        return (ip.is_private or ip.is_loopback or ip.is_link_local
                or ip.is_reserved or ip.is_multicast)
    except ValueError:
        pass
    for ph in private_hosts:
        if "." in ph and not ph[0].isdigit():
            if host.endswith("." + ph):
                return True
    return False


def pre_filter(rec, private_hosts):
    """返回 (保留?, 原因)：原因仅计数，不含任何敏感内容。"""
    if is_private(rec["host"], private_hosts):
        return (False, "private-host")
    proto = rec["protocol"]
    if proto == "vmess":
        if not rec.get("tls"):
            return (False, "vmess-non-tls")
        if rec.get("net", "tcp") not in ("tcp", "ws", ""):
            return (False, "unsupported-transport")
        if not rec.get("uuid"):
            return (False, "missing-uuid")
        # B10-EXTENSION (same defect class as B10, flagged for GPT
        # confirmation): username= is a comma-split Surge param too, so
        # a comma in the uuid corrupts the line the same way a comma in
        # a password does. Live prevalence re-measured in the probe.
        if "," in rec.get("uuid", ""):
            return (False, "comma-uuid")
    elif proto == "trojan":
        if rec.get("t_type", "tcp") not in ("tcp", "ws", ""):
            return (False, "unsupported-transport")
        if not rec.get("password"):
            return (False, "missing-password")
        # B10: any comma in the password truncates the Surge line at the
        # comma (fields are comma-split), so the node would publish with
        # a WRONG password. Rejected with or without a following space;
        # the old ", " check is subsumed by ",".
        if "," in rec["password"]:
            return (False, "comma-password")
        if rec["password"] != rec["password"].strip():
            return (False, "bad-password")
    elif proto == "ss":
        if rec.get("method", "") not in AEAD_METHODS:
            return (False, "ss-method")
        if rec.get("plugin"):
            return (False, "ss-plugin")
        if not rec.get("password"):
            return (False, "missing-password")
        # B10: same as trojan -- any comma, with or without a space.
        if "," in rec["password"]:
            return (False, "comma-password")
        if rec["password"] != rec["password"].strip():
            return (False, "bad-password")
    else:
        return (False, "protocol")
    return (True, "")


def build_surge_line(rec, display):
    proto = rec["protocol"]
    host = rec["host"]
    port = rec["port"]
    if proto == "trojan":
        pw = rec["password"]
        # B10: any comma (not just ", ") truncates the Surge line.
        if "," in pw or pw != pw.strip():
            raise ValueError("bad password")
        line = f"{display} = trojan, {host}, {port}, password={pw}"
        if rec.get("sni"):
            line += f", sni={rec['sni']}"
        if rec.get("skip_verify"):
            line += ", skip-cert-verify=true"
        if rec.get("ws"):
            line += f", ws=true, ws-path={rec.get('ws_path') or '/'}"
            if rec.get("ws_host"):
                line += f", ws-headers=Host:{rec['ws_host']}"
        return line
    if proto == "vmess":
        # B10-EXTENSION: comma in the uuid corrupts username= the same way.
        if "," in rec.get("uuid", ""):
            raise ValueError("bad uuid")
        line = (f"{display} = vmess, {host}, {port}, username={rec['uuid']}, "
                f"vmess-aead=true")
        if rec.get("tls", True):
            line += ", tls=true"
        if rec.get("sni"):
            line += f", sni={rec['sni']}"
        if rec.get("skip_verify"):
            line += ", skip-cert-verify=true"
        if rec.get("net") == "ws":
            line += f", ws=true, ws-path={rec.get('ws_path') or '/'}"
            if rec.get("ws_host"):
                line += f", ws-headers=Host:{rec['ws_host']}"
        return line
    if proto == "ss":
        pw = rec["password"]
        # B10: any comma (not just ", ") truncates the Surge line.
        if "," in pw or pw != pw.strip():
            raise ValueError("bad password")
        return f"{display} = ss, {host}, {port}, encrypt-method={rec['method']}, password={pw}"
    raise ValueError("unknown protocol")


def assign_names(items, pinned_names, ipapi):
    """items: [(record, pass_rate, first_seen)] 已按稳定性排好序。
    返回 [(record, display_name, country_code)]；命名失败一律未知，不编造。"""
    used = set(pinned_names)
    counters = {}
    out = []
    for rec, _rate, _seen in items:
        code = hint_to_code(rec.get("name_hint") or "")
        english = ""
        if not code:
            code, english = ipapi.country(rec["host"])
        cn, flag = display_name(code, english)
        base = f"{cn} {flag}" if flag else cn
        if base not in used:
            name = base
        else:
            n = counters.get(base, 2)
            while True:
                cand = f"{cn}{n} {flag}" if flag else f"{cn}{n}"
                if cand not in used:
                    name = cand
                    counters[base] = n + 1
                    break
                n += 1
        used.add(name)
        out.append((rec, name, code))
    return out


def select_publish(pinned_lines, rotation_items, blocked, private_hosts,
                   per_country_cap, publish_max_lines, ipapi):
    """pinned_lines: [(name, proto, host, port, line_text)]（原文，原样输出）。
    rotation_items: [(record, pass_rate, first_seen)]（已过滤为 DB 最近一次通过）。
    返回 (lines, stats)。"""
    lines = []
    stats = {"pinned": 0, "rotation": 0, "by_country": {}, "by_protocol": {},
             "capped": 0, "build_failed": 0, "blocked_skipped": 0}
    pinned_keys = set()
    for name, proto, host, port, text in pinned_lines:
        key = (proto, host, port)
        pinned_keys.add(key)
        if key in blocked:
            stats["blocked_skipped"] += 1
            continue
        lines.append(text)
        stats["pinned"] += 1
        stats["by_protocol"][proto] = stats["by_protocol"].get(proto, 0) + 1
    pinned_names = [n for n, _p, _h, _po, _t in pinned_lines]
    # 排序：通过率降序，首次见升序（越老越稳）；绝不用 VPS 延迟排序。
    ordered = sorted(rotation_items, key=lambda x: (-x[1], x[2]))
    named = assign_names(ordered, pinned_names, ipapi)
    country_count = {}
    for rec, name, code in named:
        if len(lines) >= publish_max_lines:
            break
        key = (rec["protocol"], rec["host"], rec["port"])
        if key in blocked or key in pinned_keys:
            stats["blocked_skipped"] += 1
            continue
        c = code or "unknown"
        if country_count.get(c, 0) >= per_country_cap:
            stats["capped"] += 1
            continue
        try:
            line = build_surge_line(rec, name)
        except ValueError:
            stats["build_failed"] += 1
            continue
        lines.append(line)
        country_count[c] = country_count.get(c, 0) + 1
        stats["rotation"] += 1
        stats["by_country"][c] = stats["by_country"].get(c, 0) + 1
        stats["by_protocol"][rec["protocol"]] = stats["by_protocol"].get(rec["protocol"], 0) + 1
    return lines, stats
