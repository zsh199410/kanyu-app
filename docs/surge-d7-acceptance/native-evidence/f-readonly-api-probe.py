#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only, privacy-safe Surge iOS F calibration API capability probe.

Runs on a trusted machine ON THE SAME PRIVATE LAN as the iPhone (or the
existing trusted bridge host). No POST, no retries, no production writes.
The API key must come from SURGE_API_KEY (never put credentials in Git).
Output intentionally contains NO policy names, IDs, URIs, IPs or raw JSON.

Environment:
  SURGE_API_BASE=http://<private-lan-ip>:6171
  SURGE_API_KEY=<from private credential store>
  SURGE_GROUP_NAME=免费节点池  (optional)
  SURGE_POLICY_NAME=<chosen direct policy>  (optional; defaults to no detail)
"""
from __future__ import annotations

import ipaddress
import json
import os
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, ProxyHandler, build_opener

_SAFE_NUMBER_FIELDS = {
    "latency_ms", "latency", "round-one-total", "round_one_total",
    "roundOneTotal", "available", "tcp", "receive",
}
_SAFE_TOP_KEYS = {
    "proxies", "policy-groups", "external-policies", "policy", "available",
    "groups", "error", "message", "result",
}


def validated_base(value: str) -> str:
    """Reject all non-private, hostnamed, or proxied credential destinations."""
    if not isinstance(value, str) or not value:
        raise ValueError("SURGE_API_BASE is required")
    url = urlsplit(value)
    if (url.scheme != "http" or url.username is not None or
            url.password is not None or url.path not in ("", "/") or
            url.query or url.fragment):
        raise ValueError("Surge API must be a bare private-LAN HTTP address")
    try:
        ip = ipaddress.ip_address(url.hostname or "")
        port = url.port
    except ValueError as exc:
        raise ValueError("Surge API must use an IP literal and valid port") from exc
    if ip.is_multicast or ip.is_unspecified or not (ip.is_private or ip.is_loopback):
        raise ValueError("Surge API address must be private or loopback")
    if port is None or port <= 0:
        raise ValueError("Surge API port must be explicit")
    return "http://" + ("[" + str(ip) + "]" if ip.version == 6 else str(ip)) + ":" + str(port)


def sanitize_structure(value) -> dict:
    """Only output bounded, recognized field names/counts and numeric values."""
    if not isinstance(value, dict):
        return {"shape": type(value).__name__}
    result = {"shape": "object",
              "present_keys": sorted(str(k) for k in value if k in _SAFE_TOP_KEYS)}
    for key in ("proxies", "policy-groups", "external-policies", "available"):
        if isinstance(value.get(key), list):
            result[key.replace("-", "_") + "_count"] = len(value[key])
    if isinstance(value.get("groups"), dict):
        result["groups_count"] = len(value["groups"])
    # Only policy-specific numeric fields are meaningful for F. Do not
    # expose nested arbitrary paths that could contain real node labels.
    numeric = {}
    def walk(obj, depth=0):
        if depth > 4 or len(numeric) >= 24:
            return
        if isinstance(obj, dict):
            for k, v in obj.items():
                if (k in _SAFE_NUMBER_FIELDS and isinstance(v, (float, int))
                        and not isinstance(v, bool)):
                    numeric[k] = v
                elif isinstance(v, (dict, list)):
                    walk(v, depth + 1)
        elif isinstance(obj, list):
            for item in obj[:10]:
                walk(item, depth + 1)
    walk(value)
    result["latency_numeric_fields"] = numeric
    return result


def get_once(base, key, path, *, opener=None):
    """GET exactly once. Body is never emitted, only parsed/sanitized."""
    if not isinstance(key, str) or not key:
        raise ValueError("SURGE_API_KEY is required")
    opener = opener if opener is not None else build_opener(ProxyHandler({}))
    req = Request(base + path, headers={"X-Key": key, "Accept": "application/json"},
                  method="GET")
    try:
        with opener.open(req, timeout=10) as resp:
            raw = resp.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                return {"status": "oversize", "ok": False}
            data = json.loads(raw.decode("utf-8"))
            return {"status": "ok", "http_status": resp.status, "ok": True,
                    "sanitized": sanitize_structure(data)}
    except HTTPError as exc:
        # Do not read/print the possibly sensitive response body.
        return {"status": "http_error", "http_status": exc.code, "ok": False}
    except (OSError, URLError, ValueError, UnicodeError, json.JSONDecodeError):
        return {"status": "unavailable_or_invalid_json", "ok": False}


def probe(base, key, group, policy=None, *, opener=None):
    base = validated_base(base)
    if not isinstance(group, str) or not group or len(group) > 120:
        raise ValueError("group must be a nonempty short string")
    endpoints = [
        ("external_policy_discovery", "/v1/policies?include_external=true"),
        ("policy_group_members", "/v1/policy_groups"),
        ("group_test_results", "/v1/policy_groups/test_results?group_name=" + quote(group, safe="")),
    ]
    if policy:
        endpoints.append(("one_policy_detail",
                          "/v1/policies/detail?policy_name=" + quote(policy, safe="")))
    results = {}
    for label, path in endpoints:
        results[label] = get_once(base, key, path, opener=opener)
    return {
        "mode": "GET_ONLY",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "group_name_redacted": True,
        "policy_name_redacted": True,
        "raw_body_logged": False,
        "post_count": 0,
        "auto_retry": False,
        "endpoints": results,
        "calibration_verdict": "UNCALIBRATED",
        "auto_clean": "NO_GO",
    }


def main() -> int:
    key = os.environ.get("SURGE_API_KEY", "")
    try:
        data = probe(os.environ.get("SURGE_API_BASE", ""), key,
                     os.environ.get("SURGE_GROUP_NAME", "免费节点池"),
                     os.environ.get("SURGE_POLICY_NAME"))
    except ValueError as exc:
        # Only validation error text is printed, never input credentials.
        print(json.dumps({"ok": False, "error": str(exc),
                          "calibration_verdict": "UNCALIBRATED"},
                         ensure_ascii=False))
        return 2
    print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if any(x.get("ok") for x in data["endpoints"].values()) else 1


if __name__ == "__main__":
    sys.exit(main())
