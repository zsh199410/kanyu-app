# -*- coding: utf-8 -*-
"""Read-only pool.db adapter for the VERIFIED 2026-11-19 VPS table schema.

This adapter extracts only relevant selector inputs from a consistent
read-only SQLite transaction. No DB migrations, updates or logging.
It cannot reconstruct proxy credentials or crawl fresh remote records:
those require a separately audited pure port of legacy crawler/rules.
NEVER print the returned rows (IP/host and source-related private data).
"""
from __future__ import annotations

import math
from pathlib import Path
import sqlite3
from urllib.parse import quote

MAX_ROWS = 100000
REQUIRED_TABLES = {"nodes", "node_tests", "pinned", "blocklist"}


class SourceRefused(ValueError):
    pass


def _sqlite_readonly(path):
    p = Path(path)
    if not p.is_absolute() or not p.is_file():
        raise SourceRefused("invalid_or_missing_db")
    uri = "file:" + quote(str(p.resolve()), safe="/") + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=8.0)
    conn.execute("PRAGMA query_only=ON")
    conn.execute("BEGIN")
    return conn


def _rows(conn, sql):
    rows = conn.execute(sql).fetchmany(MAX_ROWS + 1)
    if len(rows) > MAX_ROWS:
        raise SourceRefused("excessive_db_rows")
    return rows


def _key(protocol, host, port):
    if (not isinstance(protocol, str) or not protocol or
            not isinstance(host, str) or not host or
            isinstance(port, bool) or not isinstance(port, int) or
            port <= 0 or port > 65535):
        raise SourceRefused("invalid_db_key")
    return protocol, host, port


def read_db_snapshot(path):
    """Return normalized rows, candidate metadata and DB config text.

    Includes real host identities in memory: treat output as SECRET.
    A caller must NOT log, serialize to GitHub, or print the snapshot.
    """
    conn = _sqlite_readonly(path)
    try:
        names = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        if not REQUIRED_TABLES <= names:
            raise SourceRefused("missing_required_tables")
        node_rows = []
        seen = set()
        for row in _rows(conn,
                         "SELECT protocol,host,port,pass_count,test_count,"
                         "first_seen,last_test_at,last_result FROM nodes"):
            k = _key(row[0], row[1], row[2])
            if k in seen:
                raise SourceRefused("duplicate_node_db_key")
            seen.add(k)
            node_rows.append({
                "key": k, "pass_count": row[3], "test_count": row[4],
                "first_seen": row[5], "last_test_at": row[6],
                "last_result": row[7]
            })
        # Most recent *passing* test per key, not most recent test of
        # any result. Exact legacy query semantics documented by Muse.
        tests = {}
        for row in _rows(conn,
                         "SELECT protocol,host,port,ms FROM ("
                         "SELECT protocol,host,port,ms,"
                         " ROW_NUMBER() OVER (PARTITION BY protocol,host,port"
                         " ORDER BY tested_at DESC, rowid DESC) AS rn"
                         " FROM node_tests WHERE result='pass')"
                         " WHERE rn=1"):
            k = _key(row[0], row[1], row[2])
            value = row[3]
            if type(value) not in (int, float) or not math.isfinite(value):
                raise SourceRefused("invalid_latest_pass_latency")
            tests[k] = value
        pins = {}
        for row in _rows(conn, "SELECT protocol,host,port,name FROM pinned"):
            k = _key(row[0], row[1], row[2])
            if k in pins:
                raise SourceRefused("duplicate_pin")
            pins[k] = row[3]
        blocked = set()
        for row in _rows(conn, "SELECT protocol,host,port FROM blocklist"):
            blocked.add(_key(*row))
        config = {}
        if "config" in names:
            for key, val in _rows(conn, "SELECT key,value FROM config"):
                if key in config:
                    raise SourceRefused("duplicate_config_key")
                # Values are raw TEXT. Parsing + YAML fallback belongs to
                # audited config adapter, not an invented interpretation.
                config[key] = val
        first_published = {}
        if "published_first" in names:
            for row in _rows(conn, "SELECT protocol,host,port,first_published FROM published_first"):
                first_published[_key(*row[:3])] = row[3]
        winner_reports = []
        if "winner_reports" in names:
            for ts, name in _rows(conn, "SELECT ts,name FROM winner_reports"):
                winner_reports.append((ts, name))
        return {
            "node_rows": node_rows,
            "latest_pass_ms": tests,
            "db_pins": pins,
            "blocked_keys": blocked,
            "config_raw": config,
            "first_published": first_published,
            "winner_reports": winner_reports,
            "db_read_only": True,
            "production_modified": False,
        }
    except sqlite3.Error as exc:
        raise SourceRefused("db_schema_or_query_mismatch") from exc
    finally:
        # Never COMMIT, even accidentally: rollback the read txn.
        try:
            conn.rollback()
        finally:
            conn.close()
