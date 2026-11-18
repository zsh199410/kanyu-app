"""Fail-closed selector state persistence (A3).

Pure stdlib. State JSON file read/write with atomic tmp+rename.
A loaded state is NEVER trusted as verified: loading always marks it
unverified (``verified=False``, ``needs_revalidation=True``) until the
controller re-reads the live selection from the device and confirms it.
"""

from __future__ import annotations

import json
import os
import tempfile
import time

STATE_VERSION = 1

# States the controller can persist. See selector-controller.py for the
# meaning of each state.
STATES = (
    "REJECT_VERIFIED",
    "PROXY_VERIFIED",
    "EVIDENCE_EXPIRED",
    "VERSION_MISMATCH",
    "SELECTION_UNKNOWN",
    "CONTROLLER_UNAVAILABLE",
    "STOPPED",
)

# States in which production traffic must NOT be allowed through the
# test egress group.
NON_PRODUCTION_STATES = frozenset(
    {
        "EVIDENCE_EXPIRED",
        "VERSION_MISMATCH",
        "SELECTION_UNKNOWN",
        "CONTROLLER_UNAVAILABLE",
        "STOPPED",
    }
)


def new_state(
    state: str,
    *,
    group_name: str = "测试安全出口",
    selected_policy: str | None = None,
    candidate_sha: str | None = None,
    evidence_ts: float | None = None,
    ttl_seconds: int = 3600,
    verified: bool = False,
    reason: str = "",
    now: float | None = None,
) -> dict:
    """Build a state record. ``verified`` must only be True when the live
    selection was just read back from the device in this process run."""
    if state not in STATES:
        raise ValueError(f"unknown selector state: {state!r}")
    ts = time.time() if now is None else now
    return {
        "version": STATE_VERSION,
        "state": state,
        "group_name": group_name,
        "selected_policy": selected_policy,
        "candidate_sha": candidate_sha,
        "evidence_ts": evidence_ts,
        "ttl_seconds": ttl_seconds,
        "verified": bool(verified),
        "needs_revalidation": not bool(verified),
        "reason": reason,
        "updated_at": ts,
    }


def is_expired(record: dict, now: float | None = None) -> bool:
    """True when the record's evidence is older than its TTL.

    A record with no ``evidence_ts`` is treated as expired: no evidence,
    no trust.
    """
    if record is None:
        return True
    ts = record.get("evidence_ts")
    if ts is None:
        return True
    ttl = record.get("ttl_seconds", 3600)
    now = time.time() if now is None else now
    return (now - float(ts)) > float(ttl)


def save_state(path: str, record: dict) -> str:
    """Atomically write ``record`` as JSON to ``path`` (tmp file in the
    same directory + os.replace, fsync before rename)."""
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        dir=directory, prefix=".selector-state-", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(record, fh, ensure_ascii=False, sort_keys=True, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path, path)
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return path


def load_state(path: str, now: float | None = None) -> dict | None:
    """Load a persisted state record.

    The returned record is ALWAYS marked unverified, even if it was saved
    as verified: a restart / reload must not trust a previous run's
    verification. The caller must re-read the live device selection
    (GET /v1/policy_groups/select) before setting ``verified=True`` again.
    An expired record is additionally re-labelled EVIDENCE_EXPIRED.
    Returns None when no state file exists.
    """
    try:
        with open(path, "r", encoding="utf-8") as fh:
            record = json.load(fh)
    except FileNotFoundError:
        return None
    if not isinstance(record, dict) or record.get("version") != STATE_VERSION:
        return {
            "version": STATE_VERSION,
            "state": "SELECTION_UNKNOWN",
            "group_name": "测试安全出口",
            "selected_policy": None,
            "candidate_sha": None,
            "evidence_ts": None,
            "ttl_seconds": 3600,
            "verified": False,
            "needs_revalidation": True,
            "reason": "persisted state unreadable or wrong version; treated as unknown",
            "updated_at": time.time() if now is None else now,
        }
    record = dict(record)
    # Old state is never trusted on load.
    record["verified"] = False
    record["needs_revalidation"] = True
    if is_expired(record, now=now):
        record["state"] = "EVIDENCE_EXPIRED"
        record["reason"] = (
            (record.get("reason") or "")
            + " | evidence expired on load (TTL exceeded)"
        ).strip(" |")
    return record


def allow_production(record: dict | None) -> bool:
    """Only a freshly verified PROXY_VERIFIED record allows production
    traffic through the test egress group."""
    if not record:
        return False
    return (
        record.get("state") == "PROXY_VERIFIED"
        and bool(record.get("verified"))
        and not is_expired(record)
    )
