#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Surge #73: verified-source candidate cycle with HARD production gates.

Modes:
  --inspect-only: SQLite/pool preflight, no network or writes; exit 0/78.
  --preview: real installed pure-rule adapter + remote read-only crawl,
             no production writes; exit 0 on admitted no-op, 78 on any
             changed/unverified candidate or input anomaly.
  --publish (default): disabled unless signed-off release marker AND an
             explicit STOP/RUNNING file are present. At first rollout this
             MAY publish ONLY THE EXACT CURRENT BYTES. Future mutations
             require their own fully proven admission policy; do not
             pretend that changing a pool is automatically authorized.

Secrets: never log node names, URI, IP, passwords or whole source SHA.
No phone/API testing here. Only single_writer.publish can write served/
staging, under its existing flock, guard, ban proof and rollback.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import time

HERE = Path(__file__).resolve().parent


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, HERE / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_db = _load("pool_db_source.py", "surge_pool_db_source")
_contract = _load("candidate_contract.py", "surge_pool_candidate_contract")
_legacy = _load("legacy_source_adapter.py", "surge_legacy_adapter")
_sw = _load("single_writer.py", "surge_single_writer_cycle")


class CycleRefused(ValueError):
    pass


def _read_bytes(path):
    p = Path(path)
    if not p.is_absolute() or p.is_symlink() or not p.is_file():
        raise CycleRefused("unsafe_or_missing_input_file")
    size = p.stat().st_size
    if not 0 < size <= _contract.MAX_BYTES:
        raise CycleRefused("invalid_pool_size")
    raw = p.read_bytes()
    if not 0 < len(raw) <= _contract.MAX_BYTES:
        raise CycleRefused("invalid_pool_size")
    return raw


def _read_explicit_stop_state(path):
    """Unknown, missing, malformed and STOP all deny production."""
    p = Path(path)
    if not p.is_absolute() or p.is_symlink() or not p.is_file():
        raise CycleRefused("stop_state_unavailable")
    if p.stat().st_size > 128:
        raise CycleRefused("stop_state_malformed")
    state = p.read_text(encoding="utf-8").strip()
    if state != "RUNNING":
        raise CycleRefused("stop_or_unknown_state")
    return True


def _paths_from_env(env):
    return {
        "db": env.get("P2P3_POOL_DB", "/opt/free-node-program/data/pool.db"),
        "served": env.get("P2P3_POOL_SERVED",
                          "/opt/surge-bridge/modules/pool-new.txt"),
        "staging": env.get("P2P3_POOL_STAGING",
                           "/opt/free-node-program/publish/pool-new.txt"),
        "legacy_root": env.get("P2P3_LEGACY_ROOT", "/opt/free-node-program"),
        "stop": env.get("P2P3_STOP_STATE_FILE", ""),
        "lock": env.get("P2P3_WRITER_LOCK", "/opt/p2p3-single-writer/lock/pool.lock"),
        "writer_db": env.get("P2P3_WRITER_DB",
                             "/opt/p2p3-single-writer/pool.sqlite3"),
        "approval": env.get("P2P3_RELEASE_MARKER",
                            "/etc/p2p3-single-writer/release-ready"),
    }


def _preflight(db_path, served_path, staging_path):
    db = _db.read_db_snapshot(db_path)
    served = _read_bytes(served_path)
    staging = _read_bytes(staging_path)
    if served != staging:
        raise CycleRefused("served_staging_differ")
    pool = _contract._parse_pool(served)
    pins = {k: n for k, n in db["db_pins"].items()
            if k not in db["blocked_keys"]}
    if len(pins) != 21 or len(set(pins.values())) != 21:
        raise CycleRefused("canonical_pins_missing")
    if not set(pins.values()) <= pool.keys():
        raise CycleRefused("pinned_names_not_in_served")
    blocked_names = {n for k, n in db["db_pins"].items()
                     if k in db["blocked_keys"]}
    if blocked_names & pool.keys():
        raise CycleRefused("blocked_pins_reentered")
    return db, served, {
        "candidate_count": len(pool),
        "canonical_pin_count": 21,
        "served_staging_sha_equal": True,
        "sha_prefix": hashlib.sha256(served).hexdigest()[:12],
        "db_read_only": True,
        "production_changed": False,
    }


def inspect_live(db_path, served_path, staging_path):
    """Compatibility with existing read-only inspection tests."""
    _, _, meta = _preflight(db_path, served_path, staging_path)
    return {
        **meta,
        "source_adapter_verified": False,
        "decision": "CUTOVER_BLOCKED_GENERATOR_ADAPTER_NOT_READY",
    }


