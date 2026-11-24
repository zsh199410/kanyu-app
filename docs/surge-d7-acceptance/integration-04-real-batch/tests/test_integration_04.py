#!/usr/bin/env python3
"""Integration-04: real batch evidence + unified normalization + phone-evidence label.

Review basis (all COMMENTED, 2026-11-24 13:33-13:34):
  * GPT-6 Review 6034205305 (#127 v2) points 1-3: unified normalization
    contract; latest successful complete crawl batch per source; real
    transaction evidence (no write lock during network I/O).
  * GPT-6 Review 6034204978 (#126 v2) points 1 & 3: PHONE_EVIDENCE_READY
    label (no bare READY verdict); importers actually classify on
    trial_generation.
Explicitly NOT covered here (integration-05): Review 6034205620 (#128
v2) points 1-3 (sqlite_backup full-table digest, in-DB decision record /
outbox, same banlist version from preflight to final publish lock);
Review 6034204978 point 2 (C4 full config-variant + real native
policy-ID binding -- needs B1/G6 unlock); B5 real key config / unit
changes (needs authorisation).

Isolation: every test runs against temp dirs / temp sqlite DBs created
here. No live file is read or written (the live pool.db is never
opened). No network traffic: fetch is stubbed in the cmd_crawl tests,
and the fixture IPs/hostnames below are never connected to
(pre_filter / _filter_reason / build_config are pure functions).
Fixture hosts: TEST-NET addresses (198.51.100.x) for crawl/batch rows;
public host 8.8.8.8 / example.com where pre_filter's is_private check
must pass (TEST-NET is ipaddress-reserved and would be private-host).
No credential, UUID, token, password or subscription URI from any real
system appears here; the HMAC key below is a test-only constant.

Run: python3 tests/test_integration_04.py   (from pr-source/)
Exit 0 iff every check passes.
"""
from __future__ import annotations

import base64
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from pool import batch_state as bs
from pool import crawler, db as dbmod, lineage_adapter as la, normalize, rules, tester
from pool import migrate_batch_state as mbs
from pool import migrate_node_sources as mns
from phone_evidence import classify_failure_detail, classify_row
import import_per_observation_v2 as imp2
import import_phone_observations as imp1

# Test-only HMAC key (never a real key; tests only).
KEY = b"i04-test-key-0123456789abcdef"
NOW = int(time.time())
RESULTS = []


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond), str(detail)))
    print(("PASS " if cond else "FAIL ") + name +
          ("" if cond else " :: " + str(detail)))


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
def trojan_rec(**kw):
    d = {"protocol": "trojan", "host": "8.8.8.8", "port": 443,
         "source": "alirewa-config", "password": "pw", "t_type": "tcp",
         "sni": "example.com", "ws": False, "ws_path": "/",
         "ws_host": None, "skip_verify": False}
    d.update(kw)
    return d


def vmess_rec(**kw):
    d = {"protocol": "vmess", "host": "8.8.8.8", "port": 443,
         "source": "alirewa-config",
         "uuid": "11111111-2222-3333-4444-555555555555", "security": "auto",
         "net": "ws", "tls": True, "ws_path": "/", "ws_host": None,
         "sni": "example.com", "skip_verify": False}
    d.update(kw)
    return d


def ss_rec(**kw):
    d = {"protocol": "ss", "host": "8.8.8.8", "port": 8388,
         "source": "matin-vmess", "method": "aes-128-gcm",
         "password": "pw", "plugin": None}
    d.update(kw)
    return d


def gate(rec):
    return la.admission_gate(rec)


def pf(rec):
    return rules.pre_filter(rec, set())


def tf(rec):
    return tester._filter_reason(rec)


def fresh_base():
    d = Path(tempfile.mkdtemp(prefix="i04-"))
    shutil.copytree(SRC / "pool", d / "pool")
    for f in ("source_groups.json", "formal_source_groups.json"):
        shutil.copy2(SRC / f, d / f)
    return d


def fresh_db(base):
    """pool.db with base schema + v4 lineage tables + i04 batch tables."""
    p = base / "data" / "pool.db"
    p.parent.mkdir(parents=True, exist_ok=True)
    conn = dbmod.connect(str(p))
    # The v4 lineage migration backfills from phone_failures, so the
    # table must exist first (the base schema does not create it; in
    # production the importers create it with this exact DDL).
    conn.execute(
        "CREATE TABLE IF NOT EXISTS phone_failures ("
        "protocol TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL,"
        " reported_at INTEGER NOT NULL, source TEXT NOT NULL,"
        " detail TEXT NOT NULL)")
    conn.commit()
    conn.close()
    rc = mns.main(["migrate_node_sources.py", str(p)])
    assert rc == 0, "lineage migration failed"
    rc = mbs.main([str(p)])
    assert rc == 0, "batch migration failed"
    return p


def batch_conn(base):
    """(conn, started) with lineage + batch schema, recorder in defer mode."""
    dbp = fresh_db(base)
    conn = dbmod.connect(str(dbp))
    started = int(time.time())
    rec = la.build_lineage_recorder(conn, str(base), started, key=KEY, defer=True)
    return conn, rec, started, dbp


def run_collector(base, conn, recorder, started, recs, counts, disabled=(),
                  registry_status=None):
    """Drive a BatchCollector over canned recs; returns (collector, summary)."""
    if registry_status is None:
        registry_status = dict(recorder.registry.status)
    col = bs.BatchCollector(started, lineage=recorder,
                            lineage_reason="")
    for r in recs:
        col.observe(r)
    summary = col.finish(counts, disabled=set(disabled),
                         registry_status=registry_status)
    return col, summary


def qualified(conn, base, source, now, disabled=()):
    """qualified_batch_members with the registry loaded from base."""
    reg, _ = la.load_registry(str(base / "source_groups.json"))
    return bs.qualified_batch_members(
        conn, source, now, disabled=disabled,
        registry_status=dict(reg.status),
        known_sources={s for v in reg.groups.values() for s in v})


def counts_for(source, total=0, unparsed=0, obs_err=0, status="ok"):
    return {"sources_ok": 1 if status == "ok" else 0, "total": total,
            "by_source": {source: {"total": total, "status": status,
                                   "unparsed": unparsed,
                                   "observation_errors": obs_err}}}


