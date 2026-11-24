"""优选规则引擎：纯规则、可审计；排序按稳定性，VPS 延迟绝不作手机排名。"""

import ipaddress

from .blocklist_common import is_valid_cert_identity, is_valid_dns_hostname
from .crawler import AEAD_METHODS, parse_surge_line
from .geo import IpApi, code_to_flag, display_name, hint_to_code, is_cf_or_reserved
from .normalize import (check_password, check_uuid, is_valid_uuid,
                        norm_method, norm_transport)


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


# B10-EXTENSION v2 (GPT 7121245603, confirmed): a vmess uuid must be a
# legal UUID in the standard 8-4-4-4-12 hex shape. Only the SHAPE is
# checked (version/variant nibbles are not policed); case is free.
# A comma-containing uuid is reported as "comma-uuid" first (v1
# behaviour preserved: the comma is the more specific defect); a
# comma-free but malformed uuid is "invalid-uuid". Neither check
# truncates, replaces or rewrites the credential, and no credential
# is ever recorded by this module.
# (Integration-04: the definition lives in normalize.py so the gate /
# pre_filter / tester / build share one definition; it is re-exported
# here for backward compatibility.)
from .normalize import UUID_RE  # noqa: F401  (re-exported)


def _vmess_no_sni(rec):
    """vmess + TLS + 无有效证书身份 → 不可准入（#128 v2 严格版）。

    有效证书身份指严格校验通过的 SNI（合法 DNS hostname 或合法 IP
    SAN；占位符、空白、非法 hostname、异常 IP 形式一律无效）。
    SNI 无效时：拨号 host 为 IP → 拒绝（IP 拨号无 SNI 无法校验）；
    拨号 host 为严格合法 DNS hostname → 不拒绝（hostname 本身就是
    有效证书身份）；拨号 host 既非 IP 也非合法 DNS → 拒绝（不能只因
    ipaddress 抛错就认定是合法 DNS）。
    绝不补猜 SNI、绝不跳过证书验证；被拒的记录保留库存，只是不进
    测试/发布候选。
    """
    if rec["protocol"] != "vmess" or not rec.get("tls", True):
        return False
    if is_valid_cert_identity(rec.get("sni")):
        return False
    host = rec.get("host")
    try:
        ipaddress.ip_address(host)
        return True
    except (ValueError, TypeError):
        pass
    return not is_valid_dns_hostname(host)


def pre_filter(rec, private_hosts):
    """返回 (保留?, 原因)：原因仅计数，不含任何敏感内容。

    字段契约与 gate / tester / build 完全一致（normalize.py，集成-04）：
    传输与方法先 strip + 小写再比对；认证信息（密码 / uuid）只做
    原值检查，绝不规范化；不确定则拒绝准入。检查顺序与 gate 一致
    （TLS → 传输 → 凭据 → N3），多缺陷记录的首要原因三处相同。
    """
    if is_private(rec["host"], private_hosts):
        return (False, "private-host")
    proto = rec["protocol"]
    if proto == "vmess":
        if not rec.get("tls"):
            return (False, "vmess-non-tls")
        net, net_status = norm_transport(rec.get("net"))
        if net_status in ("unknown", "invalid") or net not in ("tcp", "ws", ""):
            return (False, "unsupported-transport")
        uuid_check = check_uuid(rec.get("uuid"))
        if uuid_check == "missing":
            return (False, "missing-uuid")
        # B10-EXTENSION (GPT 7121245603, confirmed): username= is a
        # comma-split Surge param too, so a comma in the uuid corrupts
        # the line the same way a comma in a password does.
        if uuid_check == "comma":
            return (False, "comma-uuid")
        # B10-EXTENSION v2 (GPT 7121245603): the uuid must also be a
        # legal 8-4-4-4-12 hex UUID; a malformed uuid is refused from
        # publish the same way (never truncated or rewritten).
        if uuid_check == "invalid":
            return (False, "invalid-uuid")
        # N3 (#128 v2, strict): vmess + TLS + 无有效证书身份 -> 拒准入。
        if _vmess_no_sni(rec):
            return (False, "vmess-no-sni")
    elif proto == "trojan":
        t_type, t_status = norm_transport(rec.get("t_type"))
        if t_status in ("unknown", "invalid") or t_type not in ("tcp", "ws", ""):
            return (False, "unsupported-transport")
        pw_check = check_password(rec.get("password"))
        if pw_check == "missing":
            return (False, "missing-password")
        # B10: any comma in the password truncates the Surge line at the
        # comma (fields are comma-split), so the node would publish with
        # a WRONG password. Rejected with or without a following space;
        # the old ", " check is subsumed by ",".
        if pw_check == "comma":
            return (False, "comma-password")
        if pw_check == "whitespace":
            return (False, "bad-password")
    elif proto == "ss":
        method, m_status = norm_method(rec.get("method"), AEAD_METHODS)
        if m_status != "ok":
            return (False, "ss-method")
        if rec.get("plugin"):
            return (False, "ss-plugin")
        pw_check = check_password(rec.get("password"))
        if pw_check == "missing":
            return (False, "missing-password")
        # B10: same as trojan -- any comma, with or without a space.
        if pw_check == "comma":
            return (False, "comma-password")
        if pw_check == "whitespace":
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
        # Shared check with pre_filter / tester (normalize.py).
        if check_password(pw) != "ok":
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
        # B10-EXTENSION v2 (GPT 7121245603): malformed uuids are refused too.
        # Shared check with pre_filter / tester (normalize.py).
        if check_uuid(rec.get("uuid")) != "ok":
            raise ValueError("bad uuid")
        # 防御纵深：未走 pre_filter 的路径误入时直接抛错、计 build_failed。
        # 若 GPT 只要严格的 pre_filter/_filter_reason 范围，可删此两行。
        if _vmess_no_sni(rec):
            raise ValueError("vmess-no-sni")
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
        # Shared check with pre_filter / tester (normalize.py).
        if check_password(pw) != "ok":
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
