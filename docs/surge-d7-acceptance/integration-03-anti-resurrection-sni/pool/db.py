"""SQLite 存储：只存身份与状态，绝不存密码、URI、UUID、密钥。"""

import json
import os
import sqlite3
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS nodes (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  source TEXT,
  name_hint TEXT,
  first_seen INTEGER,
  last_seen INTEGER,
  last_test_at INTEGER,
  last_result TEXT,
  last_reason TEXT,
  pass_count INTEGER DEFAULT 0,
  test_count INTEGER DEFAULT 0,
  country TEXT,
  status TEXT DEFAULT 'candidate',
  PRIMARY KEY (protocol, host, port)
);
CREATE TABLE IF NOT EXISTS sources (
  name TEXT PRIMARY KEY,
  url TEXT,
  last_success INTEGER,
  last_count INTEGER DEFAULT 0,
  ok_count INTEGER DEFAULT 0,
  fail_count INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  started INTEGER,
  finished INTEGER,
  counts TEXT,
  ok INTEGER DEFAULT 1,
  error TEXT
);
CREATE TABLE IF NOT EXISTS node_tests (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  tested_at INTEGER,
  result TEXT,
  reason TEXT,
  ms REAL
);
CREATE TABLE IF NOT EXISTS pinned (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  name TEXT,
  created INTEGER,
  by TEXT,
  PRIMARY KEY (protocol, host, port)
);
CREATE TABLE IF NOT EXISTS blocklist (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  reason TEXT,
  created INTEGER,
  by TEXT,
  PRIMARY KEY (protocol, host, port)
);
CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS audit (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER,
  actor TEXT,
  action TEXT,
  detail TEXT
);
CREATE TABLE IF NOT EXISTS winner_reports (
  ts INTEGER NOT NULL,
  name TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS published_first (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  first_published INTEGER NOT NULL,
  PRIMARY KEY (protocol, host, port)
);
CREATE INDEX IF NOT EXISTS idx_winner_ts ON winner_reports (ts);
CREATE INDEX IF NOT EXISTS idx_tests_key ON node_tests (protocol, host, port, tested_at);
CREATE INDEX IF NOT EXISTS idx_runs_kind ON runs (kind, started);
"""


def connect(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript(SCHEMA)
    db.commit()
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return db


def upsert_node(db, protocol, host, port, source, name_hint):
    now = int(time.time())
    db.execute(
        """INSERT INTO nodes
           (protocol, host, port, source, name_hint, first_seen, last_seen)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT (protocol, host, port) DO UPDATE SET
             source=excluded.source, name_hint=excluded.name_hint,
             last_seen=excluded.last_seen""",
        (protocol, host, port, source, name_hint or "", now, now),
    )


def record_test(db, protocol, host, port, result, reason, ms):
    now = int(time.time())
    db.execute(
        "INSERT INTO node_tests VALUES (?, ?, ?, ?, ?, ?, ?)",
        (protocol, host, port, now, result, reason or "", ms),
    )
    row = db.execute(
        "SELECT pass_count, test_count FROM nodes WHERE protocol=? AND host=? AND port=?",
        (protocol, host, port),
    ).fetchone()
    if row is None:
        db.execute(
            """INSERT INTO nodes
               (protocol, host, port, first_seen, last_seen, last_test_at,
                last_result, last_reason, pass_count, test_count)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (protocol, host, port, now, now, now, result, reason or "",
             1 if result == "pass" else 0, 0 if result in ("infra", "filtered") else 1),
        )
    elif result in ("infra", "filtered"):
        # 基础设施/过滤不是节点本身的失败：不计入通过率，只更新最近一次结果。
        db.execute(
            """UPDATE nodes SET last_test_at=?, last_result=?, last_reason=?, last_seen=?
               WHERE protocol=? AND host=? AND port=?""",
            (now, result, reason or "", now, protocol, host, port),
        )
    else:
        db.execute(
            """UPDATE nodes SET last_test_at=?, last_result=?, last_reason=?,
               pass_count=pass_count+?, test_count=test_count+1, last_seen=?
               WHERE protocol=? AND host=? AND port=?""",
            (now, result, reason or "", 1 if result == "pass" else 0, now,
             protocol, host, port),
        )


def log_run(db, kind, started, counts, ok=True, error=""):
    db.execute(
        "INSERT INTO runs (kind, started, finished, counts, ok, error) VALUES (?, ?, ?, ?, ?, ?)",
        (kind, started, int(time.time()), json.dumps(counts, ensure_ascii=False),
         1 if ok else 0, error or ""),
    )
    db.commit()


def log_audit(db, actor, action, detail):
    db.execute(
        "INSERT INTO audit (at, actor, action, detail) VALUES (?, ?, ?, ?)",
        (int(time.time()), actor, action,
         json.dumps(detail, ensure_ascii=False) if not isinstance(detail, str) else detail),
    )
    db.commit()


def get_pinned(db):
    return db.execute("SELECT protocol, host, port, name FROM pinned ORDER BY rowid").fetchall()


def get_blocked(db):
    rows = db.execute("SELECT protocol, host, port FROM blocklist").fetchall()
    return {(r[0], r[1], r[2]) for r in rows}


def get_config(db, key, default=None):
    row = db.execute("SELECT value FROM config WHERE key=?", (key,)).fetchone()
    if row is None:
        return default
    try:
        return json.loads(row[0])
    except (ValueError, TypeError):
        return row[0]


def set_config(db, key, value):
    db.execute(
        "INSERT INTO config (key, value) VALUES (?, ?) "
        "ON CONFLICT (key) DO UPDATE SET value=excluded.value",
        (key, json.dumps(value, ensure_ascii=False)),
    )
    db.commit()


def prune_old(db, days=30):
    cutoff = int(time.time()) - days * 86400
    db.execute("DELETE FROM node_tests WHERE tested_at < ?", (cutoff,))
    db.execute("DELETE FROM runs WHERE started < ?", (cutoff,))
    db.execute("DELETE FROM audit WHERE at < ?", (cutoff,))
    db.commit()
