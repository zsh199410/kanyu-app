#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only SQLite schema probe for Issue #73 pure candidate generator port.

Prints ONLY table/column/index names and type metadata. Never selects
or emits node rows, proxy URI, passwords, tokens, database paths, or
source content. Use from a trusted machine with the existing live DB
while legacy services remain running; no write/migration/PRAGMA WAL.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sqlite3
import sys
from urllib.parse import quote

MAX_TABLES = 100
MAX_COLUMNS = 120
ALLOWED = {"nodes", "sources", "node_tests", "pinned", "blocklist",
           "pinned_nodes", "blocked_nodes", "publish_log",
           "crawl_log", "test_log", "source_health"}


def inspect_schema(path):
    if not isinstance(path, (str, Path)):
        raise ValueError("bad_db_path")
    p = Path(path)
    if not p.is_file() or not p.is_absolute():
        raise ValueError("db_not_found_or_relative")
    uri = "file:" + quote(str(p.resolve()), safe="/") + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=3.0)
    try:
        conn.execute("PRAGMA query_only = ON")
        conn.execute("BEGIN")
        table_names = [
            r[0] for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        ]
        if len(table_names) > MAX_TABLES:
            raise ValueError("too_many_tables")
        tables = []
        for name in table_names:
            if name not in ALLOWED:
                # No details from unrelated/private tables.
                continue
            escaped = name.replace('"', '""')
            cols = conn.execute('PRAGMA table_info("' + escaped + '")').fetchall()
            if len(cols) > MAX_COLUMNS:
                raise ValueError("too_many_columns")
            tables.append({
                "table": name,
                "columns": [{"name": c[1], "type": c[2],
                             "not_null": bool(c[3]), "pk": bool(c[5])}
                            for c in cols],
            })
        conn.rollback()
        return {"schema_probe": 1,
                "table_count_total": len(table_names),
                "known_tables": tables,
                "data_rows_read": 0,
                "read_only": True,
                "production_modified": False}
    finally:
        conn.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description="Sensitive-data-safe DB schema probe")
    parser.add_argument("--db", required=True)
    args = parser.parse_args(argv)
    try:
        report = inspect_schema(args.db)
    except (ValueError, sqlite3.Error, OSError):
        # No exception details: they may contain DB path/source URI.
        print('{"ok":false,"reason":"schema_probe_failed"}')
        return 2
    print(json.dumps(report, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
