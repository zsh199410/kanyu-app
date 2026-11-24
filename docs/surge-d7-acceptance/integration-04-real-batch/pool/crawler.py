"""爬取器：Phase 0 计数（不变）+ MVP 记录解析（仅内存，绝不落盘、不记日志）。

记录含密码/UUID，只在内存中流转（爬取 → 测试 → 发布），绝不写 DB、日志、UI。
"""

import base64
import binascii
import json
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen

ALLOWED = ("trojan", "vmess", "ss")
AEAD_METHODS = {
    "aes-128-gcm", "aes-256-gcm", "chacha20-ietf-poly1305",
    "xchacha20-ietf-poly1305",
    "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm",
    "2022-blake3-chacha20-poly1305",
}


def load_sources(path):
    sources = []
    cur = None
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("- name:"):
                cur = {"name": line.split(":", 1)[1].strip(), "protocols": []}
                sources.append(cur)
            elif line.startswith("url:") and cur is not None:
                cur["url"] = line.split(":", 1)[1].strip()
            elif line.startswith("protocols:") and cur is not None:
                inner = line.split(":", 1)[1].strip().strip("[]")
                cur["protocols"] = [x.strip() for x in inner.split(",") if x.strip()]
    return [s for s in sources if s.get("url")]


def fetch(url):
    req = Request(url, headers={"User-Agent": "free-node-program/phase0"})
    with urlopen(req, timeout=20) as r:
        data = r.read(20 * 1024 * 1024)
    return data.decode("utf-8", errors="ignore")


def b64decode(s):
    s = s.strip()
    s += "=" * (-len(s) % 4)
    try:
        return base64.b64decode(s, validate=False).decode("utf-8", errors="ignore")
    except (binascii.Error, ValueError):
        return base64.urlsafe_b64decode(s).decode("utf-8", errors="ignore")


