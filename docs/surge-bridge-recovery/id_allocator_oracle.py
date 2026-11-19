"""Isolation-only independent oracle for Issue #73 server-issued command IDs.

Not a drop-in HTTP handler, not approved for live server or phone.
No sockets, hostnames, tokens, paths, or real command body fixtures.
The caller MUST hold a serialized lock and persist the returned entire
state durably before any success response is sent.

An idempotency response proves issuance was committed, not execution.
"""
from __future__ import annotations

from copy import deepcopy
from hashlib import sha256
import json
import re
from typing import Any

MAX_SAFE = 2**53 - 1
MIN_MS = 10**12
MAX_MS_EXCLUSIVE = 10**13
MAX_KEYS = 1024
KEY_RE = re.compile(r"[A-Za-z0-9_-]{22,128}\Z")


def _int(value: Any) -> bool:
    return type(value) is int


def canonical_ms(raw: Any) -> int:
    """Canonical comparison only; never replace a legacy wire ID with it."""
    if not _int(raw):
        raise ValueError("id_type_invalid")
    if 1_000_000_000 <= raw < 10_000_000_000:
        return raw * 1000
    if MIN_MS <= raw < MAX_MS_EXCLUSIVE:
        return raw
    raise ValueError("id_unit_ambiguous")


def _digest(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=True, allow_nan=False,
                     sort_keys=True, separators=(",", ":"))
    return sha256(raw.encode("utf-8")).hexdigest()


def reject(code: str, status: int = 409):
    return None, status, {"ok": False, "error": code}, False


def plan_issue(state: Any, command: Any, *, request_key: Any, now_ms: Any):
    """(next_state|None, http_status, response, must_commit).

    Server-owned ID is attached to command only after all checks.
    Existing pending command is never modified on reject/replay paths.
    """
    if not isinstance(state, dict):
        return reject("invalid_state", 503)
    if not isinstance(command, dict) or "id" in command or not isinstance(command.get("actions"), list):
        return reject("invalid_new_command", 400)
    if not isinstance(request_key, str) or not KEY_RE.fullmatch(request_key):
        return reject("invalid_idempotency_key", 400)
    if not _int(now_ms) or not MIN_MS <= now_ms < MAX_MS_EXCLUSIVE or now_ms > MAX_SAFE:
        return reject("invalid_clock", 503)
    try:
        command_digest = _digest(command)
    except (TypeError, ValueError, OverflowError):
        return reject("invalid_new_command", 400)

    allocator = state.get("id_allocator")
    if not isinstance(allocator, dict) or set(allocator) != {"version", "last_id", "keys"}:
        return reject("allocator_uninitialized_or_corrupt", 503)
    if allocator.get("version") != 1 or not _int(allocator.get("last_id")):
        return reject("allocator_uninitialized_or_corrupt", 503)
    last = allocator["last_id"]
    if not MIN_MS <= last <= MAX_SAFE:
        return reject("allocator_uninitialized_or_corrupt", 503)
    keys = allocator.get("keys")
    if not isinstance(keys, dict) or len(keys) > MAX_KEYS:
        return reject("allocator_uninitialized_or_corrupt", 503)

    try:
        for slot in (state.get("cmd"), (state.get("result") or {}).get("data")):
            if slot is not None:
                if not isinstance(slot, dict) or canonical_ms(slot.get("id")) > last:
                    return reject("allocator_high_water_inconsistent", 503)
        for record in keys.values():
            if (not isinstance(record, dict) or set(record) != {"id", "digest"}
                    or not _int(record["id"]) or not MIN_MS <= record["id"] <= last
                    or not isinstance(record["digest"], str)
                    or not re.fullmatch(r"[a-f0-9]{64}", record["digest"])):
                return reject("allocator_history_corrupt", 503)
    except (TypeError, ValueError, AttributeError):
        return reject("allocator_high_water_inconsistent", 503)

    token_fingerprint = sha256(request_key.encode("utf-8")).hexdigest()
    existing = keys.get(token_fingerprint)
    # Replay lookup intentionally precedes pending check. No second write.
    if existing is not None:
        if existing["digest"] != command_digest:
            return reject("idempotency_key_conflict")
        return None, 200, {"ok": True, "issued": True,
                           "id": existing["id"], "duplicate": True}, False
    if state.get("cmd") is not None:
        return reject("pending_command_exists")
    if len(keys) == MAX_KEYS:
        return reject("idempotency_history_full", 503)

    candidate = max(now_ms, last + 1)
    if candidate > MAX_SAFE or candidate >= MAX_MS_EXCLUSIVE:
        return reject("id_space_exhausted", 503)
    updated = deepcopy(state)
    issued = deepcopy(command)
    issued["id"] = candidate
    updated["cmd"] = issued
    updated["id_allocator"]["last_id"] = candidate
    updated["id_allocator"]["keys"][token_fingerprint] = {
        "id": candidate, "digest": command_digest,
    }
    return updated, 200, {"ok": True, "issued": True,
                          "id": candidate}, True


def commit_issue(state: dict, command: dict, *, request_key: str, now_ms: int, persist):
    """Call only inside the private authenticated serialized handler."""
    next_state, status, response, write = plan_issue(
        state, command, request_key=request_key, now_ms=now_ms)
    if not write:
        return status, response
    if not callable(persist):
        return 503, {"ok": False, "error": "durable_store_unavailable",
                     "commit_state": "unknown"}
    try:
        if persist(next_state) is False:
            raise OSError("save_refused")
    except Exception:
        return 503, {"ok": False, "error": "durable_commit_failed",
                     "commit_state": "unknown"}
    return status, response
