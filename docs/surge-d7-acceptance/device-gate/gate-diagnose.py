#!/usr/bin/env python3
"""Diagnose what the phone's Surge HTTP API actually returns.

Prints the raw shape of GET /v1/features/scripting, /v1/scripting and
/v1/policy_groups so a response-shape mismatch can be fixed. No secrets
are printed (these endpoints return names/flags only).

Usage: python gate-diagnose.py [phone_ip]
"""
import json
import sys
import urllib.error
import urllib.request

IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.5.19"
BASE = "http://%s:6171" % IP
KEY = "test123"


def get(path):
    req = urllib.request.Request(BASE + path, method="GET")
    req.add_header("X-Key", KEY)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:
        return None, "ERROR: %s" % exc


for path in ("/v1/features/scripting", "/v1/scripting", "/v1/policy_groups"):
    status, body = get(path)
    print("=" * 60)
    print(path, "-> HTTP", status)
    try:
        obj = json.loads(body)
        print(json.dumps(obj, ensure_ascii=False, indent=2)[:3000])
    except Exception:
        print(body[:2000])