# ---------------------------------------------------------------------------
# N: unified normalization contract
# ---------------------------------------------------------------------------
def section_n():
    # N1: transport case / whitespace / unknown / invalid / default agree
    # across gate, pre_filter and tester._filter_reason.
    cases = [
        # (rec, expected reason or None)
        (trojan_rec(t_type="WS"), None),
        (trojan_rec(t_type=" ws "), None),
        (trojan_rec(t_type="grpc"), "unsupported-transport"),
        (trojan_rec(t_type="tcp,udp"), "unsupported-transport"),
        (trojan_rec(t_type=" w s "), "unsupported-transport"),
        (trojan_rec(t_type=""), None),          # default tcp
        (trojan_rec(t_type=None), None),        # default tcp
        (trojan_rec(t_type=123), "unsupported-transport"),
        (vmess_rec(net="WS"), None),
        (vmess_rec(net=" ws "), None),
        (vmess_rec(net="grpc"), "unsupported-transport"),
        (vmess_rec(net="none"), "unsupported-transport"),
        (vmess_rec(net="tcp#frag@junk"), "unsupported-transport"),
        (vmess_rec(net=""), None),
        (vmess_rec(net=None), None),
    ]
    for i, (rec, want) in enumerate(cases):
        ok, reason, detail = gate(rec)
        pok, preason = pf(rec)
        treason = tf(rec)
        if want is None:
            check(f"N1.{i} {rec['protocol']} {rec.get('t_type', rec.get('net'))!r} admitted everywhere",
                  ok and pok and treason is None,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")
        else:
            check(f"N1.{i} {rec['protocol']} {rec.get('t_type', rec.get('net'))!r} refused as {want} everywhere",
                  (not ok and reason == want) and (not pok and preason == want)
                  and treason == want,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")

    # N2: ss method case / whitespace / unknown / invalid agree.
    mcases = [
        (ss_rec(method="AES-128-GCM"), None),
        (ss_rec(method=" aes-128-gcm "), None),
        (ss_rec(method="rc4-md5"), "ss-method"),
        (ss_rec(method="made-up-method"), "ss-method"),
        (ss_rec(method=" aes 128 gcm "), "ss-method"),
        (ss_rec(method=""), "ss-method"),
        (ss_rec(method=None), "ss-method"),
        (ss_rec(method=123), "ss-method"),
    ]
    for i, (rec, want) in enumerate(mcases):
        ok, reason, detail = gate(rec)
        pok, preason = pf(rec)
        treason = tf(rec)
        if want is None:
            check(f"N2.{i} ss method {rec.get('method')!r} admitted everywhere",
                  ok and pok and treason is None,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")
        else:
            check(f"N2.{i} ss method {rec.get('method')!r} refused as {want} everywhere",
                  (not ok and reason == want) and (not pok and preason == want)
                  and treason == want,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")

    # N3: password checks are shared by pre_filter / tester / build
    # (check_password). The gate checks PRESENCE only (#127 frozen gate
    # semantics: the gate records that a variant exists at a source;
    # publishability is pre_filter's job). Assert the boundary honestly.
    pwcases = [
        (trojan_rec(password="a,b"), "comma-password"),
        (trojan_rec(password="a, b"), "comma-password"),
        (trojan_rec(password=" pw"), "bad-password"),
        (trojan_rec(password="pw "), "bad-password"),
        (trojan_rec(password=""), "missing-password"),
        (trojan_rec(password=None), "missing-password"),
        (ss_rec(password="x,y"), "comma-password"),
        (ss_rec(password=" y"), "bad-password"),
    ]
    for i, (rec, want) in enumerate(pwcases):
        ok, reason, detail = gate(rec)
        pok, preason = pf(rec)
        treason = tf(rec)
        if want == "missing-password":
            check(f"N3.{i} password {rec.get('password')!r} -> {want} everywhere, no leak",
                  (not ok and reason == want) and (not pok and preason == want)
                  and treason == want and "pw" not in detail and "," not in detail,
                  f"gate={ok}/{reason}/{detail!r} pf={pok}/{preason} tester={treason}")
        else:
            check(f"N3.{i} password {rec.get('password')!r} -> gate presence-only, pf/tester {want}, no leak",
                  ok and (not pok and preason == want) and treason == want
                  and "pw" not in detail and "," not in detail,
                  f"gate={ok}/{reason}/{detail!r} pf={pok}/{preason} tester={treason}")
    try:
        rules.build_surge_line(trojan_rec(password="a,b"), "test")
        check("N3.8 build_surge_line raises on comma password", False, "no raise")
    except ValueError:
        check("N3.8 build_surge_line raises on comma password", True, "")

    # N4: uuid checks are shared by pre_filter / tester / build
    # (check_uuid). The gate checks PRESENCE only (same boundary as N3).
    ucases = [
        (vmess_rec(uuid="11111111-2222-3333-4444-555555555555"), None),
        (vmess_rec(uuid="AAAAAAAA-2222-3333-4444-555555555555"), None),
        (vmess_rec(uuid="not-a-uuid"), "invalid-uuid"),
        (vmess_rec(uuid="11111111,2222-3333-4444-555555555555"), "comma-uuid"),
        (vmess_rec(uuid=""), "missing-uuid"),
        (vmess_rec(uuid=None), "missing-uuid"),
    ]
    for i, (rec, want) in enumerate(ucases):
        ok, reason, detail = gate(rec)
        pok, preason = pf(rec)
        treason = tf(rec)
        if want is None:
            check(f"N4.{i} uuid ok admitted everywhere",
                  ok and pok and treason is None,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")
        elif want == "missing-uuid":
            check(f"N4.{i} uuid {rec.get('uuid')!r} -> {want} everywhere",
                  (not ok and reason == want) and (not pok and preason == want)
                  and treason == want,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")
        else:
            check(f"N4.{i} uuid {rec.get('uuid')!r} -> gate presence-only, pf/tester {want}",
                  ok and (not pok and preason == want) and treason == want,
                  f"gate={ok}/{reason} pf={pok}/{preason} tester={treason}")
    try:
        rules.build_surge_line(vmess_rec(uuid="not-a-uuid"), "test")
        check("N4.6 build_surge_line raises on malformed uuid", False, "no raise")
    except ValueError:
        check("N4.6 build_surge_line raises on malformed uuid", True, "")

    # N5: security is NOT normalized (D2, frozen): the gate is the only
    # enforcer and stays case-sensitive; pre_filter has no security check
    # and the tester folds unknown security to auto. Assert the
    # divergence is preserved, not "fixed".
    ok, reason, detail = gate(vmess_rec(security="AES-128-GCM"))
    check("N5.1 gate rejects uppercase security verbatim",
          (not ok and reason == "unsupported-security"
           and detail == "AES-128-GCM"),
          f"{ok}/{reason}/{detail!r}")
    ok, reason, detail = gate(vmess_rec(security="aes-128-gcm"))
    check("N5.2 gate admits lowercase security", ok, f"{reason}")
    pok, preason = pf(vmess_rec(security="AES-128-GCM"))
    check("N5.3 pre_filter has no security check (D2 preserved)",
          pok, f"{preason}")
    cfg = tester.build_config(vmess_rec(security="AES-128-GCM"))
    check("N5.4 tester folds unknown security to auto (D2 preserved)",
          cfg["outbounds"][0]["security"] == "auto",
          f"{cfg['outbounds'][0]['security']}")

    # N6: N3 overlaps the unified contract (transport first, then SNI).
    check("N6.1 ws + no SNI + IP host -> vmess-no-sni (not transport)",
          pf(vmess_rec(net=" WS ", sni=None, host="8.8.8.8")) == (False, "vmess-no-sni"),
          pf(vmess_rec(net=" WS ", sni=None, host="8.8.8.8")))
    check("N6.2 grpc + no SNI -> unsupported-transport (transport first)",
          pf(vmess_rec(net="grpc", sni=None, host="8.8.8.8")) == (False, "unsupported-transport"),
          pf(vmess_rec(net="grpc", sni=None, host="8.8.8.8")))
    check("N6.3 ws + no SNI + DNS host -> admitted (hostname is identity)",
          pf(vmess_rec(net="ws", sni=None, host="example.com")) == (True, ""),
          pf(vmess_rec(net="ws", sni=None, host="example.com")))
    check("N6.4 tester agrees with pre_filter on N3",
          tf(vmess_rec(net="ws", sni=None, host="8.8.8.8")) == "vmess-no-sni",
          tf(vmess_rec(net="ws", sni=None, host="8.8.8.8")))
    try:
        rules.build_surge_line(vmess_rec(net="ws", sni=None, host="8.8.8.8"), "test")
        check("N6.5 build_surge_line raises on vmess-no-sni", False, "no raise")
    except ValueError as e:
        check("N6.5 build_surge_line raises on vmess-no-sni", "vmess-no-sni" in str(e), str(e))

    # N7: fingerprint stability under the unified contract.
    k = KEY
    f_ws = la.fingerprint_for_record(trojan_rec(t_type="ws"), k)
    f_WS = la.fingerprint_for_record(trojan_rec(t_type="WS"), k)
    f_ws_sp = la.fingerprint_for_record(trojan_rec(t_type=" ws "), k)
    f_tcp = la.fingerprint_for_record(trojan_rec(t_type="tcp"), k)
    check("N7.1 ws/WS/' ws ' share one fingerprint",
          f_ws == f_WS == f_ws_sp, f"{f_ws} {f_WS} {f_ws_sp}")
    check("N7.2 ws and tcp fingerprints differ", f_ws != f_tcp, "")
    f_pw1 = la.fingerprint_for_record(trojan_rec(password="pw1"), k)
    f_pw2 = la.fingerprint_for_record(trojan_rec(password="pw2"), k)
    check("N7.3 password change DOES change the fingerprint (v4: auth variants are distinct)",
          f_pw1 != f_pw2, "")

# ---------------------------------------------------------------------------
# B: batch state machine (latest successful complete crawl per source)
# ---------------------------------------------------------------------------
def batch_rec(proto, host, port, source, **kw):
    if proto == "trojan":
        d = trojan_rec(host=host, port=port, source=source)
    elif proto == "vmess":
        d = vmess_rec(host=host, port=port, source=source)
    else:
        d = ss_rec(host=host, port=port, source=source)
    d.update(kw)
    return d


def section_b():
    base = fresh_base()
    conn, rec, started, dbp = batch_conn(base)
    try:
        src = "alirewa-config"
        a = batch_rec("trojan", "198.51.100.10", 443, src)
        b = batch_rec("trojan", "198.51.100.11", 443, src, t_type="ws",
                      ws=True)
        # B1: complete batch -> members consumable.
        col, s = run_collector(base, conn, rec, started, [a, b],
                               counts_for(src, total=2))
        check("B1.1 complete batch status", s[src]["status"] == "complete", s)
        bs.commit_batch(conn, col)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started + 60)
        check("B1.2 complete batch members consumable",
              members is not None and len(members) == 2 and reason == "ok",
              f"{members} {reason}")
        keys = {(m[0], m[1], m[2]) for m in members}
        check("B1.3 member identities are protocol/host/port only",
              keys == {("trojan", "198.51.100.10", 443),
                       ("trojan", "198.51.100.11", 443)}, keys)

        # B2: fetch failure -> failed batch -> BLOCKED, no members.
        started2 = started + 3600
        rec2 = la.build_lineage_recorder(conn, str(base), started2, key=KEY, defer=True)
        col2, s2 = run_collector(base, conn, rec2, started2, [],
                                 counts_for(src, total=0, status="failed"))
        check("B2.1 failed batch status", s2[src]["status"] == "failed", s2)
        bs.commit_batch(conn, col2)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started2 + 60)
        check("B2.2 failed batch blocks consumption (old complete batch superseded)",
              members is None and reason == "batch_incomplete:failed",
              f"{members} {reason}")

        # B3: partial (unparsed rows) -> BLOCKED.
        started3 = started + 7200
        rec3 = la.build_lineage_recorder(conn, str(base), started3, key=KEY, defer=True)
        col3, s3 = run_collector(base, conn, rec3, started3, [a],
                                 counts_for(src, total=2, unparsed=1))
        check("B3.1 partial batch status", s3[src]["status"] == "partial", s3)
        bs.commit_batch(conn, col3)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started3 + 60)
        check("B3.2 partial batch blocks consumption",
              members is None and reason == "batch_incomplete:partial", f"{reason}")

        # B4: empty (fetch ok, zero observed) -> BLOCKED, no empty set certified.
        started4 = started + 10800
        rec4 = la.build_lineage_recorder(conn, str(base), started4, key=KEY, defer=True)
        col4, s4 = run_collector(base, conn, rec4, started4, [],
                                 counts_for(src, total=0))
        check("B4.1 empty batch status", s4[src]["status"] == "empty", s4)
        bs.commit_batch(conn, col4)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started4 + 60)
        check("B4.2 empty batch blocks consumption",
              members is None and reason == "batch_incomplete:empty", f"{reason}")
        n_members = conn.execute(
            "SELECT COUNT(*) FROM crawl_batch_members WHERE batch_id IN"
            " (SELECT id FROM crawl_batches WHERE source=?)", (src,)).fetchone()[0]
        check("B4.3 non-complete batches write no member rows",
              n_members == 2, f"member rows={n_members} (only B1's 2)")

        # B5: disabled source -> status disabled -> BLOCKED; and a later
        # disable of a source with a complete batch also blocks it.
        started5 = started + 14400
        rec5 = la.build_lineage_recorder(conn, str(base), started5, key=KEY, defer=True)
        col5, s5 = run_collector(base, conn, rec5, started5, [a],
                                 counts_for(src, total=1),
                                 disabled=[src])
        check("B5.1 disabled source batch status", s5[src]["status"] == "disabled", s5)
        bs.commit_batch(conn, col5)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started5 + 60)
        check("B5.2 disabled batch blocks consumption",
              members is None and reason == "batch_incomplete:disabled", f"{reason}")
        # A fresh complete batch, then the source is disabled afterwards.
        started6 = started + 18000
        rec6 = la.build_lineage_recorder(conn, str(base), started6, key=KEY, defer=True)
        col6, s6 = run_collector(base, conn, rec6, started6, [a],
                                 counts_for(src, total=1))
        bs.commit_batch(conn, col6)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started6 + 60)
        check("B5.3 complete batch consumable before disable",
              members is not None and len(members) == 1, f"{members} {reason}")
        members, reason = qualified(conn, base, src, now=started6 + 60,
                                                     disabled={src})
        check("B5.4 same batch blocked once the source is disabled",
              members is None and reason == "source_disabled", f"{reason}")

        # B6: lineage unavailable (no key) -> incomplete -> BLOCKED.
        started7 = started + 21600
        col7 = bs.BatchCollector(started7, lineage=None,
                                 lineage_reason="no_key")
        col7.observe(a)
        s7 = col7.finish(counts_for(src, total=1),
                         registry_status={"alirewa-config": "active"})
        check("B6.1 no-key batch status", s7[src]["status"] == "incomplete", s7)
        bs.commit_batch(conn, col7)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started7 + 60)
        check("B6.2 incomplete batch blocks consumption",
              members is None and reason == "batch_incomplete:incomplete", f"{reason}")

        # B7: vanished variant leaves the new member set.
        started8 = started + 25200
        rec8 = la.build_lineage_recorder(conn, str(base), started8, key=KEY, defer=True)
        col8, s8 = run_collector(base, conn, rec8, started8, [a],
                                 counts_for(src, total=1))
        bs.commit_batch(conn, col8)
        conn.commit()
        members, reason = qualified(conn, base, src, now=started8 + 60)
        keys = {(m[0], m[1], m[2]) for m in members} if members else set()
        check("B7.1 vanished variant B is gone from the new member set",
              keys == {("trojan", "198.51.100.10", 443)}, keys)

        # B8: stale (>24h) and future-dated batches block.
        members, reason = qualified(conn, base, src, now=started8 + 90000)
        check("B8.1 stale batch blocks consumption",
              members is None and reason == "batch_stale", f"{reason}")
        members, reason = qualified(conn, base, src, now=started8 - 3600)
        check("B8.2 future-dated batch blocks consumption",
              members is None and reason == "batch_stale", f"{reason}")

        # B9: duplicate batch (same source+started, same bytes) is a
        # no-op; different bytes for the same key are refused.
        before = conn.execute("SELECT COUNT(*) FROM crawl_batches").fetchone()[0]
        bs.commit_batch(conn, col8)  # same collector, same bytes
        conn.commit()
        after = conn.execute("SELECT COUNT(*) FROM crawl_batches").fetchone()[0]
        check("B9.1 duplicate identical batch is a no-op",
              after == before, f"{before} -> {after}")
        col8b = bs.BatchCollector(started8, lineage=rec8, lineage_reason="")
        col8b.observe(b)  # different members, same started
        col8b.finish(counts_for(src, total=1),
                     registry_status={"alirewa-config": "active"})
        try:
            bs.commit_batch(conn, col8b)
            conn.commit()
            check("B9.2 conflicting batch for the same key is refused", False, "no raise")
        except bs.BatchUnavailable:
            conn.rollback()
            check("B9.2 conflicting batch for the same key is refused", True, "")

        # B10: paused source (B4 screening-only): the crawl still runs
        # and lineage is still recorded, but the batch never qualifies
        # for consumption. The pause is enforced at CONSUMPTION time
        # (qualified_batch_members -> source_paused_or_unverified), not
        # by falsifying the crawl outcome.
        paused = "chenzhihan-base64"
        started9 = started + 28800
        rec9 = la.build_lineage_recorder(conn, str(base), started9, key=KEY, defer=True)
        col9, s9 = run_collector(base, conn, rec9, started9,
                                 [batch_rec("trojan", "198.51.100.40", 443, paused)],
                                 counts_for(paused, total=1))
        check("B10.1 paused source crawl still completes and records registry_status=paused",
              s9[paused]["status"] == "complete"
              and s9[paused]["registry_status"] == "paused", s9)
        bs.commit_batch(conn, col9)
        conn.commit()
        members, reason = qualified(conn, base, paused, now=started9 + 60)
        check("B10.2 paused source blocks consumption",
              members is None and reason == "source_paused_or_unverified", f"{reason}")

        # B11: prune removes rows older than 30 days, keeps fresh ones.
        old_started = started - 40 * 86400
        conn.execute(
            "INSERT INTO crawl_batches (source,started,completed_at,status,error)"
            " VALUES (?,?,?,?,?)",
            ("matin-vmess", old_started, old_started, "complete", ""))
        conn.commit()
        pruned = bs.prune_batches(conn)
        conn.commit()
        check("B11.1 prune removes the 40-day-old batch row",
              pruned >= 1, f"pruned={pruned}")
        left = conn.execute(
            "SELECT COUNT(*) FROM crawl_batches WHERE source='matin-vmess'").fetchone()[0]
        check("B11.2 old batch row is gone", left == 0, f"left={left}")
        left = conn.execute(
            "SELECT COUNT(*) FROM crawl_batches WHERE source=?", (src,)).fetchone()[0]
        check("B11.3 fresh batches survive pruning", left > 0, f"left={left}")

        # B12: migration script behaviour on a fresh DB copy.
        db2 = base / "data" / "pool2.db"
        shutil.copy2(dbp, db2)
        conn2 = sqlite3.connect(str(db2))
        conn2.execute("DROP TABLE IF EXISTS crawl_batches")
        conn2.execute("DROP TABLE IF EXISTS crawl_batch_members")
        conn2.commit()
        conn2.close()
        check("B12.1 --check detects missing batch tables",
              mbs.main([str(db2), "--check"]) == 1, "")
        check("B12.2 --dry-run writes nothing",
              mbs.main([str(db2), "--dry-run"]) == 0
              and not bs.batch_schema_ready(sqlite3.connect(str(db2))), "")
        check("B12.3 migrate creates the tables",
              mbs.main([str(db2)]) == 0
              and bs.batch_schema_ready(sqlite3.connect(str(db2))), "")
        check("B12.4 --check passes after migrate",
              mbs.main([str(db2), "--check"]) == 0, "")
        try:
            rc_rollback = mbs.main([str(db2), "--rollback"])
        except SystemExit as e:  # argparse rejects the unknown flag
            rc_rollback = e.code
        check("B12.5 --rollback without --backup is refused",
              rc_rollback == 2, f"rc={rc_rollback}")
        try:
            rc_loss = mbs.main([str(db2), "--allow-data-loss"])
        except SystemExit as e:
            rc_loss = e.code
        check("B12.6 --allow-data-loss is rejected as an unknown argument",
              rc_loss == 2, f"rc={rc_loss}")
        # B12.7: a second migration in the same second succeeds with a
        # distinct backup file (counter suffix), never overwriting.
        backups_dir = os.path.join(os.path.dirname(os.path.abspath(str(db2))), "backups")
        def _n_backups():
            return len([f for f in os.listdir(backups_dir)
                        if f.startswith("batch-state-") and f.endswith(".sqlite3")]) \
                if os.path.isdir(backups_dir) else 0
        n_before = _n_backups()
        check("B12.7 immediate re-run succeeds with a new backup file",
              mbs.main([str(db2)]) == 0
              and _n_backups() == n_before + 1,
              f"backups before={n_before}")
    finally:
        conn.close()
        shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------------------
