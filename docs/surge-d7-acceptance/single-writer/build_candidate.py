# -*- coding: utf-8 -*-
"""Pure candidate computation for Surge Issue #73 (NO production permission).

This module ports the *ordering* of the documented legacy cmd_publish:
pinned -> old stable rotation -> newly eligible -> winner-clean -> trim.
It accepts a read-only normalized snapshot and PURE legacy parser/formatter
callbacks. The real pool rules.py, crawler.py and winner_clean.py function
signatures must be verified on VPS before building the production adapter.

No DB/network/filesystem I/O; never modifies existing pool, blocklist,
run logs, published_first or .prev. It returns diagnostic proposals but
ALWAYS a HOLD as operational decision until source parity and device
evidence have been independently proven.
"""
from __future__ import annotations

import hashlib
import math
from collections import Counter
from datetime import datetime, timezone


class CandidateRefused(ValueError):
    """No candidate may be published on this failure."""


def _key(k):
    if not isinstance(k, (tuple, list)) or len(k) != 3:
        raise CandidateRefused("bad_node_key")
    proto, host, port = k
    if not isinstance(proto, str) or not proto or not isinstance(host, str) or not host:
        raise CandidateRefused("bad_node_key")
    if isinstance(port, bool) or not isinstance(port, int) or not 0 < port < 65536:
        raise CandidateRefused("bad_node_key")
    return proto, host, port


def _check_config(config):
    if not isinstance(config, dict):
        raise CandidateRefused("missing_config")
    defaults = {
        "publish_max_lines": 150, "per_country_cap": 40,
        "publish_fresh_hours": 24, "publish_max_vps_ms": 300,
        "publish_min_pass_rate": 0.5, "winner_clean_enabled": False,
    }
    c = {**defaults, **config}
    for n in ("publish_max_lines", "per_country_cap", "publish_fresh_hours"):
        if type(c[n]) is not int or not 1 <= c[n] <= (150 if n == "publish_max_lines" else 1000):
            raise CandidateRefused("invalid_config_" + n)
    for n in ("publish_max_vps_ms", "publish_min_pass_rate"):
        if type(c[n]) not in (int, float) or not math.isfinite(c[n]) or c[n] <= 0:
            raise CandidateRefused("invalid_config_" + n)
    if c["publish_min_pass_rate"] > 1:
        raise CandidateRefused("invalid_pass_rate")
    return c


def _split_pool(raw, parse_fn):
    if not isinstance(raw, bytes) or not raw or len(raw) > 2 * 1024 * 1024:
        raise CandidateRefused("invalid_current_pool")
    try:
        lines = [l for l in raw.decode("utf-8").splitlines()
                 if l.strip() and not l.lstrip().startswith("#")]
    except UnicodeDecodeError as exc:
        raise CandidateRefused("pool_not_utf8") from exc
    if not lines:
        raise CandidateRefused("empty_current_pool")
    result = {}
    names = set()
    for line in lines:
        if "=" not in line:
            raise CandidateRefused("malformed_current_line")
        name = line.split("=", 1)[0].strip()
        if not name or name in names:
            raise CandidateRefused("duplicate_name")
        names.add(name)
        k = _key(parse_fn(line))
        if k in result:
            raise CandidateRefused("duplicate_key")
        result[k] = {"name": name, "line": line}
    return result


def _normal_nodes(raw):
    result = {}
    if not isinstance(raw, (list, tuple)):
        raise CandidateRefused("invalid_db_nodes")
    for row in raw:
        if not isinstance(row, dict):
            raise CandidateRefused("invalid_db_node_row")
        k = _key(row.get("key"))
        if k in result:
            raise CandidateRefused("duplicate_db_key")
        result[k] = row
    return result