def decode_body(text):
    lines = [l.strip() for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]
    uri_lines = [l for l in lines if "://" in l]
    if len(uri_lines) >= max(1, len(lines) // 2):
        return uri_lines
    try:
        decoded = b64decode("".join(lines))
    except Exception:
        return lines
    dlines = [l.strip() for l in decoded.splitlines()
              if l.strip() and "://" in l and not l.strip().startswith("#")]
    return dlines if dlines else lines


def parse_uri(line):
    """Phase 0 计数用：返回 (protocol, host, port, tls_flag)。"""
    if "://" not in line:
        return (None, None, None, None)
    scheme, rest = line.split("://", 1)
    scheme = scheme.strip().lower()
    body = rest.split("#", 1)[0].strip()
    try:
        if scheme == "vmess":
            obj = json.loads(b64decode(body))
            host = str(obj.get("add", "")).strip().strip("[]").lower()
            port = int(obj.get("port", 0))
            tls = obj.get("tls")
            is_tls = tls in ("tls", True, "true", "True", 1)
            if not host or not port:
                return (scheme, None, None, None)
            return ("vmess", host, port, is_tls)
        if scheme == "trojan":
            u = urlparse("trojan://" + body)
            if not u.hostname or not u.port:
                return (scheme, None, None, None)
            return ("trojan", u.hostname.lower(), int(u.port), None)
        if scheme == "ss":
            part = body.split("?", 1)[0]
            if "@" not in part:
                try:
                    part = b64decode(part)
                except Exception:
                    return (scheme, None, None, None)
            if "@" not in part:
                return (scheme, None, None, None)
            hostport = part.rsplit("@", 1)[1]
            if ":" not in hostport:
                return (scheme, None, None, None)
            host, port_s = hostport.rsplit(":", 1)
            host = host.strip().strip("[]").lower()
            port = int(port_s)
            if not host or not port:
                return (scheme, None, None, None)
            return ("ss", host, port, None)
        return (scheme, None, None, None)
    except Exception:
        return (scheme, None, None, None)


def crawl_all(sources_path):
    sources = load_sources(sources_path)
    total = {"sources": len(sources), "sources_ok": 0, "sources_failed": 0,
             "total_lines": 0, "by_protocol": {}, "unique_total": 0,
             "vmess_tls": 0, "vmess_non_tls": 0, "unparsed": 0,
             "other_protocol": {}, "by_source": {}}
    seen = set()
    for s in sources:
        name = s["name"]
        allowed = set(s.get("protocols") or ALLOWED)
        sc = {"total": 0, "by_protocol": {}, "unique": 0, "status": "ok", "error": ""}
        try:
            lines = decode_body(fetch(s["url"]))
        except HTTPError as e:
            sc["status"] = "failed"
            sc["error"] = f"http_{e.code}"
            total["sources_failed"] += 1
            total["by_source"][name] = sc
            continue
        except (URLError, TimeoutError, OSError):
            sc["status"] = "failed"
            sc["error"] = "network"
            total["sources_failed"] += 1
            total["by_source"][name] = sc
            continue
        except Exception:
            sc["status"] = "failed"
            sc["error"] = "other"
            total["sources_failed"] += 1
            total["by_source"][name] = sc
            continue
        total["sources_ok"] += 1
        local_seen = set()
        for line in lines:
            proto, host, port, tls = parse_uri(line)
            if proto is None:
                total["unparsed"] += 1
                continue
            if proto not in allowed:
                total["other_protocol"][proto] = total["other_protocol"].get(proto, 0) + 1
                continue
            if host is None:
                total["unparsed"] += 1
                continue
            sc["total"] += 1
            sc["by_protocol"][proto] = sc["by_protocol"].get(proto, 0) + 1
            total["by_protocol"][proto] = total["by_protocol"].get(proto, 0) + 1
            total["total_lines"] += 1
            if proto == "vmess":
                if tls:
                    total["vmess_tls"] += 1
                else:
                    total["vmess_non_tls"] += 1
            key = (proto, host, port)
            if key not in seen:
                seen.add(key)
                local_seen.add(key)
        sc["unique"] = len(local_seen)
        total["by_source"][name] = sc
    total["unique_total"] = len(seen)
    return total


# ---------------- MVP 记录解析（内存） ----------------

def _split_hostport(hostport):
    hostport = hostport.strip()
    if hostport.startswith("["):
        end = hostport.find("]")
        if end < 0:
            return (None, None)
        host = hostport[1:end].lower()
        rest = hostport[end + 1:]
        if not rest.startswith(":"):
            return (None, None)
        try:
            return (host, int(rest[1:]))
        except ValueError:
            return (None, None)
    if ":" not in hostport:
        return (None, None)
    host, port_s = hostport.rsplit(":", 1)
    try:
        return (host.strip().lower(), int(port_s))
    except ValueError:
        return (None, None)


def _bool(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v != 0
    if isinstance(v, str):
        return v.strip().lower() in ("1", "true", "yes")
    return False


def _parse_query(qs):
    out = {}
    for part in qs.split("&"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[unquote(k).lower()] = unquote(v)
        elif part:
            out[unquote(part).lower()] = ""
    return out


def parse_record(line, source):
    """返回记录 dict；无法解析返回 None；非白名单协议返回 ('other', scheme)。"""
    if "://" not in line:
        return None
    scheme, rest = line.split("://", 1)
    scheme = scheme.strip().lower()
    if scheme not in ALLOWED:
        return ("other", scheme)
    frag = ""
    if "#" in rest:
        rest, frag = rest.split("#", 1)
        frag = unquote(frag)
    try:
        if scheme == "trojan":
            main, query = (rest.split("?", 1) + [""])[:2] if "?" in rest else (rest, "")
            if "@" not in main:
                return None
            pw_enc, hostport = main.rsplit("@", 1)
            host, port = _split_hostport(hostport)
            if not host or not port:
                return None
            q = _parse_query(query)
            ws = q.get("type", "").lower() == "ws" or _bool(q.get("ws", ""))
            return {
                "protocol": "trojan", "host": host, "port": port, "source": source,
                "name_hint": frag, "password": unquote(pw_enc),
                "t_type": q.get("type", "") or "tcp",
                "sni": q.get("sni") or q.get("peer") or None,
                "ws": ws, "ws_path": q.get("path") or "/",
                "ws_host": q.get("host") or None,
                "skip_verify": _bool(q.get("allowinsecure", q.get("skip-cert-verify", ""))),
            }
        if scheme == "vmess":
            obj = json.loads(b64decode(rest))
            host = str(obj.get("add", "")).strip().strip("[]").lower()
            try:
                port = int(obj.get("port", 0))
            except (ValueError, TypeError):
                return None
            if not host or not port:
                return None
            tls_v = obj.get("tls")
            is_tls = tls_v in ("tls", True, "true", "True", 1)
            net = str(obj.get("net", "") or "").lower() or "tcp"
            return {
                "protocol": "vmess", "host": host, "port": port, "source": source,
                "name_hint": str(obj.get("ps", "") or "") or frag,
                "uuid": str(obj.get("id", "") or ""),
                "security": str(obj.get("scy", "") or "auto") or "auto",
                "net": net, "tls": is_tls,
                "ws_path": str(obj.get("path", "") or "/") or "/",
                "ws_host": str(obj.get("host", "") or "") or None,
                "sni": str(obj.get("sni", "") or "") or None,
                "skip_verify": _bool(obj.get("skip-cert-verify", "")),
            }
        if scheme == "ss":
            main, query = (rest.split("?", 1) + [""])[:2] if "?" in rest else (rest, "")
            plugin = None
            if query:
                q = _parse_query(query)
                plugin = q.get("plugin") or None
            if "@" in main:
                userinfo_part, hostport = main.rsplit("@", 1)
                try:
                    decoded = b64decode(userinfo_part)
                    if ":" in decoded and all(32 <= ord(c) < 127 or ord(c) > 127 for c in decoded):
                        method, password = decoded.split(":", 1)
                    else:
                        raise ValueError("not b64 userinfo")
                except Exception:
                    if ":" not in userinfo_part:
                        return None
                    method, password = userinfo_part.split(":", 1)
                    password = unquote(password)
                    method = unquote(method)
            else:
                try:
                    decoded = b64decode(main)
                except Exception:
                    return None
                if "@" not in decoded or ":" not in decoded:
                    return None
                userinfo, hostport = decoded.rsplit("@", 1)
                if ":" not in userinfo:
                    return None
                method, password = userinfo.split(":", 1)
            host, port = _split_hostport(hostport)
            if not host or not port or not method:
                return None
            return {
                "protocol": "ss", "host": host, "port": port, "source": source,
                "name_hint": frag, "method": method.strip().lower(),
                "password": password, "plugin": plugin,
            }
    except Exception:
        return None
    return None


def parse_surge_line(line):
    """解析 Surge 代理行，只返回 (名字, 协议, host, port, 是否完好)；密码一律丢弃。"""
    try:
        if " = " not in line:
            return (None, None, None, None, False)
        name, rest = line.split(" = ", 1)
        parts = [p.strip() for p in rest.split(",")]
        if len(parts) < 3:
            return (None, None, None, None, False)
        proto = parts[0].strip().lower()
        host = parts[1].strip().strip("[]").lower()
        port = int(parts[2].strip())
        params = {}
        for p in parts[3:]:
            if "=" in p:
                k, v = p.split("=", 1)
                params[k.strip().lower()] = v.strip()
        ok = proto in ALLOWED and bool(host) and port > 0
        if proto == "trojan":
            ok = ok and "password" in params
        elif proto == "vmess":
            ok = ok and "username" in params
        elif proto == "ss":
            ok = ok and "encrypt-method" in params and "password" in params
        return (name.strip(), proto, host, port, ok)
    except Exception:
        return (None, None, None, None, False)


def crawl_records(sources_path, skip=None, on_observation=None):
    """返回 (records, counts)：records 为去重后的白名单记录（内存）；counts 仅计数。
    skip 中的源名在抓取前就排除（不发请求、不计入 sources_ok/total）。
    on_observation（可选）：逐行解析后的回调，每解析成功一行即调用一次，
    位置在协议允许检查之后、去重判断之前（D1 Test B 位置）。回调用于
    来源血缘记录：同一三元组在多源出现时，去重前每一行都须被看见，
    否则镜像证据与认证变体全部丢失（Test A 已证）。回调内部只做
    record_sighting，不改去重与 nodes 表写入语义。回调抛错时计入
    counts["observation_errors"]，不中断抓取（血缘是附加诊断，失败
    不得拖垮生产抓取；失败只意味着该行无血缘记录，绝不产生伪证据）。
    未传回调时行为与旧版完全一致。"""
    sources = load_sources(sources_path)
    if skip:
        sources = [s for s in sources if s["name"] not in skip]
    records = {}
    counts = {"sources": len(sources), "sources_ok": 0, "sources_failed": 0,
              "total": 0, "by_protocol": {}, "unique": 0,
              "vmess_tls": 0, "vmess_non_tls": 0, "unparsed": 0,
              "other_protocol": {}, "by_source": {}}
    for s in sources:
        name = s["name"]
        allowed = set(s.get("protocols") or ALLOWED)
        sc = {"total": 0, "by_protocol": {}, "status": "ok", "error": "",
              # Integration-04 (Review 6034205305 point 2): per-source
              # parse stats, so the batch layer can tell a complete
              # crawl from a partially parsed one. The global counters
              # (counts["unparsed"] / counts["observation_errors"]) are
              # kept unchanged for backward compatibility.
              "unparsed": 0, "observation_errors": 0}
        try:
            lines = decode_body(fetch(s["url"]))
        except HTTPError as e:
            sc["status"] = "failed"
            sc["error"] = f"http_{e.code}"
            counts["sources_failed"] += 1
            counts["by_source"][name] = sc
            continue
        except (URLError, TimeoutError, OSError):
            sc["status"] = "failed"
            sc["error"] = "network"
            counts["sources_failed"] += 1
            counts["by_source"][name] = sc
            continue
        except Exception:
            sc["status"] = "failed"
            sc["error"] = "other"
            counts["sources_failed"] += 1
            counts["by_source"][name] = sc
            continue
        counts["sources_ok"] += 1
        for line in lines:
            rec = parse_record(line, name)
            if rec is None:
                counts["unparsed"] += 1
                sc["unparsed"] += 1
                continue
            if isinstance(rec, tuple):
                counts["other_protocol"][rec[1]] = counts["other_protocol"].get(rec[1], 0) + 1
                continue
            if rec["protocol"] not in allowed:
                counts["other_protocol"][rec["protocol"]] = counts["other_protocol"].get(rec["protocol"], 0) + 1
                continue
            # D1 钩子点（Test B 位置）：逐行解析成功后、去重之前。
            # 去重后才挂钩（Test A）会丢镜像证据与认证变体，禁止用。
            if on_observation is not None:
                try:
                    on_observation(rec)
                except Exception:
                    counts["observation_errors"] = counts.get("observation_errors", 0) + 1
                    sc["observation_errors"] += 1
            sc["total"] += 1
            sc["by_protocol"][rec["protocol"]] = sc["by_protocol"].get(rec["protocol"], 0) + 1
            counts["total"] += 1
            counts["by_protocol"][rec["protocol"]] = counts["by_protocol"].get(rec["protocol"], 0) + 1
            if rec["protocol"] == "vmess":
                if rec["tls"]:
                    counts["vmess_tls"] += 1
                else:
                    counts["vmess_non_tls"] += 1
            key = (rec["protocol"], rec["host"], rec["port"])
            if key not in records:
                records[key] = rec
        counts["by_source"][name] = sc
    counts["unique"] = len(records)
    return list(records.values()), counts
