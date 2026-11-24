#!/usr/bin/env python3
"""集成-03 v2 隔离测试：GPT Review 6033772552 四项收口。

- Part F: WAL 安全备份（Backup API，含已提交 WAL 数据；copy2 对照）
- Part G: 事务内重核对（预检与写入之间的竞态不被 INSERT OR IGNORE 吞掉）
- Part H: 解禁生产路径禁用 + 严格 rejected 加载 + 不可变决策日志 + 无整库恢复路径
- Part I: 端到端防复活（重抓/改名/VPS 通过 → 筛查/组批/补位/正式发布全拒；发布 guard）
- Part J: N3 严格证书身份负例（占位符/非法 hostname/异常 IP 形式/合法 DNS）
- Part K: B10 / B10-EXTENSION / O1 / N3 组合回归（#127 rules 与本包 rules 组合）
- Part L: live 发布链统一阻止清单（pool-db-source.patch + make_preview +
  _preflight；组批/补位/正式发布真实入口）

只读 live 证据、不写 live 库、不联网、不启动生产 worker。
快照副本与夹具复用 v1 work/。用法：python3 tests/test_integration_03_v2.py
退出码 0 = 全部通过；任一失败打印 FAIL 并 exit 1。
"""

import hashlib
import importlib.util
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                     # pr-source/
WORK = os.path.abspath(os.path.join(ROOT, "..", "work"))
SNAPSHOT = os.path.join(WORK, "pool-snapshot.db")
FIXTURE = os.path.join(WORK, "crawl-20261124-desensitized.json")
AUDIT_JSON = os.path.join(ROOT, "pool", "blocklist_backfill_20261121.json")
REJECTED_JSON = os.path.join(ROOT, "pool", "rejected_nodes.json")
BACKFILL = os.path.join(ROOT, "pool", "backfill_blocklist.py")
UNBLOCK = os.path.join(ROOT, "pool", "unblock_node.py")
LIVE_CLI = os.path.join(WORK, "live", "cli.py")
PATCHED_CLI = os.path.join(WORK, "cli-patched.py")
I02_POOL_DIR = os.path.abspath(os.path.join(
    ROOT, "..", "..", "pr127-integration-02", "pr-source", "pool"))

