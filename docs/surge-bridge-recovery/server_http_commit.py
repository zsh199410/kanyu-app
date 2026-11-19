# -*- coding: utf-8 -*-
"""C-round private server.py HTTP commit wrapper (NO live server).

The existing HTTP router MUST authenticate X-Dev-Token or X-Admin-Token,
hold the existing global lock, and serialize JSON before invoking a
handler below. These helpers contain no credentials, sockets or paths.
The existing atomic-save function is injected as persist(next_state).

IMPORTANT: a 503 means *confirmation unknown*, NOT proven rollback.
An fsync/rename could succeed before persist reports an exception.
Client must not re-run actions; it can only resend cached result
or query /receipt with server-side proof.
"""
from __future__ import annotations

from typing import Any

try:
    from mailbox_ack import (accept_result, accept_diagnostic,
                             issue_if_empty, receipt_status)
except ImportError as exc:
    raise RuntimeError("mailbox_protocol_not_importable") from exc


def _commit(current: dict, transition, posted: Any, *, now: float, persist):
    """Authenticated+locked caller -> status/body, commit before response."""
    if not callable(persist):
        return 503, {"ok": False, "accepted": False,
                     "error": "durable_store_unavailable",
                     "commit_state": "unknown"}
    updated, code, body, must_persist = transition(
        current, posted, now=now
    ) if transition is not issue_if_empty else issue_if_empty(current, posted)
    if not must_persist:
        return code, body
    try:
        # The private original must atomically save and fsync (or have an
        # audited durable atomic-save guarantee) BEFORE returning.
        persisted = persist(updated)
        if persisted is False:
            raise OSError("durable_store_refused")
    except Exception:
        # No exception contents on wire or public logs.
        return 503, {"ok": False, "accepted": False,
                     "error": "durable_commit_failed",
                     "commit_state": "unknown"}
    return code, body


def post_result(state: dict, posted: Any, *, now: float, persist):
    return _commit(state, accept_result, posted, now=now, persist=persist)


def post_diagnostic(state: dict, posted: Any, *, now: float, persist):
    return _commit(state, accept_diagnostic, posted, now=now, persist=persist)


def post_issue(state: dict, posted: Any, *, now: float, persist):
    return _commit(state, issue_if_empty, posted, now=now, persist=persist)


def get_receipt(state: dict, command_id: int):
    # No persistence, no command changes.
    return receipt_status(state, command_id)
