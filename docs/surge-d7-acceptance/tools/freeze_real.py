#!/usr/bin/env python3
"""D7a real-version freeze (Issue #73, GPT D7 review 6912114134,
item 3). READ-ONLY except for its two outputs.

Freezes the REAL production source subscription for the switch
window: reads the production source file
(/opt/free-node-program/publish/pool-new.txt, $SRC of
gate-publish.sh) and the phone evidence that already exists, and
selects 14 candidate lines. It does NOT publish, does NOT touch
any timer/service/phone config, and does NOT run a phone test.

Evidence sources (all read-only):
  1. probe.db probe_nodes (phone P0 hourly probe): per
     fingerprint, state / last_phone_ts / last_second_ms /
     last_success. A line is phone-fresh when state == verified
     and last_second_ms < 300 and last_phone_ts within TTL (24h).
  2. --native-record (native-results.json, transcribed full-group
     native runs): per fingerprint, success / ms / tested_at /
     version_sha. A line is fresh on the CURRENT source SHA when
     a run with version_sha == source SHA passed it <300ms within
     TTL. Runs on older versions only support "stale".
  3. pool.db pinned (the pinned-exemption list): candidate lines
     matching a pinned (protocol, host, port) are flagged; any
     flagged candidate makes publishable=false -- the exemption
     must be cancelled in the switch window first (GPT item 4).
  winner_reports (pool.db) is consulted only as a per-line note
  (latest winner ts by name); name-only matches never count as
  pass evidence.

Per-line evidence status:
  fresh   -- phone pass <300ms within TTL (probe verified, or a
             native run on the CURRENT source SHA).
  stale   -- phone pass <300ms exists, but older than TTL or on an
             older source version (e.g. the 09:05 / 11:24 partial
             rounds: they tested DIFFERENT source versions, so
             they can never make a line fresh for THIS source SHA
             and are never counted as a pass for it).
  partial -- no passing phone evidence at all (failed, slow, or
             never tested).
  unparseable -- the source line cannot be parsed (excluded from
             candidates, recorded).

Manifest status:
  needs_phone_retest -- the default. The frozen SHA has NO single
    full-group native run covering all 14 candidates within TTL.
  evidence_fresh -- all 14 candidates are fresh AND one native
    run with version_sha == source SHA covers all 14 within TTL.
    (Only then is a phone retest not required for THIS freeze.)

publishable is true ONLY when status == evidence_fresh AND no
candidate is pinned. Otherwise the manifest lists the blocking
reasons; the frozen bytes still need the switch-window phone
retest (see staging/phone-retest-steps.md).

Outputs (VPS only, mode 600):
  --frozen-out   the 14 candidate lines (REAL node URIs) -- NEVER
                 enters the PR, the upload package, or any stdout.
  --manifest-out the manifest JSON (SHAs, names, ms, statuses --
                 no URIs, no credentials).
Stdout: one JSON summary (same desensitised content as the
manifest). Nothing else is printed.

Usage (on the VPS, from the D7a tree):
  python3 tools/freeze_real.py --source /opt/free-node-program/publish/pool-new.txt \\
      --probe-db /opt/probe-service/data/probe.db \\
      --pool-db /opt/free-node-program/data/pool.db \\
      --manifest-out /opt/p2p3-d7a/freeze/real-freeze-manifest.json \\
      --frozen-out /opt/p2p3-d7a/freeze/frozen-real-14.txt
"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)

from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402

TTL_SECONDS = 86400  # 24h, same as the probe VERIFY_TTL
PASS_MS = 300
CANDIDATE_COUNT = 14


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def load_probe_evidence(probe_db_path):
    """Read-only. Returns {fingerprint: row-dict} from probe_nodes."""
    out = {}
    if not probe_db_path or not os.path.exists(probe_db_path):
        return out
    db = sqlite3.connect("file:%s?mode=ro" % probe_db_path, uri=True)
    try:
        for row in db.execute(
                "SELECT fingerprint, name, state, last_phone_ts,"
                " last_second_ms, last_success, phone_ok, phone_fail,"
                " last_seen_in_pool FROM probe_nodes"):
            out[row[0]] = {
                "name": row[1], "state": row[2],
                "last_phone_ts": row[3], "last_second_ms": row[4],
                "last_success": row[5], "phone_ok": row[6],
                "phone_fail": row[7], "last_seen_in_pool": row[8],
            }
    finally:
        db.close()
    return out


def load_native_evidence(record_path):
    """Read-only. Returns {fingerprint: best-pass-dict} plus the run
    list (for full-group coverage checks). Best pass = most recent
    success with ms < 300."""
    out = {"by_fp": {}, "runs": []}
    if not record_path or not os.path.exists(record_path):
        return out
    with open(record_path, encoding="utf-8") as f:
        rec = json.load(f)
    for run in rec.get("runs", []):
        passing = set()
        for r in run.get("results", []):
            if not r.get("success"):
                continue
            ms = r.get("ms")
            if ms is None or ms >= PASS_MS:
                continue
            fp = r.get("fingerprint")
            if fp:
                passing.add(fp)
        out["runs"].append({
            "version_sha": run.get("version_sha"),
            "tested_at": run.get("tested_at"),
            "result_count": len(run.get("results", [])),
            "passing_fps": passing,
        })
        for r in run.get("results", []):
            if not r.get("success"):
                continue
            ms = r.get("ms")
            if ms is None or ms >= PASS_MS:
                continue
            fp = r.get("fingerprint")
            if not fp:
                continue
            prev = out["by_fp"].get(fp)
            if prev is None or (run.get("tested_at") or 0) > prev["tested_at"]:
                out["by_fp"][fp] = {
                    "ms": ms, "tested_at": run.get("tested_at"),
                    "version_sha": run.get("version_sha"),
                    "name": r.get("name"),
                }
    return out


def load_pinned(pool_db_path):
    """Read-only. Returns (set of (protocol, host, port), list of
    pinned names)."""
    keys = set()
    names = []
    if not pool_db_path or not os.path.exists(pool_db_path):
        return keys, names
    db = sqlite3.connect("file:%s?mode=ro" % pool_db_path, uri=True)
    try:
        for proto, host, port, name in db.execute(
                "SELECT protocol, host, port, name FROM pinned"):
            keys.add((proto, host, port))
            names.append(name)
    finally:
        db.close()
    return keys, names


def load_winner_notes(pool_db_path):
    """Read-only. Returns {name: latest winner ts} (name-only
    corroboration, never pass evidence)."""
    out = {}
    if not pool_db_path or not os.path.exists(pool_db_path):
        return out
    db = sqlite3.connect("file:%s?mode=ro" % pool_db_path, uri=True)
    try:
        for name, ts in db.execute(
                "SELECT name, MAX(ts) FROM winner_reports GROUP BY name"):
            out[name] = ts
    finally:
        db.close()
    return out


def classify_line(line, source_sha, probe, native, now):
    """Evidence classification for one parsed source line.
    Returns a dict (never raises)."""
    name, proto, host, port, params = parse_surge_line(line)
    fp = fingerprint_of(proto, host, port, params)
    rec = {"name": name, "protocol": proto, "host": host, "port": port,
           "fingerprint_prefix": fp[:12], "fingerprint": fp,
           "evidence": "partial", "last_pass_ms": None,
           "last_pass_at": None, "last_pass_source": None,
           "evidence_run_version_prefix": None,
           "probe_state": None, "pinned": False}
    best = None  # (tested_at, ms, source, version_sha_or_None)
    prow = probe.get(fp)
    if prow:
        rec["probe_state"] = prow["state"]
        if (prow["state"] == "verified"
                and prow["last_second_ms"] is not None
                and prow["last_second_ms"] < PASS_MS
                and prow["last_phone_ts"] is not None):
            best = (prow["last_phone_ts"], prow["last_second_ms"],
                    "probe", None)
    nrow = native["by_fp"].get(fp)
    if nrow:
        cand = (nrow["tested_at"], nrow["ms"], "native",
                nrow["version_sha"])
        if best is None or cand[0] > best[0]:
            best = cand
    if best is None:
        return rec
    ts, ms, source, vsha = best
    rec["last_pass_ms"] = ms
    rec["last_pass_at"] = ts
    rec["last_pass_source"] = source
    if vsha:
        rec["evidence_run_version_prefix"] = vsha[:12]
    if source == "native" and vsha == source_sha and now - ts <= TTL_SECONDS:
        rec["evidence"] = "fresh"
    elif source == "probe" and now - ts <= TTL_SECONDS:
        rec["evidence"] = "fresh"
    else:
        rec["evidence"] = "stale"
    return rec


def freeze(source_path, probe_db_path, pool_db_path,
           native_record_path=None, now=None):
    """Read-only selection. Returns (manifest_dict, frozen_lines).
    frozen_lines are the REAL candidate lines (caller must keep
    them off the PR / stdout)."""
    now = int(now if now is not None else time.time())
    with open(source_path, "rb") as f:
        source_bytes = f.read()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    source_lines = [l for l in source_bytes.decode(
        "utf-8", errors="ignore").splitlines() if l.strip()]
    probe = load_probe_evidence(probe_db_path)
    native = load_native_evidence(native_record_path)
    pinned_keys, pinned_names = load_pinned(pool_db_path)
    winner_notes = load_winner_notes(pool_db_path)

    classified = []
    unparseable = []
    for line in source_lines:
        try:
            rec = classify_line(line, source_sha, probe, native, now)
        except Exception:
            unparseable.append({"line_prefix": line[:24],
                                "reason": "parse_error"})
            continue
        rec["pinned"] = (rec["protocol"], rec["host"], rec["port"]
                         ) in pinned_keys
        rec["last_winner_report_ts"] = winner_notes.get(rec["name"])
        rec["_line"] = line
        classified.append(rec)

    def _rank_key(rec):
        # Passing evidence first (fresh > stale > partial), then
        # most recent pass, then lowest ms.
        order = {"fresh": 0, "stale": 1, "partial": 2}
        return (order[rec["evidence"]],
                -(rec["last_pass_at"] or 0),
                rec["last_pass_ms"] if rec["last_pass_ms"] is not None
                else 10 ** 9)

    ranked = sorted(classified, key=_rank_key)
    chosen = ranked[:CANDIDATE_COUNT]

    # Full-group evidence: ONE native run with version_sha ==
    # source SHA, within TTL, whose passing set covers ALL chosen
    # fingerprints. (A union of different runs never counts: the
    # group must have been tested together on this exact version.)
    chosen_fps = {c["fingerprint"] for c in chosen}
    full_group = any(
        run["version_sha"] == source_sha
        and run["tested_at"] is not None
        and now - run["tested_at"] <= TTL_SECONDS
        and chosen_fps <= run["passing_fps"]
        for run in native["runs"])
    all_fresh = all(c["evidence"] == "fresh" for c in chosen)
    status = ("evidence_fresh" if (all_fresh and full_group)
              else "needs_phone_retest")
    pinned_in = [c["name"] for c in chosen if c["pinned"]]
    blockers = []
    if status != "evidence_fresh":
        blockers.append("no_fresh_full_group_evidence_for_frozen_sha")
    if pinned_in:
        blockers.append("pinned_exemption_present_in_candidates")
    publishable = (status == "evidence_fresh" and not pinned_in)

    frozen_lines = [c["_line"] for c in chosen]
    frozen_sha = sha_bytes(("\n".join(frozen_lines) + "\n").encode("utf-8"))
    candidates = []
    for c in chosen:
        candidates.append({
            "name": c["name"],
            "fingerprint_prefix": c["fingerprint_prefix"],
            "evidence": c["evidence"],
            "last_pass_ms": c["last_pass_ms"],
            "last_pass_at": c["last_pass_at"],
            "last_pass_source": c["last_pass_source"],
            "evidence_run_version_prefix":
                c["evidence_run_version_prefix"],
            "probe_state": c["probe_state"],
            "pinned": c["pinned"],
            "last_winner_report_ts": c["last_winner_report_ts"],
        })
    manifest = {
        "tool": "freeze_real",
        "frozen_at": now,
        "source": {"path": source_path,
                   "sha256": source_sha,
                   "sha256_prefix": source_sha[:12],
                   "lines": len(source_lines)},
        "candidates": {"count": len(candidates),
                       "sha256": frozen_sha,
                       "sha256_prefix": frozen_sha[:12],
                       "lines": candidates},
        "evidence_summary": {
            "fresh": sum(1 for c in chosen if c["evidence"] == "fresh"),
            "stale": sum(1 for c in chosen if c["evidence"] == "stale"),
            "partial": sum(1 for c in chosen
                           if c["evidence"] == "partial"),
            "unparseable_lines": len(unparseable),
            "native_runs_consulted": len(native["runs"]),
            "probe_rows_consulted": len(probe),
            "full_group_evidence_for_frozen_sha": full_group,
        },
        "pinned_check": {
            "pinned_table_rows": len(pinned_names),
            "pinned_in_source_lines": sum(
                1 for c in classified if c["pinned"]),
            "pinned_in_candidates": len(pinned_in),
            "pinned_candidate_names": pinned_in,
        },
        "status": status,
        "publishable": publishable,
        "blockers": blockers,
        "unparseable": unparseable,
    }
    return manifest, frozen_lines


def main(argv=None):
    ap = argparse.ArgumentParser(description="D7a real-version freeze "
                                            "(read-only, Issue #73)")
    ap.add_argument("--source", required=True)
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--pool-db", default=None)
    ap.add_argument("--native-record", default=None)
    ap.add_argument("--manifest-out", required=True)
    ap.add_argument("--frozen-out", required=True)
    ap.add_argument("--now", type=int, default=None)
    args = ap.parse_args(argv)
    manifest, frozen_lines = freeze(
        args.source, args.probe_db, args.pool_db,
        native_record_path=args.native_record, now=args.now)
    for path, data in ((args.frozen_out,
                        ("\n".join(frozen_lines) + "\n").encode("utf-8")),
                       (args.manifest_out,
                        (json.dumps(manifest, ensure_ascii=False, indent=2)
                         + "\n").encode("utf-8"))):
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.rename(tmp, path)
    summary = dict(manifest)
    summary["frozen_file"] = {"lines": len(frozen_lines),
                              "sha256_prefix": manifest["candidates"]["sha256_prefix"],
                              "path_recorded_only_on_vps": True}
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