sys.path.insert(0, ROOT)
from pool import rules as rules_mod          # noqa: E402
from pool import tester as tester_mod        # noqa: E402
from pool import screening as screening_mod  # noqa: E402
from pool import blocklist_common as common_mod  # noqa: E402
from pool import backfill_blocklist as bf_mod    # noqa: E402

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("PASS %s" % name)
    else:
        FAIL += 1
        print("FAIL %s %s" % (name, detail))


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def load_pkg_sub(pkg_name, pkg_dir, mod_name):
    """把 pkg_dir 作为包 pkg_name 加载其中的 mod_name（相对导入可解析）。"""
    pkg_spec = importlib.util.spec_from_file_location(
        pkg_name, os.path.join(pkg_dir, "__init__.py"),
        submodule_search_locations=[pkg_dir])
    pkg = importlib.util.module_from_spec(pkg_spec)
    sys.modules[pkg_name] = pkg
    pkg_spec.loader.exec_module(pkg)
    spec = importlib.util.spec_from_file_location(
        "%s.%s" % (pkg_name, mod_name),
        os.path.join(pkg_dir, mod_name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    sys.modules["%s.%s" % (pkg_name, mod_name)] = mod
    spec.loader.exec_module(mod)
    return mod


def make_wal_db(path, n_seed=3):
    """建一个 WAL 模式库并返回 (conn, table)。调用方负责关 conn。"""
    if os.path.exists(path):
        os.unlink(path)
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
    conn.execute("CREATE TABLE blocklist (protocol TEXT, host TEXT, port INTEGER, "
                 "reason TEXT, created INTEGER, by TEXT, "
                 "PRIMARY KEY (protocol, host, port))")
    for i in range(n_seed):
        conn.execute("INSERT INTO t VALUES (?, ?)", (i, "seed-%d" % i))
    conn.commit()
    return conn


# ---------------------------------------------------------------- Part F: WAL 备份
def part_f_wal_backup():
    print("== Part F: WAL 安全备份（Backup API） ==")
    tmp = tempfile.mkdtemp(prefix="i03f-")
    db = os.path.join(tmp, "pool.db")
    conn = make_wal_db(db)
    # 写入一批行后不 checkpoint、不关库：数据仍在 -wal 文件里。
    for i in range(100, 110):
        conn.execute("INSERT INTO t VALUES (?, ?)", (i, "wal-row-%d" % i))
    conn.execute("INSERT INTO blocklist VALUES ('ss','203.0.113.99',443,'r',1,'x')")
    conn.commit()
    wal_path = db + "-wal"
    check("F0 前置：-wal 文件非空（数据尚未 checkpoint）",
          os.path.exists(wal_path) and os.path.getsize(wal_path) > 0,
          "wal size=%s" % (os.path.getsize(wal_path) if os.path.exists(wal_path) else "missing"))
    bak = os.path.join(tmp, "pool.db.bak")
    sha = common_mod.sqlite_backup(db, bak)
    check("F1 Backup API 备份成功且返回 SHA-256",
          os.path.exists(bak) and len(sha) == 64, sha[:16])
    chk = sqlite3.connect("file:%s?mode=ro" % bak, uri=True)
    check("F1 备份 integrity_check ok",
          chk.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
    check("F1 备份包含 WAL 中未 checkpoint 的 10 行（copy2 会丢）",
          chk.execute("SELECT COUNT(*) FROM t WHERE id >= 100").fetchone()[0] == 10)
    check("F1 备份包含 WAL 中的 blocklist 行",
          chk.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0] == 1)
    check("F1 备份文件 0600",
          (os.stat(bak).st_mode & 0o777) == 0o600)
    chk.close()
    # 对照：同一时刻 copy2 主库文件 → 丢 WAL 已提交数据（证明旧做法不可靠）。
    # 注意：小库尚未 checkpoint 时，主库文件可能连表结构都未落盘，
    # copy2 得到的是空库（无 t 表）——这比“丢 10 行”更严重，同样是丢数据。
    copy_path = os.path.join(tmp, "copy.db")
    shutil.copy2(db, copy_path)
    live_total = conn.execute("SELECT COUNT(*) FROM t").fetchone()[0]
    c2 = sqlite3.connect("file:%s?mode=ro" % copy_path, uri=True)
    try:
        copy_total = c2.execute("SELECT COUNT(*) FROM t").fetchone()[0]
        lost = copy_total < live_total
        detail = "copy=%d live=%d" % (copy_total, live_total)
    except sqlite3.OperationalError:
        lost = True
        detail = "copy has no t table at all; live=%d" % live_total
    c2.close()
    check("F2 对照：copy2 主库文件丢 WAL 已提交数据", lost, detail)
    conn.close()
    # 目标已存在 / 同文件 / 别名一律拒绝
    try:
        common_mod.sqlite_backup(db, bak)
        check("F3 已存在目标拒绝覆盖", False, "no raise")
    except FileExistsError:
        check("F3 已存在目标拒绝覆盖", True)
    link = os.path.join(tmp, "link.db")
    os.symlink(db, link)
    try:
        common_mod.sqlite_backup(db, link)
        check("F3 符号链接目标拒绝", False, "no raise")
    except (FileExistsError, ValueError):
        check("F3 符号链接目标拒绝", True)
    try:
        common_mod.sqlite_backup(db, db)
        check("F3 同文件目标拒绝", False, "no raise")
    except (FileExistsError, ValueError):
        check("F3 同文件目标拒绝", True)
    try:
        common_mod.sqlite_backup(os.path.join(tmp, "nope.db"),
                                 os.path.join(tmp, "x.bak"))
        check("F3 源缺失拒绝", False, "no raise")
    except FileNotFoundError:
        check("F3 源缺失拒绝", True)
    # 并发写入下备份仍一致
    db2 = os.path.join(tmp, "pool2.db")
    conn2 = make_wal_db(db2, n_seed=50)
    stop = {"flag": False}

    def writer():
        i = 0
        while not stop["flag"]:
            try:
                conn2.execute("INSERT INTO t VALUES (?, ?)", (1000 + i, "w"))
                conn2.commit()
            except sqlite3.Error:
                pass
            i += 1
            time.sleep(0.001)

    th = threading.Thread(target=writer)
    th.start()
    bak2 = os.path.join(tmp, "pool2.db.bak")
    try:
        common_mod.sqlite_backup(db2, bak2)
        ok = True
    except Exception as exc:  # noqa: BLE001
        ok = False
        print("backup under write failed: %r" % (exc,))
    stop["flag"] = True
    th.join()
    conn2.close()
    chk2 = sqlite3.connect("file:%s?mode=ro" % bak2, uri=True) if ok else None
    check("F4 并发写入下备份完成且 integrity ok",
          ok and chk2.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
    if chk2 is not None:
        chk2.close()
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- Part G: 事务内重核对
def part_g_txn_recheck():
    print("== Part G: 事务内重核对（预检与写入之间的竞态） ==")
    tmp = tempfile.mkdtemp(prefix="i03g-")
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    _data, entries = bf_mod.load_audit(AUDIT_JSON)
    # G1：预检 absent，事务开始前外部写入同三元组不同 reason → 拒绝并回滚
    rows = bf_mod.audit_db(db, entries)
    assert all(s == "absent" for _e, s, _d in rows)
    first = entries[0]
    ext = sqlite3.connect(db)
    ext.execute("INSERT INTO blocklist VALUES (?,?,?,?,?,?)",
                (first["protocol"], first["host"], first["port"],
                 "other-reason", 1, "outsider"))
    ext.commit()
    ext.close()
    conn = sqlite3.connect(db)
    try:
        conn.execute("BEGIN IMMEDIATE")
        bf_mod.apply_rows(conn, rows, entries, "i03-test", int(time.time()))
        conn.commit()
        check("G1 事务内异 reason 冲突拒绝写入", False, "no raise")
    except ValueError as exc:
        conn.rollback()
        check("G1 事务内异 reason 冲突拒绝写入", "INSERT OR IGNORE" in str(exc),
              str(exc)[:120])
    finally:
        conn.close()
    c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    check("G1 回滚后 blocklist 仍 12 条（11 + 外部 1 条），无 audit 行",
          c.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0] == 12 and
          c.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-backfill'").fetchone()[0] == 0)
    c.close()
    # G2：预检 absent，事务开始前外部写入同三元组同 reason → 幂等跳过，不重复写 audit
    db2 = os.path.join(tmp, "pool2.db")
    shutil.copy2(SNAPSHOT, db2)
    rows2 = bf_mod.audit_db(db2, entries)
    ext = sqlite3.connect(db2)
    ext.execute("INSERT INTO blocklist VALUES (?,?,?,?,?,?)",
                (first["protocol"], first["host"], first["port"],
                 first["reason"], 1, "outsider"))
    ext.commit()
    ext.close()
    conn = sqlite3.connect(db2)
    try:
        conn.execute("BEGIN IMMEDIATE")
        inserted = bf_mod.apply_rows(conn, rows2, entries, "i03-test",
                                     int(time.time()))
        conn.commit()
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        check("G2 同 reason 并发写入幂等跳过", False, repr(exc))
        inserted = -1
    finally:
        conn.close()
    c = sqlite3.connect("file:%s?mode=ro" % db2, uri=True)
    check("G2 同 reason 并发写入幂等跳过（inserted=24，audit=24）",
          inserted == 24 and
          c.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-backfill'").fetchone()[0] == 24 and
          c.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0] == 36)
    c.close()
    # G3：事务内验证函数本身：完整通过、缺失拒绝
    conn = sqlite3.connect(db2)
    ok, problems = bf_mod._verify_in_transaction(conn, entries)
    check("G3 事务内验证：回填后 25 条全在且 reason 一致",
          ok and not problems, str(problems))
    conn.execute("DELETE FROM blocklist WHERE protocol=? AND host=? AND port=?",
                 (entries[5]["protocol"], entries[5]["host"], entries[5]["port"]))
    ok2, problems2 = bf_mod._verify_in_transaction(conn, entries)
    check("G3 事务内验证：缺 1 条即报 missing",
          not ok2 and len(problems2) == 1 and "missing" in problems2[0],
          str(problems2))
    conn.rollback()
    conn.close()
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- Part H: 解禁禁用 + 严格加载 + 决策日志
def part_h_unblock_disabled():
    print("== Part H: 解禁生产路径禁用 + 严格 rejected 加载 + 决策日志 ==")
    tmp = tempfile.mkdtemp(prefix="i03h-")
    # H1/H2：strict loader 对缺文件 / 缺 entries / 空 / 重复 / 畸形 fail-closed
    cases = {
        "missing-file": None,
        "no-entries": {"version": 1},
        "empty-entries": {"version": 1, "entries": []},
        "no-version": {"entries": [{"protocol": "vmess", "host": "203.0.113.1",
                                    "port": 443, "decision_ref": "x"}]},
        "dup": {"version": 1, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443,
             "decision_ref": "x"},
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443,
             "decision_ref": "y"}]},
        "bad-protocol": {"version": 1, "entries": [
            {"protocol": "http", "host": "203.0.113.1", "port": 443,
             "decision_ref": "x"}]},
        "bad-port": {"version": 1, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 70000,
             "decision_ref": "x"}]},
        "no-decision-ref": {"version": 1, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443}]},
        "empty-decision-ref": {"version": 1, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443,
             "decision_ref": "   "}]},
    }
    for name, payload in cases.items():
        p = os.path.join(tmp, "rej-%s.json" % name)
        if payload is not None:
            with open(p, "w", encoding="utf-8") as f:
                json.dump(payload, f)
        for loader, label in ((screening_mod.load_rejected, "screening"),
                              (common_mod.load_rejected_strict, "common")):
            try:
                loader(p)
                check("H1 strict loader 拒 %s（%s）" % (name, label), False,
                      "no raise")
            except (OSError, ValueError):
                check("H1 strict loader 拒 %s（%s）" % (name, label), True)
    # 损坏 JSON 同样拒绝
    bad_json = os.path.join(tmp, "rej-badjson.json")
    with open(bad_json, "w", encoding="utf-8") as f:
        f.write("{not json")
    try:
        screening_mod.load_rejected(bad_json)
        check("H1 strict loader 拒损坏 JSON", False, "no raise")
    except ValueError:
        check("H1 strict loader 拒损坏 JSON", True)
    # 正常文件仍可加载
    check("H1 正常 rejected 文件加载 1 条",
          len(screening_mod.load_rejected(REJECTED_JSON)) == 1)
    # H3：unblock --apply 禁用（缺参数与完整参数均拒绝，不备份不写库）
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
         "--apply", "--backup", os.path.join(tmp, "b.bak"), "--by", "i03-test",
         "--decision-log", os.path.join(tmp, "d.jsonl")])
    target = ["--db", db, "--protocol", "ss", "--host", "156.146.38.168",
              "--port", "443"]
    r = run([sys.executable, UNBLOCK] + target + ["--apply",
             "--backup", os.path.join(tmp, "u.bak"),
             "--approved-by", "i03-test", "--decision-ref", "test-ref",
             "--evidence", "test-evidence"])
    check("H3 unblock --apply 完整参数仍拒绝（DISABLED exit 2）",
          r.returncode == 2 and "DISABLED" in r.stdout, r.stdout[-160:])
    check("H3 拒绝后不产生备份文件",
          not os.path.exists(os.path.join(tmp, "u.bak")))
    c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    check("H3 拒绝后 blocklist 仍 36 条、audit 无 unblock 行",
          c.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0] == 36 and
          c.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-unblock'").fetchone()[0] == 0)
    c.close()
    # H4：门控后路径事务内快照比对——预读后外部改行 → 拒绝并回滚
    sys.path.insert(0, os.path.join(ROOT, "pool"))
    import unblock_node as ub_mod
    ub_mod.PRODUCTION_UNBLOCK_ENABLED = True
    try:
        stale_snapshot = ("phone-fail-20261121", 1111111111, "someone-else")
        rc = ub_mod.cmd_apply(db, ("ss", "156.146.38.168", 443),
                              stale_snapshot, "i03-test", "test-ref",
                              "test-evidence",
                              os.path.join(tmp, "u2.bak"),
                              decision_log=os.path.join(tmp, "du.jsonl"))
    finally:
        ub_mod.PRODUCTION_UNBLOCK_ENABLED = False
    check("H4 门控后路径：快照过期（reason/created/by 不符）拒绝",
          rc == 1, "rc=%s" % rc)
    c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    check("H4 拒绝后行仍在、audit 无 unblock 行",
          c.execute("SELECT COUNT(*) FROM blocklist WHERE protocol='ss' AND host='156.146.38.168' AND port=443").fetchone()[0] == 1 and
          c.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-unblock'").fetchone()[0] == 0)
    c.close()
    check("H4 拒绝后备份文件保留（Backup API 产物，供人工核查）",
          os.path.exists(os.path.join(tmp, "u2.bak")))
    # H5：决策日志只追加不截断 + 拒绝符号链接 + 不存在时以 0600 创建
    dlog = os.path.join(tmp, "dec.jsonl")
    common_mod.append_decision_log(dlog, {"marker": 1})
    check("H5 决策日志不存在时以 0600 创建",
          (os.stat(dlog).st_mode & 0o777) == 0o600)
    common_mod.append_decision_log(dlog, {"type": "test", "n": 1})
    common_mod.append_decision_log(dlog, {"type": "test", "n": 2})
    lines = open(dlog, encoding="utf-8").readlines()
    check("H5 决策日志只追加（marker + 2 条 = 3 行）",
          len(lines) == 3 and json.loads(lines[0])["marker"] == 1)
    link = os.path.join(tmp, "link.jsonl")
    os.symlink(dlog, link)
    try:
        common_mod.append_decision_log(link, {"type": "test"})
        check("H5 决策日志拒绝符号链接", False, "no raise")
    except ValueError:
        check("H5 决策日志拒绝符号链接", True)
    # H6：无整库恢复路径（--restore 不被接受；源码无恢复写回）
    r = run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
             "--restore", os.path.join(tmp, "b.bak")])
    check("H6 backfill --restore 不被接受（argparse exit 2）",
          r.returncode == 2, "rc=%d" % r.returncode)
    r = run([sys.executable, UNBLOCK, "--db", db, "--protocol", "ss",
             "--host", "156.146.38.168", "--port", "443", "--restore"])
    check("H6 unblock --restore 不被接受（argparse exit 2）",
          r.returncode == 2, "rc=%d" % r.returncode)
    for script in (BACKFILL, UNBLOCK):
        text = open(script, encoding="utf-8").read()
        check("H6 %s 无 --restore 参数定义且源码无 shutil 拷贝写回"
              % os.path.basename(script),
              'add_argument("--restore"' not in text
              and "add_argument('--restore'" not in text
              and "shutil" not in text)
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- Part I: 端到端防复活
# 真实调用点是打过 cli-v2.patch 的 cmd_test / cmd_publish（非新建未接线模块）。
# 干净候选 host 用公开 IP（8.8.8.8 / 1.1.1.1，仅作身份字符串，不产生流量）：
# TEST-NET 段会被 live is_private() 判为保留地址而拒收，不能作“干净候选”。
CLEAN_TROJAN_HOST = "8.8.8.8"
CLEAN_VMESS_HOST = "1.1.1.1"
CANADA_KEY = ("vmess", "104.18.42.163", 443)


