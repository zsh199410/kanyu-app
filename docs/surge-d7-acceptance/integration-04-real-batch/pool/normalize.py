#!/usr/bin/env python3
"""Shared field-normalization contract (integration-04, Review 6034205305
point 1 / Review 6034204978 point 1).

ONE contract for the admission gate (lineage_adapter), pre_filter
(rules), _filter_reason / build_config (tester) and build_surge_line
(rules). Before this module the four gates disagreed:

  * trojan t_type / ss method: the gate lowercased, pre_filter and the
    tester compared case-sensitively. A trojan URI with type=WS was
    admitted to lineage but refused from publish.
  * vmess net: the gate did not strip, pre_filter did not strip, the
    parser lowercased without stripping -- " ws " was refused by all
    three, but for three different unstated reasons.
  * password: pre_filter / build_surge_line rejected ANY "," (B10),
    the tester only rejected ", " (comma+space) and reported it as
    "bad-password" instead of "comma-password".
  * vmess uuid: pre_filter / build_surge_line checked comma + format,
    the tester checked neither (only "missing").

Contract (the only normalization this module ever performs):

  * ENUM fields (vmess net, trojan t_type, ss method): strip surrounding
    ASCII whitespace and lowercase. These tokens are defined by the
    protocol as case-insensitive identifiers; the parser already
    lowercases vmess net and ss method, so stripping + lowercasing only
    makes the established equivalence explicit and identical in all
    four gates. A token that strips to a KNOWN value is that value.
    A token that is a well-formed non-empty token but NOT known
    ("grpc", "tcp,udp", "made-up-method") is kept verbatim (lowercased)
    and reported as "unknown" -- the gates reject it with the existing
    reason ("unsupported-transport" / "ss-method"); nothing is folded
    into tcp. A value that is not a string, is whitespace-only, or
    contains internal whitespace / control characters is "invalid" and
    is rejected the same way. Empty / missing transport defaults to
    "tcp" (the parser's long-standing default); an empty ss method is
    "invalid" (there is no default method).
  * AUTH fields (password, uuid): NEVER normalized. Passwords and uuids
    are compared verbatim. Only the CHECK is shared: any "," anywhere
    -> "comma-password" / "comma-uuid"; leading/trailing whitespace on
    a password -> "bad-password"; a uuid must match the 8-4-4-4-12 hex
    shape (is_valid_uuid, moved here from rules.py; shape-only, no
    version/variant policing). Nothing is truncated, replaced or
    rewritten, and no credential value is ever returned in a reason
    detail (details carry only the fixed reason words).
  * vmess security: NOT normalized (D2, frozen). It is kept verbatim
    and the gate still checks membership case-sensitively; the tester
    still folds unknown values to "auto". That divergence is documented
    in the O1 matrix and is NOT part of this contract.
  * SNI / ws_path / ws_host / host: not normalized here. SNI is
    validated strictly by #128 N3 (blocklist_common); host is
    lowercased + stripped by the parser on both entry paths.

Uncertain -> refuse admission: any "unknown" or "invalid" enum, any
comma / whitespace password, any malformed uuid is refused by every
gate that checks it. The gates never guess an equivalence the protocol
does not define.

This module is pure (no imports from pool, no I/O, no secrets).
"""
import re

# ---------------------------------------------------------------------------
# Enum tokens: transport (vmess net / trojan t_type) and ss method
# ---------------------------------------------------------------------------

_TRANSPORT_OK = frozenset({"tcp", "ws"})
_WS = re.compile(r"\s")
_CTRL = re.compile(r"[\x00-\x1f\x7f]")


