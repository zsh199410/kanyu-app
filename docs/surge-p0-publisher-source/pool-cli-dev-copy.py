"""CLI：crawl / test / publish / serve / import-pinned / status / rollback / retest-one。

所有输出只含计数与状态，绝不输出 URI、密码、UUID、密钥、完整行。
"""

import argparse
import json
import logging
import os
import sys
import time

from . import db as dbmod
from .crawler import crawl_all, crawl_records, parse_record, parse_surge_line
from .geo import IpApi, hint_to_code
from .publish import atomic_publish, read_publish_lines, rollback, self_check
from .rules import (build_surge_line, is_private, load_private_hosts,
                    pre_filter, select_publish)
from .tester import test_many, test_one

PUBLISH_FILENAME = "pool-new.txt"
TEST_URL_NOTE = "generate_204"


def base_dir():
    if os.path.exists("/opt/free-node-program/config.yaml"):
        return "/opt/free-node-program"
    return os.getcwd()


def setup_logging(base):
    os.makedirs(os.path.join(base, "logs"), exist_ok=True)
    # 日志只写文件，不写 stdout：stdout 留给 JSON 结果（计数），保持机器可读。
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[
            logging.FileHandler(os.path.join(base, "logs", "pool.log")),
        ],
    )
    return logging.getLogger("pool")


def load_yaml_simple(path):
    out = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or ":" not in line:
                    continue
                k, v = line.split(":", 1)
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if v.startswith("[") and v.endswith("]"):
                    out[k] = [x.strip() for x in v[1:-1].split(",") if x.strip()]
                else:
                    try:
                        out[k] = int(v)
                    except ValueError:
                        try:
                            out[k] = float(v)
                        except ValueError:
                            if v.lower() in ("true", "false"):
                                out[k] = v.lower() == "true"
                            else:
                                out[k] = v
    except OSError:
        pass
    return out


def read_pinned_lines(base):
    """返回 [(name, proto, host, port, line_text)]（原文，仅内存）；密码不进日志。"""
    for cand in ("/opt/surge-bridge/pinned-nodes.txt",
                 os.path.join(base, "pinned-nodes.txt")):
        if os.path.exists(cand):
            out = []
            with open(cand) as f:
                for line in f:
                    line = line.rstrip("\n")
                    if not line.strip():
                        continue
                    name, proto, host, port, ok = parse_surge_line(line)
                    if ok:
                        out.append((name, proto, host, port, line))
            return out
    return []


def surge_line_to_record(line, source="pinned-or-publish"):
    """把 Surge 代理行转回可测试记录（仅内存，用于单节点复测）。"""
    name, proto, host, port, ok = parse_surge_line(line)
    if not ok:
        return None
    parts = [p.strip() for p in line.split(" = ", 1)[1].split(",")]
    params = {}
    for p in parts[3:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip().lower()] = v.strip()
    if proto == "trojan":
        ws_headers = params.get("ws-headers", "")
        ws_host = None
        for h in ws_headers.split("|"):
            if h.strip().lower().startswith("host:"):
                ws_host = h.split(":", 1)[1].strip()
        return {"protocol": "trojan", "host": host, "port": port, "source": source,
                "name_hint": name, "password": params.get("password", ""),
                "t_type": "ws" if params.get("ws", "").lower() == "true" else "tcp",
                "sni": params.get("sni"), "ws": params.get("ws", "").lower() == "true",
                "ws_path": params.get("ws-path") or "/",
                "ws_host": ws_host,
                "skip_verify": params.get("skip-cert-verify", "").lower() == "true"}
    if proto == "vmess":
        ws_headers = params.get("ws-headers", "")
        ws_host = None
        for h in ws_headers.split("|"):
            if h.strip().lower().startswith("host:"):
                ws_host = h.split(":", 1)[1].strip()
        return {"protocol": "vmess", "host": host, "port": port, "source": source,
                "name_hint": name, "uuid": params.get("username", ""),
                "security": "auto", "net": "ws" if params.get("ws", "").lower() == "true" else "tcp",
                "tls": params.get("tls", "").lower() == "true",
                "ws_path": params.get("ws-path") or "/",
                "ws_host": ws_host, "sni": params.get("sni"),
                "skip_verify": params.get("skip-cert-verify", "").lower() == "true"}
    if proto == "ss":
        return {"protocol": "ss", "host": host, "port": port, "source": source,
                "name_hint": name, "method": params.get("encrypt-method", ""),
                "password": params.get("password", ""), "plugin": None}
    return None