def _synthetic_records(audit_entries, rename_prefix="改名-"):
    """为 25 条禁入三元组造新鲜抓取记录（改名 + 合法配置 + 占位凭据）。"""
    recs = []
    for e in audit_entries:
        base = {"protocol": e["protocol"], "host": e["host"],
                "port": e["port"], "source": "i03-synth",
                "name_hint": rename_prefix + e["name"]}
        if e["protocol"] == "vmess":
            base.update({"tls": True, "net": "ws",
                         "uuid": "00000000-0000-0000-0000-000000000000",
                         "sni": "xmfhlpy.com", "security": "auto"})
        elif e["protocol"] == "trojan":
            base.update({"password": "placeholder", "sni": "xmfhlpy.com",
                         "ws": True, "ws_path": "/"})
        else:
            base.update({"method": "aes-128-gcm", "password": "placeholder"})
        recs.append(base)
    return recs


def _clean_records():
    return [
        {"protocol": "trojan", "host": CLEAN_TROJAN_HOST, "port": 443,
         "source": "i03-synth", "name_hint": "测试甲",
         "password": "placeholder", "sni": "clean.example.com",
         "ws": True, "ws_path": "/"},
        {"protocol": "vmess", "host": CLEAN_VMESS_HOST, "port": 443,
         "source": "i03-synth", "name_hint": "测试乙",
         "tls": True, "net": "ws",
         "uuid": "00000000-0000-0000-0000-000000000000",
         "sni": "clean.example.com", "security": "auto"},
    ]


def _seed_pass_evidence(conn, triples, now, ms=120.0, n_tests=25):
    """给指定三元组造新鲜 VPS 通过证据（nodes + node_tests）。"""
    for proto, host, port in triples:
        conn.execute(
            "UPDATE nodes SET last_result='pass', last_reason='', "
            "last_test_at=?, pass_count=?, test_count=? "
            "WHERE protocol=? AND host=? AND port=?",
            (now, n_tests, n_tests, proto, host, port))
        if conn.execute("SELECT changes()").fetchone()[0] == 0:
            conn.execute(
                "INSERT INTO nodes (protocol, host, port, source, first_seen, "
                "last_seen, last_test_at, last_result, last_reason, "
                "pass_count, test_count, status) VALUES (?,?,?,?,?,?,?,?,?,?,?, 'candidate')",
                (proto, host, port, "i03-synth", now, now, now, "pass", "",
                 n_tests, n_tests))
        conn.execute("DELETE FROM node_tests WHERE protocol=? AND host=? AND port=?",
                     (proto, host, port))
        for i in range(n_tests):
            conn.execute("INSERT INTO node_tests VALUES (?,?,?,?,?,?,?)",
                         (proto, host, port, now - i * 60, "pass", "", ms))
    conn.commit()