# T: explicit-transaction crawl (no write lock during network I/O)
# ---------------------------------------------------------------------------
def section_t():
    import logging
    from types import SimpleNamespace
    from pool import cli as cli_mod

    vmess_obj = {"v": "2", "ps": "v1", "add": "198.51.100.20",
                 "port": "443", "id": "11111111-2222-3333-4444-555555555555",
                 "aid": "0", "net": "ws", "type": "none", "host": "",
                 "path": "/", "tls": "tls", "sni": "example.com",
                 "scy": "auto"}
    vmess_line = ("vmess://" + base64.b64encode(
        json.dumps(vmess_obj).encode()).decode())
    bodies = {
        "http://example.invalid/alirewa":
            "trojan://pw@198.51.100.10:443?type=WS&sni=example.com#t1\n"
            "trojan://pw@198.51.100.11:443?type=ws&sni=example.com#t2\n",
        "http://example.invalid/matin": vmess_line + "\n",
    }
    sources_yaml = (
        "- name: alirewa-config\n"
        "  url: http://example.invalid/alirewa\n"
        "  protocols: [trojan]\n"
        "- name: matin-vmess\n"
        "  url: http://example.invalid/matin\n"
        "  protocols: [vmess]\n")

    def run_crawl(base, env_key=True, break_flush=False):
        """Run cmd_crawl once with a stubbed fetcher. Returns (rc, counts, fetch_seen)."""
        dbp = fresh_db(base)
        with open(base / "sources.yaml", "w", encoding="utf-8") as f:
            f.write(sources_yaml)
        fetch_seen = []
        orig_fetch = crawler.fetch

        def fake_fetch(url):
            # No DB write may be visible while network I/O runs: a
            # read-only probe must see zero lineage rows at every fetch.
            probe = sqlite3.connect("file:%s?mode=ro" % dbp, uri=True)
            try:
                n = probe.execute(
                    "SELECT COUNT(*) FROM node_sources").fetchone()[0]
            finally:
                probe.close()
            fetch_seen.append(n)
            return bodies[url]

        crawler.fetch = fake_fetch
        old_key = os.environ.get("POOL_LINEAGE_HMAC_KEY")
        if env_key:
            os.environ["POOL_LINEAGE_HMAC_KEY"] = KEY.decode()
        elif "POOL_LINEAGE_HMAC_KEY" in os.environ:
            del os.environ["POOL_LINEAGE_HMAC_KEY"]
        orig_flush = la.LineageRecorder.flush
        if break_flush:
            def _boom(self, conn):
                raise RuntimeError("injected flush failure")
            la.LineageRecorder.flush = _boom
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                rc = cli_mod.cmd_crawl(
                    SimpleNamespace(dry_run=False, no_lineage=False),
                    str(base), logging.getLogger("i04-test"))
            out = buf.getvalue()
        finally:
            crawler.fetch = orig_fetch
            la.LineageRecorder.flush = orig_flush
            if old_key is None:
                os.environ.pop("POOL_LINEAGE_HMAC_KEY", None)
            else:
                os.environ["POOL_LINEAGE_HMAC_KEY"] = old_key
        try:
            counts = json.loads(out)
        except ValueError:
            counts = {"_raw": out}
        return rc, counts, fetch_seen, dbp

    # T1: happy path -- deferred recorder, one explicit commit.
    base = fresh_base()
    try:
        rc, counts, fetch_seen, dbp = run_crawl(base)
        check("T1.1 cmd_crawl succeeds", rc == 0, f"rc={rc} {counts}")
        check("T1.2 no lineage rows visible during any fetch (no write lock in I/O)",
              fetch_seen == [0, 0], f"fetch_seen={fetch_seen}")
        check("T1.3 lineage ran in defer mode",
              counts.get("lineage", {}).get("deferred") is True, counts.get("lineage"))
        check("T1.4 batch ran", counts.get("batch", {}).get("enabled") is True,
              counts.get("batch"))
        conn = sqlite3.connect(str(dbp))
        try:
            n_nodes = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
            n_batch = conn.execute(
                "SELECT COUNT(*) FROM crawl_batches WHERE status='complete'").fetchone()[0]
            n_members = conn.execute(
                "SELECT COUNT(*) FROM crawl_batch_members").fetchone()[0]
            n_sight = conn.execute(
                "SELECT COUNT(*) FROM node_sources").fetchone()[0]
            runs = conn.execute(
                "SELECT ok FROM runs WHERE kind='crawl'").fetchall()
        finally:
            conn.close()
        check("T1.5 nodes upserted (2 trojan + 1 vmess)",
              n_nodes == 3, f"nodes={n_nodes}")
        check("T1.6 both sources have a complete batch",
              n_batch == 2, f"batches={n_batch}")
        check("T1.7 batch members written (2 + 1)",
              n_members == 3, f"members={n_members}")
        check("T1.8 lineage sightings written (2 + 1)",
              n_sight == 3, f"sightings={n_sight}")
        check("T1.9 exactly one successful run row",
              runs == [(1,)], f"runs={runs}")
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # T2: a failure inside the transaction rolls the WHOLE crawl back.
    base = fresh_base()
    try:
        rc, counts, fetch_seen, dbp = run_crawl(base, break_flush=True)
        check("T2.1 cmd_crawl reports failure", rc == 1, f"rc={rc}")
        conn = sqlite3.connect(str(dbp))
        try:
            n_nodes = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
            n_batch = conn.execute("SELECT COUNT(*) FROM crawl_batches").fetchone()[0]
            n_members = conn.execute(
                "SELECT COUNT(*) FROM crawl_batch_members").fetchone()[0]
            n_sight = conn.execute(
                "SELECT COUNT(*) FROM node_sources").fetchone()[0]
            runs = conn.execute(
                "SELECT ok, error FROM runs WHERE kind='crawl'").fetchall()
        finally:
            conn.close()
        check("T2.2 failed crawl leaves zero nodes",
              n_nodes == 0, f"nodes={n_nodes}")
        check("T2.3 failed crawl leaves zero batch rows",
              n_batch == 0, f"batches={n_batch}")
        check("T2.4 failed crawl leaves zero batch members",
              n_members == 0, f"members={n_members}")
        check("T2.5 failed crawl leaves zero lineage sightings (no consumable evidence)",
              n_sight == 0, f"sightings={n_sight}")
        check("T2.6 one failed run row recorded (observability only)",
              runs == [(0, "crawl_commit_failed")], f"runs={runs}")
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # T3: missing key -> lineage unavailable, batch incomplete, crawl
    # still runs (nodes land), consumers BLOCK.
    base = fresh_base()
    try:
        rc, counts, fetch_seen, dbp = run_crawl(base, env_key=False)
        check("T3.1 crawl without a key still succeeds",
              rc == 0, f"rc={rc} {counts}")
        check("T3.2 lineage reports no_key",
              counts.get("lineage", {}).get("reason") == "no_key",
              counts.get("lineage"))
        conn = sqlite3.connect(str(dbp))
        try:
            n_nodes = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
            n_batch = conn.execute("SELECT COUNT(*) FROM crawl_batches").fetchone()[0]
        finally:
            conn.close()
        check("T3.3 nodes still land without lineage",
              n_nodes == 3, f"nodes={n_nodes}")
        check("T3.4 no-key crawl writes incomplete batches only",
              n_batch == 2, f"batches={n_batch}")
        conn = dbmod.connect(str(dbp))
        try:
            import pool.batch_state as _bs
            from pool.lineage_adapter import load_registry as _lr
            reg, _ = _lr(str(base / "source_groups.json"))
            m, why = _bs.qualified_batch_members(
                conn, "alirewa-config", int(time.time()),
                registry_status=dict(reg.status),
                known_sources={s for v in reg.groups.values() for s in v})
        finally:
            conn.close()
        check("T3.5 no-key batch is not consumable",
              m is None and why.startswith("batch_incomplete"), f"{m} {why}")
    finally:
        shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------------------
