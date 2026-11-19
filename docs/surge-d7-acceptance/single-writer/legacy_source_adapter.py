# -*- coding: utf-8 -*-
"""Adapt the installed legacy pure rules/crawler/geo/winner functions.

No direct writes to production SQLite or pool files. The remote source
fetch in crawl_records is READ-ONLY network I/O and intentionally limited
by the legacy crawler's own per-source 20s/20MB bounds. Importing only
pure modules avoids importing the side-effectful pool.cli.

This adapter must be byte-compared against the installed legacy generator
on the VPS before any release. Its output is preview-only.
"""
from __future__ import annotations

from datetime import datetime, timezone
import importlib
import json
from pathlib import Path
import sys

class LegacyAdapterRefused(ValueError):
    pass


def _load_installed_modules(source_root: str):
    root = Path(source_root)
    if (not root.is_absolute() or not root.is_dir() or
            not (root / "pool" / "__init__.py").is_file() or
            not (root / "pool" / "crawler.py").is_file() or
            not (root / "pool" / "rules.py").is_file() or
            not (root / "pool" / "geo.py").is_file()):
        raise LegacyAdapterRefused("legacy_source_path_invalid")
    # This is the already installed, locally audited source root, not a
    # remote import. All invoked module call signatures must be checked
    # by the VPS parity acceptance before enabling the timer.
    p = str(root)
    if p not in sys.path:
        sys.path.insert(0, p)
    try:
        crawler = importlib.import_module("pool.crawler")
        rules = importlib.import_module("pool.rules")
        geo = importlib.import_module("pool.geo")
        winner = importlib.import_module("pool.winner_clean")
    except (ImportError, AttributeError, OSError) as exc:
        raise LegacyAdapterRefused("legacy_import_failed") from exc
    expected = (
        (crawler, ("crawl_records", "parse_surge_line")),
        (rules, ("pre_filter", "build_surge_line", "assign_names",
                 "load_private_hosts")),
        (geo, ("IpApi", "hint_to_code")),
        (winner, ("clean_rotation",)),
    )
    for module, symbols in expected:
        if any(not callable(getattr(module, s, None)) for s in symbols):
            raise LegacyAdapterRefused("legacy_callback_missing")
    return crawler, rules, geo, winner


def _scalar(raw, key):
    if isinstance(raw, (bool, int, float, list, dict)):
        return raw
    if not isinstance(raw, str):
        raise LegacyAdapterRefused("bad_config_value_" + key)
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return raw.strip()


def normalize_config(yaml_path, raw_db_config, *, yaml_loader=None):
    """Use real YAML config first; DB config overrides per old publisher.

    Refuse a missing YAML parser: never silently substitute cmd_publish's
    12-hour fallback for the live 24-hour freshness window.
    """
    if yaml_loader is None:
        try:
            import yaml
        except ImportError as exc:
            raise LegacyAdapterRefused("pyyaml_required_for_legacy_config") from exc
        yaml_loader = yaml.safe_load
    p = Path(yaml_path)
    if not p.is_absolute() or not p.is_file():
        raise LegacyAdapterRefused("missing_legacy_yaml")
    try:
        cfg = yaml_loader(p.read_text(encoding="utf-8")) or {}
    except (ValueError, TypeError, OSError) as exc:
        raise LegacyAdapterRefused("invalid_legacy_yaml") from exc
    if not isinstance(cfg, dict) or not isinstance(raw_db_config, dict):
        raise LegacyAdapterRefused("invalid_legacy_config")
    merged = dict(cfg)
    for k, v in raw_db_config.items():
        if not isinstance(k, str) or not k:
            raise LegacyAdapterRefused("invalid_config_key")
        merged[k] = _scalar(v, k)
    required = (
        "publish_max_lines", "publish_fresh_hours", "publish_max_vps_ms",
        "publish_min_pass_rate", "winner_clean_enabled",
        "winner_clean_window_days", "winner_clean_min_winner_days",
    )
    if any(k not in merged for k in required):
        raise LegacyAdapterRefused("missing_effective_legacy_setting")
    # Use the actual live per-country default only if absent, as reported
    # by the audited original cmd_publish configuration path.
    merged.setdefault("per_country_cap", 40)
    disabled = merged.get("disabled_sources", [])
    if not isinstance(disabled, (list, tuple, set)) or not all(
        isinstance(s, str) for s in disabled
    ):
        raise LegacyAdapterRefused("invalid_disabled_sources")
    for key in ("winner_clean_window_days", "winner_clean_min_winner_days"):
        val = merged[key]
        if type(val) is not int or not 1 <= val <= 365:
            raise LegacyAdapterRefused("invalid_" + key)
    if type(merged["winner_clean_enabled"]) is not bool:
        raise LegacyAdapterRefused("invalid_winner_clean_enabled")
    if type(merged.get("vmess_tls_only", True)) is not bool:
        raise LegacyAdapterRefused("invalid_vmess_tls_only")
    return merged


def _parse_fn(crawler):
    def parse(line):
        name, proto, host, port, valid = crawler.parse_surge_line(line)
        if valid is not True:
            raise LegacyAdapterRefused("legacy_proxy_line_invalid")
        return proto, host, int(port)
    return parse