def cmd_crawl(args, base, log):
    started = int(time.time())
    if args.dry_run:
        counts = crawl_all(os.path.join(base, "sources.yaml"))
        print(json.dumps(counts, ensure_ascii=False, indent=2))
        return 0
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    disabled = set(dbmod.get_config(conn, "disabled_sources", []) or [])
    # 禁用源在抓取前排除：不发请求、不计入 sources_ok/total、不进库存。
    records, counts = crawl_records(os.path.join(base, "sources.yaml"), skip=disabled)
    for rec in records:
        dbmod.upsert_node(conn, rec["protocol"], rec["host"], rec["port"],
                          rec["source"], rec.get("name_hint") or "")
    for s in counts.get("by_source", {}):
        sc = counts["by_source"][s]
        ok_inc = 1 if sc["status"] == "ok" else 0
        fail_inc = 0 if sc["status"] == "ok" else 1
        conn.execute(
            """INSERT INTO sources (name, last_success, last_count, ok_count, fail_count)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT (name) DO UPDATE SET
                 last_success=excluded.last_success, last_count=excluded.last_count,
                 ok_count=ok_count+?, fail_count=fail_count+?""",
            (s, started if sc["status"] == "ok" else None, sc.get("total", 0),
             ok_inc, fail_inc, ok_inc, fail_inc))
    dbmod.log_run(conn, "crawl", started, counts)
    conn.commit()
    log.info("crawl done sources_ok=%s total=%s unique=%s",
             counts["sources_ok"], counts["total"], counts["unique"])
    print(json.dumps(counts, ensure_ascii=False, indent=2))
    return 0


def _fresh_records(base, skip=None):
    records, counts = crawl_records(os.path.join(base, "sources.yaml"), skip=skip)
    return records, counts