def _load_cli_harness(tmp):
    """把打过补丁的 cli.py 连同 v2 pool 装进隔离包 i03clipool 并加载。

    相对导入全部在包内解析；rejected_nodes.json 须随包复制
    （load_rejected 默认取模块旁文件）。返回 cli 模块。
    """
    pkg_dir = os.path.join(tmp, "i03clipool")
    os.makedirs(pkg_dir)
    for f in ("__init__.py", "db.py", "crawler.py", "geo.py", "rules.py",
              "tester.py", "screening.py", "blocklist_common.py"):
        shutil.copy2(os.path.join(ROOT, "pool", f), os.path.join(pkg_dir, f))
    shutil.copy2(os.path.join(ROOT, "pool", "rejected_nodes.json"),
                 os.path.join(pkg_dir, "rejected_nodes.json"))
    shutil.copy2(os.path.join(WORK, "live", "publish.py"),
                 os.path.join(pkg_dir, "publish.py"))
    shutil.copy2(PATCHED_CLI, os.path.join(pkg_dir, "cli.py"))
    cli_mod = load_pkg_sub("i03clipool", pkg_dir, "cli")

    class _FakeIpApi:
        def country(self, host):
            return ("US", "United States")

    cli_mod.IpApi = _FakeIpApi
    return cli_mod


def part_i_end_to_end():
    print("== Part I: 端到端防复活（重抓/改名/VPS 通过 → 全路径拒绝） ==")
    tmp = tempfile.mkdtemp(prefix="i03i-")
    audit = json.load(open(AUDIT_JSON))
    entries = audit["entries"]
    banned25 = {(e["protocol"], e["host"], e["port"]) for e in entries}
    rejected = screening_mod.load_rejected(REJECTED_JSON)
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
         "--apply", "--backup", os.path.join(tmp, "b.bak"), "--by", "i03-test",
         "--decision-log", os.path.join(tmp, "d.jsonl")])
    now = int(time.time())
    recs = _synthetic_records(entries)
    clean = _clean_records()
    conn = sqlite3.connect(db)
    banlist = screening_mod.load_banlist(conn, REJECTED_JSON)
    blocked = banlist["blocked"]
    check("I0 回填后阻止清单 = 36 条 blocklist + 1 条 rejected",
          len(blocked) == 36 and len(rejected) == 1,
          "blocked=%d rejected=%d" % (len(blocked), len(rejected)))
    # I1：screen_records 排除全部 25 条（改名也无用），原因 blocklisted
    kept, excluded = screening_mod.screen_records(recs, blocked, rejected, set())
    check("I1 screen_records 排除全部 25 条改名重抓记录",
          len(kept) == 0 and len(excluded) == 25 and
          all(why == "blocklisted" for _r, why in excluded),
          "kept=%d excluded=%d" % (len(kept), len(excluded)))
    # I2：严格漏斗同样排除（先给 25 条造通过证据，再筛）。
    # 注意：漏斗 SQL 的 port != 19999 先行排除 11 条 19999 端口节点，
    # 它们到不了 banned 检查——仍不在输出内，不算漏网。
    _seed_pass_evidence(conn, banned25, now)
    rows, excl = screening_mod.strict_candidates(conn, blocked, rejected, now)
    excl_keys = {(r[0], r[1], r[2]) for r, _ in excl}
    row_keys = {(r[0], r[1], r[2]) for r in rows}
    port19999 = {k for k in banned25 if k[2] == 19999}
    check("I2 严格漏斗输出不含任何被禁三元组",
          not (row_keys & banned25), "rows=%d" % len(rows))
    check("I2 严格漏斗排除全部 14 条非 19999 被禁三元组",
          banned25 - port19999 <= excl_keys, "excl=%d" % len(excl_keys))
    check("I2 11 条 19999 端口被禁三元组同样不在漏斗输出内（端口规则先行排除）",
          len(port19999) == 11 and not (row_keys & port19999))
    # I3：发布 guard——含被禁行的整批拒绝；干净批通过；无法解析的行拒绝
    banned_line = ("改名-伊朗3 = ss, 193.151.160.18, 19999, "
                   "encrypt-method=aes-128-gcm, password=placeholder")
    clean_line = ("测试甲 = trojan, 8.8.8.8, 443, password=placeholder, "
                  "sni=clean.example.com, ws=true, ws-path=/")
    try:
        screening_mod.verify_publish_guard([clean_line, banned_line], banlist)
        check("I3 发布 guard 拒含被禁行的整批", False, "no raise")
    except ValueError as exc:
        check("I3 发布 guard 拒含被禁行的整批", "banned" in str(exc), str(exc))
    check("I3 发布 guard 放行干净批",
          screening_mod.verify_publish_guard([clean_line], banlist) == 1)
    try:
        screening_mod.verify_publish_guard(["not a surge line"], banlist)
        check("I3 发布 guard 拒无法解析的行", False, "no raise")
    except ValueError:
        check("I3 发布 guard 拒无法解析的行", True)
    # I4：banlist 版本——改动后版本变化，恢复后还原
    v0 = banlist["version"]
    conn.execute("INSERT INTO blocklist VALUES ('ss','8.8.8.8',443,'r',1,'x')")
    conn.commit()
    v1 = screening_mod.load_banlist(conn, REJECTED_JSON)["version"]
    check("I4 banlist 版本随 blocklist 改动而变化", v0 != v1)
    conn.execute("DELETE FROM blocklist WHERE host='8.8.8.8'")
    conn.commit()
    check("I4 删改后版本恢复",
          screening_mod.load_banlist(conn, REJECTED_JSON)["version"] == v0)
    conn.close()
    # I5–I7：真实 cmd_test / cmd_publish 端到端（隔离 base + 打桩）
    _part_i_cli(tmp, db, entries, banned25, rejected, recs, clean, now)
    shutil.rmtree(tmp, ignore_errors=True)


