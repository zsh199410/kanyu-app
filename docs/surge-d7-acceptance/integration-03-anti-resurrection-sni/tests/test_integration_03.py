#!/usr/bin/env python3
"""集成-03 隔离测试：N2 持久禁入 + N3 SNI 准入。

只读 live 证据、不写 live 库、不联网、不启动生产 worker。
快照副本：work/pool-snapshot.db（2026-11-24 11:52 UTC 复制）；
新鲜抓取夹具：work/crawl-20261124-desensitized.json（4023 条，
2026-11-24 11:55 新鲜抓取，uuid/password 已剥离）。

用法：python3 tests/test_integration_03.py
退出码 0 = 全部通过；任一失败打印 FAIL 并 exit 1。
"""

import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                     # pr-source/
WORK = os.path.abspath(os.path.join(ROOT, "..", "work"))
SNAPSHOT = os.path.join(WORK, "pool-snapshot.db")
FIXTURE = os.path.join(WORK, "crawl-20261124-desensitized.json")
AUDIT_JSON = os.path.join(ROOT, "pool", "blocklist_backfill_20261121.json")
REJECTED_JSON = os.path.join(ROOT, "pool", "rejected_nodes.json")
BACKFILL = os.path.join(ROOT, "pool", "backfill_blocklist.py")
UNBLOCK = os.path.join(ROOT, "pool", "unblock_node.py")

sys.path.insert(0, ROOT)
from pool import rules as rules_mod          # noqa: E402
from pool import tester as tester_mod        # noqa: E402
from pool import screening as screening_mod  # noqa: E402

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


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


