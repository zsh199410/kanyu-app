"""sing-box 真握手测试：每节点独立 SOCKS 入口，经节点拉 generate_204。

绝不把配置、URI、密码写进日志；sing-box stderr 默认丢弃（调试时可用环境变量开启）。
"""

import ipaddress
import json
import os
import socket
import subprocess
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from .blocklist_common import is_valid_cert_identity, is_valid_dns_hostname
from .crawler import AEAD_METHODS
from .normalize import check_password, check_uuid, norm_method, norm_transport

SB = "/usr/local/bin/sing-box"
TEST_URL = "https://captive.apple.com/generate_204"
DEBUG = os.environ.get("POOL_TEST_DEBUG") == "1"


def _vmess_no_sni(rec):
    """vmess + TLS + 无有效证书身份 → 不可准入（v2 严格版）。

    与 rules.py 的同名函数同款同序：有效证书身份指严格校验通过的
    SNI（合法 DNS hostname 或合法 IP SAN；占位符、空白、非法
    hostname、异常 IP 形式一律无效）。SNI 无效时：拨号 host 为 IP
    → 拒绝；拨号 host 为严格合法 DNS hostname → 不拒绝（hostname
    本身就是有效证书身份）；既非 IP 也非合法 DNS → 拒绝。
    绝不补猜 SNI、绝不跳过证书验证。
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


def _filter_reason(rec):
    """与 rules.pre_filter 同款同序的拒绝原因（integration-04：字段
    契约与 gate / pre_filter / build 完全一致，见 normalize.py）。
    返回 None 表示可测。密码 "," 现与 pre_filter 一致判
    comma-password（旧版 ", " 判 bad-password 是分歧，已统一）；
    uuid 补 comma-uuid / invalid-uuid（与 pre_filter 同序）。
    """
    proto = rec["protocol"]
    if proto == "vmess":
        if not rec.get("tls"):
            return "vmess-non-tls"
        net, net_status = norm_transport(rec.get("net"))
        if net_status in ("unknown", "invalid") or net not in ("tcp", "ws", ""):
            return "unsupported-transport"
        uuid_check = check_uuid(rec.get("uuid"))
        if uuid_check == "missing":
            return "missing-uuid"
        if uuid_check == "comma":
            return "comma-uuid"
        if uuid_check == "invalid":
            return "invalid-uuid"
        if _vmess_no_sni(rec):
            return "vmess-no-sni"
    elif proto == "trojan":
        t_type, t_status = norm_transport(rec.get("t_type"))
        if t_status in ("unknown", "invalid") or t_type not in ("tcp", "ws", ""):
            return "unsupported-transport"
        pw_check = check_password(rec.get("password"))
        if pw_check == "missing":
            return "missing-password"
        if pw_check == "comma":
            return "comma-password"
        if pw_check == "whitespace":
            return "bad-password"
    elif proto == "ss":
        method, m_status = norm_method(rec.get("method"), AEAD_METHODS)
        if m_status != "ok":
            return "ss-method"
        if rec.get("plugin"):
            return "ss-plugin"
        pw_check = check_password(rec.get("password"))
        if pw_check == "missing":
            return "missing-password"
        if pw_check == "comma":
            return "comma-password"
        if pw_check == "whitespace":
            return "bad-password"
    return None


def build_config(rec):
    proto = rec["protocol"]
    out = {"tag": "node"}
    if proto == "trojan":
        out.update({"type": "trojan", "server": rec["host"], "server_port": rec["port"],
                    "password": rec["password"],
                    "tls": {"enabled": True, "insecure": bool(rec.get("skip_verify"))}})
        if rec.get("sni"):
            out["tls"]["server_name"] = rec["sni"]
        if rec.get("ws"):
            out["transport"] = {"type": "ws", "path": rec.get("ws_path") or "/"}
            if rec.get("ws_host"):
                out["transport"]["headers"] = {"Host": rec["ws_host"]}
    elif proto == "vmess":
        tls_on = bool(rec.get("tls", True))
        out.update({"type": "vmess", "server": rec["host"], "server_port": rec["port"],
                    "uuid": rec["uuid"],
                    "security": rec.get("security") or "auto",
                    "alter_id": 0,
                    "tls": {"enabled": tls_on, "insecure": bool(rec.get("skip_verify"))}})
        if out["security"] not in ("auto", "aes-128-gcm", "chacha20-poly1305", "none"):
            out["security"] = "auto"
        if tls_on and rec.get("sni"):
            out["tls"]["server_name"] = rec["sni"]
        # Defensive normalization (integration-04): _filter_reason has
        # already admitted only normalized tcp/ws; under that input the
        # result is identical to the old raw comparison.
        if norm_transport(rec.get("net"))[0] == "ws":
            out["transport"] = {"type": "ws", "path": rec.get("ws_path") or "/"}
            if rec.get("ws_host"):
                out["transport"]["headers"] = {"Host": rec["ws_host"]}
    elif proto == "ss":
        # Defensive normalization (integration-04): _filter_reason has
        # already admitted only an AEAD method; under that input the
        # result is identical to the old raw value.
        out.update({"type": "shadowsocks", "server": rec["host"], "server_port": rec["port"],
                    "method": norm_method(rec.get("method"), AEAD_METHODS)[0],
                    "password": rec["password"]})
    cfg = {
        "log": {"level": "error"},
        "dns": {"servers": [{"tag": "local", "type": "local"}], "final": "local"},
        "inbounds": [{"type": "mixed", "listen": "127.0.0.1", "listen_port": 0}],
        "outbounds": [out, {"type": "direct", "tag": "direct"}],
        "route": {"final": "node"},
    }
    return cfg


def _wait_port(port, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def test_one(rec, port, timeout=8):
    """返回 (result, ms, reason)：pass / fail / infra / filtered。"""
    reason = _filter_reason(rec)
    if reason:
        return ("filtered", 0.0, reason)
    cfg = build_config(rec)
    cfg["inbounds"][0]["listen_port"] = port
    tmp = None
    proc = None
    try:
        fd, tmp = tempfile.mkstemp(prefix="sb-test-", suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump(cfg, f)
        os.chmod(tmp, 0o600)
        err = None
        if DEBUG:
            err = open(tmp + ".log", "w")
        proc = subprocess.Popen(
            [SB, "run", "-c", tmp],
            stdout=subprocess.DEVNULL,
            stderr=err if err else subprocess.DEVNULL)
        if not _wait_port(port, 3.0):
            return ("infra", 0.0, "singbox-start")
        try:
            r = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}",
                 "--socks5-hostname", f"127.0.0.1:{port}",
                 "--max-time", str(timeout), TEST_URL],
                capture_output=True, timeout=timeout + 4)
            out = r.stdout.decode("utf-8", errors="ignore").strip().split()
            if len(out) >= 2 and out[0].isdigit() and out[0] != "000":
                try:
                    ms = float(out[1]) * 1000.0
                except ValueError:
                    ms = 0.0
                return ("pass", ms, "")
            return ("fail", 0.0, "curl-failed")
        except subprocess.TimeoutExpired:
            return ("fail", 0.0, "curl-timeout")
        except Exception:
            return ("fail", 0.0, "curl-error")
    except Exception:
        return ("infra", 0.0, "test-error")
    finally:
        if proc is not None:
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            if DEBUG:
                try:
                    os.unlink(tmp + ".log")
                except OSError:
                    pass


def test_many(records, concurrency=8, port_base=40000, port_count=100):
    """并发测试；sing-box 启动失败时换一个端口重试一次。返回 [(rec, result, ms, reason)]。"""
    counter = {"n": 0}
    lock = threading.Lock()

    def run(rec):
        with lock:
            counter["n"] += 1
            port = port_base + (counter["n"] % port_count)
        result, ms, reason = test_one(rec, port)
        if result == "infra" and reason == "singbox-start":
            with lock:
                counter["n"] += 1
                port2 = port_base + (counter["n"] % port_count)
            result, ms, reason = test_one(rec, port2)
        return (rec, result, ms, reason)

    with ThreadPoolExecutor(max_workers=concurrency) as ex:
        return list(ex.map(run, records))