def _part_i_cli(tmp, db, entries, banned25, rejected, recs, clean, now):
    import argparse
    import logging
    base = os.path.join(tmp, "base")
    os.makedirs(os.path.join(base, "data"), exist_ok=True)
    os.makedirs(os.path.join(base, "publish"), exist_ok=True)
    os.makedirs(os.path.join(base, "logs"), exist_ok=True)
    shutil.copy2(db, os.path.join(base, "data", "pool.db"))
    dbp = os.path.join(base, "data", "pool.db")
    # winner-clean 是 Scheme B 能力，不在本审查范围内：隔离 base 内关闭，
    # 否则 cmd_publish 会导入 harness 未带的 winner_clean 模块。
    conn = sqlite3.connect(dbp)
    conn.execute("UPDATE config SET value='false' WHERE key='winner_clean_enabled'")
    conn.commit()
    pins_db = {(r[0], r[1], r[2]): r[3] for r in conn.execute(
        "SELECT protocol, host, port, name FROM pinned").fetchall()}
    banlist = screening_mod.load_banlist(conn, REJECTED_JSON)
    pins21 = {k: v for k, v in pins_db.items() if k not in banlist["blocked"]}
    conn.close()
    assert len(pins21) == 21, "canonical pins must be 21, got %d" % len(pins21)
    pin_lines = []
    for (proto, host, port), name in sorted(pins21.items()):
        pin_lines.append("%s = trojan, %s, %d, password=placeholder, "
                         "sni=cfnode.vip668.xin, ws=true, ws-path=/"
                         % (name, host, port))
    with open(os.path.join(base, "config.yaml"), "w", encoding="utf-8") as f:
        f.write("publish_max_lines: 150\nper_country_cap: 40\n"
                "publish_fresh_hours: 24\npublish_max_vps_ms: 300\n"
                "publish_min_pass_rate: 0.5\nwinner_clean_enabled: false\n"
                "concurrency: 8\n")
    open(os.path.join(base, "private-hosts.txt"), "w").close()
    open(os.path.join(base, "sources.yaml"), "w").write("sources: []\n")
    with open(os.path.join(base, "pinned-nodes.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(pin_lines) + "\n")
    pub_file = os.path.join(base, "publish", "pool-new.txt")
    with open(pub_file, "w", encoding="utf-8") as f:
        f.write("\n".join(pin_lines) + "\n")
        f.write("加拿大 🇨🇦 = vmess, 104.18.42.163, 443, "
                "username=00000000-0000-0000-0000-000000000000, "
                "vmess-aead=true, tls=true\n")
    cli_mod = _load_cli_harness(tmp)
    parse = cli_mod.parse_surge_line
    # read_pinned_lines 优先读 live /opt 路径：隔离 harness 内改读 base 文件。
    def _pinned_lines(_base):
        out = []
        with open(os.path.join(_base, "pinned-nodes.txt")) as f:
            for line in f:
                line = line.rstrip("\n")
                if not line.strip():
                    continue
                name, proto, host, port, ok = parse(line)
                if ok:
                    out.append((name, proto, host, port, line))
        return out
    cli_mod.read_pinned_lines = _pinned_lines
    log = logging.getLogger("i03-test")
    log.addHandler(logging.NullHandler())
    all_recs = list(recs) + list(clean)

    def fake_crawl(sources_path, skip=None):
        return (list(all_recs),
                {"sources": 1, "sources_ok": 1, "total": len(all_recs),
                 "unique": len(all_recs), "by_source": {}})

    def fake_test(records, concurrency=8, **_kw):
        return [(rec, "fail", 0.0, "synthetic-fail") for rec in records]

    cli_mod.crawl_records = fake_crawl
    cli_mod.test_many = fake_test
    # I5：cmd_test——被禁三元组不得进入测试集（0 行新测试），干净候选正常测
    conn = sqlite3.connect(dbp)
    for e in entries:
        conn.execute("UPDATE nodes SET last_result='fail', last_reason='curl-failed', "
                     "last_test_at=? WHERE protocol=? AND host=? AND port=?",
                     (now, e["protocol"], e["host"], e["port"]))
    conn.commit()
    conn.close()
    rc = cli_mod.cmd_test(argparse.Namespace(mode="incremental", limit=800),
                          base, log)
    check("I5 打补丁 cmd_test exit 0", rc == 0, "rc=%s" % rc)
    conn = sqlite3.connect("file:%s?mode=ro" % dbp, uri=True)
    # 只计 fake 测试器写的行（reason='synthetic-fail'）：I2 预置的种子行不算
    tested_banned = conn.execute(
        "SELECT COUNT(*) FROM node_tests WHERE reason='synthetic-fail' AND "
        "(protocol, host, port) IN (SELECT protocol, host, port FROM blocklist)"
        ).fetchone()[0]
    tested_clean = conn.execute(
        "SELECT COUNT(*) FROM node_tests WHERE reason='synthetic-fail' AND "
        "host IN ('8.8.8.8','1.1.1.1')").fetchone()[0]
    check("I5 cmd_test 未测任何被禁三元组（0 行新测试）",
          tested_banned == 0, "rows=%d" % tested_banned)
    check("I5 cmd_test 正常测了 2 条干净候选",
          tested_clean == 2, "rows=%d" % tested_clean)
    conn.close()

    # I6：cmd_publish——纵有新鲜通过证据，被禁三元组不得进发布；干净候选进发布
    conn = sqlite3.connect(dbp)
    _seed_pass_evidence(conn,
                        list(banned25) + [(c["protocol"], c["host"], c["port"])
                                          for c in clean] + [CANADA_KEY],
                        int(time.time()))
    conn.close()
    rc = cli_mod.cmd_publish(argparse.Namespace(), base, log)
    check("I6 打补丁 cmd_publish exit 0", rc == 0, "rc=%s" % rc)
    after = open(pub_file, encoding="utf-8").read()
    out_keys = {parse(l)[1:4] for l in after.splitlines() if l.strip()}
    check("I6 发布文件不含任何被禁三元组",
          not (out_keys & banned25) and not (out_keys & set(rejected)),
          "banned in publish: %s" % (out_keys & banned25,))
    check("I6 发布文件含 2 条干净轮换（发布本身在跑）",
          ("trojan", CLEAN_TROJAN_HOST, 443) in out_keys and
          ("vmess", CLEAN_VMESS_HOST, 443) in out_keys)
    check("I6 发布文件含 21 条钉选 + 加拿大",
          len([k for k in out_keys if k in pins21]) == 21 and
          CANADA_KEY in out_keys,
          "pins=%d canada=%s total=%d"
          % (len([k for k in out_keys if k in pins21]),
             CANADA_KEY in out_keys, len(out_keys)))
    check("I6 发布文件共 24 行（21 钉选 + 加拿大 + 2 干净轮换）",
          len(out_keys) == 24, "total=%d" % len(out_keys))
    # I7：guard 版本复核——发布中途 banlist 版本变了即拒绝整批，文件一字节未变
    orig_load = cli_mod.load_banlist
    calls = {"n": 0}

    def flaky_load(conn):
        calls["n"] += 1
        bl = orig_load(conn)
        if calls["n"] == 2:
            bl = dict(bl)
            bl["version"] = "tampered-version"
        return bl

    cli_mod.load_banlist = flaky_load
    before7 = open(pub_file, "rb").read()
    try:
        rc7 = cli_mod.cmd_publish(argparse.Namespace(), base, log)
    finally:
        cli_mod.load_banlist = orig_load
    check("I7 banlist 版本中途变化即拒绝发布（exit 1）",
          rc7 == 1, "rc=%s" % rc7)
    check("I7 拒绝后发布文件一字节未变",
          open(pub_file, "rb").read() == before7)


# ---------------------------------------------------------------- Part J: N3 严格证书身份
def part_j_strict_sni():
    print("== Part J: N3 严格证书身份负例 ==")
    private = set()

    def vmess(host, sni, tls=True, net="tcp"):
        return {"protocol": "vmess", "host": host, "port": 1270,
                "tls": tls, "net": net,
                "uuid": "00000000-0000-0000-0000-000000000000",
                "sni": sni, "security": "auto"}

    def assert_reject(name, rec):
        ok, reason = rules_mod.pre_filter(rec, private)
        c1 = ok is False and reason == "vmess-no-sni"
        c2 = tester_mod._filter_reason(rec) == "vmess-no-sni"
        try:
            rules_mod.build_surge_line(rec, "X")
            c3 = False
        except ValueError as exc:
            c3 = str(exc) == "vmess-no-sni"
        check("J %s 双入口同拒 + build 抛错" % name, c1 and c2 and c3,
              "pre=%s/%s filter=%s build=%s" % (ok, reason,
                                                tester_mod._filter_reason(rec), c3))

    def assert_allow(name, rec):
        ok, reason = rules_mod.pre_filter(rec, private)
        check("J %s 放行" % name,
              ok is True and tester_mod._filter_reason(rec) is None,
              "pre=%s/%s" % (ok, reason))

    # J1：大小写占位符
    for sni in ("<NIL>", "<Nil>", "nil", "NIL", "NULL", "null", "None",
                "none", "N/A", "n/a", "unknown", "UNKNOWN", "<none>"):
        assert_reject("占位符 %r" % sni, vmess("8.8.8.8", sni))
    # J2：空白
    for sni in (" ", "   ", "\t", " \n "):
        assert_reject("空白 SNI %r" % sni, vmess("8.8.8.8", sni))
    # J3：非法 hostname（尾随点是合法 FQDN 写法，不在此列）
    for sni in ("exa mple.com", "bad_host.com", "-bad.com", "bad-.com",
                "a..b.com", ".example.com",
                "x" * 64 + ".com", "a" * 250 + ".com"):
        assert_reject("非法 hostname SNI %r" % (sni[:30],), vmess("8.8.8.8", sni))
    # J4：异常 IP 形式
    for sni in ("999.999.999.999", "1.2.3.256", "2001:db8:::1",
                "1.2.3.4.5", "example.com:443", "1.2.3"):
        assert_reject("异常 IP 形式 SNI %r" % sni, vmess("8.8.8.8", sni))
    # J5：合法 DNS SNI 放行（含一个尾随点的合法 FQDN 写法）
    for sni in ("example.com", "sub.example.co.uk", "EXAMPLE.COM",
                "a-b.example.com", "xmfhlpy.com", "example.com."):
        assert_allow("合法 DNS SNI %r" % sni, vmess("8.8.8.8", sni))
    # J6：合法 IP SAN 放行
    for sni in ("8.8.8.8", "2001:db8::1"):
        assert_allow("合法 IP SAN SNI %r" % sni, vmess("8.8.8.8", sni))
    # J7：非字符串 SNI
    for sni in (123, True, ["x"], {"a": 1}):
        assert_reject("非字符串 SNI %r" % (sni,), vmess("8.8.8.8", sni))
    # J8：host 既非 IP 也非合法 DNS + 无 SNI → 拒
    for host in ("exa mple.com", "bad_host", "https://example.com/x",
                 "999.999.999.999"):
        assert_reject("非法 host %r 无 SNI" % host, vmess(host, None))
    # J9：host 为合法 DNS + 无 SNI → 不拒（hostname 本身就是证书身份）
    for host in ("node.example.com", "sub.example.co.uk", "EXAMPLE.COM"):
        assert_allow("合法 DNS host %r 无 SNI" % host, vmess(host, None))
    # J10：夹具回归——456 条 pre_filter 以 vmess-no-sni 拒；157 条 DNS 拨号无 SNI 一条未拒
    data = json.load(open(FIXTURE))
    recs = data["records"]
    vm_tls = [r for r in recs if r["protocol"] == "vmess" and r.get("tls")]
    got_reject = [r for r in vm_tls
                  if rules_mod.pre_filter(r, private) == (False, "vmess-no-sni")]
    check("J10 夹具回归：pre_filter 以 vmess-no-sni 拒 456 条（与 v1 口径一致）",
          len(got_reject) == 456, "got=%d" % len(got_reject))
    import ipaddress
    dns_dial = [r for r in vm_tls
                if (r.get("sni") is None or
                    (isinstance(r.get("sni"), str)
                     and r["sni"].strip() in ("", "<nil>")))
                and not _is_ip(r["host"])]
    check("J10 夹具回归：157 条 DNS 拨号无 SNI 一条未被 N3 拒",
          len(dns_dial) == 157 and not any(
              rules_mod.pre_filter(r, private) == (False, "vmess-no-sni")
              for r in dns_dial),
          "dns=%d" % len(dns_dial))


def _is_ip(h):
    import ipaddress
    try:
        ipaddress.ip_address(h)
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------- Part K: 组合回归
def part_k_combination():
    print("== Part K: B10 / B10-EXTENSION / O1 / N3 组合回归 ==")
    i02_rules = load_pkg_sub("i02pool", I02_POOL_DIR, "rules")
    private = set()

    def composed(rec):
        """合并门：#127 门（B10/B10-EXTENSION/O1）先行，再叠加本包 N3。"""
        ok, reason = i02_rules.pre_filter(rec, private)
        if not ok:
            return (False, reason)
        if rules_mod._vmess_no_sni(rec):
            return (False, "vmess-no-sni")
        return (True, "")

    def vmess(**over):
        rec = {"protocol": "vmess", "host": "8.8.8.8", "port": 443,
               "tls": True, "net": "ws",
               "uuid": "00000000-0000-0000-0000-000000000000",
               "sni": "example.com", "security": "auto"}
        rec.update(over)
        return rec

    def trojan(**over):
        rec = {"protocol": "trojan", "host": "8.8.8.8", "port": 443,
               "password": "placeholder", "sni": "example.com",
               "t_type": "tcp"}
        rec.update(over)
        return rec

    def ss(**over):
        rec = {"protocol": "ss", "host": "8.8.8.8", "port": 443,
               "method": "aes-128-gcm", "password": "placeholder"}
        rec.update(over)
        return rec

    check("K1 B10 trojan 逗号密码拒（comma-password）",
          composed(trojan(password="a,b")) == (False, "comma-password"))
    check("K1 B10 ss 逗号密码拒（comma-password）",
          composed(ss(password="a,b")) == (False, "comma-password"))
    check("K2 B10-EXTENSION vmess 逗号 uuid 拒（comma-uuid）",
          composed(vmess(uuid="00000000-0000-0000-0000-000000000000,x"))
          == (False, "comma-uuid"))
    check("K3 O1 vmess grpc 传输拒（unsupported-transport）",
          composed(vmess(net="grpc")) == (False, "unsupported-transport"))
    check("K3 O1 ss 非 AEAD 方法拒（ss-method）",
          composed(ss(method="rc4-md5")) == (False, "ss-method"))
    check("K3 O1 ss plugin 拒（ss-plugin）",
          composed(ss(plugin="v2ray-plugin")) == (False, "ss-plugin"))
    check("K4 N3 vmess IP 拨号无 SNI 拒（vmess-no-sni，#127 门放行后由 N3 拒）",
          i02_rules.pre_filter(vmess(sni=None), private) == (True, "") and
          composed(vmess(sni=None)) == (False, "vmess-no-sni"))
    check("K5 干净 vmess 全门通过",
          composed(vmess()) == (True, ""))
    check("K5 干净 trojan 全门通过",
          composed(trojan()) == (True, ""))
    check("K5 干净 ss 全门通过",
          composed(ss()) == (True, ""))
    check("K6 多重违规 fail-closed（逗号 uuid + grpc + 无 SNI 仍拒）",
          composed(vmess(uuid="x,y", net="grpc", sni=None))[0] is False)
    check("K6 合并顺序：逗号 uuid 优先于 N3（先 uuid 后 SNI）",
          composed(vmess(uuid="x,y", sni=None)) == (False, "comma-uuid"))
    # K7：静态核对——本包 rules.py 只含 N3 严格补丁，未整份覆盖 #127 的改动
    v2_rules_text = open(os.path.join(ROOT, "pool", "rules.py"),
                         encoding="utf-8").read()
    i02_rules_text = open(os.path.join(I02_POOL_DIR, "rules.py"),
                          encoding="utf-8").read()
    check("K7 本包 rules.py 含 N3 严格校验且不含 #127 的 comma-uuid（无整份覆盖）",
          "is_valid_cert_identity" in v2_rules_text and
          "comma-uuid" not in v2_rules_text)
    check("K7 #127 rules.py 含 B10-EXTENSION comma-uuid（组合门另一侧真实存在）",
          "comma-uuid" in i02_rules_text)


def main():
    part_f_wal_backup()
    part_g_txn_recheck()
    part_h_unblock_disabled()
    part_i_end_to_end()
    part_j_strict_sni()
    part_k_combination()
    part_l_live_chain()
    print("TOTAL: pass=%d fail=%d" % (PASS, FAIL))
    return 0 if FAIL == 0 else 1



# ---------------------------------------------------------------- Part L: live 发布链统一阻止清单
# 覆盖 Review 6033772552 第 3 点的真实调用点：production_cycle →
# make_preview → build_candidate（组批/补位）与 _preflight（发布前守卫）。
# 关键事实（已核实）：live 链的 blocked_keys 只来自 blocklist 表；
# GPT 已拒的 rejected_nodes.json 在 live 链里从未被读，且 188.114.99.137
# 不在表内。pool-db-source.patch 把 rejected 并入 read_db_snapshot 的
# blocked_keys，使 preflight / build_candidate / assess_candidate 共用
# 同一受信版本（banlist_version 与 screening.load_banlist 一致）。
PROD_CHAIN_DIR = os.path.join(WORK, "prod-chain")
POOL_DB_SOURCE_PATCH = os.path.join(ROOT, "pool-db-source.patch")
REJECTED_KEY = ("vmess", "188.114.99.137", 443)


def _patched_reader_module(tmp):
    """把 pool-db-source.patch 打到 live pool_db_source.py 副本上并导入。"""
    d = os.path.join(tmp, "patched-reader")
    os.makedirs(os.path.join(d, "single-writer"))
    shutil.copy2(os.path.join(PROD_CHAIN_DIR, "pool_db_source.py"),
                 os.path.join(d, "single-writer", "pool_db_source.py"))
    r = subprocess.run(["patch", "-p1", "--quiet", "-i", POOL_DB_SOURCE_PATCH],
                       cwd=d, capture_output=True, text=True)
    assert r.returncode == 0, "pool-db-source.patch apply failed: " + r.stdout + r.stderr
    path = os.path.join(d, "single-writer", "pool_db_source.py")
    spec = importlib.util.spec_from_file_location("i03_patched_pool_db_source", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["i03_patched_pool_db_source"] = mod
    spec.loader.exec_module(mod)
    return mod


def _set_rejected_env(value):
    """设置 P2P3_REJECTED_NODES，返回恢复函数。"""
    old = os.environ.get("P2P3_REJECTED_NODES")
    if value is None:
        os.environ.pop("P2P3_REJECTED_NODES", None)
    else:
        os.environ["P2P3_REJECTED_NODES"] = value

    def restore():
        if old is None:
            os.environ.pop("P2P3_REJECTED_NODES", None)
        else:
            os.environ["P2P3_REJECTED_NODES"] = old
    return restore


def part_l_live_chain():
    print("== Part L: live 发布链统一阻止清单（pool-db-source.patch） ==")
    tmp = tempfile.mkdtemp(prefix="i03l-")
    reader = _patched_reader_module(tmp)
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
         "--apply", "--backup", os.path.join(tmp, "b.bak"), "--by", "i03-test",
         "--decision-log", os.path.join(tmp, "d.jsonl")])
    # L1：打补丁的 reader 读回填后库 → blocked_keys = 36 表内 + 1 已拒
    restore = _set_rejected_env(REJECTED_JSON)
    try:
        snap = reader.read_db_snapshot(db)
    finally:
        restore()
    check("L1 打补丁的 reader：blocked_keys = 36 表内 + 1 已拒 = 37",
          len(snap["blocked_keys"]) == 37, "n=%d" % len(snap["blocked_keys"]))
    check("L1 打补丁的 reader：已拒三元组在 blocked_keys 内",
          REJECTED_KEY in snap["blocked_keys"])
    check("L1 打补丁的 reader：rejected_keys 恰为 1 条",
          snap["rejected_keys"] == {REJECTED_KEY})
    conn = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    v_screen = screening_mod.load_banlist(conn, REJECTED_JSON)["version"]
    conn.close()
    check("L1 同一版本：reader 的 banlist_version 与 screening.load_banlist 一致",
          snap["banlist_version"] == v_screen)
    restore = _set_rejected_env(REJECTED_JSON)
    try:
        snap2 = reader.read_db_snapshot(db)
    finally:
        restore()
    check("L1 版本确定：两次读取 banlist_version 相同",
          snap2["banlist_version"] == snap["banlist_version"])
    # L2：rejected 文件缺失即 fail-closed（环境变量指向缺失路径；默认路径亦缺失）
    restore = _set_rejected_env(os.path.join(tmp, "no-such-rejected.json"))
    try:
        reader.read_db_snapshot(db)
        check("L2 rejected 路径缺失即拒绝（SourceRefused）", False, "no raise")
    except reader.SourceRefused:
        check("L2 rejected 路径缺失即拒绝（SourceRefused）", True)
    finally:
        restore()
    if not os.path.exists("/opt/free-node-program/pool/rejected_nodes.json"):
        restore = _set_rejected_env(None)
        try:
            reader.read_db_snapshot(db)
            check("L2 默认 rejected 路径缺失即拒绝（SourceRefused）", False, "no raise")
        except reader.SourceRefused:
            check("L2 默认 rejected 路径缺失即拒绝（SourceRefused）", True)
        finally:
            restore()
    # L3：rejected 文件损坏形态一律 fail-closed
    bad_cases = {
        "bad-json": "{not json",
        "empty-entries": json.dumps({"version": 1, "entries": []}),
        "dup": json.dumps({"version": 1, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443,
             "decision_ref": "x"},
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443,
             "decision_ref": "y"}]}),
        "no-decision-ref": json.dumps({"version": 1, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443}]}),
        "version-0": json.dumps({"version": 0, "entries": [
            {"protocol": "vmess", "host": "203.0.113.1", "port": 443,
             "decision_ref": "x"}]}),
    }
    for name, content in bad_cases.items():
        bad_path = os.path.join(tmp, "bad-%s.json" % name)
        with open(bad_path, "w", encoding="utf-8") as f:
            f.write(content)
        restore = _set_rejected_env(bad_path)
        try:
            reader.read_db_snapshot(db)
            check("L3 rejected 损坏（%s）即拒绝" % name, False, "no raise")
        except reader.SourceRefused:
            check("L3 rejected 损坏（%s）即拒绝" % name, True)
        finally:
            restore()
    _part_l_preview(tmp, reader, db)
    shutil.rmtree(tmp, ignore_errors=True)