# ---------------------------------------------------------------- Part A: 回填
def part_a_backfill():
    print("== Part A: N2 回填（快照副本） ==")
    tmp = tempfile.mkdtemp(prefix="i03-a-")
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    nodes_before = sqlite3.connect("file:%s?mode=ro" % db, uri=True).execute(
        "SELECT COUNT(*), SUM(pass_count), SUM(test_count) FROM nodes").fetchone()
    tests_before = sqlite3.connect("file:%s?mode=ro" % db, uri=True).execute(
        "SELECT COUNT(*) FROM node_tests").fetchone()[0]
    blocked_before = sqlite3.connect("file:%s?mode=ro" % db, uri=True).execute(
        "SELECT COUNT(*) FROM blocklist").fetchone()[0]

    r = run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
             "--dry-run"])
    check("A1 dry-run exit 0", r.returncode == 0, r.stdout[-200:] + r.stderr[-200:])
    check("A1 dry-run: 25 absent 0 conflict",
          "present=0 absent=25 conflict=0" in r.stdout, r.stdout[-200:])
    check("A1 dry-run 未写库",
          sqlite3.connect("file:%s?mode=ro" % db, uri=True).execute(
              "SELECT COUNT(*) FROM blocklist").fetchone()[0] == blocked_before)

    r = run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
             "--check"])
    check("A2 --check 回填前 exit 1（25 条全缺）", r.returncode == 1,
          "rc=%d" % r.returncode)

    backup = os.path.join(tmp, "pool.db.bak")
    r = run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
             "--apply", "--backup", backup, "--by", "i03-test"])
    check("A3 --apply exit 0", r.returncode == 0, r.stdout[-300:] + r.stderr[-300:])
    check("A3 备份 SHA 与源库一致",
          sha256_file(db) == sha256_file(backup))
    conn = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    check("A3 blocklist 11 -> 36",
          conn.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0] == 36)
    check("A3 audit 新增 25 行 blocklist-backfill",
          conn.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-backfill'").fetchone()[0] == 25)
    check("A3 nodes 一字节未变",
          conn.execute("SELECT COUNT(*), SUM(pass_count), SUM(test_count) FROM nodes").fetchone() == nodes_before)
    check("A3 node_tests 一行未变",
          conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0] == tests_before)
    audit = json.load(open(AUDIT_JSON))
    for e in audit["entries"]:
        row = conn.execute(
            "SELECT reason, by FROM blocklist WHERE protocol=? AND host=? AND port=?",
            (e["protocol"], e["host"], e["port"])).fetchone()
        if row is None or row[0] != "phone-fail-20261121" or row[1] != "i03-test":
            check("A3 逐条 reason/by: %s" % e["name"], False, str(row))
            break
    else:
        check("A3 逐条 reason=phone-fail-20261121 by=i03-test", True)
    conn.close()

    r = run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
             "--apply", "--backup", os.path.join(tmp, "pool.db.bak2"),
             "--by", "i03-test"])
    check("A4 幂等：重跑 exit 0 且 inserted=0",
          r.returncode == 0 and "inserted=0" in r.stdout, r.stdout[-200:])
    conn = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    check("A4 幂等：audit 不重复写",
          conn.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-backfill'").fetchone()[0] == 25)
    conn.close()

    r = run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
             "--check"])
    check("A5 --check 回填后 exit 0", r.returncode == 0, r.stdout[-200:])

    # 冲突 fail-closed：预置一条同三元组不同 reason 的行
    db2 = os.path.join(tmp, "pool2.db")
    shutil.copy2(SNAPSHOT, db2)
    c2 = sqlite3.connect(db2)
    c2.execute("INSERT INTO blocklist VALUES ('ss','193.151.160.18',19999,'other-reason',1,'x')")
    c2.commit()
    c2.close()
    r = run([sys.executable, BACKFILL, "--db", db2, "--audit", AUDIT_JSON,
             "--apply", "--backup", os.path.join(tmp, "pool2.db.bak"),
             "--by", "i03-test"])
    check("A6 冲突 fail-closed：exit 1 且不写库",
          r.returncode == 1 and
          sqlite3.connect("file:%s?mode=ro" % db2, uri=True).execute(
              "SELECT COUNT(*) FROM blocklist").fetchone()[0] == 12,
          "rc=%d" % r.returncode)
    check("A6 冲突不产生备份写后文件",
          not os.path.exists(os.path.join(tmp, "pool2.db.bak")))

    # live 路径拒绝
    r = run([sys.executable, BACKFILL, "--db",
             "/opt/free-node-program/data/pool.db", "--audit", AUDIT_JSON,
             "--apply", "--backup", os.path.join(tmp, "live.bak"),
             "--by", "i03-test"])
    check("A7 live 路径无 --allow-live 拒绝", r.returncode == 2,
          "rc=%d" % r.returncode)
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- Part B: N3
def part_b_n3():
    print("== Part B: N3 SNI 准入（双入口 + 真实夹具） ==")
    private = set()

    def vmess(host, sni, tls=True, net="tcp"):
        return {"protocol": "vmess", "host": host, "port": 1270,
                "tls": tls, "net": net, "uuid": "00000000-0000-0000-0000-000000000000",
                "sni": sni, "security": "auto"}

    # 6/6 对照复现：4 条失败变体（sni 缺失/空/空白/字面 <nil>）+ 3 条对照
    fail_shapes = [
        ("sni=None", vmess("8.8.8.8", None)),
        ("sni=''", vmess("8.8.4.4", "")),
        ("sni='   '", vmess("1.1.1.1", "   ")),
        ("sni='<nil>'", vmess("9.9.9.9", "<nil>")),
    ]
    ctrl_shapes = [
        ("sni=xmfhlpy.com", vmess("8.8.8.8", "xmfhlpy.com")),
        ("sni=xmfhlpy.com:443", vmess("8.8.4.4", "xmfhlpy.com")),
        ("sni=xmfhlpy.com ws", vmess("1.1.1.1", "xmfhlpy.com", net="ws")),
    ]
    for name, rec in fail_shapes:
        ok, reason = rules_mod.pre_filter(rec, private)
        check("B1 pre_filter 拒 %s" % name,
              ok is False and reason == "vmess-no-sni", "%s/%s" % (ok, reason))
        check("B1 _filter_reason 拒 %s" % name,
              tester_mod._filter_reason(rec) == "vmess-no-sni")
        try:
            rules_mod.build_surge_line(rec, "X")
            check("B1 build_surge_line 抛错 %s" % name, False, "no raise")
        except ValueError as exc:
            check("B1 build_surge_line 抛错 %s" % name,
                  str(exc) == "vmess-no-sni", str(exc))
    for name, rec in ctrl_shapes:
        ok, reason = rules_mod.pre_filter(rec, private)
        check("B2 pre_filter 放行 %s" % name, ok is True, "%s/%s" % (ok, reason))
        check("B2 _filter_reason 放行 %s" % name,
              tester_mod._filter_reason(rec) is None)
        try:
            line = rules_mod.build_surge_line(rec, "X")
            check("B2 build_surge_line 成功 %s" % name, "sni=xmfhlpy.com" in line, line)
        except ValueError as exc:
            check("B2 build_surge_line 成功 %s" % name, False, str(exc))

    # 合法 DNS hostname 不误拒
    dns_rec = vmess("node.example.com", None)
    ok, _r = rules_mod.pre_filter(dns_rec, private)
    check("B3 DNS hostname 无 SNI 不误拒",
          ok is True and tester_mod._filter_reason(dns_rec) is None)
    # IPv6 拨号同样规则
    v6_rec = vmess("2606:4700:4700::1111", None)
    check("B4 IPv6 拨号无 SNI 拒",
          rules_mod.pre_filter(v6_rec, private) == (False, "vmess-no-sni"))
    # 非 TLS vmess 仍走原有原因，不被 N3 抢占
    nontls = vmess("8.8.8.8", None, tls=False)
    check("B5 非 TLS vmess 仍为 vmess-non-tls",
          rules_mod.pre_filter(nontls, private) == (False, "vmess-non-tls") and
          tester_mod._filter_reason(nontls) == "vmess-non-tls")
    # trojan / ss 不受 N3 影响
    troj = {"protocol": "trojan", "host": "8.8.8.8", "port": 443,
            "password": "pw", "sni": None}
    check("B6 trojan 无 SNI 不受 N3 影响",
          rules_mod.pre_filter(troj, private) == (True, "") and
          tester_mod._filter_reason(troj) is None)

    # 真实夹具：2026-11-24 11:55 新鲜抓取 4023 条
    data = json.load(open(FIXTURE))
    recs = data["records"]
    check("B7 夹具 4023 条且凭据全为占位符（无真实值）",
          len(recs) == 4023 and
          {r.get("uuid") for r in recs if r["protocol"] == "vmess"} ==
          {"00000000-0000-0000-0000-000000000000"} and
          {r.get("password") for r in recs
           if r["protocol"] in ("trojan", "ss")} == {"placeholder"})
    vm_tls = [r for r in recs if r["protocol"] == "vmess" and r.get("tls")]

    def sni_missing(r):
        s = r.get("sni")
        return s is None or (isinstance(s, str) and s.strip() in ("", "<nil>"))

    def is_ip(h):
        import ipaddress
        try:
            ipaddress.ip_address(h)
            return True
        except ValueError:
            return False

    no_sni = [r for r in vm_tls if sni_missing(r)]
    ip_dial = [r for r in no_sni if is_ip(r["host"])]
    dns_dial = [r for r in no_sni if not is_ip(r["host"])]
    check("B8 夹具 vmess+TLS=1015 无 SNI=619 (61.0%)",
          len(vm_tls) == 1015 and len(no_sni) == 619,
          "vm_tls=%d no_sni=%d" % (len(vm_tls), len(no_sni)))
    check("B8 其中 IP 拨号 462 / DNS 拨号 157",
          len(ip_dial) == 462 and len(dns_dial) == 157,
          "ip=%d dns=%d" % (len(ip_dial), len(dns_dial)))
    # N3 规则在夹具上的实际裁决：IP 拨号全拒、DNS 拨号全放
    got_reject = [r for r in vm_tls
                  if rules_mod.pre_filter(r, private) == (False, "vmess-no-sni")]
    got_reject_t = [r for r in vm_tls
                    if tester_mod._filter_reason(r) == "vmess-no-sni"]
    check("B9 pre_filter 在夹具上以 vmess-no-sni 拒 456 条",
          len(got_reject) == 456, "got=%d" % len(got_reject))
    other = [r for r in ip_dial
             if rules_mod.pre_filter(r, private)[1] != "vmess-no-sni"]
    check("B9 另 6 条（grpc/h2）被更早的 unsupported-transport 拒，合计 462",
          len(other) == 6 and
          all(rules_mod.pre_filter(r, private) == (False, "unsupported-transport")
              for r in other) and
          {r.get("net") for r in other} == {"grpc", "h2"},
          "other=%d" % len(other))
    check("B9 _filter_reason 与 pre_filter 在夹具上逐条一致",
          got_reject == got_reject_t)
    check("B9 被拒的 462 条全部是 IP 拨号无 SNI",
          all(is_ip(r["host"]) and sni_missing(r) for r in got_reject))
    check("B9 157 条 DNS 拨号无 SNI 一条未被 N3 拒",
          not any(rules_mod.pre_filter(r, private) == (False, "vmess-no-sni")
                  for r in dns_dial))
    # :1270 全量：16 条无 SNI，全部 IP 拨号，全部应拒
    p1270 = [r for r in vm_tls if r["port"] == 1270]
    p1270_nosni = [r for r in p1270 if sni_missing(r)]
    check("B10 :1270 无 SNI 16 条且全部 IP 拨号",
          len(p1270_nosni) == 16 and all(is_ip(r["host"]) for r in p1270_nosni),
          "n=%d" % len(p1270_nosni))
    check("B10 :1270 无 SNI 16 条全部被 N3 拒",
          all(rules_mod.pre_filter(r, private) == (False, "vmess-no-sni")
              for r in p1270_nosni))