def cmd_test(args, base, log):
    started = int(time.time())
    cfg = load_yaml_simple(os.path.join(base, "config.yaml"))
    private = load_private_hosts(os.path.join(base, "private-hosts.txt"))
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    disabled = set(dbmod.get_config(conn, "disabled_sources", []) or [])
    vmess_tls_only = dbmod.get_config(conn, "vmess_tls_only", True)
    if vmess_tls_only is None:
        vmess_tls_only = True
    records, crawl_counts = _fresh_records(base, skip=disabled)
    # 预过滤（不计入失败）：私有、非 TLS VMess（若开关开）、方法、插件、传输、坏密码。
    kept = []
    filtered = {}
    for rec in records:
        if rec["source"] in disabled:
            filtered["source-disabled"] = filtered.get("source-disabled", 0) + 1
            continue
        ok, reason = pre_filter(rec, private)
        if rec["protocol"] == "vmess" and not rec.get("tls") and not vmess_tls_only:
            ok, reason = True, ""
        if not ok:
            filtered[reason] = filtered.get(reason, 0) + 1
            continue
        kept.append(rec)
    # 测试集
    old_lines = read_publish_lines(os.path.join(base, "publish"), PUBLISH_FILENAME)
    old_keys = set()
    for line in old_lines:
        _n, p, h, po, ok = parse_surge_line(line)
        if ok:
            old_keys.add((p, h, po))
    if args.mode == "full":
        test_set = kept
    elif args.mode == "bootstrap":
        # 按源轮询取样，分散来源，避免一家独大。
        by_source = {}
        for rec in kept:
            by_source.setdefault(rec["source"], []).append(rec)
        test_set = []
        srcs = sorted(by_source)
        idx = 0
        while len(test_set) < args.limit and any(by_source[s] for s in srcs):
            s = srcs[idx % len(srcs)]
            if by_source[s]:
                test_set.append(by_source[s].pop(0))
            idx += 1
    else:  # incremental
        db_keys = {(r[0], r[1], r[2]): (r[3], r[4]) for r in conn.execute(
            "SELECT protocol, host, port, last_result, last_test_at FROM nodes")}
        # fail（节点失败）与 infra（测试器自身失败，未真正测到）都要复活重测。
        failed_keys = {k for k, (res, _t) in db_keys.items() if res in ("fail", "infra")}
        test_set = []
        for rec in kept:
            key = (rec["protocol"], rec["host"], rec["port"])
            if key not in db_keys or key in old_keys or key in failed_keys:
                test_set.append(rec)
        # 已发布节点优先复测（保证池内节点每轮都被验到），再补新节点与失败复活；
        # 上限 800，避免增量失控。
        test_set.sort(key=lambda rec: 0 if (rec["protocol"], rec["host"], rec["port"]) in old_keys else 1)
        if len(test_set) > 800:
            test_set = test_set[:800]
    log.info("test mode=%s set=%s filtered=%s", args.mode, len(test_set), filtered)
    t0 = time.time()
    r1 = test_many(test_set, concurrency=cfg.get("concurrency", 8))
    for rec, result, ms, reason in r1:
        dbmod.record_test(conn, rec["protocol"], rec["host"], rec["port"],
                          result, reason, ms)
    conn.commit()
    passes = [rec for rec, result, _ms, _r in r1 if result == "pass"]
    r1_counts = {}
    for _rec, result, _ms, _r in r1:
        r1_counts[result] = r1_counts.get(result, 0) + 1
    r2_counts = {}
    if passes and args.mode != "full":
        time.sleep(45)
        r2 = test_many(passes, concurrency=cfg.get("concurrency", 8))
        for rec, result, ms, reason in r2:
            dbmod.record_test(conn, rec["protocol"], rec["host"], rec["port"],
                              result, reason, ms)
        conn.commit()
        for _rec, result, _ms, _r in r2:
            r2_counts[result] = r2_counts.get(result, 0) + 1
    elif passes and args.mode == "full":
        # 全量也做两轮复测（仅复测通过者），与增量一致。
        time.sleep(45)
        r2 = test_many(passes, concurrency=cfg.get("concurrency", 8))
        for rec, result, ms, reason in r2:
            dbmod.record_test(conn, rec["protocol"], rec["host"], rec["port"],
                              result, reason, ms)
        conn.commit()
        for _rec, result, _ms, _r in r2:
            r2_counts[result] = r2_counts.get(result, 0) + 1
    dbmod.prune_old(conn)
    counts = {"mode": args.mode, "set": len(test_set), "filtered": filtered,
              "round1": r1_counts, "round2": r2_counts,
              "seconds": round(time.time() - t0, 1)}
    dbmod.log_run(conn, "test", started, counts)
    conn.commit()
    log.info("test done %s", counts)
    print(json.dumps(counts, ensure_ascii=False, indent=2))
    return 0