def _part_l_preview(tmp, reader, db):
    import types
    from pool import crawler as crawler_mod
    from pool import geo as geo_mod
    now = int(time.time())
    audit = json.load(open(AUDIT_JSON))
    entries = audit["entries"]
    banned25 = {(e["protocol"], e["host"], e["port"]) for e in entries}
    banned26 = banned25 | {REJECTED_KEY}
    recs = _synthetic_records(entries)
    recs.append({"protocol": "vmess", "host": "188.114.99.137", "port": 443,
                 "source": "i03-synth", "name_hint": "改名-已拒",
                 "tls": True, "net": "ws",
                 "uuid": "00000000-0000-0000-0000-000000000000",
                 "sni": "xmfhlpy.com", "security": "auto"})
    clean = _clean_records()
    conn = sqlite3.connect(db)
    conn.execute("UPDATE config SET value='false' WHERE key='winner_clean_enabled'")
    _seed_pass_evidence(conn,
                        list(banned26) +
                        [(c["protocol"], c["host"], c["port"]) for c in clean] +
                        [CANADA_KEY], now)
    conn.commit()
    pins_db = {(r[0], r[1], r[2]): r[3] for r in conn.execute(
        "SELECT protocol, host, port, name FROM pinned").fetchall()}
    conn.close()
    restore = _set_rejected_env(REJECTED_JSON)
    try:
        snap = reader.read_db_snapshot(db)
    finally:
        restore()
    pins21 = {k: v for k, v in pins_db.items() if k not in snap["blocked_keys"]}
    assert len(pins21) == 21, "canonical pins must be 21, got %d" % len(pins21)
    pin_lines = []
    for (proto, host, port), name in sorted(pins21.items()):
        pin_lines.append("%s = trojan, %s, %d, password=placeholder, "
                         "sni=cfnode.vip668.xin, ws=true, ws-path=/"
                         % (name, host, port))
    current = ("\n".join(pin_lines) +
               "\n加拿大 🇨🇦 = vmess, 104.18.42.163, 443, "
               "username=00000000-0000-0000-0000-000000000000, "
               "vmess-aead=true, tls=true\n").encode("utf-8")
    # adapter harness：真实 legacy adapter + 真实 staging build_candidate
    adir = os.path.join(tmp, "adapter")
    os.makedirs(adir)
    shutil.copy2(os.path.join(PROD_CHAIN_DIR, "legacy_source_adapter.py"),
                 os.path.join(adir, "legacy_source_adapter.py"))
    shutil.copy2(os.path.join(WORK, "live", "build_candidate.py"),
                 os.path.join(adir, "build_candidate.py"))
    spec = importlib.util.spec_from_file_location(
        "i03_legacy_adapter",
        os.path.join(adir, "legacy_source_adapter.py"))
    adapter = importlib.util.module_from_spec(spec)
    sys.modules["i03_legacy_adapter"] = adapter
    spec.loader.exec_module(adapter)
    root = os.path.join(tmp, "legacy-root")
    os.makedirs(root)
    open(os.path.join(root, "private-hosts.txt"), "w").close()
    open(os.path.join(root, "config.yaml"), "w").write("# i03 harness\n")
    all_recs = list(recs) + list(clean)

    class _FakeIpApi:
        def country(self, host):
            return ("US", "United States")

    geo_stub = types.SimpleNamespace(IpApi=_FakeIpApi,
                                     hint_to_code=geo_mod.hint_to_code)
    winner_stub = types.SimpleNamespace(
        clean_rotation=lambda lines: list(lines))
    modules = (crawler_mod, rules_mod, geo_stub, winner_stub)

    def yaml_loader(text):
        return {"publish_max_lines": 150, "per_country_cap": 40,
                "publish_fresh_hours": 24, "publish_max_vps_ms": 300,
                "publish_min_pass_rate": 0.5, "winner_clean_enabled": False,
                "winner_clean_window_days": 7, "winner_clean_min_winner_days": 3,
                "disabled_sources": []}

    # L4：make_preview（组批/补位真实入口）——25 条被禁 + 1 条已拒不得进入
    preview = adapter.make_preview(
        db_snapshot=snap, current_pool=current, legacy_root=root, now=now,
        modules=modules,
        fresh_record_provider=lambda _root, _cfg: list(all_recs),
        pinned_lines_provider=lambda _root: list(pin_lines),
        yaml_loader=yaml_loader)
    out = preview["proposed_bytes"].decode("utf-8")
    out_keys = {crawler_mod.parse_surge_line(l)[1:4]
                for l in out.splitlines() if l.strip()}
    check("L4 make_preview 输出不含 25 条被禁 + 1 条已拒三元组",
          not (out_keys & banned26), "leaked: %s" % (out_keys & banned26,))
    check("L4 make_preview 输出含 2 条干净候选（组批本身在跑）",
          ("trojan", CLEAN_TROJAN_HOST, 443) in out_keys and
          ("vmess", CLEAN_VMESS_HOST, 443) in out_keys)
    check("L4 make_preview 输出含 21 条钉选 + 加拿大，共 24 行",
          len([k for k in out_keys if k in pins21]) == 21 and
          CANADA_KEY in out_keys and preview["proposed_count"] == 24,
          "count=%d" % preview["proposed_count"])
    check("L4 make_preview 明确标注 preview-only、未授权生产写入",
          preview["production_write_authorized"] is False and
          preview["preview_only"] is True)
    _part_l_preflight(tmp, reader, db, current, pins21)