def _eligible(nodes, tests, config, now):
    """DB last_result + recent test + rate + most recent passing ms."""
    result = {}
    if not isinstance(tests, dict):
        raise CandidateRefused("invalid_tests_snapshot")
    fresh_from = now - config["publish_fresh_hours"] * 3600
    for k, row in nodes.items():
        if row.get("last_result") != "pass":
            continue
        t = row.get("last_test_at")
        if type(t) not in (int, float) or not math.isfinite(t) or not fresh_from <= t <= now:
            continue
        passed, count = row.get("pass_count", 0), row.get("test_count", 0)
        if type(passed) is not int or type(count) is not int or passed < 0 or count < 0 or passed > count:
            raise CandidateRefused("bad_pass_counts")
        rate = passed / count if count else 1.0
        ms = tests.get(k)
        if (type(ms) not in (int, float) or not math.isfinite(ms)
                or ms < 0 or ms > config["publish_max_vps_ms"]
                or rate < config["publish_min_pass_rate"]):
            continue
        seen = row.get("first_seen")
        if type(seen) not in (int, float) or not math.isfinite(seen):
            raise CandidateRefused("bad_first_seen")
        result[k] = {"rate": rate, "first_seen": seen}
    return result


def build_candidate(*, current_pool, config, node_rows, latest_pass_ms,
                    fresh_records, pinned_file_lines, db_pins, blocked_keys,
                    parse_fn, prefilter_fn, render_fn, name_fn, country_fn,
                    winner_clean_fn=None, now=None):
    """Compute a candidate preview from verified read-only normalized inputs.

    Required pure callbacks from legacy source (not invented implementations):
    parse_fn(line)->(protocol,host,port);
    prefilter_fn(fresh_record)->bool;
    render_fn(fresh_record,name)->valid Surge proxy declaration str;
    name_fn(list[(key,record)],reserved_names)->dict[key,name];
    country_fn(name)->country code; winner_clean_fn(rotation_lines)->lines.

    The caller must provide the real legacy functions after source audit.
    `fresh_records` is the in-memory crawler output, never an invented URI.
    `db_pins` is key->name, `pinned_file_lines` is source file data.
    All outputs are only proposals; no release authorization is conferred.
    """
    c = _check_config(config)
    timestamp = datetime.now(timezone.utc).timestamp() if now is None else now
    if type(timestamp) not in (int, float) or not math.isfinite(timestamp):
        raise CandidateRefused("invalid_clock")
    for fn in (parse_fn, prefilter_fn, render_fn, name_fn, country_fn):
        if not callable(fn):
            raise CandidateRefused("unverified_legacy_callback")
    old = _split_pool(current_pool, parse_fn)
    nodes = _normal_nodes(node_rows)
    if not isinstance(fresh_records, dict) or not isinstance(db_pins, dict):
        raise CandidateRefused("bad_source_snapshot")
    if not isinstance(blocked_keys, (set, frozenset, tuple, list)):
        raise CandidateRefused("bad_blocklist")
    blocked = {_key(k) for k in blocked_keys}
    pins = {_key(k): n for k, n in db_pins.items()}
    if not all(isinstance(n, str) and n for n in pins.values()):
        raise CandidateRefused("bad_pinned_names")
    for k in fresh_records:
        _key(k)
    if not isinstance(pinned_file_lines, (list, tuple)):
        raise CandidateRefused("bad_pinned_file")
    file_pins = {}
    for line in pinned_file_lines:
        k = _key(parse_fn(line))
        if k in blocked:
            continue
        if k in file_pins:
            raise CandidateRefused("duplicate_pinned_entry")
        file_pins[k] = line
    # Backfilling DB pinned is forbidden here, even when original cli
    # would INSERT OR IGNORE. This new function has no DB write capability.
    pinned_keys = set(file_pins) | set(pins)
    if len(pinned_keys) != 21 or pinned_keys & blocked:
        raise CandidateRefused("canonical_21_pins_missing_or_blocked")
    eligible = _eligible(nodes, latest_pass_ms, c, timestamp)
    result_pinned = dict(file_pins)
    # DB-only pinned: preserve old bytes if possible, otherwise construct
    # from a genuinely fresh in-memory record only.
    for k, name in pins.items():
        if k in result_pinned:
            continue
        if k in old:
            result_pinned[k] = old[k]["line"]
        elif k in fresh_records and prefilter_fn(fresh_records[k]):
            result_pinned[k] = render_fn(fresh_records[k], name)
        else:
            raise CandidateRefused("pinned_uri_missing")
    if len(result_pinned) != 21:
        raise CandidateRefused("pin_count_not_21")

    # Anti-flap: keep old declarations VERBATIM when VPS gate passes.
    kept = {}
    by_country = Counter()
    for k, oldrow in old.items():
        if k in blocked or k in pinned_keys or k not in eligible:
            continue
        country = country_fn(oldrow["name"])
        if by_country[country] >= c["per_country_cap"]:
            continue
        kept[k] = oldrow["line"]
        by_country[country] += 1

    fresh_eligible = [
        (k, fresh_records[k])
        for k in sorted(eligible, key=lambda k:
                        (-eligible[k]["rate"], eligible[k]["first_seen"], k))
        if k not in blocked and k not in pinned_keys and k not in kept
        and k in fresh_records and prefilter_fn(fresh_records[k])
    ]
    reserved = {line.split("=", 1)[0].strip()
                for line in list(result_pinned.values()) + list(kept.values())}
    names = name_fn(fresh_eligible, reserved)
    if not isinstance(names, dict):
        raise CandidateRefused("bad_name_assignment")
    additions = {}
    for k, record in fresh_eligible:
        name = names.get(k)
        if not isinstance(name, str) or not name or name in reserved:
            raise CandidateRefused("missing_or_duplicate_name_assignment")
        country = country_fn(name)
        if by_country[country] >= c["per_country_cap"]:
            continue
        rendered = render_fn(record, name)
        if not isinstance(rendered, str) or _key(parse_fn(rendered)) != k:
            raise CandidateRefused("builder_key_mismatch")
        additions[k] = rendered
        reserved.add(name)
        by_country[country] += 1
        if len(result_pinned) + len(kept) + len(additions) >= c["publish_max_lines"]:
            break

    rotation = list(kept.values()) + list(additions.values())
    if c["winner_clean_enabled"]:
        # This signature must be supplied by the audited legacy adapter.
        if not callable(winner_clean_fn):
            raise CandidateRefused("winner_clean_callback_required")
        cleaned = winner_clean_fn(rotation)
        if not isinstance(cleaned, (tuple, list)) or any(
                x not in rotation for x in cleaned):
            raise CandidateRefused("winner_clean_invalid_result")
        rotation = list(cleaned)
    all_lines = list(result_pinned.values()) + rotation
    if len(all_lines) > c["publish_max_lines"]:
        # Trim only non-pin rotation, preserving pinned lines; legacy rate
        # ordering must be rechecked against actual source before adapter.
        count = c["publish_max_lines"] - len(result_pinned)
        if count < 0:
            raise CandidateRefused("pins_exceed_limit")
        all_lines = list(result_pinned.values()) + rotation[:count]
    if not all_lines or len(all_lines) > c["publish_max_lines"]:
        raise CandidateRefused("candidate_empty_or_oversized")
    seen_names = [l.split("=", 1)[0].strip() for l in all_lines]
    if len(seen_names) != len(set(seen_names)):
        raise CandidateRefused("candidate_duplicate_names")
    preview = ("\n".join(all_lines) + "\n").encode("utf-8")
    return {
        "decision": "PREVIEW_ONLY_NOT_ADMITTED",
        "proposed_bytes": preview,
        "proposed_sha256": hashlib.sha256(preview).hexdigest(),
        "proposed_count": len(all_lines),
        "canonical_pin_count": len(result_pinned),
        "kept_old_count": len(kept),
        "new_count": len(additions),
        "preview_only": True,
        "production_write_authorized": False,
        "production_delete_authorized": False,
    }