def cmd_publish(args, base, log):
    started = int(time.time())
    cfg = load_yaml_simple(os.path.join(base, "config.yaml"))
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    per_cap = dbmod.get_config(conn, "per_country_cap", None)
    max_lines = dbmod.get_config(conn, "publish_max_lines", None)
    vmess_tls_only = dbmod.get_config(conn, "vmess_tls_only", True)
    per_cap = int(per_cap) if per_cap is not None else int(cfg.get("per_country_cap", 40))
    max_lines = int(max_lines) if max_lines is not None else int(cfg.get("publish_max_lines", 150))
    private = load_private_hosts(os.path.join(base, "private-hosts.txt"))
    blocked = dbmod.get_blocked(conn)
    pinned_db = {(r[0], r[1], r[2]): r[3] for r in dbmod.get_pinned(conn)}
    pinned_lines = read_pinned_lines(base)
    # 若 DB 钉选为空但文件有钉选（首次导入前），以文件为准补入 DB（仅身份）。
    if not pinned_db and pinned_lines:
        for name, proto, host, port, _text in pinned_lines:
            conn.execute(
                "INSERT OR IGNORE INTO pinned VALUES (?, ?, ?, ?, ?, ?)",
                (proto, host, port, name, started, "import"))
        conn.commit()
        pinned_db = {(r[0], r[1], r[2]): r[3] for r in dbmod.get_pinned(conn)}
    pinned_keys = {(p, h, po) for _n, p, h, po, _t in pinned_lines}
    # 仅 DB 钉选（UI 钉选、尚未进钉选文件）：发布时同样视为钉选，
    # 不得被轮换逻辑覆盖或丢弃；无旧行又无新鲜记录的只记数、不编造。
    db_only_keys = [k for k in pinned_db if k not in pinned_keys and k not in blocked]
    db_only_set = set(db_only_keys)
    old_lines = read_publish_lines(os.path.join(base, "publish"), PUBLISH_FILENAME)
    old_rotation = []  # (name, proto, host, port, line)
    old_rotation_keys = set()
    for line in old_lines:
        name, proto, host, port, ok = parse_surge_line(line)
        if not ok:
            continue
        if (proto, host, port) in pinned_keys:
            continue
        old_rotation.append((name, proto, host, port, line))
        old_rotation_keys.add((proto, host, port))
    # DB 最近一次通过且新鲜（publish_fresh_hours 小时内）的轮换候选。
    fresh_hours = int(cfg.get("publish_fresh_hours", 12))
    cutoff = started - fresh_hours * 3600
    rows = conn.execute(
        """SELECT protocol, host, port, pass_count, test_count, first_seen
           FROM nodes WHERE last_result='pass' AND last_test_at >= ?
           ORDER BY first_seen""",
        (cutoff,)).fetchall()
    db_pass = {}
    for proto, host, port, pc, tc, first_seen in rows:
        rate = (pc / tc) if tc else 1.0
        db_pass[(proto, host, port)] = (rate, first_seen or 0)
    # VPS 侧准入门：最近一次通过的握手延迟须 <= publish_max_vps_ms，
    # 且终身通过率须 >= publish_min_pass_rate；延迟只取 node_tests，不编造。
    max_vps_ms = float(cfg.get("publish_max_vps_ms", 300))
    min_rate = float(cfg.get("publish_min_pass_rate", 0.5))
    gated = {}
    for key, (rate, first_seen) in db_pass.items():
        if rate < min_rate:
            continue
        row = conn.execute(
            "SELECT ms FROM node_tests WHERE protocol=? AND host=? AND port=? "
            "AND result='pass' ORDER BY tested_at DESC LIMIT 1", key).fetchone()
        if row is None or row[0] is None or row[0] > max_vps_ms:
            continue
        gated[key] = (rate, first_seen)
    db_pass = gated
    # 新鲜爬取记录（仅内存），用于新建轮换行；禁用源同样排除在外。
    disabled_pub = set(dbmod.get_config(conn, "disabled_sources", []) or [])
    records, _cc = _fresh_records(base, skip=disabled_pub)
    by_key = {}
    for rec in records:
        key = (rec["protocol"], rec["host"], rec["port"])
        if key not in by_key:
            by_key[key] = rec
    # 旧轮换保留：DB 仍通过、新鲜、未拉黑的，原文保留（不改名，防抖动）。
    kept_old = []
    kept_old_names = set()
    country_count = {}
    for name, proto, host, port, line in old_rotation:
        key = (proto, host, port)
        if key in blocked or key in db_only_set or key not in db_pass:
            continue
        kept_old.append((name, proto, host, port, line))
        kept_old_names.add(name)
        code = hint_to_code(name) or "unknown"
        country_count[code] = country_count.get(code, 0) + 1
    # 新轮换：DB 通过、新鲜、未在旧轮换、未钉选、未拉黑、有新鲜记录的。
    new_items = []
    for key, (rate, first_seen) in db_pass.items():
        if key in blocked or key in pinned_keys or key in db_only_set or key in old_rotation_keys:
            continue
        rec = by_key.get(key)
        if rec is None:
            continue
        ok, _reason = pre_filter(rec, private)
        if rec["protocol"] == "vmess" and not rec.get("tls") and not vmess_tls_only:
            ok = True
        if not ok:
            continue
        new_items.append((rec, rate, first_seen))
    ipapi = IpApi()
    pinned_names = [n for n, _p, _h, _po, _t in pinned_lines]
    db_old_names = [n for n, p, h, po, _t in old_rotation if (p, h, po) in db_only_set]
    db_named = [pinned_db[k] for k in db_only_keys if pinned_db.get(k)]
    reserved_names = pinned_names + db_old_names + db_named + sorted(kept_old_names)
    # 新轮换命名时，旧轮换名与钉选名一律保留，避免重名。
    from .rules import assign_names as _assign
    ordered = sorted(new_items, key=lambda x: (-x[1], x[2]))
    named = _assign(ordered, reserved_names, ipapi)
    new_lines = []
    capped = 0
    build_failed = 0
    for rec, name, code in named:
        if len(pinned_lines) + len(kept_old) + len(new_lines) >= max_lines:
            break
        c = code or "unknown"
        if country_count.get(c, 0) >= per_cap:
            capped += 1
            continue
        try:
            line = build_surge_line(rec, name)
        except ValueError:
            build_failed += 1
            continue
        new_lines.append(line)
        country_count[c] = country_count.get(c, 0) + 1
    # 仅 DB 钉选行：旧行原样复用；否则用 DB 名建行；DB 名为空的走命名；
    # 既无旧行又无新鲜记录的只记数、不编造。
    old_map = {(p, h, po): (n, t) for n, p, h, po, t in old_rotation}
    db_pinned_lines = []
    need_name = []
    pinned_uri_missing = 0
    for key in db_only_keys:
        if key in old_map:
            db_pinned_lines.append(old_map[key][1])
            continue
        rec = by_key.get(key)
        if rec is None:
            pinned_uri_missing += 1
            continue
        ok, _r = pre_filter(rec, private)
        if rec["protocol"] == "vmess" and not rec.get("tls") and not vmess_tls_only:
            ok = True
        if not ok:
            pinned_uri_missing += 1
            continue
        disp = pinned_db.get(key) or ""
        if disp:
            try:
                db_pinned_lines.append(build_surge_line(rec, disp))
            except ValueError:
                build_failed += 1
        else:
            need_name.append((rec, 1.0, 0))
    if need_name:
        named_db = _assign(need_name,
                           reserved_names + [n for _r, n, _c in named], ipapi)
        for rec, name, _code in named_db:
            try:
                db_pinned_lines.append(build_surge_line(rec, name))
            except ValueError:
                build_failed += 1
    lines = [t for _n, _p, _h, _po, t in pinned_lines
             if (_p, _h, _po) not in blocked]
    lines += db_pinned_lines
    lines += [t for _n, _p, _h, _po, t in kept_old]
    lines += new_lines
    # Scheme B 胜者清洗（默认关闭）：只动轮换，钉选永不动；信号不足时不剔除。
    wc_enabled_cfg = dbmod.get_config(conn, "winner_clean_enabled", None)
    if wc_enabled_cfg is None:
        wc_enabled_cfg = bool(cfg.get("winner_clean_enabled", False))
    wc_enabled = bool(wc_enabled_cfg)
    try:
        wc_window = int(dbmod.get_config(conn, "winner_clean_window_days", None)
                        or cfg.get("winner_clean_window_days", 7))
    except (TypeError, ValueError):
        wc_window = 7
    try:
        wc_min_days = int(dbmod.get_config(conn, "winner_clean_min_winner_days", None)
                          or cfg.get("winner_clean_min_winner_days", 3))
    except (TypeError, ValueError):
        wc_min_days = 3
    wc_window = min(30, max(1, wc_window))
    wc_min_days = min(7, max(1, wc_min_days))
    # 记录轮换节点首次发布时间（Scheme B 宽限期依据）：只记轮换，钉选不记。
    for _n, _p, _h, _po, _t in kept_old:
        conn.execute("INSERT OR IGNORE INTO published_first VALUES (?,?,?,?)",
                     (_p, _h, _po, started))
    for _t in new_lines:
        _n, _p, _h, _po, _ok = parse_surge_line(_t)
        if _ok:
            conn.execute("INSERT OR IGNORE INTO published_first VALUES (?,?,?,?)",
                         (_p, _h, _po, started))
    conn.commit()
    wc_removed = []
    wc_days = None
    if wc_enabled:
        from .winner_clean import clean_rotation, winner_window
        wnames, wdays = winner_window(conn, started, wc_window)
        wc_days = wdays
        pinned_names_all = set(pinned_db.values())
        pinned_names_all.update(n for n, _p, _h, _po, _t in pinned_lines)
        for t in db_pinned_lines:
            n, _p, _h, _po, ok = parse_surge_line(t)
            if ok and n:
                pinned_names_all.add(n)
        rot_pairs = [(n, t) for n, _p, _h, _po, t in kept_old]
        for t in new_lines:
            n, _p, _h, _po, ok = parse_surge_line(t)
            if ok:
                rot_pairs.append((n, t))
        # 宽限期：发布不足 wc_window 天的轮换节点不参与清洗（给手机一天时间验它）。
        grace_cutoff = started - wc_window * 86400
        eligible = []
        for n, t in rot_pairs:
            _nn, _p, _h, _po, _ok = parse_surge_line(t)
            if not _ok:
                eligible.append((n, t))
                continue
            row = conn.execute(
                "SELECT first_published FROM published_first "
                "WHERE protocol=? AND host=? AND port=?", (_p, _h, _po)).fetchone()
            first_pub = row[0] if row else started
            if first_pub <= grace_cutoff:
                eligible.append((n, t))
        kept_pairs, wc_removed = clean_rotation(
            eligible, pinned_names_all, wnames, wdays, wc_min_days, True)
        kept_set = {n for n, _t in kept_pairs}
        kept_set.update(n for n, _t in rot_pairs
                        if n not in {e_n for e_n, _e_t in eligible})
        kept_old = [x for x in kept_old if x[0] in kept_set]
        new_kept = []
        for t in new_lines:
            n, _p, _h, _po, ok = parse_surge_line(t)
            if ok and n in kept_set:
                new_kept.append(t)
        new_lines = new_kept
        lines = ([t for _n, _p, _h, _po, t in pinned_lines
                  if (_p, _h, _po) not in blocked]
                 + db_pinned_lines
                 + [t for _n, _p, _h, _po, t in kept_old]
                 + new_lines)
        if wc_removed:
            log.info("winner-clean removed=%s names=%s", len(wc_removed), wc_removed)
    # 超上限时，优先 drop 最不稳的旧轮换（按通过率升序）。
    if len(lines) > max_lines:
        keep_pinned = [t for _n, _p, _h, _po, t in pinned_lines
                       if (_p, _h, _po) not in blocked] + db_pinned_lines
        over = len(lines) - max_lines
        kept_sorted = sorted(kept_old,
                             key=lambda x: db_pass.get((x[1], x[2], x[3]), (0, 0))[0])
        drop = { (x[1], x[2], x[3]) for x in kept_sorted[:over] }
        kept_old = [x for x in kept_old if (x[1], x[2], x[3]) not in drop]
        lines = keep_pinned + [t for _n, _p, _h, _po, t in kept_old] + new_lines
        lines = lines[:max_lines]
    ok, err = self_check(lines, private, max_lines)
    counts = {"pinned": len([1 for _n, _p, _h, _po, _t in pinned_lines
                             if (_p, _h, _po) not in blocked]) + len(db_pinned_lines),
              "pinned_db_only": len(db_pinned_lines),
              "pinned_uri_missing": pinned_uri_missing,
              "kept_old": len(kept_old), "new": len(new_lines),
              "total": len(lines), "capped": capped, "build_failed": build_failed,
              "winner_clean_enabled": wc_enabled,
              "winner_clean_removed": len(wc_removed),
              "winner_days": wc_days}
    if not ok:
        dbmod.log_run(conn, "publish", started, counts, ok=False, error=err)
        conn.commit()
        log.error("publish self-check failed: %s", err)
        print(json.dumps({"ok": False, "error": err, **counts}, ensure_ascii=False))
        return 1
    atomic_publish(os.path.join(base, "publish"), PUBLISH_FILENAME, lines)
    # 同步 published_first：离开池子的轮换行清掉首次发布记录，重进重算宽限期。
    final_rot = set()
    for _t in lines:
        _n, _p, _h, _po, _ok = parse_surge_line(_t)
        if _ok and (_p, _h, _po) not in pinned_keys and (_p, _h, _po) not in db_only_set:
            final_rot.add((_p, _h, _po))
    if final_rot:
        _q = ",".join(["(?,?,?)"] * len(final_rot))
        _params = [v for _k in final_rot for v in _k]
        conn.execute(
            "DELETE FROM published_first WHERE (protocol,host,port) NOT IN (%s)" % _q,
            _params)
    else:
        conn.execute("DELETE FROM published_first")
    dbmod.log_run(conn, "publish", started, counts)
    conn.commit()
    log.info("publish done %s", counts)
    print(json.dumps({"ok": True, **counts}, ensure_ascii=False, indent=2))
    return 0


