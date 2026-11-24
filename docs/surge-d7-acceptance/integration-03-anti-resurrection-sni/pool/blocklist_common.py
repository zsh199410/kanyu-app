"""集成-03 v2 共享基础：严格阻止清单加载、不可变决策日志、WAL 安全备份、严格证书身份校验。

只用标准库。本模块是 pool 包内 rules.py / tester.py / screening.py /
backfill_blocklist.py / unblock_node.py 的共享依赖；backfill 与 unblock
作为独立脚本运行时通过自身所在目录导入本模块（见各脚本顶部的
sys.path 处理），不依赖 live pool 包。

v2 改动（对应 GPT Review 6033772552）：
- load_rejected_strict：缺文件、缺 entries、空、重复、畸形一律
  fail-closed 抛错，绝不悄悄返回空集（v1 的 unblock.load_rejected
  在文件缺失时返回 {}，screening.load_rejected 对缺 entries 默许空集）。
- sqlite_backup：改用 SQLite Backup API（含已提交 WAL 数据），
  替代 shutil.copy2 + 主库 SHA 对比（主库 SHA 相同不证明 WAL 数据
  已进备份）；独占新建备份文件（O_EXCL、0600）、拒同文件及别名、
  绝不覆盖已有文件；备份后校验 integrity 与逻辑内容（表清单与行数）。
- append_decision_log：只追加（O_APPEND + fsync），永不截断；
  解除/回填决策与证据引用以此文件为准，不只依赖 30 天清理的 audit 表。
- is_valid_cert_identity / is_valid_dns_hostname：严格证书身份校验。
  占位符（大小写不限）、空白、非法 hostname、异常 IP 形式一律无效；
  合法 DNS hostname 本身就是有效证书身份（不能只因 ipaddress 抛错
  就认定是合法 DNS）；合法 IP SAN 按已明确支持契约处理，不推测上游。
"""

import hashlib
import ipaddress
import json
import os
import re
import sqlite3

# ---------------------------------------------------------------- 原因口径
REASON_PHONE_FAIL = "phone-fail-20261121"
REASON_OVER_TARGET = "over-target-20261121"
ALLOWED_REASONS = (REASON_PHONE_FAIL, REASON_OVER_TARGET)

# verdict -> reason：DELETE_OVER_TARGET 是容量裁剪，不是手机死亡证据；
# 两类都保持禁入（保守禁入），但不得混淆事实、不得把回填覆盖成更严格原因。
VERDICT_REASON = {
    "DELETE_CANDIDATE_PHONE": REASON_PHONE_FAIL,
    "ALLOWLIST_DELETE": REASON_PHONE_FAIL,
    "DELETE_OVER_TARGET": REASON_OVER_TARGET,
}


def reason_for_verdict(verdict):
    """按原始 verdict 返回应写入 blocklist 的 reason；未知 verdict 拒绝。"""
    try:
        return VERDICT_REASON[verdict]
    except KeyError:
        raise ValueError("unknown verdict for reason mapping: %r" % (verdict,))


# ---------------------------------------------------------------- 严格阻止清单加载
PROTOCOLS = ("ss", "trojan", "vmess")


def load_rejected_strict(path):
    """严格加载 rejected_nodes.json，返回 {triple: entry}。

    fail-closed：文件缺失、JSON 损坏、顶层非对象、entries 缺失/非列表/
    为空、version 缺失或 <1、条目缺字段、协议/端口非法、decision_ref
    为空、重复三元组——任一情况都抛错，绝不悄悄返回空集。
    空 entries 也拒绝：该文件是已裁决记录，空列表意味着记录丢失或
    截断写坏，不能当成“无拒绝项”放行。
    """
    if not path or not os.path.exists(path):
        raise FileNotFoundError("rejected file missing: %r" % (path,))
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("rejected file top level must be an object")
    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("rejected file entries must be a non-empty list")
    version = data.get("version")
    if not isinstance(version, int) or isinstance(version, bool) or version < 1:
        raise ValueError("rejected file version must be an int >= 1")
    out = {}
    for e in entries:
        if not isinstance(e, dict):
            raise ValueError("rejected entry must be an object: %r" % (e,))
        for field in ("protocol", "host", "port", "decision_ref"):
            if field not in e:
                raise ValueError("rejected entry missing %s: %r" % (field, e))
        if e["protocol"] not in PROTOCOLS:
            raise ValueError("bad protocol: %r" % (e,))
        if not isinstance(e["host"], str) or not e["host"]:
            raise ValueError("bad host: %r" % (e,))
        if (not isinstance(e["port"], int) or isinstance(e["port"], bool)
                or not 1 <= e["port"] <= 65535):
            raise ValueError("bad port: %r" % (e,))
        if (not isinstance(e["decision_ref"], str)
                or not e["decision_ref"].strip()):
            raise ValueError(
                "rejected entry decision_ref must be a non-empty string: %r"
                % (e,))
        key = (e["protocol"], e["host"], e["port"])
        if key in out:
            raise ValueError("duplicate triple in rejected file: %r" % (key,))
        out[key] = e
    return out


# ---------------------------------------------------------------- 不可变决策日志
def append_decision_log(path, record):
    """向决策日志追加一条 JSON 记录（只追加，永不截断/改写）。

    文件不存在时以 0600 创建；拒绝符号链接；每次追加后 fsync。
    调用方须保证 record 不含任何凭据（密码/UUID/token/URI）。
    本函数不校验 record 内容，只保证追加语义；内容校验在调用方。
    """
    if not isinstance(record, dict):
        raise ValueError("decision record must be an object")
    if os.path.islink(path):
        raise ValueError("decision log must not be a symlink: %r" % (path,))
    line = (json.dumps(record, ensure_ascii=False, sort_keys=True)
            + "\n").encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, line)
        os.fsync(fd)
    finally:
        os.close(fd)


