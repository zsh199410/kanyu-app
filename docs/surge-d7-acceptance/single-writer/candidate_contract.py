# -*- coding: utf-8 -*-
"""Pure, fail-closed candidate pre-admission contract for Surge Issue #73.

No network, DB or filesystem writes. This validates a *candidate payload*,
not the trustworthiness of the unknown legacy pool generator. Unless the
legacy algorithm and its proof have been ported and independently verified,
the only accepted candidate is an exact byte-for-byte carry-forward. This
module NEVER authorizes production publication on its own.

Caller must independently verify SOURCE/DB integrity, single-writer
guard/STOP, phone-loaded proof where relevant, and fresh backups.
"""
from __future__ import annotations

import hashlib

EXPECTED_PIN_COUNT = 21
MAX_BYTES = 2 * 1024 * 1024


def _parse_pool(raw: bytes) -> dict:
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_BYTES:
        raise ValueError("invalid_payload_size_or_type")
    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise ValueError("invalid_utf8") from exc
    names = {}
    for line in text.splitlines():
        # A pool file is a list of named proxy declarations, never a full
        # Surge configuration or policy/rules file.
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("not_a_proxy_declaration")
        name, sep, definition = line.partition("=")
        name, definition = name.strip(), definition.strip()
        if not name or not definition or name in names:
            raise ValueError("invalid_or_duplicate_node_name")
        if name in ("DIRECT", "REJECT") or definition.upper() in ("DIRECT", "REJECT"):
            raise ValueError("not_a_proxy_declaration")
        if "," not in definition:
            raise ValueError("not_a_proxy_declaration")
        names[name] = line
    if not names:
        raise ValueError("empty_node_pool")
    return names


def assess_candidate(current: bytes, candidate: bytes, canonical_pins,
                     blocklisted_names=(), *, generator_verified=False):
    """Evaluate a pure candidate, fail-closed where source proof is missing.

    Even generator_verified=True is NOT a production permit. It only
    enables consideration of additions/rotation for a future independent
    F/G candidate-source/URL fingerprint verifier. No production authorizing
    fields are ever set True in this contract.
    """
    original = _parse_pool(current)
    proposed = _parse_pool(candidate)
    if not isinstance(canonical_pins, (list, tuple)) or any(
        not isinstance(n, str) or not n for n in canonical_pins
    ):
        raise ValueError("invalid_canonical_pins")
    if len(canonical_pins) != EXPECTED_PIN_COUNT or len(set(canonical_pins)) != EXPECTED_PIN_COUNT:
        raise ValueError("canonical_pin_count_not_21")
    if not isinstance(blocklisted_names, (list, tuple, set)):
        raise ValueError("invalid_blocklist")
    blocked = set(blocklisted_names)
    if not all(isinstance(n, str) and n for n in blocked):
        raise ValueError("invalid_blocklist")
    pins = set(canonical_pins)
    if pins & blocked:
        raise ValueError("blocked_pin_conflict")
    if not pins <= original.keys():
        raise ValueError("missing_pins_in_current_pool")
    if not pins <= proposed.keys():
        raise ValueError("missing_pins_in_candidate")
    if any(original[n] != proposed[n] for n in pins):
        raise ValueError("pinned_definition_modified")
    if blocked & proposed.keys():
        raise ValueError("blocklisted_node_present")

    removed = sorted(original.keys() - proposed.keys())
    modified = sorted(n for n in original.keys() & proposed.keys()
                      if original[n] != proposed[n])
    added = sorted(proposed.keys() - original.keys())

    # Current F waiver is not calibration. Deletions, silent credential
    # replacement and generated additions cannot become valid just because
    # a JSON input claims the producer is "verified".
    if removed:
        raise ValueError("automatic_removal_not_authorized")
    if modified:
        raise ValueError("existing_definition_changed")
    if added and not generator_verified:
        raise ValueError("unverified_new_nodes")
    if len(added) > 4:
        raise ValueError("new_node_cap_exceeded")

    # A proof of source trust/usable probes is NOT implemented here.
    # Accept additions as a structural candidate preview only, never as
    # an executable production release authorization.
    identical = current == candidate
    return {
        "decision": ("HOLD_NO_CHANGE" if identical else
                     "REVIEW_GENERATED_CHANGES"),
        "candidate_count": len(proposed),
        "pin_count": len(pins),
        "added_count": len(added),
        "removed_count": 0,
        "modified_count": 0,
        "candidate_sha256": hashlib.sha256(candidate).hexdigest(),
        "identical_bytes": identical,
        "source_independently_verified": False,
        "production_write_authorized": False,
        "production_delete_authorized": False,
    }
