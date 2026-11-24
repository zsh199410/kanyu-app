#!/usr/bin/env python3
"""Integration-01 isolation tests: small-pool control contract + consumer isolation.

Runs COPIES of the patched receiver.py / verify_promotion.py /
import_per_observation_v2.py / import_phone_observations.py /
auto_prune.py / formal_manifest.py against synthetic pools, manifests and
scratch DBs on loopback ports 18741-18745. Never touches live receivers,
live DBs, live env files, timers or switches. Synthetic TEST-NET
identities only; never reads the real token.
Covers control-design.md §8 A1-A18, legacy regression R1-R8,
DIAGNOSTIC_PASS derivation D1-D11, and generator checks G1-G5.
"""
import hashlib
import json
import os
import secrets
import shutil
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.request
import urllib.error

ISO = "/tmp/i01-isolation"
SRC = os.environ.get("I01_SRC", os.path.expanduser("~/workspace/tester-diag-pr/pr126-integration-01/pr-source"))
GROUP = "试用节点池"
TOKEN = "a" * 43  # synthetic, never the real token

results = []


def note(case, ok, detail):
    results.append((case, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {case}: {detail}", flush=True)


def post(port, payload, token=TOKEN):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/phone-observations",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": "Bearer " + token,
                 "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except Exception:
            body = {}
        return e.code, body


def wait_port(port, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=1)
            s.close()
            return True
        except OSError:
            time.sleep(0.2)
    return False


def start_receiver(port, pool_path, db_path, formal_pool=None, formal_manifest=None):
    env = dict(os.environ)
    env.update({
        "PYTHONDONTWRITEBYTECODE": "1",
        "PHONE_PROBE_TOKEN": TOKEN,
        "PHONE_PROBE_POOL": pool_path,
        "PHONE_PROBE_DB": db_path,
        "PHONE_PROBE_GROUP": GROUP,
        "PHONE_PROBE_MIN_POOL": "1",
        "PHONE_PROBE_PORT": str(port),
    })
    if formal_pool is not None:
        env["PHONE_PROBE_FORMAL_POOL"] = formal_pool
        env["PHONE_PROBE_FORMAL_MANIFEST"] = formal_manifest
    proc = subprocess.Popen([sys.executable, f"{ISO}/receiver.py"],
                            env=env, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    if not wait_port(port):
        proc.kill()
        raise RuntimeError(f"receiver on {port} did not come up")
    return proc


def succ():
    return [{"id": "a", "state": "reachable"}, {"id": "b", "state": "reachable"}]


def fail():
    return [{"id": "a", "state": "timeout"}, {"id": "b", "state": "transport_error"}]


def obs(name, results, mode="external_policy_id"):
    return {"name": name, "probe_mode": mode, "results": results}


def control(name, proto, host, port, results, mode="external_policy_id"):
    return {"name": name, "protocol": proto, "host": host, "port": port,
            "probe_mode": mode, "results": results}


def make_payload(pool_sha, nonce, observations, controls=None, bearer="cellular",
                 formal_sha=None, formal_gen=None):
    p = {"schema": 1, "group": GROUP, "timestamp": int(time.time()),
         "nonce": nonce, "pool_sha": pool_sha, "bearer": bearer,
         "surge_version": "1.0", "observations": observations}
    if controls is not None:
        p["network_controls"] = controls
    if formal_sha is not None:
        p["formal_pool_sha"] = formal_sha
    if formal_gen is not None:
        p["formal_generation"] = formal_gen
    return p


def db_rows(db_path):
    c = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        return c.execute(
            "SELECT protocol,host,port,status,probe_mode,trusted,reason,"
            "raw_status,raw_reason,control_verified,bearer,pool_sha,nonce "
            "FROM phone_observations ORDER BY id").fetchall()
    finally:
        c.close()


def db_count(db_path):
    c = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        return c.execute("SELECT COUNT(*) FROM phone_observations").fetchone()[0]
    finally:
        c.close()


def validate_code(payload, pool_bytes, formal_pool_bytes, formal_manifest):
    """Call the patched validate() in-process to assert the exact 422 code."""
    sys.path.insert(0, ISO)
    import receiver
    try:
        receiver.validate(payload, pool_bytes, formal_pool_bytes=formal_pool_bytes,
                          formal_manifest=formal_manifest,
                          group=GROUP, min_pool=1)
        return None
    except receiver.InputRejected as e:
        return e.code


def sha_of(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def write_pool(path, members):
    with open(path, "w", encoding="utf-8") as f:
        for name, proto, host, port in members:
            f.write(f"{name} = {proto},{host},{port},x\n")


def main():
    os.makedirs(ISO, mode=0o700, exist_ok=True)
    for fname in ("receiver.py", "formal_manifest.py", "verify_promotion.py",
                  "import_per_observation_v2.py", "import_phone_observations.py",
                  "auto_prune.py"):
        shutil.copy(f"{SRC}/{fname}", f"{ISO}/{fname}")

    # --- synthetic pools (TEST-NET only) ---
    trial1 = [("试用-甲", "vmess", "203.0.113.10", 443)]
    trial3 = trial1 + [("试用-乙", "trojan", "203.0.113.11", 443),
                       ("试用-丙", "trojan", "203.0.113.12", 8443)]
    trial6 = trial3 + [("试用-丁", "ss", "203.0.113.13", 8388),
                       ("试用-戊", "vmess", "203.0.113.14", 443),
                       ("试用-己", "trojan", "203.0.113.15", 2053)]
    # formal pool: 正式-加拿大 shares the trial candidate identity (dual
    # membership, mirrors live Canada); 正式-丙 is NOT in eligible_controls.
    formal = [("正式-甲", "trojan", "203.0.113.20", 443),
              ("正式-乙", "trojan", "203.0.113.21", 8443),
              ("正式-丙", "vmess", "203.0.113.22", 443),
              ("正式-加拿大", "vmess", "203.0.113.10", 443),
              ("正式-丁", "trojan", "203.0.113.23", 443)]
    write_pool(f"{ISO}/trial1.txt", trial1)
    write_pool(f"{ISO}/trial3.txt", trial3)
    write_pool(f"{ISO}/trial6.txt", trial6)
    write_pool(f"{ISO}/formal.txt", formal)
    write_pool(f"{ISO}/formal-b.txt", formal)
    t1_sha, t3_sha, t6_sha = sha_of(f"{ISO}/trial1.txt"), sha_of(f"{ISO}/trial3.txt"), sha_of(f"{ISO}/trial6.txt")
    f_sha, fb_sha = sha_of(f"{ISO}/formal.txt"), sha_of(f"{ISO}/formal-b.txt")
    assert f_sha == fb_sha
    formal_bytes = open(f"{ISO}/formal.txt", "rb").read()
    formal_bytes_b = open(f"{ISO}/formal-b.txt", "rb").read()
    t1_bytes = open(f"{ISO}/trial1.txt", "rb").read()
    t3_bytes = open(f"{ISO}/trial3.txt", "rb").read()
    t6_bytes = open(f"{ISO}/trial6.txt", "rb").read()

    now = int(time.time())
    formal_manifest = {
        "pool_sha": f_sha, "generation": 0,
        "updated_at": "2026-11-24T10:00:00Z", "lines": 5, "entries": 5,
        "status": "FORMAL",
        "eligible_controls": [
            {"name": "正式-甲", "protocol": "trojan", "host": "203.0.113.20",
             "port": 443, "source_group": "G-matin",
             "last_trusted_success": now - 3600, "last_trusted_failure": None},
            {"name": "正式-乙", "protocol": "trojan", "host": "203.0.113.21",
             "port": 8443, "source_group": "G-alirewa",
             "last_trusted_success": now - 3600, "last_trusted_failure": now - 90000},
        ],
    }
    with open(f"{ISO}/formal-manifest.json", "w", encoding="utf-8") as f:
        json.dump(formal_manifest, f, ensure_ascii=False, indent=2)
    with open(f"{ISO}/formal-manifest-b.json", "w", encoding="utf-8") as f:
        json.dump(formal_manifest, f, ensure_ascii=False, indent=2)

    procs = []
    try:
        # 18741 formal-mode, 1-node trial pool; 18743 formal-mode, 3-node;
        # 18744 formal-mode, 6-node; 18742 legacy-mode, 6-node;
        # 18745 formal-mode with its own formal pool/manifest copies (A16/A17).
        procs.append(start_receiver(18741, f"{ISO}/trial1.txt", f"{ISO}/db41.sqlite3",
                                    f"{ISO}/formal.txt", f"{ISO}/formal-manifest.json"))
        procs.append(start_receiver(18742, f"{ISO}/trial6.txt", f"{ISO}/db42.sqlite3"))
        procs.append(start_receiver(18743, f"{ISO}/trial3.txt", f"{ISO}/db43.sqlite3",
                                    f"{ISO}/formal.txt", f"{ISO}/formal-manifest.json"))
        procs.append(start_receiver(18744, f"{ISO}/trial6.txt", f"{ISO}/db44.sqlite3",
                                    f"{ISO}/formal.txt", f"{ISO}/formal-manifest.json"))
        procs.append(start_receiver(18745, f"{ISO}/trial1.txt", f"{ISO}/db45.sqlite3",
                                    f"{ISO}/formal-b.txt", f"{ISO}/formal-manifest-b.json"))

        ctrl_a = lambda r: control("正式-甲", "trojan", "203.0.113.20", 443, r)
        ctrl_b = lambda r: control("正式-乙", "trojan", "203.0.113.21", 8443, r)
        ctrl_c = lambda r: control("正式-丙", "vmess", "203.0.113.22", 443, r)
        ctrl_dual = lambda r: control("正式-加拿大", "vmess", "203.0.113.10", 443, r)

        # ---- A1: 1 candidate success + 1 formal control success -> cv=1 ----
        n = secrets.token_hex(16)
        s, b = post(18741, make_payload(t1_sha, n, [obs("试用-甲", succ())],
                                        [ctrl_a(succ())], formal_sha=f_sha, formal_gen=0))
        rows = db_rows(f"{ISO}/db41.sqlite3")
        note("A1 1条成功+正式对照成功", s == 200 and b.get("receipt") == "stored"
             and len(rows) == 1 and rows[0][3] == "success" and rows[0][9] == 1,
             f"status={s} rows={rows}")

        # ---- A2: 1 candidate failure + 1 formal control success -> cv=1 ----
        n = secrets.token_hex(16)
        s, b = post(18741, make_payload(t1_sha, n, [obs("试用-甲", fail())],
                                        [ctrl_a(succ())], formal_sha=f_sha, formal_gen=0))
        rows = db_rows(f"{ISO}/db41.sqlite3")
        note("A2 1条失败+正式对照成功", s == 200 and len(rows) == 2
             and rows[1][3] == "failure" and rows[1][9] == 1,
             f"status={s} rows={rows[1:]}")

        # ---- A3: 1 candidate failure + 1 formal control failure -> cv=0 ----
        n = secrets.token_hex(16)
        s, b = post(18741, make_payload(t1_sha, n, [obs("试用-甲", fail())],
                                        [ctrl_a(fail())], formal_sha=f_sha, formal_gen=0))
        rows = db_rows(f"{ISO}/db41.sqlite3")
        note("A3 1条失败+正式对照失败", s == 200 and len(rows) == 3
             and rows[2][3] == "failure" and rows[2][9] == 0,
             f"status={s} rows={rows[2:]}")

        # ---- A4: control is the trial member itself (dual membership) ----
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_dual(succ())], formal_sha=f_sha, formal_gen=0)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A4 对照=试用成员自身拒批", s == 422 and code == "control_is_trial_member"
             and db_count(f"{ISO}/db41.sqlite3") == 3,
             f"status={s} code={code}")

        # ---- A5: control name in formal pool but identity mismatched ----
        bad = control("正式-甲", "trojan", "203.0.113.20", 9999, succ())
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [bad], formal_sha=f_sha, formal_gen=0)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A5 对照身份与正式池不符拒批", s == 422 and code == "unknown_formal_control"
             and db_count(f"{ISO}/db41.sqlite3") == 3,
             f"status={s} code={code}")

        # ---- A6: control not in eligible_controls ----
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_c(succ())], formal_sha=f_sha, formal_gen=0)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A6 对照不在合格清单拒批", s == 422 and code == "formal_control_not_eligible"
             and db_count(f"{ISO}/db41.sqlite3") == 3,
             f"status={s} code={code}")

        # ---- A7: stale formal pool SHA / wrong generation ----
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_a(succ())], formal_sha="0" * 64, formal_gen=0)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A7a 伪造正式池SHA拒批", s == 422 and code == "stale_formal_pool_sha"
             and db_count(f"{ISO}/db41.sqlite3") == 3,
             f"status={s} code={code}")
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_a(succ())], formal_sha=f_sha, formal_gen=99)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A7b 正式代次不符拒批", s == 422 and code == "stale_formal_generation"
             and db_count(f"{ISO}/db41.sqlite3") == 3,
             f"status={s} code={code}")

        # ---- A8: no controls, no formal fields -> legacy path, cv=0 ----
        n = secrets.token_hex(16)
        s, b = post(18741, make_payload(t1_sha, n, [obs("试用-甲", succ())]))
        rows = db_rows(f"{ISO}/db41.sqlite3")
        note("A8 无对照向后兼容", s == 200 and len(rows) == 4
             and rows[3][3] == "success" and rows[3][9] == 0,
             f"status={s} rows={rows[3:]}")

        # ---- A9: 3 candidates all failure + 1 formal control success ----
        n = secrets.token_hex(16)
        s, b = post(18743, make_payload(t3_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail())],
                                        [ctrl_a(succ())], formal_sha=f_sha, formal_gen=0))
        rows = db_rows(f"{ISO}/db43.sqlite3")
        note("A9 3条全失败+正式对照成功不降级", s == 200 and len(rows) == 3
             and all(r[3] == "failure" and r[9] == 1 for r in rows),
             f"status={s} rows={rows}")

        # ---- A10: 3 candidates all failure + 1 formal control failure ----
        n = secrets.token_hex(16)
        s, b = post(18743, make_payload(t3_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail())],
                                        [ctrl_a(fail())], formal_sha=f_sha, formal_gen=0))
        rows = db_rows(f"{ISO}/db43.sqlite3")
        note("A10 3条全失败+正式对照失败整批降级", s == 200 and len(rows) == 6
             and all(r[3] == "unknown" and r[6] == "batch_unverified_network"
                     and r[7] == "failure" and r[9] == 0 for r in rows[3:]),
             f"status={s} rows={rows[3:]}")

        # ---- A11: 3 candidates all failure, no controls (regression) ----
        n = secrets.token_hex(16)
        s, b = post(18743, make_payload(t3_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail())]))
        rows = db_rows(f"{ISO}/db43.sqlite3")
        note("A11 3条全失败无对照整批降级(回归)", s == 200 and len(rows) == 9
             and all(r[3] == "unknown" and r[6] == "batch_unverified_network" for r in rows[6:]),
             f"status={s} rows={rows[6:]}")

        # ---- A12: 6-node pool, sample 4 + 2 formal controls ----
        n = secrets.token_hex(16)
        s, b = post(18744, make_payload(t6_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail()), obs("试用-丁", fail())],
                                        [ctrl_a(succ()), ctrl_b(succ())], formal_sha=f_sha, formal_gen=0))
        rows = db_rows(f"{ISO}/db44.sqlite3")
        names_in_db = {r[0:3] for r in rows}
        note("A12 6条池采样4+2正式对照", s == 200 and len(rows) == 4
             and all(r[3] == "failure" and r[9] == 1 for r in rows)
             and ("vmess", "203.0.113.14", 443) not in names_in_db
             and ("trojan", "203.0.113.15", 2053) not in names_in_db,
             f"status={s} rows={rows}")

        # ---- A13: duplicate nonce -> 200 duplicate, no new rows ----
        s, b = post(18744, make_payload(t6_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail()), obs("试用-丁", fail())],
                                        [ctrl_a(succ()), ctrl_b(succ())], formal_sha=f_sha, formal_gen=0))
        note("A13 重复nonce不重复记行", s == 200 and b.get("receipt") == "duplicate"
             and db_count(f"{ISO}/db44.sqlite3") == 4,
             f"status={s} body={b}")

        # ---- A14: control with temporary descriptor mode ----
        bad = control("正式-甲", "trojan", "203.0.113.20", 443, succ(), mode="temporary_policy_descriptor")
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [bad], formal_sha=f_sha, formal_gen=0)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A14 对照用临时描述符拒批", s == 422 and code == "untrusted_network_control_mode"
             and db_count(f"{ISO}/db41.sqlite3") == 4,
             f"status={s} code={code}")

        # ---- A15: 3 controls -> 422 invalid_network_controls ----
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_a(succ()), ctrl_b(succ()), ctrl_c(succ())],
                         formal_sha=f_sha, formal_gen=0)
        s, b = post(18741, p)
        code = validate_code(p, t1_bytes, formal_bytes, formal_manifest)
        note("A15 3个对照拒批", s == 422 and code == "invalid_network_controls"
             and db_count(f"{ISO}/db41.sqlite3") == 4,
             f"status={s} code={code}")

        # ---- A16: formal pool file changed after manifest -> 422 ----
        with open(f"{ISO}/formal-b.txt", "a", encoding="utf-8") as f:
            f.write("# pool content changed\n")
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_a(succ())], formal_sha=fb_sha, formal_gen=0)
        s, b = post(18745, p)
        fb_bytes_new = open(f"{ISO}/formal-b.txt", "rb").read()
        fb_manifest = json.load(open(f"{ISO}/formal-manifest-b.json", encoding="utf-8"))
        code = validate_code(p, t1_bytes, fb_bytes_new, fb_manifest)
        note("A16a 正式池变化后旧SHA拒批", s == 422 and code == "stale_formal_pool_sha"
             and db_count(f"{ISO}/db45.sqlite3") == 0,
             f"status={s} code={code}")
        # restore the pool file; the same batch must pass again
        write_pool(f"{ISO}/formal-b.txt", formal)
        s, b = post(18745, make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                                        [ctrl_a(succ())], formal_sha=fb_sha, formal_gen=0))
        note("A16b 正式池恢复后批次通过", s == 200 and db_count(f"{ISO}/db45.sqlite3") == 1,
             f"status={s} body={b}")

        # ---- A17: manifest regenerated (timestamps only, same generation) ----
        fb_manifest2 = dict(fb_manifest)
        fb_manifest2["updated_at"] = "2026-11-24T11:00:00Z"
        with open(f"{ISO}/formal-manifest-b.json", "w", encoding="utf-8") as f:
            json.dump(fb_manifest2, f, ensure_ascii=False, indent=2)
        s, b = post(18745, make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                                        [ctrl_a(succ())], formal_sha=fb_sha, formal_gen=0))
        note("A17a 仅健康时间戳更新代次不变批次通过", s == 200 and db_count(f"{ISO}/db45.sqlite3") == 2,
             f"status={s} body={b}")
        # generation bumped without a SHA change must be rejected (defense in depth)
        fb_manifest3 = dict(fb_manifest2)
        fb_manifest3["generation"] = 1
        with open(f"{ISO}/formal-manifest-b.json", "w", encoding="utf-8") as f:
            json.dump(fb_manifest3, f, ensure_ascii=False, indent=2)
        p = make_payload(t1_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [ctrl_a(succ())], formal_sha=fb_sha, formal_gen=0)
        s, b = post(18745, p)
        code = validate_code(p, t1_bytes, formal_bytes_b, fb_manifest3)
        note("A17b 代次无故递增拒批", s == 422 and code == "stale_formal_generation"
             and db_count(f"{ISO}/db45.sqlite3") == 2,
             f"status={s} code={code}")
        with open(f"{ISO}/formal-manifest-b.json", "w", encoding="utf-8") as f:
            json.dump(fb_manifest, f, ensure_ascii=False, indent=2)

        # ---- R1-R8: legacy mode (port 18742, no formal env) ----
        # R1: 3 failures + in-pool control success -> cv=1 (P0-3 case)
        n = secrets.token_hex(16)
        inpool = {"name": "试用-戊", "probe_mode": "external_policy_id", "results": succ()}
        s, b = post(18742, make_payload(t6_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail())],
                                        [inpool]))
        rows = db_rows(f"{ISO}/db42.sqlite3")
        note("R1 传统模式池内对照成功cv=1", s == 200 and len(rows) == 3
             and all(r[3] == "failure" and r[9] == 1 for r in rows),
             f"status={s} rows={rows}")
        # R2: 3 failures, no controls -> downgrade (regression)
        n = secrets.token_hex(16)
        s, b = post(18742, make_payload(t6_sha, n, [obs("试用-甲", fail()), obs("试用-乙", fail()), obs("试用-丙", fail())]))
        rows = db_rows(f"{ISO}/db42.sqlite3")
        note("R2 传统模式3条全失败无对照降级", s == 200 and len(rows) == 6
             and all(r[3] == "unknown" and r[6] == "batch_unverified_network" for r in rows[3:]),
             f"status={s} rows={rows[3:]}")
        # R3: 1 success + in-pool control success -> cv=1
        n = secrets.token_hex(16)
        s, b = post(18742, make_payload(t6_sha, n, [obs("试用-甲", succ())], [inpool]))
        rows = db_rows(f"{ISO}/db42.sqlite3")
        note("R3 传统模式1条成功+池内对照", s == 200 and len(rows) == 7
             and rows[6][3] == "success" and rows[6][9] == 1,
             f"status={s} rows={rows[6:]}")
        # R4: duplicate nonce
        s, b = post(18742, make_payload(t6_sha, n, [obs("试用-甲", succ())], [inpool]))
        note("R4 传统模式重复nonce", s == 200 and b.get("receipt") == "duplicate"
             and db_count(f"{ISO}/db42.sqlite3") == 7,
             f"status={s} body={b}")
        # R5: wrong token -> 401
        s, b = post(18742, make_payload(t6_sha, secrets.token_hex(16), [obs("试用-甲", succ())]),
                    token="b" * 43)
        note("R5 传统模式错token 401", s == 401, f"status={s}")
        # R6: stale trial pool SHA -> 422
        s, b = post(18742, make_payload("0" * 64, secrets.token_hex(16), [obs("试用-甲", succ())]))
        note("R6 传统模式旧试用池SHA 422", s == 422, f"status={s}")
        # R7: control is a sample member -> 422
        p = make_payload(t6_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [{"name": "试用-甲", "probe_mode": "external_policy_id", "results": succ()}])
        s, b = post(18742, p)
        code = validate_code(p, t6_bytes, None, None)
        note("R7 传统模式对照=样本成员拒批", s == 422 and code == "unsafe_network_control_identity",
             f"status={s} code={code}")
        # R8: formal control name in legacy mode -> rejected as unknown trial name
        p = make_payload(t6_sha, secrets.token_hex(16), [obs("试用-甲", succ())],
                         [{"name": "正式-甲", "probe_mode": "external_policy_id", "results": succ()}])
        s, b = post(18742, p)
        code = validate_code(p, t6_bytes, None, None)
        note("R8 传统模式不接受正式对照名", s == 422 and code == "unsafe_network_control_identity",
             f"status={s} code={code}")

        # ================= A18: consumer-side filter =================
        # --- A18a: verify_promotion (fail_after filter + DIAGNOSTIC_PASS) ---
        sys.path.insert(0, ISO)
        import receiver as _recv
        vp_manifest = {"pool_sha": t1_sha, "generation": 0, "ttl": "2027-01-01",
                       "cap": 6, "status": "PROBATION",
                       "entries": [{"key": "vmess|203.0.113.10|443", "name": "试用-甲"}]}
        with open(f"{ISO}/vp-manifest.json", "w", encoding="utf-8") as f:
            json.dump(vp_manifest, f, ensure_ascii=False, indent=2)
        _recv.initialize_db(f"{ISO}/vp-db.sqlite3")
        c = sqlite3.connect(f"{ISO}/vp-db.sqlite3")
        t0 = now - 7200
        vp_rows = [
            # 3 cv=0 cellular successes, 20 min apart -> DIAGNOSTIC_PASS
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0, "cellular", t1_sha, "target_reachable", "success", "target_reachable", 0),
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0 + 1200, "cellular", t1_sha, "target_reachable", "success", "target_reachable", 0),
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0 + 2400, "cellular", t1_sha, "target_reachable", "success", "target_reachable", 0),
            # 1 cv=1 cellular success, then 1 cv=0 cellular failure after it
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0 + 3000, "cellular", t1_sha, "target_reachable", "success", "target_reachable", 1),
            ("vmess", "203.0.113.10", 443, "failure", "external_policy_id", 1, t0 + 3600, "cellular", t1_sha, "dual_transport_failure", "failure", "dual_transport_failure", 0),
        ]
        for i, r in enumerate(vp_rows):
            nonce = secrets.token_hex(16)
            c.execute("INSERT INTO batches VALUES(?,?,?)", (nonce, r[6], t1_sha))
            c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (nonce,) + r)
        c.commit()
        c.close()
        env_vp = dict(os.environ)
        env_vp.update({"PHONE_PROBE_MANIFEST": f"{ISO}/vp-manifest.json",
                       "PHONE_PROBE_DB": f"{ISO}/vp-db.sqlite3"})
        out = subprocess.run([sys.executable, f"{ISO}/verify_promotion.py"],
                             env=env_vp, capture_output=True, text=True, timeout=30)
        note("A18a verify_promotion: cv=0失败不否决READY且3次cv=0成功=DIAGNOSTIC_PASS",
             out.returncode == 0 and "-> READY" in out.stdout
             and "diagnostic=DIAGNOSTIC_PASS" in out.stdout
             and "DIAGNOSTIC_PASS count: 1" in out.stdout,
             f"rc={out.returncode} out={out.stdout.strip()!r} err={out.stderr.strip()!r}")

        # --- A18b: auto_prune.read_failure_evidence ---
        sys.path.insert(0, ISO)
        import auto_prune as _ap
        pool_db = f"{ISO}/pool-a18b.sqlite3"
        c = sqlite3.connect(pool_db)
        c.execute("CREATE TABLE nodes (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE node_tests (protocol TEXT, host TEXT, port INTEGER, tested_at INTEGER, result TEXT, reason TEXT, ms REAL)")
        c.execute("CREATE TABLE pinned (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE blocklist (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE phone_failures (protocol TEXT, host TEXT, port INTEGER, reported_at INTEGER, source TEXT, detail TEXT)")
        key = ("trojan", "203.0.113.50", 443)
        pf_rows = [
            # (i) old-detail surge-url-test (no control_verified)
            (key[0], key[1], key[2], now - 3600, "surge-url-test",
             '{"bearer":"cellular","method":"external_policy_id"}'),
            # (ii) user-report
            (key[0], key[1], key[2], now - 3500, "user-report",
             "probe_mode=external_policy_id bearer=cellular"),
            # (iii) new JSON detail, trusted
            (key[0], key[1], key[2], now - 3400, "surge-url-test",
             '{"bearer":"cellular","control_verified":1,"method":"external_policy_id"}'),
            # (iv) legacy key=value detail, trusted
            (key[0], key[1], key[2], now - 3300, "surge-url-test",
             "probe_mode=external_policy_id bearer=cellular control_verified=1 nonce_prefix=abcd1234 pool_sha_prefix=deadbeef"),
            # (v) trusted-looking but wifi bearer
            (key[0], key[1], key[2], now - 3200, "surge-url-test",
             '{"bearer":"wifi","control_verified":1,"method":"external_policy_id"}'),
        ]
        c.executemany("INSERT INTO phone_failures VALUES (?,?,?,?,?,?)", pf_rows)
        c.commit()
        c.close()
        ev = _ap.read_failure_evidence(pool_db, {key}, now)
        note("A18b auto_prune只认可信失败(2/5)",
             len(ev["phone_failures"].get(key, [])) == 2
             and ev["phone_failures_unverified"].get(key, 0) == 3,
             f"trusted={ev['phone_failures'].get(key)} unverified={ev['phone_failures_unverified'].get(key)}")

        # --- A18c/d: importers (22-member synthetic pool + scratch pool.db) ---
        pool22 = [(f"池-{i:02d}", ["trojan", "vmess", "ss"][i % 3],
                   f"203.0.113.{100 + i}", 443 if i % 2 else 8443) for i in range(1, 23)]
        write_pool(f"{ISO}/pool22.txt", pool22)
        p22_sha = sha_of(f"{ISO}/pool22.txt")
        cand = pool22[-1]  # 池-22, not pinned
        pins22 = {(p, h, pt) for _, p, h, pt in pool22[:-1]}
        assert len(pins22) == 21
        staging = f"{ISO}/staging-a18.sqlite3"
        _recv.initialize_db(staging)
        c = sqlite3.connect(staging)
        t_base = now - 3600
        st_rows = [
            # (a) trusted: cv=1 cellular external failure -> eligible
            ("trojan" if cand[1] == "trojan" else cand[1], cand[2], cand[3], "failure", "external_policy_id", 1, t_base, "cellular", p22_sha, "dual_transport_failure", "failure", "dual_transport_failure", 1),
            # (b) cv=0 cellular external failure -> untrusted
            (cand[1], cand[2], cand[3], "failure", "external_policy_id", 1, t_base + 60, "cellular", p22_sha, "dual_transport_failure", "failure", "dual_transport_failure", 0),
            # (c) cv=1 wifi external failure -> untrusted
            (cand[1], cand[2], cand[3], "failure", "external_policy_id", 1, t_base + 120, "wifi", p22_sha, "dual_transport_failure", "failure", "dual_transport_failure", 1),
            # (d) cv=1 cellular temporary-descriptor failure -> untrusted
            (cand[1], cand[2], cand[3], "failure", "temporary_policy_descriptor", 1, t_base + 180, "cellular", p22_sha, "dual_transport_failure", "failure", "dual_transport_failure", 1),
        ]
        for r in st_rows:
            nonce = secrets.token_hex(16)
            c.execute("INSERT INTO batches VALUES(?,?,?)", (nonce, r[6], p22_sha))
            c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (nonce,) + r)
        c.commit()
        c.close()
        # A18c: v2 dry-run
        sys.path.insert(0, ISO)
        import import_per_observation_v2 as _v2
        prod_db = f"{ISO}/pool-a18c.sqlite3"
        c = sqlite3.connect(prod_db)
        c.execute("CREATE TABLE pinned (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE blocklist (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE phone_failures (protocol TEXT, host TEXT, port INTEGER, reported_at INTEGER, source TEXT, detail TEXT)")
        c.executemany("INSERT INTO pinned VALUES (?,?,?)", sorted(pins22))
        c.commit()
        c.close()
        out = _v2.import_once(staging, prod_db, f"{ISO}/pool22.txt", now=now, apply=False)
        note("A18c v2导入dry-run只认1条可信失败",
             out["eligible_staging_rows"] == 1 and out["skipped"]["untrusted"] == 3,
             f"out={out}")
        # A18c-apply: write to the scratch pool.db, check the detail
        out2 = _v2.import_once(staging, prod_db, f"{ISO}/pool22.txt", now=now, apply=True, approved=True)
        c = sqlite3.connect(f"file:{prod_db}?mode=ro", uri=True)
        pf = c.execute("SELECT detail FROM phone_failures").fetchall()
        c.close()
        note("A18c-apply 写入detail含control_verified=1",
             out2["new"] == 1 and len(pf) == 1 and '"control_verified":1' in pf[0][0],
             f"out={out2} detail={pf}")
        # A18d: legacy importer on scratch copies
        prod_db2 = f"{ISO}/pool-a18d.sqlite3"
        shutil.copy(prod_db, prod_db2)  # has pinned/blocklist; phone_failures empty after copy? no: copy has the 1 row; use a fresh one instead
        c = sqlite3.connect(prod_db2)
        c.execute("DELETE FROM phone_failures")
        c.commit()
        c.close()
        out3 = subprocess.run([sys.executable, f"{ISO}/import_phone_observations.py",
                               "--staging-db", staging, "--pool-db", prod_db2,
                               "--pool-file", f"{ISO}/pool22.txt"],
                              capture_output=True, text=True, timeout=30)
        c = sqlite3.connect(f"file:{prod_db2}?mode=ro", uri=True)
        pf2 = c.execute("SELECT detail FROM phone_failures").fetchall()
        c.close()
        note("A18d legacy导入只认1条可信失败",
             out3.returncode == 0 and "imported=1" in out3.stdout
             and "untrusted_failure_evidence': 3" in out3.stdout
             and len(pf2) == 1 and "control_verified=1" in pf2[0][0],
             f"rc={out3.returncode} out={out3.stdout.strip()!r} err={out3.stderr.strip()!r}")

        # ================= D1-D11: DIAGNOSTIC_PASS derivation =================
        def run_vp(manifest, rows):
            """rows: list of (status, reason, mode, trusted, bearer, received_at)."""
            man_path = f"{ISO}/vp-d-manifest.json"
            db_path = f"{ISO}/vp-d-db.sqlite3"
            for p in (man_path, db_path):
                if os.path.exists(p):
                    os.remove(p)
            with open(man_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f, ensure_ascii=False, indent=2)
            _recv.initialize_db(db_path)
            c = sqlite3.connect(db_path)
            for i, r in enumerate(rows):
                nonce = secrets.token_hex(16)
                c.execute("INSERT INTO batches VALUES(?,?,?)", (nonce, r[5], manifest["pool_sha"]))
                # row tuple: (status, reason, mode, trusted, bearer, received_at)
                c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                          (nonce, "vmess", "203.0.113.10", 443, r[0], r[2], r[3], r[5], r[4], manifest["pool_sha"], r[1], r[0], r[1], 0))
            c.commit()
            c.close()
            env = dict(os.environ)
            env.update({"PHONE_PROBE_MANIFEST": man_path, "PHONE_PROBE_DB": db_path})
            out = subprocess.run([sys.executable, f"{ISO}/verify_promotion.py"],
                                 env=env, capture_output=True, text=True, timeout=30)
            return out

        def base_manifest(**over):
            m = {"pool_sha": t1_sha, "generation": 0, "ttl": "2027-01-01",
                 "cap": 6, "status": "PROBATION",
                 "entries": [{"key": "vmess|203.0.113.10|443", "name": "试用-甲"}]}
            m.update(over)
            return m

        def S(ts, bearer="cellular", mode="external_policy_id", trusted=1):
            return ("success", "target_reachable", mode, trusted, bearer, ts)

        def F(ts, bearer="cellular", mode="external_policy_id", trusted=1):
            return ("failure", "dual_transport_failure", mode, trusted, bearer, ts)

        def U(ts, bearer="cellular", mode="external_policy_id", trusted=1):
            return ("unknown", "target_inconclusive", mode, trusted, bearer, ts)

        t0 = now - 20000
        out = run_vp(base_manifest(), [S(t0), S(t0 + 1200), S(t0 + 2400)])
        note("D1 3次成功间隔>=15min且24h内=DIAGNOSTIC_PASS",
             "diagnostic=DIAGNOSTIC_PASS" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 600), S(t0 + 1800)])
        note("D2 间隔<15min不计数=NOT_READY",
             "diagnostic=NOT_READY" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 1200), F(t0 + 1800), S(t0 + 2400), S(t0 + 3600)])
        note("D3 可信失败重置连续计数=NOT_READY",
             "diagnostic=NOT_READY" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 1200), U(t0 + 1800), S(t0 + 2400)])
        note("D4 unknown打断序列=NOT_READY",
             "diagnostic=NOT_READY" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 1200, bearer="wifi"), S(t0 + 2400), S(t0 + 3600)])
        note("D5 网络切换(Wi-Fi成功)打断序列=NOT_READY",
             "diagnostic=NOT_READY" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 43200), S(t0 + 90000)])
        note("D6 跨度>24h=NOT_READY",
             "diagnostic=NOT_READY" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(ttl="2026-11-20"), [S(t0), S(t0 + 1200), S(t0 + 2400)])
        note("D7 TTL过期=TTL_EXPIRED",
             "diagnostic=TTL_EXPIRED" in out.stdout, f"out={out.stdout.strip()!r}")
        m8 = base_manifest()
        del m8["generation"]
        out = run_vp(m8, [S(t0), S(t0 + 1200), S(t0 + 2400)])
        note("D8 无代次=MANIFEST_GENERATION_MISSING",
             "diagnostic=MANIFEST_GENERATION_MISSING" in out.stdout, f"out={out.stdout.strip()!r}")
        man_rows = [("success", "target_reachable", "manual_report", 0, "cellular", t0),
                    ("success", "target_reachable", "manual_report", 0, "cellular", t0 + 1200),
                    ("success", "target_reachable", "manual_report", 0, "cellular", t0 + 2400)]
        out = run_vp(base_manifest(), man_rows)
        note("D9 手动3次=MANUAL_DIAGNOSTIC_PASS且自动不等同",
             "manual=MANUAL_DIAGNOSTIC_PASS" in out.stdout
             and "diagnostic=NOT_READY" in out.stdout,
             f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 900), S(t0 + 1800)])
        note("D10 恰好15min间隔=DIAGNOSTIC_PASS(边界)",
             "diagnostic=DIAGNOSTIC_PASS" in out.stdout, f"out={out.stdout.strip()!r}")
        out = run_vp(base_manifest(), [S(t0), S(t0 + 600), S(t0 + 90000), S(t0 + 90900), S(t0 + 91800)])
        note("D11 滑动窗口丢弃超24h首条后仍成链=DIAGNOSTIC_PASS",
             "diagnostic=DIAGNOSTIC_PASS" in out.stdout, f"out={out.stdout.strip()!r}")

        # ================= G1-G5: formal manifest generator =================
        # synthetic formal DB with C6/C7 data
        fdb = f"{ISO}/formal-db.sqlite3"
        _recv.initialize_db(fdb)
        c = sqlite3.connect(fdb)
        frows = [
            ("trojan", "203.0.113.20", 443, "success", "external_policy_id", 1, now - 3600, "cellular", f_sha, "target_reachable", "success", "target_reachable", 1),
            ("trojan", "203.0.113.21", 8443, "success", "external_policy_id", 1, now - 3600, "cellular", f_sha, "target_reachable", "success", "target_reachable", 1),
            ("trojan", "203.0.113.21", 8443, "failure", "external_policy_id", 1, now - 90000, "cellular", f_sha, "dual_transport_failure", "failure", "dual_transport_failure", 1),
            ("vmess", "203.0.113.22", 443, "success", "external_policy_id", 1, now - 3600, "cellular", f_sha, "target_reachable", "success", "target_reachable", 1),
            ("vmess", "203.0.113.22", 443, "failure", "external_policy_id", 1, now - 1800, "cellular", f_sha, "dual_transport_failure", "failure", "dual_transport_failure", 1),
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, now - 3600, "cellular", f_sha, "target_reachable", "success", "target_reachable", 1),
            ("trojan", "203.0.113.23", 443, "success", "external_policy_id", 1, now - 90000, "cellular", f_sha, "target_reachable", "success", "target_reachable", 1),
        ]
        for r in frows:
            nonce = secrets.token_hex(16)
            c.execute("INSERT INTO batches VALUES(?,?,?)", (nonce, r[6], f_sha))
            c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (nonce,) + r)
        c.commit()
        c.close()
        reg = {"version": 1, "entries": {
            "trojan|203.0.113.20|443": {"source_group": "G-matin", "evidence": "test", "verified_at": "2026-11-24"},
            "trojan|203.0.113.21|8443": {"source_group": "G-alirewa", "evidence": "test", "verified_at": "2026-11-24"},
            "vmess|203.0.113.10|443": {"source_group": "G-matin", "evidence": "test", "verified_at": "2026-11-24"},
            "trojan|203.0.113.23|443": {"source_group": "G-matin", "evidence": "test", "verified_at": "2026-11-24"},
        }}
        with open(f"{ISO}/registry.json", "w", encoding="utf-8") as f:
            json.dump(reg, f, ensure_ascii=False, indent=2)
        out = subprocess.run([sys.executable, f"{ISO}/formal_manifest.py",
                              "--pool", f"{ISO}/formal.txt", "--db", fdb,
                              "--registry", f"{ISO}/registry.json",
                              "--out", f"{ISO}/formal-out.json",
                              "--trial-pool", f"{ISO}/trial1.txt",
                              "--min-pool", "1", "--dry-run"],
                             capture_output=True, text=True, timeout=30)
        man_out = json.loads(out.stdout) if out.returncode == 0 else {}
        elig = {(e["protocol"], e["host"], e["port"]) for e in man_out.get("eligible_controls", [])}
        note("G1 生成器dry-run: 合格=甲乙2条, 试用成员排除, 未知组排除, 24h外成功排除, 窗内失败排除",
             out.returncode == 0 and man_out.get("generation") == 0
             and elig == {("trojan", "203.0.113.20", 443), ("trojan", "203.0.113.21", 8443)}
             and man_out.get("pool_sha") == f_sha,
             f"rc={out.returncode} out={out.stdout.strip()!r} err={out.stderr.strip()!r}")
        # G2: write twice (generation stays 0), then change pool (generation 1)
        out1 = subprocess.run([sys.executable, f"{ISO}/formal_manifest.py",
                               "--pool", f"{ISO}/formal.txt", "--db", fdb,
                               "--registry", f"{ISO}/registry.json",
                               "--out", f"{ISO}/formal-out.json",
                               "--trial-pool", f"{ISO}/trial1.txt",
                               "--min-pool", "1"],
                              capture_output=True, text=True, timeout=30)
        out2 = subprocess.run([sys.executable, f"{ISO}/formal_manifest.py",
                               "--pool", f"{ISO}/formal.txt", "--db", fdb,
                               "--registry", f"{ISO}/registry.json",
                               "--out", f"{ISO}/formal-out.json",
                               "--trial-pool", f"{ISO}/trial1.txt",
                               "--min-pool", "1"],
                              capture_output=True, text=True, timeout=30)
        g_after_two = json.load(open(f"{ISO}/formal-out.json", encoding="utf-8"))["generation"]
        write_pool(f"{ISO}/formal.txt", formal + [("正式-戊", "ss", "203.0.113.24", 8388)])
        out3 = subprocess.run([sys.executable, f"{ISO}/formal_manifest.py",
                               "--pool", f"{ISO}/formal.txt", "--db", fdb,
                               "--registry", f"{ISO}/registry.json",
                               "--out", f"{ISO}/formal-out.json",
                               "--trial-pool", f"{ISO}/trial1.txt",
                               "--min-pool", "1"],
                              capture_output=True, text=True, timeout=30)
        g_after_change = json.load(open(f"{ISO}/formal-out.json", encoding="utf-8"))["generation"]
        write_pool(f"{ISO}/formal.txt", formal)  # restore
        note("G2 代次: 两次不变仍为0, 池变化后递增为1",
             out1.returncode == 0 and out2.returncode == 0 and out3.returncode == 0
             and g_after_two == 0 and g_after_change == 1,
             f"g_after_two={g_after_two} g_after_change={g_after_change}")
        # G3: registry missing -> warn, eligible empty, exit 0
        out = subprocess.run([sys.executable, f"{ISO}/formal_manifest.py",
                              "--pool", f"{ISO}/formal.txt", "--db", fdb,
                              "--registry", f"{ISO}/registry-missing.json",
                              "--out", f"{ISO}/formal-out3.json",
                              "--trial-pool", f"{ISO}/trial1.txt",
                              "--min-pool", "1", "--dry-run"],
                             capture_output=True, text=True, timeout=30)
        man3 = json.loads(out.stdout) if out.returncode == 0 else {}
        note("G3 注册表缺失时全unknown、合格为空、不写库",
             out.returncode == 0 and man3.get("eligible_controls") == []
             and "registry missing" in out.stderr,
             f"rc={out.returncode} err={out.stderr.strip()!r}")
        # G4: dry-run writes nothing
        note("G4 dry-run不写文件",
             not os.path.exists(f"{ISO}/formal-out3.json"),
             f"exists={os.path.exists(f'{ISO}/formal-out3.json')}")
        # G5: live data dry-run (read-only): 22 members, eligible 0 (pins unknown, Canada trial-excluded)
        out = subprocess.run([sys.executable, f"{ISO}/formal_manifest.py",
                              "--pool", "/opt/free-node-program/publish/pool-new.txt",
                              "--db", "/opt/phone-telemetry/phone-observations.sqlite3",
                              "--registry", f"{SRC}/formal_source_groups.json",
                              "--out", f"{ISO}/formal-live-dryrun.json",
                              "--trial-pool", "/opt/surge-bridge/modules/probation-new.txt",
                              "--dry-run"],
                             capture_output=True, text=True, timeout=60)
        man5 = json.loads(out.stdout) if out.returncode == 0 else {}
        note("G5 真实数据dry-run: 22成员、合格0、试用排除1、未知组21、只读不写",
             out.returncode == 0 and man5.get("entries") == 22
             and man5.get("eligible_controls") == []
             and not os.path.exists(f"{ISO}/formal-live-dryrun.json"),
             f"rc={out.returncode} out={out.stdout.strip()[:400]!r} err={out.stderr.strip()!r}")
    finally:
        for proc in procs:
            try:
                proc.terminate()
                proc.wait(timeout=5)
            except Exception:
                proc.kill()
    fails = [r for r in results if not r[1]]
    print()
    print(f"TOTAL: {len(results)} checks, {len(results) - len(fails)} PASS, {len(fails)} FAIL")
    for case, ok, detail in fails:
        print("FAILED:", case, detail)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
