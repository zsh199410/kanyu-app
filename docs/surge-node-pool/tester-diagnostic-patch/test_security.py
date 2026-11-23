"""安全回归测试 v2（GPT #124 审查 P0 安全阻塞）。

验证：
1. umask 022/027 下，sing-box stderr 临时文件仍为 0600（os.open 显式 mode）。
2. 恶意日志注入：sing-box 错误行含 token/SNI/IPv6/密码时，分类结果
   (stage, detail) 与写入 DB 的 diag 均不含任何注入敏感值；且原始日志
   不持久化（临时文件在 test_one 返回后即被删除）。
3. 有界读取：超大日志文件只读末尾 32 KiB、只保留 ERROR 行、最多 20 行。
4. 子进程生命周期：test_one 返回后（pass/fail/timeout 各路径），
   子进程已终止、端口已关闭、/tmp 无 sb-test-* 残留。
5. classify_stage：curl 各退出码与 HTTP 非 000 但 curl 失败的分类。

用法：python3 test_security.py <隔离包目录> <输出json>
隔离包目录为含 pool/ 子包的目录（已打 v2 补丁的隔离副本）。
节点测试用隔离副本跑真实 sing-box+curl（只读订阅抓取，不写生产库）。
"""
import glob
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import time

PKG = sys.argv[1]
OUT = sys.argv[2]
sys.path.insert(0, PKG)
from pool.tester import (_create_log_file, _read_error_lines, _stop_proc,
                         classify_stage, _diag, test_one, LOG_MAX_BYTES, LOG_MAX_LINES)
from pool.crawler import crawl_records

report = {}

# --- 1. umask 022/027 下日志文件仍为 0600 ---
modes = {}
for mask in (0o022, 0o027, 0o077):
    old = os.umask(mask)
    try:
        path = os.path.join(tempfile.gettempdir(), f"sb-umask-test-{mask:o}.log")
        f = _create_log_file(path)
        f.write("ERROR test\n")
        f.close()
        mode = stat.S_IMODE(os.stat(path).st_mode)
        modes[oct(mask)] = oct(mode)
        assert mode == 0o600, f"umask {oct(mask)}: log mode {oct(mode)} != 0600"
        os.unlink(path)
    finally:
        os.umask(old)
report["umask_log_mode_0600"] = modes

# --- 2. 恶意日志注入：分类结果与 DB diag 不含敏感值 ---
SECRETS = {
    "token": "FAKE-TOKEN-DO-NOT-USE-12345",
    "sni": "secret-sni.evil.example.com",
    "ipv6": "2001:db8:85a3::8a2e:370:7334",
    "password": "FAKE-PASSWORD-DO-NOT-USE",
    "host": "evil-inject.example.net",
}
malicious_log = (
    "2026-11-24T00:00:00Z ERROR sing-box: outbound/vmess[node]: "
    f"dial tcp: lookup {SECRETS['host']} failed; sni={SECRETS['sni']} "
    f"token={SECRETS['token']} ip={SECRETS['ipv6']} pass={SECRETS['password']}\n"
    "2026-11-24T00:00:01Z ERROR sing-box: connection timeout after 5s\n"
)
stage, detail = classify_stage(97, "000", malicious_log)
diag = _diag(curl_exit=97, http_code="000", stage=stage, detail=detail,
             timings={"total": 0.05, "lookup": 0.01, "connect": 0.0, "appconnect": 0.0})
blob = json.dumps({"stage": stage, "detail": detail, "diag": diag}, ensure_ascii=False)
leaked = [k for k, v in SECRETS.items() if v in blob]
assert not leaked, f"secrets leaked into diag: {leaked}"
assert stage in ("http", "tcp", "tls", "dns", "timeout", "socks", "infra", "other", "pass")
report["injection_classify"] = {"stage": stage, "detail": detail, "leaked": leaked}

# 注入的 stage/detail 若进 DB 也必须干净（用隔离 DB 验证）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sqlite3
tmpdb = os.path.join(tempfile.gettempdir(), "sb-injection-test.db")
if os.path.exists(tmpdb):
    os.unlink(tmpdb)