# P: PHONE_EVIDENCE_READY label (no bare READY verdict)
# ---------------------------------------------------------------------------
def section_p():
    import receiver as _recv
    base = fresh_base()
    try:
        sha = "a" * 64
        manifest = {"pool_sha": sha, "generation": 0, "ttl": "2027-01-01",
                    "cap": 6, "status": "PROBATION",
                    "entries": [{"key": "vmess|203.0.113.10|443", "name": "试用-甲",
                                 "source_group": "G-chenzhihan"},
                                {"key": "vmess|203.0.113.11|443", "name": "试用-乙",
                                 "source_group": "G-alirewa"}]}
        man_path = str(base / "vp-manifest.json")
        with open(man_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        db_path = str(base / "vp-db.sqlite3")
        _recv.initialize_db(db_path)
        c = sqlite3.connect(db_path)
        t0 = NOW - 7200
        rows = [
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0, "cellular", sha, "target_reachable", "success", "target_reachable", 0, 0, 1),
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0 + 1200, "cellular", sha, "target_reachable", "success", "target_reachable", 0, 0, 1),
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0 + 2400, "cellular", sha, "target_reachable", "success", "target_reachable", 0, 0, 1),
            ("vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, t0 + 3600, "cellular", sha, "target_reachable", "success", "target_reachable", 1, 0, 1),
            ("vmess", "203.0.113.11", 443, "success", "external_policy_id", 1, t0, "cellular", sha, "target_reachable", "success", "target_reachable", 1, None, 1),
            ("vmess", "203.0.113.11", 443, "success", "external_policy_id", 1, t0 + 1200, "cellular", sha, "target_reachable", "success", "target_reachable", 1, None, 1),
            ("vmess", "203.0.113.11", 443, "success", "external_policy_id", 1, t0 + 2400, "cellular", sha, "target_reachable", "success", "target_reachable", 1, None, 1),
        ]
        for r in rows:
            nonce = secrets.token_hex(16)
            c.execute("INSERT INTO batches (nonce, received_at, payload_sha) VALUES(?,?,?)", (nonce, r[6], sha))
            c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified,trial_generation,dual_target_ok) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (nonce,) + r)
        c.commit()
        c.close()
        env = dict(os.environ)
        env.update({"PHONE_PROBE_MANIFEST": man_path, "PHONE_PROBE_DB": db_path})
        out = subprocess.run([sys.executable, str(SRC / "verify_promotion.py")],
                             env=env, capture_output=True, text=True, timeout=30)
        stdout = out.stdout
        tokens = re.findall(r"[A-Z_]+", stdout)
        check("P1.1 verify_promotion exits 0", out.returncode == 0,
              f"rc={out.returncode} err={out.stderr.strip()!r}")
        check("P1.2 qualifying chain reports PHONE_EVIDENCE_READY",
              "-> PHONE_EVIDENCE_READY" in stdout, stdout)
        check("P1.3 PHONE_EVIDENCE_READY count line present",
              "PHONE_EVIDENCE_READY count: 1" in stdout, stdout)
        check("P1.4 GLOBAL_READY is NOT_EVALUATED with all seven gates listed",
              "GLOBAL_READY: NOT_EVALUATED" in stdout
              and "real_identity=NOT_CHECKED_BY_THIS_SCRIPT" in stdout
              and "surge_native_lt_300ms=NOT_CHECKED_BY_THIS_SCRIPT" in stdout
              and "current_vps_le_300ms=NOT_CHECKED_BY_THIS_SCRIPT" in stdout
              and "source_diversity=NOT_CHECKED_BY_THIS_SCRIPT" in stdout
              and "ttl=CHECKED_BY_THIS_SCRIPT" in stdout
              and "blocklist=NOT_CHECKED_BY_THIS_SCRIPT" in stdout
              and "publish_authorisation=NOT_CHECKED_BY_THIS_SCRIPT" in stdout,
              stdout)
        check("P1.5 no bare READY token anywhere in the output (old parsers cannot misread)",
              "READY" not in tokens, f"tokens with READY: {[t for t in tokens if 'READY' in t]}")
        check("P1.6 old parser pattern '-> READY' finds nothing",
              "-> READY" not in stdout, stdout)
        check("P1.7 legacy rows reported only, not counted",
              "legacy_rows=3" in stdout and "legacy=LEGACY_PARTIAL" in stdout, stdout)
        check("P1.8 diagnostic chain still passes",
              "diagnostic=DIAGNOSTIC_PASS" in stdout, stdout)
    finally:
        shutil.rmtree(base, ignore_errors=True)