def cmd_import_pinned(args, base, log):
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    lines = read_pinned_lines(base)
    imported = 0
    by_proto = {}
    for name, proto, host, port, _text in lines:
        cur = conn.execute(
            "SELECT 1 FROM pinned WHERE protocol=? AND host=? AND port=?",
            (proto, host, port)).fetchone()
        if cur is None:
            conn.execute(
                "INSERT INTO pinned VALUES (?, ?, ?, ?, ?, ?)",
                (proto, host, port, name, int(time.time()), "import"))
            imported += 1
        by_proto[proto] = by_proto.get(proto, 0) + 1
    conn.commit()
    out = {"pinned_lines": len(lines), "new_imported": imported, "by_protocol": by_proto}
    log.info("import-pinned %s", out)
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def cmd_status(args, base, log):
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    nodes = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
    by_proto = dict(conn.execute(
        "SELECT protocol, COUNT(*) FROM nodes GROUP BY protocol").fetchall())
    by_result = dict(conn.execute(
        "SELECT last_result, COUNT(*) FROM nodes GROUP BY last_result").fetchall())
    pinned = conn.execute("SELECT COUNT(*) FROM pinned").fetchone()[0]
    blocked = conn.execute("SELECT COUNT(*) FROM blocklist").fetchone()[0]
    runs = conn.execute(
        "SELECT kind, started, counts, ok FROM runs ORDER BY started DESC LIMIT 5").fetchall()
    pub_lines = read_publish_lines(os.path.join(base, "publish"), PUBLISH_FILENAME)
    out = {"nodes": nodes, "by_protocol": by_proto, "by_last_result": by_result,
           "pinned": pinned, "blocked": blocked, "publish_lines": len(pub_lines),
           "recent_runs": [{"kind": r[0], "started": r[1], "ok": r[3]} for r in runs]}
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def cmd_rollback(args, base, log):
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    ok, err = rollback(os.path.join(base, "publish"), PUBLISH_FILENAME)
    if ok:
        dbmod.log_audit(conn, "cli", "rollback", {"file": PUBLISH_FILENAME})
    print(json.dumps({"ok": ok, "error": err}, ensure_ascii=False))
    return 0 if ok else 1