sys.path.insert(0, PKG)
from pool import db as dbmod
db = dbmod.connect(tmpdb)
dbmod.record_test(db, "vmess", "203.0.113.20", 443, "fail", "curl-failed", 0.0, diag)
db.commit()
row = db.execute("SELECT * FROM node_tests WHERE host='203.0.113.20'").fetchone()
db.close()
os.unlink(tmpdb)
blob2 = repr(row)
leaked2 = [k for k, v in SECRETS.items() if v in blob2]
assert not leaked2, f"secrets leaked into DB row: {leaked2}"
report["injection_db_row_clean"] = True

# --- 3. 有界读取 ---
big = os.path.join(tempfile.gettempdir(), "sb-biglog-test.log")
with open(big, "w") as f:
    for i in range(20000):
        f.write(f"2026-11-24T00:00:00Z INFO sing-box: filler line {i} " + "x" * 60 + "\n")
    for i in range(30):
        f.write(f"2026-11-24T00:00:00Z ERROR sing-box: error line {i}\n")
    f.write("2026-11-24T00:00:00Z ERROR sing-box: final error marker\n")
got = _read_error_lines(big)
os.unlink(big)
assert "final error marker" in got, "bounded read lost the tail ERROR"
assert len(got.encode()) <= LOG_MAX_BYTES + 4096, f"bounded read too large: {len(got)}"
assert got.count("ERROR") <= LOG_MAX_LINES, f"too many lines: {got.count('ERROR')}"
assert "filler line" not in got, "non-ERROR lines leaked into read"
report["bounded_read"] = {"bytes": len(got.encode()), "error_lines": got.count("ERROR"),
                          "tail_preserved": True}

# --- 4. 子进程生命周期：真实 test_one 三路径后无残留 ---
records, _ = crawl_records("/opt/free-node-program/sources.yaml")
by_key = {(r["protocol"], r["host"], r["port"]): r for r in records}
CASES = [
    ("vmess", "172.64.145.93", 443, "LIFE-candidate"),
    ("vmess", "38.68.135.131", 1270, "LIFE-former-healthy"),
    ("trojan", "103.125.216.11", 443, "LIFE-neg"),
]


def port_open(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.5):
            return True
    except OSError:
        return False


life = []
port = 46300
for proto, host, p, label in CASES:
    rec = by_key.get((proto, host, p))
    if not rec:
        life.append({"label": label, "error": "MISSING in crawl"})
        continue
    before = set(glob.glob(os.path.join(tempfile.gettempdir(), "sb-test-*")))
    out = test_one(rec, port)
    time.sleep(0.5)
    after = set(glob.glob(os.path.join(tempfile.gettempdir(), "sb-test-*")))
    leftover = sorted(after - before)
    assert not leftover, f"{label}: leftover temp files: {leftover}"
    assert not port_open(port), f"{label}: port {port} still open after test_one"
    result, ms, reason, diag = out
    life.append({"label": label, "result": result, "ms": round(ms, 1),
                 "reason": reason, "stage": diag.get("stage"),
                 "detail": diag.get("detail"), "leftover_files": leftover,
                 "port_closed": True})
    port += 1
report["lifecycle"] = life

# --- 5. classify_stage：curl 退出码与 HTTP 非 000 组合 ---
cases = [
    (0, "204", "", ("pass", "http-204")),
    (97, "403", "", ("pass", "http-403")),   # HTTP 已返回则按 HTTP 判定
    (97, "000", "unexpected HTTP response status: 403", ("http", "relay-403")),
    (97, "000", "HTTP response status: 404", ("http", "relay-http-404")),
    (0, "000", "dial tcp: connection refused", ("tcp", "connection-refused")),
    (0, "000", "TLS handshake failure: certificate verify failed", ("tls", "tls-verify")),
    (0, "000", "no such host", ("dns", "dns-fail")),
    (0, "000", "i/o timeout", ("timeout", "singbox-timeout")),
    (28, "000", "", ("timeout", "curl-timeout-28")),
    (7, "000", "", ("tcp", "curl-connect-7")),
    (6, "000", "", ("dns", "curl-dns-6")),
    (97, "000", "", ("socks", "curl-socks-97")),
    (22, "000", "", ("other", "curl-exit-22")),
    (0, "000", "", ("other", "unknown")),
]
for exit_code, http, log, expected in cases:
    got = classify_stage(exit_code, http, log)
    assert got == expected, f"classify({exit_code},{http},{log!r})={got}, want {expected}"
report["classify_matrix"] = {"cases": len(cases), "all_match": True}

with open(OUT, "w") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps(report, ensure_ascii=False, indent=2))