def _part_l_preflight(tmp, reader, db, current, pins21):
    # L5：_preflight 发布前守卫（打补丁的 production_cycle 副本）
    pdir = os.path.join(tmp, "patch-stage")
    os.makedirs(os.path.join(pdir, "single-writer"))
    shutil.copy2(os.path.join(PROD_CHAIN_DIR, "pool_db_source.py"),
                 os.path.join(pdir, "single-writer", "pool_db_source.py"))
    r = subprocess.run(["patch", "-p1", "--quiet", "-i", POOL_DB_SOURCE_PATCH],
                       cwd=pdir, capture_output=True, text=True)
    assert r.returncode == 0, "pool-db-source.patch apply failed: " + r.stdout + r.stderr
    cdir = os.path.join(tmp, "cycle")
    os.makedirs(cdir)
    for f in ("production_cycle.py", "legacy_source_adapter.py",
              "candidate_contract.py", "safe_additions.py", "single_writer.py"):
        shutil.copy2(os.path.join(PROD_CHAIN_DIR, f), os.path.join(cdir, f))
    shutil.copy2(os.path.join(pdir, "single-writer", "pool_db_source.py"),
                 os.path.join(cdir, "pool_db_source.py"))
    spec = importlib.util.spec_from_file_location(
        "i03_production_cycle", os.path.join(cdir, "production_cycle.py"))
    cycle = importlib.util.module_from_spec(spec)
    sys.modules["i03_production_cycle"] = cycle
    spec.loader.exec_module(cycle)
    served = os.path.join(tmp, "served.txt")
    staging = os.path.join(tmp, "staging.txt")
    open(served, "wb").write(current)
    open(staging, "wb").write(current)
    restore = _set_rejected_env(REJECTED_JSON)
    try:
        db2, _served_bytes, meta = cycle._preflight(db, served, staging)
        check("L5 _preflight 放行干净池（21 钉选 + 加拿大，22 行）",
              meta["candidate_count"] == 22 and meta["canonical_pin_count"] == 21,
              "meta=%s" % (meta,))
        check("L5 _preflight 读到的 blocked_keys 含已拒三元组（37 条）",
              REJECTED_KEY in db2["blocked_keys"] and
              len(db2["blocked_keys"]) == 37)
        bad_line = ("香港11 🇭🇰 = trojan, 156.224.79.105, 443, "
                    "password=placeholder, sni=cfnode.vip668.xin, "
                    "ws=true, ws-path=/")
        bad = current + bad_line.encode("utf-8") + b"\n"
        open(served, "wb").write(bad)
        open(staging, "wb").write(bad)
        try:
            cycle._preflight(db, served, staging)
            check("L5 _preflight 拒含被禁钉选名的池（blocked_pins_reentered）",
                  False, "no raise")
        except cycle.CycleRefused as exc:
            check("L5 _preflight 拒含被禁钉选名的池（blocked_pins_reentered）",
                  str(exc) == "blocked_pins_reentered", str(exc))
    finally:
        restore()


if __name__ == "__main__":
    sys.exit(main())