# ---------------------------------------------------------------------------
# I: importer generation classification + rollback consumer
# ---------------------------------------------------------------------------
def _write_pool22(path):
    pool22 = [(f"池-{i:02d}", ["trojan", "vmess", "ss"][i % 3],
               f"203.0.113.{100 + i}", 443 if i % 2 else 8443) for i in range(1, 23)]
    with open(path, "w", encoding="utf-8") as f:
        for name, proto, host, port in pool22:
            if proto == "trojan":
                f.write(f"{name} = trojan, {host}, {port}, password=pw, sni=example.com\n")
            elif proto == "vmess":
                f.write(f"{name} = vmess, {host}, {port}, username=11111111-2222-3333-4444-555555555555, tls=true\n")
            else:
                f.write(f"{name} = ss, {host}, {port}, encrypt-method=aes-128-gcm, password=pw\n")
    return pool22


def _staging_with_rows(base, name, pool_sha, cand, rows, with_gen_col=True):
    """rows: (proto,host,port,status,mode,trusted,ts,bearer,sha,reason,
    raw_status,raw_reason,cv[,gen[,dual]]). Returns staging path."""
    import receiver as _recv
    staging = str(base / name)
    _recv.initialize_db(staging)
    c = sqlite3.connect(staging)
    if not with_gen_col:
        # Old DB: drop the v2 columns so the importer sees null/0.
        cols = {r[1] for r in c.execute("PRAGMA table_info(phone_observations)")}
        if "trial_generation" in cols:
            c.execute("ALTER TABLE phone_observations DROP COLUMN trial_generation")
        if "dual_target_ok" in cols:
            c.execute("ALTER TABLE phone_observations DROP COLUMN dual_target_ok")
        c.commit()
    for r in rows:
        nonce = secrets.token_hex(16)
        c.execute("INSERT INTO batches (nonce, received_at, payload_sha) VALUES(?,?,?)",
                  (nonce, r[6], pool_sha))
        if with_gen_col:
            gen = r[13] if len(r) > 13 else None
            dual = r[14] if len(r) > 14 else 0
            c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified,trial_generation,dual_target_ok) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (nonce,) + r[:13] + (gen, dual))
        else:
            c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                      (nonce,) + r[:13])
    c.commit()
    c.close()
    return staging


