#!/usr/bin/env python3
"""Offline integrity gate for an unsigned iOS IPA or downloaded Actions artifact ZIP.

Usage:
  python scripts/verify_ipa_artifact.py path/to/Kanyu-unsigned.ipa --sha256 EXPECTED
  python scripts/verify_ipa_artifact.py path/to/artifact.zip --sha256 EXPECTED

The digest always applies to the exact file passed in, not an inner IPA.
This is NOT a signature, installability, device test or source-SHA attestation.
"""
import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path


def inspect(path: Path, expected: str | None = None) -> dict:
    if not path.is_file():
        raise ValueError("file not found")
    digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
    if expected is not None:
        if len(expected) != 64 or any(c not in "0123456789abcdefABCDEF" for c in expected):
            raise ValueError("expected SHA-256 must be 64 hexadecimal characters")
        if digest.lower() != expected.lower():
            raise ValueError("SHA-256 mismatch")
    if not zipfile.is_zipfile(path):
        raise ValueError("not a ZIP/IPA archive")
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad:
            raise ValueError(f"CRC error in {bad}")
        names = z.namelist()
        if len(names) != len(set(names)):
            raise ValueError("duplicate archive entry names")
        if path.suffix.lower() == ".ipa":
            apps = {n.split("/")[1] for n in names if n.startswith("Payload/") and len(n.split("/")) > 2 and n.split("/")[1].endswith(".app")}
            if len(apps) != 1 or not any(n.startswith(f"Payload/{next(iter(apps))}/") for n in names):
                raise ValueError("IPA must contain exactly one Payload/*.app directory")
            kind = "ipa"
        else:
            ipas = [n for n in names if n.lower().endswith(".ipa") and not n.endswith("/")]
            if len(ipas) != 1:
                raise ValueError("artifact ZIP must contain exactly one IPA")
            with z.open(ipas[0]) as inner:
                if not zipfile.is_zipfile(inner):
                    raise ValueError("inner IPA is not ZIP")
            kind = "artifact-zip"
    return {"path": str(path), "kind": kind, "sha256": digest, "bytes": path.stat().st_size, "crc": "ok", "source_commit_verified": False, "device_tested": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path)
    parser.add_argument("--sha256", help="Expected SHA-256 for the exact input file")
    args = parser.parse_args()
    try:
        result = inspect(args.file, args.sha256)
    except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps({"ok": True, **result}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