def cmd_retest_one(args, base, log):
    conn = dbmod.connect(os.path.join(base, "data", "pool.db"))
    key = (args.protocol, args.host.lower(), args.port)
    rec = None
    records, _cc = _fresh_records(base)
    for r in records:
        if (r["protocol"], r["host"], r["port"]) == key:
            rec = r
            break
    if rec is None:
        for line in [t for _n, _p, _h, _po, t in read_pinned_lines(base)] + \
                read_publish_lines(os.path.join(base, "publish"), PUBLISH_FILENAME):
            cand = surge_line_to_record(line)
            if cand and (cand["protocol"], cand["host"], cand["port"]) == key:
                rec = cand
                break
    if rec is None:
        print(json.dumps({"ok": False, "error": "uri-missing"}, ensure_ascii=False))
        return 1
    result, ms, reason = test_one(rec, 40000 + (hash(key) % 90))
    dbmod.record_test(conn, rec["protocol"], rec["host"], rec["port"], result, reason, ms)
    conn.commit()
    print(json.dumps({"ok": True, "result": result, "ms": round(ms, 1), "reason": reason},
                     ensure_ascii=False))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="pool")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crawl")
    c.add_argument("--dry-run", action="store_true", default=False)
    t = sub.add_parser("test")
    t.add_argument("--mode", choices=["incremental", "full", "bootstrap"],
                   default="incremental")
    t.add_argument("--limit", type=int, default=800)
    t.add_argument("--concurrency", type=int, default=8)
    sub.add_parser("publish")
    sub.add_parser("serve")
    sub.add_parser("import-pinned")
    sub.add_parser("status")
    sub.add_parser("rollback")
    r = sub.add_parser("retest-one")
    r.add_argument("--protocol", required=True)
    r.add_argument("--host", required=True)
    r.add_argument("--port", type=int, required=True)
    a = p.parse_args(argv)
    base = base_dir()
    log = setup_logging(base)
    if a.cmd == "crawl":
        return cmd_crawl(a, base, log)
    if a.cmd == "test":
        return cmd_test(a, base, log)
    if a.cmd == "publish":
        return cmd_publish(a, base, log)
    if a.cmd == "serve":
        from .serve import run_server
        return run_server(base)
    if a.cmd == "import-pinned":
        return cmd_import_pinned(a, base, log)
    if a.cmd == "status":
        return cmd_status(a, base, log)
    if a.cmd == "rollback":
        return cmd_rollback(a, base, log)
    if a.cmd == "retest-one":
        return cmd_retest_one(a, base, log)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