def _prod_db(base, name, pins):
    prod = str(base / name)
    c = sqlite3.connect(prod)
    c.execute("CREATE TABLE pinned (protocol TEXT, host TEXT, port INTEGER)")
    c.execute("CREATE TABLE blocklist (protocol TEXT, host TEXT, port INTEGER)")
    c.execute("CREATE TABLE phone_failures (protocol TEXT, host TEXT, port INTEGER, reported_at INTEGER, source TEXT, detail TEXT)")
    c.executemany("INSERT INTO pinned VALUES (?,?,?)", sorted(pins))
    c.commit()
    c.close()
    return prod


def section_i():
    import receiver as _recv
    base = fresh_base()
    try:
        pool22 = _write_pool22(str(base / "pool22.txt"))
        with open(str(base / "pool22.txt"), "rb") as f:
            p22_sha = __import__("hashlib").sha256(f.read()).hexdigest()
        cand = pool22[-1]  # 池-22, not pinned
        pins22 = {(p, h, pt) for _, p, h, pt in pool22[:-1]}
        t_base = NOW - 3600

        def F(ts, mode="external_policy_id", bearer="cellular", cv=1, gen=None, dual=0):
            return (cand[1], cand[2], cand[3], "failure", mode, 1, ts, bearer,
                    p22_sha, "dual_transport_failure", "failure",
                    "dual_transport_failure", cv, gen, dual)

        # I1: v2 importer -- formal row imports, trial row is skipped.
        staging = _staging_with_rows(base, "staging-i1.sqlite3", p22_sha, cand, [
            F(t_base, gen=None),            # formal historical, trusted
            F(t_base + 60, gen=3),          # trial generation 3, trusted
            F(t_base + 120, gen=3, cv=0),   # trial + untrusted
            F(t_base + 180, gen=None, bearer="wifi"),  # formal + wifi
        ])
        prod = _prod_db(base, "pool-i1.sqlite3", pins22)
        out = imp2.import_once(staging, prod, str(base / "pool22.txt"),
                               now=NOW, apply=False)
        check("I1.1 v2 dry-run: only the formal row is eligible",
              out["eligible_staging_rows"] == 1, f"out={out}")
        check("I1.2 v2 dry-run: both trial rows are skipped as trial_generation_bound (trial check precedes G10)",
              out["skipped"].get("trial_generation_bound") == 2, f"out={out}")
        check("I1.3 v2 dry-run: the remaining row stays untrusted",
              out["skipped"].get("untrusted") == 1, f"out={out}")
        out2 = imp2.import_once(staging, prod, str(base / "pool22.txt"),
                                now=NOW, apply=True, approved=True)
        c = sqlite3.connect("file:%s?mode=ro" % prod, uri=True)
        details = [r[0] for r in c.execute("SELECT detail FROM phone_failures")]
        c.close()
        check("I1.4 v2 apply writes exactly one row",
              out2["new"] == 1 and len(details) == 1, f"out={out2} details={details}")
        check("I1.5 v2 written detail carries evidence_class=formal_historical",
              '"evidence_class":"formal_historical"' in details[0], details)
        check("I1.6 v2 written detail keeps trial_generation null",
              '"trial_generation":null' in details[0], details)

        # I2: legacy importer -- same classification, key=value detail.
        prod2 = _prod_db(base, "pool-i2.sqlite3", pins22)
        out3 = subprocess.run(
            [sys.executable, str(SRC / "import_phone_observations.py"),
             "--staging-db", staging, "--pool-db", prod2,
             "--pool-file", str(base / "pool22.txt")],
            capture_output=True, text=True, timeout=30)
        c = sqlite3.connect("file:%s?mode=ro" % prod2, uri=True)
        details2 = [r[0] for r in c.execute("SELECT detail FROM phone_failures")]
        c.close()
        check("I2.1 legacy importer exits 0 and imports exactly one row",
              out3.returncode == 0 and "imported=1" in out3.stdout
              and len(details2) == 1,
              f"rc={out3.returncode} out={out3.stdout.strip()!r} err={out3.stderr.strip()!r}")
        check("I2.2 legacy skipped counts name trial_generation_bound",
              "trial_generation_bound': 2" in out3.stdout, out3.stdout)
        check("I2.3 legacy written detail carries evidence_class=formal_historical",
              "evidence_class=formal_historical" in details2[0], details2)

        # I3: old staging DB (no trial_generation column) -- formal rows
        # still import (generation None == formal historical).
        staging_old = _staging_with_rows(base, "staging-i3.sqlite3", p22_sha, cand, [
            F(t_base, gen=None),
        ], with_gen_col=False)
        prod3 = _prod_db(base, "pool-i3.sqlite3", pins22)
        out4 = imp2.import_once(staging_old, prod3, str(base / "pool22.txt"),
                                now=NOW, apply=True, approved=True)
        check("I3.1 old-DB v2 import still admits the formal row",
              out4["new"] == 1, f"out={out4}")

        # I4: the real consumer (auto_prune) -- trial rows never count,
        # formal rows still count, rollback cannot resurrect isolation.
        import auto_prune as _ap
        key = ("trojan", "203.0.113.122", 443)
        prod4 = str(base / "pool-i4.sqlite3")
        c = sqlite3.connect(prod4)
        c.execute("CREATE TABLE nodes (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE node_tests (protocol TEXT, host TEXT, port INTEGER, tested_at INTEGER, result TEXT, reason TEXT, ms REAL)")
        c.execute("CREATE TABLE pinned (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE blocklist (protocol TEXT, host TEXT, port INTEGER)")
        c.execute("CREATE TABLE phone_failures (protocol TEXT, host TEXT, port INTEGER, reported_at INTEGER, source TEXT, detail TEXT)")
        pf_rows = [
            # (a) trial JSON detail, cv=1 + external + cellular -> must NOT count
            (key[0], key[1], key[2], NOW - 3600, "surge-url-test",
             '{"bearer":"cellular","control_verified":1,"method":"external_policy_id","trial_generation":3,"dual_target_ok":1}'),
            # (b) trial key=value detail, cv=1 + external + cellular -> must NOT count
            (key[0], key[1], key[2], NOW - 3500, "surge-url-test",
             "probe_mode=external_policy_id bearer=cellular control_verified=1 trial_generation=7 dual_target_ok=1"),
            # (c) formal JSON detail, cv=1 + external + cellular -> counts
            (key[0], key[1], key[2], NOW - 3400, "surge-url-test",
             '{"bearer":"cellular","control_verified":1,"method":"external_policy_id","trial_generation":null,"dual_target_ok":0,"evidence_class":"formal_historical"}'),
            # (d) legacy key=value detail, cv=1 + external + cellular, no generation -> counts
            (key[0], key[1], key[2], NOW - 3300, "surge-url-test",
             "probe_mode=external_policy_id bearer=cellular control_verified=1 nonce_prefix=abcd1234 pool_sha_prefix=deadbeef"),
            # (e) old-detail JSON without control_verified -> unverified (A18b behaviour)
            (key[0], key[1], key[2], NOW - 3200, "surge-url-test",
             '{"bearer":"cellular","method":"external_policy_id"}'),
        ]
        c.executemany("INSERT INTO phone_failures VALUES (?,?,?,?,?,?)", pf_rows)
        c.commit()
        c.close()
        ev = _ap.read_failure_evidence(prod4, {key}, NOW)
        check("I4.1 consumer trusts exactly the 2 formal rows (trial rows excluded)",
              len(ev["phone_failures"].get(key, [])) == 2,
              f"trusted={ev['phone_failures'].get(key)}")
        check("I4.2 consumer counts the 3 others as unverified history",
              ev["phone_failures_unverified"].get(key, 0) == 3,
              f"unverified={ev['phone_failures_unverified'].get(key)}")
        check("I4.3 classifier agrees with the consumer on every row",
              all(classify_failure_detail(r[5]) ==
                  ("trial_bound" if i in (0, 1) else "formal_historical")
                  for i, r in enumerate(pf_rows)),
              [classify_failure_detail(r[5]) for r in pf_rows])
        # Rollback simulation: the OLD importer code path never wrote a
        # trial row (it had no trial input at all), and the consumer
        # above proves a trial row already in the DB cannot be consumed.
        # The invariant is structural: importers only write
        # evidence_class=formal_historical rows (I1/I2), and the consumer
        # only trusts formal_historical rows (I4.1). No rollback path can
        # turn a trial row into trusted evidence.
        check("I4.4 no trial row is consumable after any rollback (structural)",
              classify_failure_detail(pf_rows[0][5]) == "trial_bound"
              and classify_failure_detail(pf_rows[1][5]) == "trial_bound", "")
        # I4.5: stale-layout fallback -- when the classifier module is
        # absent, the consumer keeps the exact pre-#04 G10 behaviour
        # (trial row trusted if it carries cv=1 + external + cellular)
        # instead of crashing. The #04 package always ships both files,
        # so this branch is only for layouts that copy auto_prune.py
        # alone; it is NOT the #04 behaviour.
        saved = _ap.classify_failure_detail
        try:
            _ap.classify_failure_detail = None
            check("I4.5 fallback without classifier keeps pre-#04 G10 behaviour",
                  _ap._is_trusted_phone_failure("surge-url-test", pf_rows[0][5]) is True
                  and _ap._is_trusted_phone_failure("surge-url-test", pf_rows[2][5]) is True,
                  "")
        finally:
            _ap.classify_failure_detail = saved
        check("I4.6 classifier restored after fallback test",
              _ap.classify_failure_detail is not None
              and _ap._is_trusted_phone_failure("surge-url-test", pf_rows[0][5]) is False,
              "")
    finally:
        shutil.rmtree(base, ignore_errors=True)

