"""D2 version / evidence binding (GPT D1 review 6881291219, blocker 1).

Problem (D1): run_publish() took the caller-passed source_version_sha and
used it for the native gate AND the sidecar without ever proving that SHA
corresponds to the actual candidate source bytes; run_sync() trusted
--source-version the same way. A stale sidecar could be freely paired
with a replaced source file, and old qualified evidence could be pasted
onto a new version whose identical-fingerprint lines would then pass.

Fix: a non-confusable version chain, recomputed from ACTUAL BYTES at
every step, never from a caller assertion alone:

  source_sha             sha256 of the FULL natively-tested source
                         subscription file bytes (the version the phone
                         actually measured)
  published_sha          sha256 of the published subset bytes
  admitted_fingerprints  sorted list of fingerprints the native record
                         admits for source_sha (re-derived from the
                         native record, never copied from a sidecar)
  published_fingerprints sorted list of fingerprints actually present
                         in the published lines (subset of admitted)
  chain_id               sha256 of the canonical JSON of the four
                         fields above -- any edit to any field breaks it

Verification (verify_version_chain) re-derives EVERYTHING from the
actual file bytes + the native record and compares:
  - chain_id recomputes (tamper-evidence for the sidecar itself)
  - published_sha == sha256(actual published bytes)
  - published_fingerprints == fingerprints parsed from actual lines
  - admitted_fingerprints == admitted set re-derived from the native
    record for chain.source_sha (the sidecar may not claim a different
    admission set than the evidence supports)
  - published_fingerprints is a subset of admitted_fingerprints

Threat model (honest boundary): this binding defeats MISCONFIGURATION
and stale-pairing accidents -- old evidence pasted onto a new version,
a sidecar paired with a replaced file, a legacy writer overwriting the
source. It does NOT defend against a malicious writer with full
filesystem write access: such a writer could craft a fully
self-consistent chain AND write the served file directly, bypassing
every check. The lock + gate assume a non-malicious writer; the chain
makes accidental mis-pairing impossible and malicious mis-pairing
auditable (the chain_id + SHAs are logged, so a forged chain is
detectable after the fact by recomputation).

Sidecar format v2 (pool-new.txt.meta.json): the D1 v1 field
source_version_sha is kept for compatibility; the new version_chain
object is authoritative. D2 sync REFUSES v1-only sidecars (no chain):
a publish file without a verifiable chain cannot be proven to match
its evidence, so it must never be served.

All diagnostics use SHA prefixes (first 12 hex) and counts only.
No passwords, URIs, tokens, or subscription URLs are ever output.
"""

import hashlib
import json
import os

from .native_gate import evidence_admitted_fps, load_native_record
from .phone_gate import fingerprint_of, parse_surge_line
from .publish_lock import sha256_file

CHAIN_FORMAT = "version-chain-v1"
SHA_PREFIX_LEN = 12


def sha256_bytes(data):
    """SHA256 hex of raw bytes."""
    return hashlib.sha256(data).hexdigest()


def sha256_lines(lines):
    """SHA256 hex of the canonical subscription bytes for `lines`.

    Canonical bytes are exactly what _atomic_write_inner writes:
    "\\n".join(lines) + "\\n", UTF-8.
    """
    return hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()


def fingerprints_of_lines(lines):
    """(fingerprints set, unparsable count) for Surge lines.

    Unparsable lines have no fingerprint; callers must treat a nonzero
    unparsable count as fail-closed (a published file must be fully
    parsable).
    """
    fps = set()
    unparsable = 0
    for line in lines:
        parsed = parse_surge_line(line)
        if parsed is None:
            unparsable += 1
            continue
        _name, proto, host, port, params = parsed
        fps.add(fingerprint_of(proto, host, port, params))
    return fps, unparsable