# ---------------------------------------------------------------- Part C: 筛查
def part_c_screening():
    print("== Part C: 统一筛查（快照副本） ==")
    tmp = tempfile.mkdtemp(prefix="i03-c-")
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    audit = json.load(open(AUDIT_JSON))
    blocked25 = {(e["protocol"], e["host"], e["port"]) for e in audit["entries"]}
    rejected = screening_mod.load_rejected(REJECTED_JSON)
    check("C0 rejected 清单 1 条（188.114.99.137:443 vmess）",
          len(rejected) == 1 and
          ("vmess", "188.114.99.137", 443) in rejected)

    conn = sqlite3.connect(db)
    now = conn.execute("SELECT MAX(last_test_at) FROM nodes").fetchone()[0]
    rows0, excl0 = screening_mod.strict_candidates(conn, set(), set(), now)
    check("C1 未排除时严格集 21 条", len(rows0) == 21, "got=%d" % len(rows0))
    rows1, excl1 = screening_mod.strict_candidates(conn, blocked25, rejected, now)
    check("C2 回填排除后严格集 9 条", len(rows1) == 9, "got=%d" % len(rows1))
    removed = {(r[0], r[1], r[2]) for r, _ in excl1}
    check("C2 排除 12 条且全部在 25 条回填集内",
          len(excl1) == 12 and removed <= blocked25,
          "excluded=%d" % len(excl1))
    check("C2 5 条复活候选全部被排除",
          {("ss", "156.146.38.168", 443), ("ss", "156.146.38.169", 443),
           ("ss", "156.146.38.170", 443), ("ss", "173.244.56.9", 443),
           ("trojan", "167.88.61.85", 443)} <= removed)
    # 9 条剩余的身份
    remaining = {(r[0], r[1], r[2]) for r in rows1}
    check("C3 剩余 9 条含加拿大（已在正式池，非补位候选）",
          ("vmess", "104.18.42.163", 443) in remaining)
    # N3 叠加：9 条里 3 条 :1270 无 SNI 变体应被记录级排除
    data = json.load(open(FIXTURE))
    fresh = {(r["protocol"], r["host"], r["port"]): r for r in data["records"]}
    n3_out = 0
    for r in rows1:
        rec = fresh.get((r[0], r[1], r[2]))
        if rec and rules_mod.pre_filter(rec, set()) == (False, "vmess-no-sni"):
            n3_out += 1
    check("C4 9 条中 3 条 :1270 无 SNI 变体被 N3 记录级排除",
          n3_out == 3, "got=%d" % n3_out)
    # rejected 机制：合成一个严格集内的被拒三元组，验证排除原因
    c2 = sqlite3.connect(db)
    cur = c2.execute("UPDATE nodes SET last_test_at=?, last_result='pass', last_reason='', pass_count=25, test_count=25 WHERE protocol='vmess' AND host='188.114.99.137' AND port=443", (now,))
    assert cur.rowcount == 1, "rejected triple must already exist in nodes"
    c2.execute("DELETE FROM node_tests WHERE protocol='vmess' AND host='188.114.99.137' AND port=443")
    for i in range(25):
        c2.execute("INSERT INTO node_tests VALUES ('vmess','188.114.99.137',443,?, 'pass','',76.0)", (now - i * 60,))
    c2.commit()
    rows2, excl2 = screening_mod.strict_candidates(c2, blocked25, rejected, now)
    rej = [r for r, why in excl2 if why == "rejected-gpt"]
    check("C5 合成被拒三元组进严格集后被 rejected-gpt 排除",
          len(rej) == 1 and rej[0][:3] == ("vmess", "188.114.99.137", 443),
          "rej=%s" % rej)
    check("C5 被拒三元组不在输出行内",
          ("vmess", "188.114.99.137", 443) not in {(r[0], r[1], r[2]) for r in rows2})
    c2.close()
    conn.close()
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- Part D: 解禁
def part_d_unblock():
    print("== Part D: 解禁流程负例（快照副本） ==")
    tmp = tempfile.mkdtemp(prefix="i03-d-")
    db = os.path.join(tmp, "pool.db")
    shutil.copy2(SNAPSHOT, db)
    # 先回填，使库里有 25 条可解禁
    run([sys.executable, BACKFILL, "--db", db, "--audit", AUDIT_JSON,
         "--apply", "--backup", os.path.join(tmp, "b.bak"), "--by", "i03-test"])
    target = ["--db", db, "--protocol", "ss", "--host", "156.146.38.168",
              "--port", "443"]
    r = run([sys.executable, UNBLOCK] + target + ["--dry-run"])
    check("D1 dry-run exit 0 且不写库", r.returncode == 0, r.stdout[-200:])
    check("D1 dry-run 后 blocklist 仍 36 条",
          sqlite3.connect("file:%s?mode=ro" % db, uri=True).execute(
              "SELECT COUNT(*) FROM blocklist").fetchone()[0] == 36)
    r = run([sys.executable, UNBLOCK] + target + ["--apply",
             "--backup", os.path.join(tmp, "u.bak")])
    check("D2 --apply 缺 --approved-by/--decision-ref/--evidence 拒绝",
          r.returncode == 2, "rc=%d" % r.returncode)
    r = run([sys.executable, UNBLOCK, "--db", db, "--protocol", "ss",
             "--host", "8.8.8.8", "--port", "443", "--dry-run"])
    check("D3 不在 blocklist 的三元组拒绝解禁", r.returncode == 1,
          "rc=%d" % r.returncode)
    r = run([sys.executable, UNBLOCK, "--db", db, "--protocol", "vmess",
             "--host", "188.114.99.137", "--port", "443", "--dry-run"])
    check("D4 rejected 清单内三元组拒绝只解 blocklist", r.returncode == 1,
          "rc=%d" % r.returncode)
    r = run([sys.executable, UNBLOCK] + target + ["--apply",
             "--backup", os.path.join(tmp, "u.bak"),
             "--approved-by", "i03-test", "--decision-ref", "test-ref",
             "--evidence", "test-evidence"])
    check("D5 完整参数 --apply exit 0", r.returncode == 0,
          r.stdout[-200:] + r.stderr[-200:])
    conn = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    check("D5 解禁后 blocklist 36 -> 35",
          conn.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0] == 35)
    check("D5 audit 写 1 行 blocklist-unblock",
          conn.execute("SELECT COUNT(*) FROM audit WHERE action='blocklist-unblock'").fetchone()[0] == 1)
    check("D5 nodes/node_tests 未动",
          conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0] == 7798 and
          conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0] > 0)
    conn.close()
    shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------- Part E: 口径复核
