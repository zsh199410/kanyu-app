# -*- coding: utf-8 -*-
"""Drop-in pure mailbox transitions for an authenticated private server.py.

CURRENT server.py only has a single cmd and single result; its legacy
/result always says 200 ok:true even for mismatched IDs, and overwrites
result slot. That is NOT a verified ACK. These transitions are a proposed
patch for its existing per-request global lock and atomic-save handler,
NOT a complete standalone web server.

Authentication MUST remain checked by server.py BEFORE calling them.
Caller MUST commit the returned next_state atomically before sending 200.
No function here sends commands or modifies a phone.
"""
from __future__ import annotations

from copy import deepcopy
import json
from typing import Any

MAX_RESULT_BYTES = 8192
ALLOWED_DIAG = frozenset({
    "LEGACY_CHECKPOINT_INVALID", "LEGACY_PENDING_FENCED",
    "LEDGER_CORRUPT", "PENDING_ID_MISMATCH", "OUTCOME_UNKNOWN",
    "RESULT_DELIVERY_UNKNOWN", "ACK_UNVERIFIED", "DUPLICATE_OR_FENCED",
    "MALFORMED_COMMAND", "INVALID_RESULT", "RESULT_NOT_DURABLE",
    "PENDING_WITHOUT_COMMAND", "RECEIPT_RECONCILED",
})


def _valid_id(v):
    return type(v) is int and 0 < v <= 2**53 - 1


def _encoded(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False)


def accept_result(state: dict, posted: Any, *, now: float):
    """Return (new_state, HTTP_status, response, should_save).

    A result is accepted only if it matches a pending command's ID.
    Repeated byte/semantic-identical result for the *last accepted ID*
    is ACKed without mutating state. Stale or conflicting results cannot
    erase another pending command or overwrite the single result slot.
    """
    if not isinstance(state, dict) or not isinstance(posted, dict):
        return state, 400, {"ok": False, "error": "invalid_result"}, False
    id_ = posted.get("id")
    if not _valid_id(id_) or not isinstance(posted.get("outputs"), list):
        return state, 400, {"ok": False, "error": "invalid_result"}, False
    if len(posted["outputs"]) > 64:
        return state, 413, {"ok": False, "error": "result_too_large"}, False
    try:
        encoded = _encoded(posted)
    except (TypeError, ValueError):
        return state, 400, {"ok": False, "error": "invalid_result"}, False
    if len(encoded.encode("utf-8")) > MAX_RESULT_BYTES:
        return state, 413, {"ok": False, "error": "result_too_large"}, False

    pending = state.get("cmd")
    if isinstance(pending, dict) and pending.get("id") == id_:
        updated = deepcopy(state)
        updated["result"] = {"at": float(now), "data": deepcopy(posted)}
        updated["cmd"] = None
        # Caller must persist updated state before returning this ACK.
        return updated, 200, {
            "ok": True, "accepted": True, "acked_id": id_}, True

    previous = state.get("result")
    if pending is None and isinstance(previous, dict):
        prev_data = previous.get("data")
        try:
            same = (isinstance(prev_data, dict) and
                    prev_data.get("id") == id_ and
                    _encoded(prev_data) == encoded)
        except (TypeError, ValueError):
            same = False
        if same:
            return state, 200, {
                "ok": True, "accepted": True, "acked_id": id_,
                "duplicate": True}, False
    return state, 409, {
        "ok": False, "accepted": False,
        "error": "pending_id_or_result_mismatch"}, False


def accept_diagnostic(state: dict, posted: Any, *, now: float):
    """Store only bounded, nonsecret diagnostics; never clear cmd/result."""
    if not isinstance(state, dict) or not isinstance(posted, dict):
        return state, 400, {"ok": False}, False
    code=posted.get("code")
    cmd=posted.get("command_id")
    legacy=posted.get("legacy_last_id")
    phase=posted.get("phase")
    if (code not in ALLOWED_DIAG or
            not type(cmd) is int or not 0 <= cmd <= 2**53-1 or
            not type(legacy) is int or not 0 <= legacy <= 2**53-1 or
            phase not in ("none", "in_progress", "result_ready")):
        return state, 400, {"ok": False}, False
    updated=deepcopy(state)
    previous=updated.get("bridge_diagnostic")
    n=(previous.get("count",0) if isinstance(previous,dict) else 0)
    updated["bridge_diagnostic"]={
        "at":float(now), "code":code, "command_id":cmd,
        "legacy_last_id":legacy, "phase":phase, "count":min(n+1,999999)
    }
    # No cmd/result/last_poll/polls changes, no execution effect.
    return updated, 200, {"ok": True, "diagnostic_stored": True}, True


def issue_if_empty(state: dict, command: Any):
    """Optional admin-side hardening: never overwrite an active mailbox."""
    if not isinstance(command,dict) or not _valid_id(command.get("id")):
        return state,400,{"ok":False,"error":"invalid_command"},False
    if state.get("cmd") is not None:
        return state,409,{"ok":False,"error":"pending_command_exists"},False
    old_result=state.get("result")
    if (isinstance(old_result,dict) and
            isinstance(old_result.get("data"),dict) and
            command["id"] <= old_result["data"].get("id",0)):
        return state,409,{"ok":False,"error":"command_id_not_increasing"},False
    updated=deepcopy(state)
    updated["cmd"]=deepcopy(command)
    return updated,200,{"ok":True,"issued":True},True


def receipt_status(state: dict, command_id: int, posted_result: Any):
    """Read-only authenticated GET /receipt check, does NOT modify mailbox.

    A cached result can be confirmed after /result ACK was lost, even
    though the server has already removed cmd. A new pending command is
    NOT erased by this check.
    """
    if not isinstance(state, dict) or not _valid_id(command_id):
        return 400, {"confirmed": False}
    record=state.get("result")
    if not isinstance(record,dict) or not isinstance(record.get("data"),dict):
        return 200, {"confirmed":False}
    try:
        verified=(record["data"].get("id")==command_id and
                  _encoded(record["data"]) == _encoded(posted_result))
    except (ValueError,TypeError):
        verified=False
    return 200, {"confirmed":bool(verified)}
