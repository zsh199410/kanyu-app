# -*- coding: utf-8 -*-
"""Conservative rotation ledger handover for Surge #73.

Pure planning and an opt-in migration to the NEW writer's PRIVATE SQLite.
Never updates pool.db / published_first / winner_reports. Never grants
deletion eligibility. Its epoch captures historical first_published for
audit, but RESETS a separate protection_since timestamp at handover
to prevent a simultaneous wave of deletion eligibility after day one.

To preserve correctness across concurrent publishes, an eventual writable
reconciler must execute inside the same single_writer flock. It is NOT yet
connected to production_cycle; auto-clean remains disabled.
"""
from __future__ import annotations
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3

PIN_COUNT = 21
SCHEMA = """
CREATE TABLE IF NOT EXISTS rotation_ledger (
  node_digest TEXT PRIMARY KEY,
  legacy_first_published INTEGER,
  protection_since INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  origin TEXT NOT NULL,
  deletion_approved INTEGER NOT NULL DEFAULT 0 CHECK(deletion_approved=0)
);
CREATE TABLE IF NOT EXISTS rotation_ledger_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
"""


class LedgerRefused(ValueError):
    pass


def _node_id(key):
    if (not isinstance(key, tuple) or len(key) != 3 or
            not isinstance(key[0], str) or not isinstance(key[1], str) or
            type(key[2]) is not int or key[2] <= 0 or key[2] >= 65536):
        raise LedgerRefused("node_key_invalid")
    raw = json.dumps(list(key), ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def handover_plan(*, current_pool, db_snapshot, parse_fn, now):
    if (not isinstance(now, (int, float)) or isinstance(now, bool)
            or not math.isfinite(now) or now <= 0):
        raise LedgerRefused("invalid_handover_epoch")
    if not isinstance(current_pool, bytes) or not current_pool:
        raise LedgerRefused("invalid_pool")
    if not callable(parse_fn):
        raise LedgerRefused("parser_unavailable")
    try:
        lines = [line for line in current_pool.decode("utf-8").splitlines()
                 if line.strip() and not line.lstrip().startswith("#")]
    except UnicodeError as exc:
        raise LedgerRefused("invalid_pool_utf8") from exc
    if not lines:
        raise LedgerRefused("empty_pool")
    if not isinstance(db_snapshot, dict):
        raise LedgerRefused("missing_source_snapshot")
    pins = {k:name for k,name in db_snapshot["db_pins"].items()
            if k not in db_snapshot["blocked_keys"]}
    if len(pins) != PIN_COUNT or len(set(pins.values())) != PIN_COUNT:
        raise LedgerRefused("canonical_pins_not_21")
    blocked = set(db_snapshot["blocked_keys"])
    published = db_snapshot["first_published"]
    seen, pin_seen = set(), set()
    rows = []
    for line in lines:
        key = tuple(parse_fn(line))
        ident = _node_id(key)
        if ident in seen or key in blocked:
            raise LedgerRefused("duplicate_or_blocked_node")
        seen.add(ident)
        name = line.split("=", 1)[0].strip()
        if key in pins:
            if pins[key] != name:
                raise LedgerRefused("pin_name_mismatch")
            pin_seen.add(key)
            continue
        prior = published.get(key)
        if prior is not None and (
            type(prior) not in (int, float) or
            not math.isfinite(prior) or prior <= 0 or prior > now
        ):
            raise LedgerRefused("invalid_legacy_first_published")
        rows.append({
            "node_digest": ident,
            # Only private writer DB holds hashes and timestamps;
            # never print node names or network identifiers to GitHub.
            "legacy_first_published": int(prior) if prior is not None else None,
            "protection_since": int(now),
            "last_seen": int(now),
            "origin": "legacy_survivor",
            "deletion_approved": 0,
        })
    if pin_seen != set(pins):
        raise LedgerRefused("pinned_members_missing")
    return {
        "meta": {
            "source_pool_sha256": hashlib.sha256(current_pool).hexdigest(),
            "handover_epoch": int(now),
            "pin_count": PIN_COUNT,
            "rotation_count": len(rows),
            "legacy_history_count": sum(
                x["legacy_first_published"] is not None for x in rows),
            "deletion_allowed": False,
            "winner_clean_eligible": False,
        },
        "rows": rows,
    }


def public_summary(plan):
    meta = plan["meta"]
    return {k: meta[k] for k in (
        "pin_count", "rotation_count", "legacy_history_count",
        "deletion_allowed", "winner_clean_eligible"
    )} | {"decision": "LEDGER_HANDOVER_READ_ONLY_PLAN"}


def bootstrap_private_db(db_path, plan, *, approved=False):
    """Separate opt-in writer-DB bootstrap; NOT invoked by production_cycle.

    Never changes the legacy pool.db or a live subscriber file.
    Refuse existing ledger metadata; repeated/partial migrations must
    be reviewed rather than silently overwritten or reset.
    """
    if approved is not True:
        raise LedgerRefused("ledger_bootstrap_not_approved")
    p = Path(db_path)
    if not p.is_absolute() or p.is_symlink() or not p.parent.is_dir():
        raise LedgerRefused("invalid_private_db_location")
    if p.name == "pool.db" or "/free-node-program/" in str(p):
        raise LedgerRefused("legacy_db_path_forbidden")
    meta = plan["meta"]
    if meta["deletion_allowed"] is not False or meta["pin_count"] != 21:
        raise LedgerRefused("unsafe_ledger_plan")
    conn = sqlite3.connect(str(p), timeout=5.0)
    try:
        conn.execute("BEGIN IMMEDIATE")
        for statement in SCHEMA.split(";"):
            if statement.strip():
                conn.execute(statement)
        existing = conn.execute(
            "SELECT COUNT(*) FROM rotation_ledger_meta").fetchone()[0]
        if existing:
            raise LedgerRefused("ledger_already_initialized")
        for row in plan["rows"]:
            conn.execute(
                "INSERT INTO rotation_ledger "
                "(node_digest,legacy_first_published,protection_since,"
                "last_seen,origin,deletion_approved) VALUES (?,?,?,?,?,0)",
                (row["node_digest"],row["legacy_first_published"],
                 row["protection_since"],row["last_seen"],row["origin"])
            )
        for key,val in meta.items():
            conn.execute(
                "INSERT INTO rotation_ledger_meta(key,value) VALUES (?,?)",
                (key, json.dumps(val, ensure_ascii=False))
            )
        conn.commit()
        os.chmod(p, 0o600)
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()
    return public_summary(plan) | {"decision":"LEDGER_STAGED_AUTO_DELETE_OFF"}