def _clean_token(raw):
    """Return (token, status) for one raw enum value.

    token is the stripped + lowercased token, or None. status is one of:
      "default" -- raw is None or "" (caller maps it to the protocol
                   default; for transport that default is "tcp").
      "ok"      -- a clean non-empty token with no internal whitespace
                   or control characters.
      "unknown" -- (decided by the caller against its allowed set; this
                   helper only reports "ok" vs malformed, see below).
      "invalid" -- raw is not a string, is whitespace-only, or contains
                   internal whitespace / control characters.
    The caller decides "ok" vs "unknown" by membership in its allowed
    set; this helper returns the cleaned token for both cases so the
    caller can echo it in the reason detail (the lowered token only,
    never the raw input).
    """
    if raw is None or raw == "":
        return None, "default"
    if not isinstance(raw, str):
        return None, "invalid"
    token = raw.strip().lower()
    if token == "":
        return None, "invalid"
    if _WS.search(token) or _CTRL.search(token):
        return None, "invalid"
    return token, "ok"


def norm_transport(raw):
    """Normalize a vmess net / trojan t_type value.

    Returns (value, status): value is "tcp" | "ws" | <unknown token> |
    None; status is "ok" | "unknown" | "invalid" | "default".
    "default" means the field was absent/empty and the caller must use
    "tcp" (the parser's long-standing default). "unknown" means a
    well-formed token the protocol does not define (kept lowercased for
    the reason detail; never folded into tcp). "invalid" means the value
    cannot be a token at all.
    """
    token, status = _clean_token(raw)
    if status == "default":
        return "tcp", "default"
    if status == "invalid":
        return None, "invalid"
    if token in _TRANSPORT_OK:
        return token, "ok"
    return token, "unknown"


def norm_method(raw, allowed):
    """Normalize an ss encrypt-method value against `allowed`.

    Returns (value, status): value is the cleaned token or None; status
    is "ok" | "unknown" | "invalid". There is no default method: a
    missing/empty method is "invalid" (the gates report "ss-method").
    """
    token, status = _clean_token(raw)
    if status == "default":
        return None, "invalid"
    if status == "invalid":
        return None, "invalid"
    if token in allowed:
        return token, "ok"
    return token, "unknown"


# ---------------------------------------------------------------------------
# Auth fields: checked verbatim, never normalized
# ---------------------------------------------------------------------------

def check_password(pw):
    """Shared password check (trojan / ss).

    Returns "ok" | "missing" | "comma" | "whitespace":
      "missing"    -- not a string, or empty.
      "comma"      -- any "," anywhere (B10: the Surge line is
                      comma-split; a comma password would publish with
                      a WRONG password). Reported as "comma-password".
      "whitespace" -- leading/trailing whitespace (would publish with a
                      wrong password too). Reported as "bad-password".
      "ok"         -- otherwise.
    The comma check precedes the whitespace check (a comma is the more
    specific defect). The password value itself is never returned.
    """
    if not isinstance(pw, str) or pw == "":
        return "missing"
    if "," in pw:
        return "comma"
    if pw != pw.strip():
        return "whitespace"
    return "ok"


UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


def is_valid_uuid(u):
    """True iff u is a string in 8-4-4-4-12 hex UUID shape.

    Shape-only: version/variant nibbles are NOT policed; case is free.
    (Moved here from rules.py so all four gates share one definition;
    rules.py re-exports it for backward compatibility.)
    """
    return isinstance(u, str) and bool(UUID_RE.match(u))


def check_uuid(u):
    """Shared vmess uuid check.

    Returns "ok" | "missing" | "comma" | "invalid":
      "missing" -- not a string, or empty.
      "comma"   -- any "," anywhere (B10-EXTENSION: username= is a
                   comma-split Surge param too). Reported as "comma-uuid".
      "invalid" -- not a legal 8-4-4-4-12 hex UUID shape. Reported as
                   "invalid-uuid".
      "ok"      -- otherwise.
    The comma check precedes the format check (v1 behaviour preserved).
    The uuid value itself is never returned.
    """
    if not isinstance(u, str) or u == "":
        return "missing"
    if "," in u:
        return "comma"
    if not is_valid_uuid(u):
        return "invalid"
    return "ok"