def _canonical_chain_bytes(source_sha, published_sha, admitted_fps,
                           published_fps):
    """Canonical bytes whose SHA is the chain_id (field order fixed)."""
    payload = {
        "format": CHAIN_FORMAT,
        "source_sha": source_sha,
        "published_sha": published_sha,
        "admitted_fingerprints": sorted(admitted_fps),
        "published_fingerprints": sorted(published_fps),
    }
    return json.dumps(payload, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def build_version_chain(source_sha, published_lines, admitted_fps):
    """Build a version chain for a gated publish.

    Raises ValueError when the published lines are not fully parsable
    or when any published fingerprint is outside the admitted set
    (the gate must have admitted every published line).
    """
    published_fps, unparsable = fingerprints_of_lines(published_lines)
    if unparsable:
        raise ValueError("published lines unparsable: %d" % unparsable)
    if not published_fps.issubset(set(admitted_fps)):
        raise ValueError("published fingerprint outside admitted set")
    published_sha = sha256_lines(published_lines)
    chain_id = hashlib.sha256(_canonical_chain_bytes(
        source_sha, published_sha, set(admitted_fps),
        published_fps)).hexdigest()
    return {
        "format": CHAIN_FORMAT,
        "source_sha": source_sha,
        "published_sha": published_sha,
        "admitted_fingerprints": sorted(admitted_fps),
        "published_fingerprints": sorted(published_fps),
        "chain_id": chain_id,
    }


def verify_version_chain(chain, published_lines, native_record_path,
                         probe_db=None, now=None):
    """Verify a sidecar chain against ACTUAL bytes + native record.

    Returns (ok, error, summary). ok True only when every check passes:
      - chain is a dict with format version-chain-v1 and all fields
      - chain_id recomputes from the chain fields
      - published_sha == sha256 of the actual published_lines bytes
      - published_fingerprints == fingerprints parsed from actual lines
      - the native record's EVIDENCE admits exactly
        chain.admitted_fingerprints for chain.source_sha (re-derived
        via evidence_admitted_fps, IGNORING freshness/TTL -- the chain
        proves the file matches its evidence version; whether that
        evidence is still fresh is the gate's job at use time, so a
        TTL-expired anchor can still be classified last-verified-safe)
      - published_fingerprints is a subset of the admitted set
    error is None on success, else a short machine-readable string.
    summary carries counts + SHA prefixes only.
    """
    summary = {"chain_format": None, "published_lines": len(published_lines)}
    if not isinstance(chain, dict):
        return False, "chain_not_a_dict", summary
    if chain.get("format") != CHAIN_FORMAT:
        return False, "chain_bad_format", summary
    summary["chain_format"] = CHAIN_FORMAT
    source_sha = chain.get("source_sha")
    published_sha = chain.get("published_sha")
    admitted_list = chain.get("admitted_fingerprints")
    published_list = chain.get("published_fingerprints")
    chain_id = chain.get("chain_id")
    if not isinstance(source_sha, str) or len(source_sha) != 64:
        return False, "chain_bad_source_sha", summary
    if not isinstance(published_sha, str) or len(published_sha) != 64:
        return False, "chain_bad_published_sha", summary
    if not isinstance(admitted_list, list) or not isinstance(published_list, list):
        return False, "chain_bad_fingerprint_lists", summary
    if not isinstance(chain_id, str) or len(chain_id) != 64:
        return False, "chain_bad_chain_id", summary
    summary["source_sha_prefix"] = source_sha[:SHA_PREFIX_LEN]
    summary["published_sha_prefix"] = published_sha[:SHA_PREFIX_LEN]
    # 1. chain_id must recompute from the chain's own fields.
    expected_id = hashlib.sha256(_canonical_chain_bytes(
        source_sha, published_sha, set(admitted_list),
        set(published_list))).hexdigest()
    if expected_id != chain_id:
        return False, "chain_id_mismatch", summary
    # 2. published_sha must equal the ACTUAL published bytes.
    actual_published_sha = sha256_lines(published_lines)
    if actual_published_sha != published_sha:
        return False, "chain_published_sha_mismatch", summary
    # 3. published fingerprints must equal the ACTUAL lines' fingerprints.
    actual_published_fps, unparsable = fingerprints_of_lines(published_lines)
    if unparsable:
        return False, "chain_published_lines_unparsable", summary
    if actual_published_fps != set(published_list):
        return False, "chain_published_fingerprints_mismatch", summary
    # 4. the admitted set must be exactly what the native record's
    #    EVIDENCE says for chain.source_sha (re-derived here, ignoring
    #    freshness -- see the docstring; the sidecar is evidence, not
    #    authority, and the gate decides freshness at use time).
    record, rec_err = load_native_record(native_record_path)
    if rec_err is not None:
        return False, "chain_native_record_%s" % rec_err, summary
    admitted = evidence_admitted_fps(record, source_sha)
    if set(admitted_list) != set(admitted):
        return False, "chain_admitted_set_mismatch", summary
    # 5. published must be a subset of admitted.
    if not actual_published_fps.issubset(set(admitted)):
        return False, "chain_published_not_admitted", summary
    summary["admitted_count"] = len(admitted)
    summary["published_count"] = len(actual_published_fps)
    summary["chain_id_prefix"] = chain_id[:SHA_PREFIX_LEN]
    return True, None, summary


def read_chain_sidecar(publish_dir, filename):
    """Read a <file>.meta.json sidecar; return (meta, chain_or_None).

    meta is the whole sidecar dict or None; chain is the version_chain
    object or None (v1-only sidecars return chain None).
    """
    sidecar = os.path.join(publish_dir, filename) + ".meta.json"
    try:
        with open(sidecar, encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, ValueError):
        return None, None
    if not isinstance(meta, dict):
        return None, None
    chain = meta.get("version_chain")
    if not isinstance(chain, dict):
        return meta, None
    return meta, chain


def write_chain_sidecar(publish_dir, filename, chain):
    """Write/refresh a <file>.meta.json sidecar carrying a v2 chain.

    Keeps the D1 v1 source_version_sha field (taken from the chain) for
    compatibility; the version_chain object is authoritative. Returns
    the sidecar path. The sidecar is 600.
    """
    from .publish_lock import file_manifest, _iso  # local import: no cycle
    import time
    target = os.path.join(publish_dir, filename)
    meta = {
        "source_version_sha": chain["source_sha"],
        "version_chain": chain,
        "manifest": file_manifest(target),
        "written_at": int(time.time()),
        "written_at_iso": _iso(),
    }
    sidecar = target + ".meta.json"
    with open(sidecar, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    try:
        os.chmod(sidecar, 0o600)
    except OSError:
        pass
    return sidecar