# ---------------------------------------------------------------- WAL 安全备份
def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _table_rowcounts(conn):
    """返回 {表名: 行数}（不含 sqlite_sequence 之外的内部表）；用于备份后逻辑校验。"""
    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name")]
    out = {}
    for t in tables:
        out[t] = conn.execute(
            'SELECT COUNT(*) FROM "%s"' % t.replace('"', '""')).fetchone()[0]
    return out


def sqlite_backup(src_path, dst_path):
    """用 SQLite Backup API 复制数据库（含已提交 WAL 数据），返回备份文件 SHA-256。

    替代 shutil.copy2 + 主库 SHA 对比：copy2 只拷主库文件，WAL 中未
    checkpoint 的已提交数据不会进备份，而主库 SHA 相同无法发现这一点。
    Backup API 从源连接读取逻辑内容（含 WAL），目标是自包含的完整副本。

    fail-closed：
    - 源文件缺失 → FileNotFoundError；
    - 目标已存在（任何类型，含符号链接）→ 拒绝覆盖；
    - 目标解析后与源同一文件 → 拒绝；
    - 备份后 integrity_check 非 ok，或表清单/行数与源不一致 → 报错，
      并删除不完整的备份文件。
    目标文件以 O_EXCL + 0600 创建；并发写入者存在时 Backup API 仍给出
    一致快照（不依赖瞬时探测代替互斥；跨进程写互斥由 live 单写手负责，
    本函数不声称探测到无写者）。
    """
    if not os.path.exists(src_path):
        raise FileNotFoundError("backup source missing: %r" % (src_path,))
    if os.path.lexists(dst_path):
        raise FileExistsError(
            "backup destination already exists, refusing to overwrite: %r"
            % (dst_path,))
    if os.path.realpath(dst_path) == os.path.realpath(src_path):
        raise ValueError("backup destination is the source file: %r"
                         % (dst_path,))
    # O_EXCL 独占创建空文件（0600），sqlite3 再以该文件为目标库。
    fd = os.open(dst_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
    src_conn = sqlite3.connect("file:%s?mode=ro" % src_path, uri=True)
    try:
        try:
            src_counts = _table_rowcounts(src_conn)
        except sqlite3.Error:
            src_counts = None
        dst_conn = sqlite3.connect(dst_path)
        try:
            src_conn.backup(dst_conn)
        finally:
            dst_conn.close()
    finally:
        src_conn.close()
    # 校验：integrity + 逻辑内容（表清单与行数须与源一致）。
    try:
        chk = sqlite3.connect("file:%s?mode=ro" % dst_path, uri=True)
        try:
            row = chk.execute("PRAGMA integrity_check").fetchone()
            if row is None or row[0] != "ok":
                raise ValueError("backup integrity_check failed: %r" % (row,))
            if src_counts is not None:
                dst_counts = _table_rowcounts(chk)
                if dst_counts != src_counts:
                    raise ValueError(
                        "backup logical content mismatch: src=%r dst=%r"
                        % (src_counts, dst_counts))
        finally:
            chk.close()
    except Exception:
        try:
            os.unlink(dst_path)
        except OSError:
            pass
        raise
    return sha256_file(dst_path)


# ---------------------------------------------------------------- 严格证书身份校验
_LABEL_RE = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")

# 占位符（大小写不限）：抓取/解析层常见的“无值”标记，不得当成有效 SNI。
_SNI_PLACEHOLDERS = frozenset({
    "<nil>", "nil", "null", "none", "n/a", "na", "unknown",
    "<none>", "<null>", "<unknown>", "-", "--", "nulls", "nilnull",
})


def is_valid_dns_hostname(value):
    """严格 DNS hostname 校验（LDH 规则 + 总长 + TLD 非纯数字）。

    允许一个尾随点（合法 FQDN 写法）；标签 1–63 字符、首尾字母数字、
    中间可含连字符；拒绝下划线、空格、空标签、超长；TLD 纯数字时拒绝
    （避免把 "999.999.999.999" 这类异常 IP 形式当成合法 DNS）。
    """
    if not isinstance(value, str):
        return False
    host = value.strip()
    if not host or len(host) > 253:
        return False
    if host.endswith("."):
        host = host[:-1]
        if not host:
            return False
    labels = host.split(".")
    if any(not label for label in labels):
        return False
    if not all(_LABEL_RE.match(label) for label in labels):
        return False
    if labels[-1].isdigit():
        return False
    return True


def _looks_like_ip_attempt(value):
    """值是否像一次 IP 书写尝试（IPv4 数字点分、或含冒号的 IPv6 尝试）。"""
    if ":" in value:
        return True
    if re.fullmatch(r"[0-9.]+", value):
        return True
    return False


def is_valid_cert_identity(value):
    """严格证书身份校验：有效 SNI / IP SAN / DNS hostname 才算有效。

    - 非字符串、空白、占位符（大小写不限）→ 无效；
    - 能解析为 IP → 有效（合法 IP SAN，按已明确支持契约处理）；
    - 像 IP 却解析失败（999.999.999.999、1.2.3.256、2001:db8:::1、
      1.2.3.4.5、example.com:443）→ 无效，不推测上游；
    - 其余须通过严格 DNS hostname 校验才算有效；不能只因
      ipaddress 抛错就认定是合法 DNS。
    """
    if not isinstance(value, str):
        return False
    v = value.strip()
    if not v:
        return False
    if v.lower() in _SNI_PLACEHOLDERS:
        return False
    try:
        ipaddress.ip_address(v)
        return True
    except ValueError:
        pass
    if _looks_like_ip_attempt(v):
        return False
    return is_valid_dns_hostname(v)