# ---------------------------------------------------------------------------
# C: candidate computation + grouped round-robin sub-batches (GPT 7123361053)
# ---------------------------------------------------------------------------
def _build_candidate_db(base):
    """DB with complete batches for 3 sources in 3 independent groups.
    Returns (conn, db_path, started, fingerprints) where fingerprints maps
    (protocol, host, port) -> fingerprint for the admitted members."""
    conn, rec, started, dbp = batch_conn(base)
    members = {
        "alirewa-config": [
            batch_rec("trojan", "198.51.100.10", 443, "alirewa-config"),
            batch_rec("trojan", "198.51.100.11", 443, "alirewa-config",
                      t_type="ws", ws=True),
        ],
        "matin-vmess": [
            batch_rec("vmess", "198.51.100.20", 443, "matin-vmess"),
            batch_rec("vmess", "198.51.100.21", 443, "matin-vmess"),
        ],
        "chenzhihan-v2ray": [
            batch_rec("trojan", "198.51.100.30", 443, "chenzhihan-v2ray"),
            batch_rec("trojan", "198.51.100.31", 443, "chenzhihan-v2ray",
                      t_type="ws", ws=True),
        ],
    }
    fps = {}
    for source, recs in members.items():
        r = la.build_lineage_recorder(conn, str(base), started, key=KEY, defer=True)
        col, s = run_collector(base, conn, r, started, recs,
                               counts_for(source, total=len(recs)))
        assert s[source]["status"] == "complete", s
        for recd in recs:
            fps[(recd["protocol"], recd["host"], recd["port"])] = \
                la.fingerprint_for_record(recd, KEY)
        bs.commit_batch(conn, col)
    conn.commit()
    return conn, dbp, started, fps