def _pinned_file(base):
    # Matches disclosed old priority: bridge override, then base.
    choices = [
        Path("/opt/surge-bridge/pinned-nodes.txt"),
        Path(base) / "pinned-nodes.txt",
    ]
    for p in choices:
        if p.is_file():
            return [x for x in p.read_text(encoding="utf-8").splitlines()
                    if x.strip() and not x.lstrip().startswith("#")]
    raise LegacyAdapterRefused("pinned_source_not_found")


def _winner_filter(rotation, *, snapshot, now, config, parse):
    """Reproduce reported grace / winner-window behavior as a pure filter.

    Only the read-only winner_reports/published_first snapshot is used.
    A per-node timestamp not found in published_first is grace-exempt.
    A further VPS comparison must prove parity with legacy clean_rotation.
    """
    if not config["winner_clean_enabled"]:
        return list(rotation)
    window_days = config["winner_clean_window_days"]
    threshold = now - window_days * 86400
    valid_reports = []
    for ts, name in snapshot["winner_reports"]:
        if isinstance(ts, int) and isinstance(name, str) and ts >= threshold:
            valid_reports.append((ts, name))
    winner_names = {n for _, n in valid_reports}
    day_count = len({
        datetime.fromtimestamp(ts, tz=timezone.utc).date()
        for ts, _ in valid_reports
    })
    if day_count < config["winner_clean_min_winner_days"]:
        return list(rotation)
    kept = []
    for line in rotation:
        key = parse(line)
        name = line.split("=", 1)[0].strip()
        first = snapshot["first_published"].get(key)
        # Current code's grace means newly published entries are exempt.
        if first is None or first > threshold or name in winner_names:
            kept.append(line)
    return kept


def make_preview(*, db_snapshot, current_pool, legacy_root,
                 now, modules=None, fresh_record_provider=None,
                 pinned_lines_provider=None, yaml_loader=None):
    """Preview candidate with REAL legacy callbacks, no publication.

    Providers are injectible only for isolated tests. Default uses
    installed old crawler's read-only HTTP fetch and a read-only DB
    snapshot delivered by pool_db_source.
    """
    root = Path(legacy_root)
    if not root.is_absolute():
        raise LegacyAdapterRefused("legacy_root_not_absolute")
    if modules is None:
        modules = _load_installed_modules(str(root))
    crawler, rules, geo, winner = modules
    config = normalize_config(root / "config.yaml", db_snapshot["config_raw"],
                              yaml_loader=yaml_loader)
    parse = _parse_fn(crawler)
    private = rules.load_private_hosts(str(root / "private-hosts.txt"))
    if pinned_lines_provider is None:
        pinned_lines = _pinned_file(root)
    else:
        pinned_lines = pinned_lines_provider(root)
    if fresh_record_provider is None:
        records, _counts = crawler.crawl_records(
            str(root / "sources.yaml"), skip=set(config.get("disabled_sources", [])))
    else:
        records = fresh_record_provider(root, config)
    if not isinstance(records, (list, tuple)):
        raise LegacyAdapterRefused("crawl_records_must_return_list")
    fresh = {}
    for item in records:
        if not isinstance(item, dict):
            raise LegacyAdapterRefused("bad_crawl_record")
        key = item.get("protocol"), item.get("host"), item.get("port")
        if key not in fresh:
            fresh[key] = item
    prefiltered = []
    ipapi = geo.IpApi()
    # Explicit latest passing DB gate used in the existing pure preview.
    def prefilter(rec):
        ok, reason = rules.pre_filter(rec, private)
        if (not ok and reason == "vmess-non-tls" and
                not config.get("vmess_tls_only", True)):
            return True
        return bool(ok)

    def render(rec, name):
        return rules.build_surge_line(rec, name)

    # Compute the normalized eligibility for rate-aware name assignment.
    # This is not an independent admission proof.
    from importlib.util import spec_from_file_location, module_from_spec
    core_path = Path(__file__).resolve().with_name("build_candidate.py")
    spec = spec_from_file_location("_surge_candidate_core", core_path)
    core = module_from_spec(spec)
    spec.loader.exec_module(core)
    rows = core._normal_nodes(db_snapshot["node_rows"])
    eligible = core._eligible(
        rows, db_snapshot["latest_pass_ms"], core._check_config(config), now)

    def name_fn(items, reserved):
        ordered = [(rec, eligible[key]["rate"], eligible[key]["first_seen"])
                   for key, rec in items]
        assigned = rules.assign_names(ordered, set(reserved), ipapi)
        result = {}
        for rec, name, _code in assigned:
            key = rec.get("protocol"), rec.get("host"), rec.get("port")
            if key in result:
                raise LegacyAdapterRefused("duplicate_assigned_name_key")
            result[key] = name
        return result

    def country_fn(name):
        return geo.hint_to_code(name) or "unknown"

    def winner_fn(rotating_lines):
        return _winner_filter(rotating_lines, snapshot=db_snapshot,
                              now=now, config=config, parse=parse)

    return core.build_candidate(
        current_pool=current_pool,
        config=config,
        node_rows=db_snapshot["node_rows"],
        latest_pass_ms=db_snapshot["latest_pass_ms"],
        fresh_records=fresh,
        pinned_file_lines=pinned_lines,
        db_pins=db_snapshot["db_pins"],
        blocked_keys=db_snapshot["blocked_keys"],
        parse_fn=parse,
        prefilter_fn=prefilter,
        render_fn=render,
        name_fn=name_fn,
        country_fn=country_fn,
        winner_clean_fn=winner_fn,
        now=now,
    )