def _verify_pinned_keys(current, db, crawler):
    actual = {}
    for line in current.decode("utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        name, proto, host, port, valid = crawler.parse_surge_line(line)
        if not valid:
            raise CycleRefused("invalid_current_proxy_line")
        key = (proto, host, port)
        if key in actual:
            raise CycleRefused("duplicate_proxy_key")
        actual[key] = name
    protected = {k:n for k,n in db["db_pins"].items()
                 if k not in db["blocked_keys"]}
    if len(protected) != 21 or any(actual.get(k) != name
                                  for k, name in protected.items()):
        raise CycleRefused("pinned_identity_mismatch")
    if any(k in actual for k in db["blocked_keys"]):
        raise CycleRefused("blocked_proxy_reentered")
    return list(protected.values())


def build_preview(db, current, root, now):
    """Untrusted preview: produces data, not a publish permit."""
    crawler, rules, geo, winner = _legacy._load_installed_modules(root)
    pins = _verify_pinned_keys(current, db, crawler)
    preview = _legacy.make_preview(
        db_snapshot=db, current_pool=current, legacy_root=root,
        now=now, modules=(crawler, rules, geo, winner))
    candidate = preview["proposed_bytes"]
    if preview["canonical_pin_count"] != 21:
        raise CycleRefused("pin_count_mismatch")
    # This strict contract refuses any missing/modified old member.
    # Until F native evidence is calibrated, even legacy VPS-based
    # pruning is not automatically allowed to remove existing nodes.
    try:
        admission = _contract.assess_candidate(
            current, candidate, pins,
            blocklisted_names=[n for k,n in db["db_pins"].items()
                               if k in db["blocked_keys"]],
            generator_verified=False,
        )
    except ValueError as exc:
        return preview, {
            "decision": "HOLD_UNVERIFIED_CHANGE",
            "reason": str(exc),
            "production_write_authorized": False,
            "production_delete_authorized": False,
            "candidate_count": len(_contract._parse_pool(current)),
        }
    return preview, admission


def _check_release_marker(path, env):
    if env.get("P2P3_ENABLE_PRODUCTION") != "YES_EXPLICITLY":
        raise CycleRefused("production_not_enabled")
    p = Path(path)
    if not p.is_absolute() or p.is_symlink() or not p.is_file():
        raise CycleRefused("release_marker_missing")
    if p.stat().st_size > 1024 or p.read_text(encoding="utf-8").strip() != "PR93_APPROVED_SAME_BYTES_ONLY":
        raise CycleRefused("release_marker_malformed")
    return True


def run_cycle(*, env=None, mode="inspect-only", now=None, publisher=None,
              previewer=None):
    env = os.environ if env is None else env
    cfg = _paths_from_env(env)
    if mode not in ("inspect-only", "preview", "publish"):
        raise CycleRefused("invalid_mode")
    if mode == "publish":
        # Fail before any external requests when release is not enabled.
        _check_release_marker(cfg["approval"], env)
        _read_explicit_stop_state(cfg["stop"])
    db, served, meta = _preflight(cfg["db"], cfg["served"], cfg["staging"])
    if mode == "inspect-only":
        return {**meta, "decision": "INSPECT_ONLY", "ok": True}
    timestamp = time.time() if now is None else now
    try:
        if previewer is None:
            preview, admission = build_preview(
                db, served, cfg["legacy_root"], timestamp)
        else:
            preview, admission = previewer(
                db, served, cfg["legacy_root"], timestamp)
    except (ValueError, OSError, TypeError, ImportError, AttributeError) as exc:
        raise CycleRefused("generator_refused") from exc

    if (preview.get("production_write_authorized") is True or
            admission.get("production_delete_authorized") is True):
        raise CycleRefused("unsafe_candidate_claim")
    status = {
        **meta,
        "new_candidate_count": preview.get("proposed_count"),
        "preview_matches_current": preview.get("proposed_bytes") == served,
        "admission_decision": admission["decision"],
        "production_changed": False,
    }
    if admission["decision"] != "HOLD_NO_CHANGE":
        return {**status, "decision": "HOLD_UNVERIFIED_CHANGE",
                "ok": mode == "preview"}
    if mode == "preview":
        return {**status, "decision": "PREVIEW_ONLY", "ok": True}
    # Production same-byte only. Independently authorized by release marker,
    # STOP state and real legacy bans. The structural contract intentionally
    # never grants write authority itself.
    if preview["proposed_bytes"] != served:
        raise CycleRefused("same_byte_only_violation")
    fn = _sw.publish if publisher is None else publisher
    receipt = fn(
        lock_path=cfg["lock"], served_path=cfg["served"],
        staging_path=cfg["staging"], candidate_bytes=served,
        expected_current_sha=hashlib.sha256(served).hexdigest(),
        db_path=cfg["writer_db"],
        stop_check=lambda: not _stop_running(cfg["stop"]),
        lock_timeout=30.0,
    )
    # Fail closed on mismatch, never claim a successful publish.
    if not isinstance(receipt, dict) or receipt.get("ok") is not True:
        raise CycleRefused("writer_receipt_invalid")
    if (_read_bytes(cfg["served"]) != served or
            _read_bytes(cfg["staging"]) != served):
        raise CycleRefused("post_publish_sha_mismatch")
    return {**status, "decision": "SAME_BYTES_PUBLISHED",
            "ok": True, "production_changed": False,
            "writer_receipt_ok": receipt.get("ok") is True}


def _stop_running(path):
    try:
        return _read_explicit_stop_state(path)
    except (ValueError, OSError, UnicodeError):
        return False


def main(argv=None):
    p = argparse.ArgumentParser(description="Surge audited single-writer cycle")
    modes = p.add_mutually_exclusive_group()
    modes.add_argument("--inspect-only", action="store_true")
    modes.add_argument("--preview", action="store_true")
    modes.add_argument("--publish", action="store_true")
    args = p.parse_args(argv)
    mode = ("inspect-only" if args.inspect_only else "preview"
            if args.preview else "publish")
    try:
        result = run_cycle(mode=mode)
    except (CycleRefused, _db.SourceRefused, _sw.PublishRefused,
            ValueError, OSError, TypeError, UnicodeError):
        # Never include exception strings: they might hold node info.
        print('{"ok":false,"decision":"CUTOVER_BLOCKED_PREFLIGHT","production_changed":false}')
        return 78
    print(json.dumps(result, sort_keys=True, ensure_ascii=True))
    return 0 if result.get("ok") else 78


if __name__ == "__main__":
    sys.exit(main())
