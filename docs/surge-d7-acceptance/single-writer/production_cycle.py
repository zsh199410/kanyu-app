#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Conservative production-cycle preflight; source adapter NOT YET APPROVED.

The future single-writer timer points here, but this iteration never
publishes or modifies anything. It can inspect actual on-disk bytes and
SQLite schema read-only. It MUST exit nonzero when triggered by systemd,
until the audited legacy crawler/rules/winner-clean adapter and admission
policy have been implemented and tested against current VPS baselines.

Exit 78: not safe to activate replacement scheduler.
No network, no file writes, no API POST, no node URI output.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, HERE / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_db = _load("pool_db_source.py", "surge_pool_db_source")
_contract = _load("candidate_contract.py", "surge_pool_candidate_contract")


def _read_bytes(path):
    if not isinstance(path, (str, Path)) or not Path(path).is_absolute():
        raise ValueError("invalid_path")
    # Fail closed instead of accepting a symlink that could point at
    # another path if it is changed during inspection.
    p = Path(path)
    if p.is_symlink() or not p.is_file():
        raise ValueError("invalid_file_or_symlink")
    if p.stat().st_size > _contract.MAX_BYTES or p.stat().st_size == 0:
        raise ValueError("invalid_pool_size")
    return p.read_bytes()


def inspect_live(db_path, served_path, staging_path):
    """Read-only preflight; returns only safe counts and abbreviated SHA."""
    db = _db.read_db_snapshot(db_path)
    served, staging = _read_bytes(served_path), _read_bytes(staging_path)
    if served != staging:
        raise ValueError("served_staging_differ")
    parsed = _contract._parse_pool(served)
    pins = {k: name for k, name in db["db_pins"].items()
            if k not in db["blocked_keys"]}
    if len(pins) != _contract.EXPECTED_PIN_COUNT:
        raise ValueError("canonical_pin_count_not_21")
    # Pin identity must be proven from the actual trusted source before
    # a concrete release; name-only check can be preflight evidence only.
    if not set(pins.values()).issubset(parsed):
        raise ValueError("pinned_names_not_in_served")
    if any(n in parsed for n in (
            name for k, name in db["db_pins"].items()
            if k in db["blocked_keys"])):
        raise ValueError("blocked_pin_reentered")
    return {
        "candidate_count": len(parsed),
        "canonical_pin_count": len(pins),
        "served_staging_sha_equal": True,
        "sha_prefix": hashlib.sha256(served).hexdigest()[:12],
        "db_read_only": True,
        "production_changed": False,
        "source_adapter_verified": False,
        "decision": "CUTOVER_BLOCKED_GENERATOR_ADAPTER_NOT_READY",
    }


def main(argv=None):
    p = argparse.ArgumentParser(description="Surge read-only production preflight")
    p.add_argument("--inspect-only", action="store_true")
    args = p.parse_args(argv)
    db = os.environ.get("P2P3_POOL_DB", "/opt/free-node-program/data/pool.db")
    served = os.environ.get("P2P3_POOL_SERVED",
                            "/opt/surge-bridge/modules/pool-new.txt")
    staging = os.environ.get("P2P3_POOL_STAGING",
                             "/opt/free-node-program/publish/pool-new.txt")
    try:
        result = inspect_live(db, served, staging)
    except (OSError, ValueError, _db.SourceRefused, json.JSONDecodeError):
        print('{"ok":false,"decision":"CUTOVER_BLOCKED_PREFLIGHT","production_changed":false}')
        return 78
    # A read-only inspect command exits 0; triggering the production
    # service always exits 78 until the *real* adapter is ready.
    result["ok"] = bool(args.inspect_only)
    print(json.dumps(result, ensure_ascii=True, sort_keys=True))
    return 0 if args.inspect_only else 78


if __name__ == "__main__":
    sys.exit(main())