def part_e_recount():
    print("== Part E: 15→10 口径复核（P1-2 新鲜可用集 vs 25 条回填集） ==")
    # P1-2 §2.1：16 条新鲜 ≤300ms（2026-11-24 10:19 复测）
    fresh16 = {
        ("ss", "37.19.198.160", 443), ("vmess", "guanwang.awsno.com", 443),
        ("ss", "156.146.38.169", 443), ("ss", "156.146.38.170", 443),
        ("ss", "173.244.56.9", 443), ("ss", "37.19.198.236", 443),
        ("ss", "37.19.198.243", 443), ("trojan", "167.88.61.198", 443),
        ("trojan", "167.88.61.20", 443), ("trojan", "167.88.61.85", 443),
        ("ss", "156.146.38.168", 443), ("ss", "37.19.198.244", 443),
        ("ss", "51.222.12.127", 445), ("trojan", "167.88.61.52", 443),
        ("vmess", "172.64.145.93", 443), ("vmess", "188.114.99.137", 443),
    }
    audit = json.load(open(AUDIT_JSON))
    blocked25 = {(e["protocol"], e["host"], e["port"]) for e in audit["entries"]}
    rejected = screening_mod.load_rejected(REJECTED_JSON)
    in_backfill = fresh16 & blocked25
    in_rejected = fresh16 & set(rejected)
    truly_new = fresh16 - blocked25 - set(rejected)
    check("E1 16 条新鲜可用中 11 条在 25 条回填集内（非 P1-2 所称 5 条）",
          len(in_backfill) == 11, "got=%d: %s" % (len(in_backfill), sorted(in_backfill)))
    check("E2 其中 6 条是 10:55/12:55/13:55 自动清退（P1-2 只核了 R1–R4）",
          {("ss", "37.19.198.160", 443), ("ss", "37.19.198.236", 443),
           ("ss", "37.19.198.243", 443), ("ss", "37.19.198.244", 443),
           ("trojan", "167.88.61.20", 443), ("trojan", "167.88.61.52", 443)}
          <= in_backfill)
    check("E3 1 条为 GPT 已拒（188.114.99.137:443）",
          in_rejected == {("vmess", "188.114.99.137", 443)})
    check("E4 真正新合格节点 4 条（非 10 条）",
          len(truly_new) == 4, "got=%s" % sorted(truly_new))
    check("E4 4 条为 au1rxx / chenzhihan / matin-ss / matin-vmess 各 1 组",
          truly_new == {("vmess", "guanwang.awsno.com", 443),
                        ("trojan", "167.88.61.198", 443),
                        ("ss", "51.222.12.127", 445),
                        ("vmess", "172.64.145.93", 443)})


def main():
    part_a_backfill()
    part_b_n3()
    part_c_screening()
    part_d_unblock()
    part_e_recount()
    print("TOTAL: pass=%d fail=%d" % (PASS, FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
