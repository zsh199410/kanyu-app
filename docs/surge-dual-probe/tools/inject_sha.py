#!/usr/bin/env python3
"""Inject CLIENT_VERSION into probe-task-dual.js (build-time step).

CLIENT_VERSION is the SCRIPT build id. It is NOT the pool content SHA:
  sha12 = sha256(file bytes with the constant set to the placeholder
          'dual-v1-000000000000')[0:12]
  The constant is then set to 'dual-v1-<sha12>'.
The pool content SHA travels separately as source_version_sha: the server
computes it from the pool file when issuing tasks (info.pool_sha) and the
script echoes it back verbatim; the server re-verifies it at ingest.
Verification (test_dual_probe.py T06 + tools/verify_sha.py):
  take the file, replace the 12-hex value back with '000000000000',
  sha256 it, first 12 hex must equal the constant's suffix.
Usage: python3 tools/inject_sha.py [path-to-probe-task-dual.js]
"""
import hashlib
import re
import sys

PLACEHOLDER = "dual-v1-000000000000"
PATTERN = re.compile(r"(const CLIENT_VERSION = 'dual-v1-)([0-9a-f]{12})(';)")


def compute_sha12(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def main(path: str) -> str:
    raw = open(path, "rb").read()
    # Normalize to placeholder first so re-injection is idempotent.
    norm = PATTERN.sub(r"\g<1>000000000000\g<3>", raw.decode("utf-8")).encode("utf-8")
    sha12 = compute_sha12(norm)
    out = PATTERN.sub(r"\g<1>" + sha12 + r"\g<3>", norm.decode("utf-8")).encode("utf-8")
    open(path, "wb").write(out)
    return sha12


if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else "script/probe-task-dual.js"
    print("CLIENT_VERSION=dual-v1-" + main(p))