def section_c():
    from pool import candidates as cand
    from pool.lineage_adapter import load_registry as _lr

    # C1: mixed verdicts -- admission failure + blocklist + clean members.
    base = fresh_base()
    try:
        conn, dbp, started, fps = _build_candidate_db(base)
        reg, _ = _lr(str(base / "source_groups.json"))
        # Block one member in the persistent blocklist.
        conn.execute("INSERT INTO blocklist (protocol, host, port, reason) "
                     "VALUES (?,?,?,?)",
                     ("vmess", "198.51.100.21", 443, "phone-fail-20261121"))
        conn.commit()
        admission = {}
        for k, fp in fps.items():
            admission[(k[0], k[1], k[2], fp)] = (True, "")
        # One member fails the unified admission (supplied result wins
        # over the lineage proof).
        bad = ("trojan", "198.51.100.11", 443)
        admission[(bad[0], bad[1], bad[2], fps[bad])] = (False, "unsupported-transport")
        report = cand.compute_candidates(
            conn, reg, now=started + 60, admission=admission)
        by_key = {(r["protocol"], r["host"], r["port"]): r
                  for r in report["candidates"]}
        check("C1.1 six members reported, one verdict row each",
              len(report["candidates"]) == 6, f"{len(report['candidates'])}")
        check("C1.2 admission-failed member excluded with its reason",
              by_key[bad]["verdict"] == "excluded"
              and by_key[bad]["reason"] == "admission_unsupported-transport",
              by_key[bad])
        check("C1.3 blocklisted member excluded as blocklisted",
              by_key[("vmess", "198.51.100.21", 443)]["reason"] == "blocklisted",
              by_key[("vmess", "198.51.100.21", 443)])
        check("C1.4 four members admitted",
              len(report["admitted"]) == 4, f"{len(report['admitted'])}")
        check("C1.5 diversity counts three independent groups",
              report["diversity"]["independent_groups"] == 3
              and report["diversity"]["groups"] == {
                  "G-alirewa": 1, "G-matin": 1, "G-chenzhihan": 2},
              report["diversity"])
        check("C1.6 batchable is 1 (one triple, leftovers cannot form another)",
              report["batchable"] == 1, f"batchable={report['batchable']}")
        check("C1.7 the packed batch has one member per group",
              len(report["batches"]) == 1
              and len({m["group"] for m in report["batches"][0]}) == 3,
              report["batches"])
        check("C1.8 admitted members carry the lineage admission proof",
              all(r["admission_source"] in ("supplied", "lineage_at_crawl")
                  for r in report["admitted"]), report["admitted"])
        # C2: zero is reported as zero, never padded.
        admission_all_bad = {k: (False, "unsupported-transport")
                             for k in admission}
        report0 = cand.compute_candidates(
            conn, reg, now=started + 60, admission=admission_all_bad)
        check("C2.1 all-excluded set reports batchable 0, honestly",
              report0["batchable"] == 0 and len(report0["admitted"]) == 0
              and len(report0["excluded"]) == 6,
              f"batchable={report0['batchable']} admitted={len(report0['admitted'])}")
        check("C2.2 zero-batch report still lists every exclusion reason",
              {r["reason"] for r in report0["excluded"]}
              == {"admission_unsupported-transport", "blocklisted"},
              {r["reason"] for r in report0["excluded"]})
        # C3: stale batches -> nothing consumable, batchable 0.
        report_stale = cand.compute_candidates(
            conn, reg, now=started + 90000, admission=admission)
        check("C3.1 stale batches report batchable 0",
              report_stale["batchable"] == 0
              and all(s["members"] == 0 for s in report_stale["sources"].values()),
              f"batchable={report_stale['batchable']}")
        # C4: a batch member with no lineage proof and no supplied
        # admission is excluded as admission_unknown (fail-closed).
        conn.execute(
            "INSERT INTO crawl_batch_members (batch_id, protocol, host, port, fingerprint)"
            " SELECT id, 'trojan', '198.51.100.99', 443, ? FROM crawl_batches"
            " WHERE source='alirewa-config' ORDER BY started DESC LIMIT 1",
            ("f" * 64,))
        conn.commit()
        report4 = cand.compute_candidates(
            conn, reg, now=started + 60, admission=admission)
        ghost = [r for r in report4["candidates"]
                 if r["host"] == "198.51.100.99"]
        check("C4.1 member without lineage proof or admission is admission_unknown",
              len(ghost) == 1 and ghost[0]["verdict"] == "excluded"
              and ghost[0]["reason"] == "admission_unknown", ghost)
        conn.close()
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # C5: sub-batch partition -- union preserved, diagnostic-only, room
    # for an independent control in every run.
    base = fresh_base()
    try:
        conn, dbp, started, fps = _build_candidate_db(base)
        reg, _ = _lr(str(base / "source_groups.json"))
        admission = {(k[0], k[1], k[2], fp): (True, "")
                     for k, fp in fps.items()}
        report = cand.compute_candidates(
            conn, reg, now=started + 60, admission=admission)
        check("C5.1 six admitted across three groups -> batchable 2",
              len(report["admitted"]) == 6 and report["batchable"] == 2,
              f"admitted={len(report['admitted'])} batchable={report['batchable']}")
        subs = report["sub_batches"]
        union = {(m["protocol"], m["host"], m["port"])
                 for s in subs for m in s["members"]}
        admitted_keys = {(r["protocol"], r["host"], r["port"])
                         for r in report["admitted"]}
        check("C5.2 sub-batch union is exactly the admitted set",
              union == admitted_keys, f"union={union} admitted={admitted_keys}")
        check("C5.3 every sub-batch is diagnostic-only (publish_eligible False)",
              all(s["publish_eligible"] is False for s in subs), subs)
        check("C5.4 every sub-batch reserves a control slot",
              all(s["control_slots_reserved"] == 1 for s in subs), subs)
        check("C5.5 no sub-batch exceeds run_cap - control_slots (5)",
              all(len(s["members"]) <= 5 for s in subs),
              [len(s["members"]) for s in subs])
        check("C5.6 six members split into 2 sub-batches (5 + 1)",
              len(subs) == 2 and sorted(len(s["members"]) for s in subs) == [1, 5],
              [len(s["members"]) for s in subs])
        check("C5.7 the first sub-batch spans all three groups (round-robin interleave)",
              len({m["group"] for m in subs[0]["members"]}) == 3,
              subs[0]["members"])
        check("C5.8 partitioning does not change the full-set batchable count",
              report["batchable"] == 2, f"batchable={report['batchable']}")
        # Tighter run cap: 4 - 1 = 3 per sub-batch -> 2 sub-batches of 3.
        subs4 = cand.partition_sub_batches(report["admitted"], run_cap=4,
                                           control_slots=1)
        check("C5.9 run_cap=4/control_slots=1 gives two sub-batches of 3",
              len(subs4) == 2 and all(len(s["members"]) == 3 for s in subs4),
              [len(s["members"]) for s in subs4])
        conn.close()
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # C6: C4 server-side verification still applies to sub-batch
    # evidence; G6=0 means diagnostic-only; real READY stays BLOCKED.
    import receiver as _recv
    base = fresh_base()
    try:
        sha = "b" * 64

        def run_vp(rows, gen=0):
            manifest = {"pool_sha": sha, "generation": gen, "ttl": "2027-01-01",
                        "cap": 6, "status": "PROBATION",
                        "entries": [{"key": "vmess|203.0.113.10|443", "name": "试用-甲",
                                     "source_group": "G-chenzhihan"}]}
            man_path = str(base / "vp-c-manifest.json")
            db_path = str(base / "vp-c-db.sqlite3")
            for p in (man_path, db_path):
                if os.path.exists(p):
                    os.remove(p)
            with open(man_path, "w", encoding="utf-8") as f:
                json.dump(manifest, f, ensure_ascii=False, indent=2)
            _recv.initialize_db(db_path)
            c = sqlite3.connect(db_path)
            t0 = NOW - 7200
            for i, (cv, ts) in enumerate(rows):
                nonce = secrets.token_hex(16)
                c.execute("INSERT INTO batches (nonce, received_at, payload_sha) VALUES(?,?,?)",
                          (nonce, ts, sha))
                c.execute("INSERT INTO phone_observations (nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified,trial_generation,dual_target_ok) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                          (nonce, "vmess", "203.0.113.10", 443, "success", "external_policy_id", 1, ts, "cellular", sha, "target_reachable", "success", "target_reachable", cv, gen, 1))
            c.commit()
            c.close()
            env = dict(os.environ)
            env.update({"PHONE_PROBE_MANIFEST": man_path, "PHONE_PROBE_DB": db_path})
            return subprocess.run([sys.executable, str(SRC / "verify_promotion.py")],
                                  env=env, capture_output=True, text=True, timeout=30)

        t0 = NOW - 7200
        out = run_vp([(0, t0), (0, t0 + 1200), (0, t0 + 2400)])
        check("C6.1 sub-batch successes without a control: DIAGNOSTIC_PASS only (G6=0)",
              "diagnostic=DIAGNOSTIC_PASS" in out.stdout, out.stdout)
        check("C6.2 same run: real PHONE_EVIDENCE_READY stays BLOCKED",
              "-> PHONE_EVIDENCE_READY" not in out.stdout
              and "NOT_READY reason=NO_CONTROL_VERIFIED_SUCCESS" in out.stdout,
              out.stdout)
        out2 = run_vp([(0, t0), (0, t0 + 1200), (0, t0 + 2400), (1, t0 + 3600)])
        check("C6.3 with a control_verified success in the chain, C4 passes (PHONE_EVIDENCE_READY)",
              "-> PHONE_EVIDENCE_READY" in out2.stdout, out2.stdout)
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # C7: the CLI entry is read-only and matches the library computation.
    base = fresh_base()
    try:
        conn, dbp, started, fps = _build_candidate_db(base)
        reg, _ = _lr(str(base / "source_groups.json"))
        admission = {(k[0], k[1], k[2], fp): (True, "")
                     for k, fp in fps.items()}
        bad = ("trojan", "198.51.100.11", 443)
        admission[(bad[0], bad[1], bad[2], fps[bad])] = (False, "unsupported-transport")
        adm_path = str(base / "admission.json")
        with open(adm_path, "w", encoding="utf-8") as f:
            json.dump({"|".join([k[0], k[1], str(k[2]), k[3]]): {"ok": v[0], "reason": v[1]}
                       for k, v in admission.items()}, f)
        conn.close()
        import hashlib
        with open(dbp, "rb") as f:
            before = hashlib.sha256(f.read()).hexdigest()
        out = subprocess.run(
            [sys.executable, "-m", "pool.candidates",
             "--db", str(dbp), "--registry", str(base / "source_groups.json"),
             "--admission", adm_path, "--now", str(started + 60)],
            cwd=str(SRC), capture_output=True, text=True, timeout=30)
        with open(dbp, "rb") as f:
            after = hashlib.sha256(f.read()).hexdigest()
        check("C7.1 CLI exits 0 with valid JSON",
              out.returncode == 0, f"rc={out.returncode} err={out.stderr.strip()!r}")
        rep = json.loads(out.stdout) if out.returncode == 0 else {}
        check("C7.2 CLI batchable matches the library computation (1)",
              rep.get("batchable") == 1, f"batchable={rep.get('batchable')}")
        check("C7.3 CLI marks the admission-failed member excluded with its reason",
              any(r["host"] == "198.51.100.11"
                  and r["reason"] == "admission_unsupported-transport"
                  for r in rep.get("candidates", [])),
              rep.get("candidates"))
        check("C7.4 CLI left the DB byte-identical (read-only)",
              before == after, f"{before} vs {after}")
        check("C7.5 CLI sub-batches are diagnostic-only",
              all(s["publish_eligible"] is False
                  for s in rep.get("sub_batches", [])), rep.get("sub_batches"))
    finally:
        shutil.rmtree(base, ignore_errors=True)

    # C8: a DB without the batch schema (the live pre-migration shape)
    # must fail closed, not crash: zero batches, every source reports
    # schema_missing, CLI exits 0. Found by running the CLI against the
    # real snapshot copy (2026-11-24): compute_candidates raised
    # OperationalError on crawl_batches before this fix.
    base = fresh_base()
    try:
        dbp = str(base / "pool.db")
        conn = sqlite3.connect(dbp)
        conn.execute("CREATE TABLE nodes (protocol TEXT, host TEXT,"
                     " port INTEGER, source TEXT)")
        conn.execute("CREATE TABLE blocklist (protocol TEXT, host TEXT,"
                     " port INTEGER)")
        conn.commit()
        reg, _ = _lr(str(base / "source_groups.json"))
        rep = cand.compute_candidates(
            conn, reg, now=1700000000, ttl_s=86400)
        check("C8.1 no batch schema -> zero batches, no exception",
              rep.get("batchable") == 0 and rep.get("candidates") == [],
              f"batchable={rep.get('batchable')}")
        check("C8.2 every source reports schema_missing",
              all(s["consumable_reason"] == "schema_missing"
                  for s in rep.get("sources", {}).values())
              and len(rep.get("sources", {})) > 0,
              rep.get("sources"))
        conn.close()
        out = subprocess.run(
            [sys.executable, "-m", "pool.candidates",
             "--db", dbp, "--registry", str(base / "source_groups.json"),
             "--now", "1700000000"],
            cwd=str(SRC), capture_output=True, text=True, timeout=30)
        check("C8.3 CLI on a schema-less DB exits 0 with batchable 0",
              out.returncode == 0
              and json.loads(out.stdout).get("batchable") == 0,
              f"rc={out.returncode} err={out.stderr.strip()!r}")
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main():
    section_n()
    section_b()
    section_t()
    section_p()
    section_i()
    section_c()
    failed = [r for r in RESULTS if not r[1]]
    print("=" * 60)
    print("integration-04: %d passed, %d failed, %d total"
          % (len(RESULTS) - len(failed), len(failed), len(RESULTS)))
    for name, ok, detail in failed:
        print("FAILED: %s :: %s" % (name, detail))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
