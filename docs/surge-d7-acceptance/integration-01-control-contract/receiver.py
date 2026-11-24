#!/usr/bin/env python3
"""Fail-closed PHONE probe ingress. Staging evidence ONLY; not a publisher.

Loopback listener behind separately configured authenticated HTTPS reverse proxy.
No real proxy URI/secret is included in outputs or log entries.

Formal-control mode (integration-01, Issue #73 G1-G7): when configured
with PHONE_PROBE_FORMAL_POOL + PHONE_PROBE_FORMAL_MANIFEST, controls are
validated against the FORMAL pool instead of the trial pool: V2 formal
pool SHA + manifest generation binding, V3 control identity byte-identical
to the formal pool entry, V4 control not a trial member, V5 control not a
batch candidate, V6 control in the manifest's eligible_controls, V7
probe_mode='external_policy_id' and at most 2 controls. Any failure
rejects the whole batch (422, fail-closed); the "drop the control and
accept the candidate" alternative was rejected (G3). When the two env
vars are unset, behaviour is exactly the legacy in-pool-control path
(formal receiver, 8724, unchanged).

Integration-01 v2 (Review 6033276893, 5 items):
  1. C4 is verified by the RECEIVER (V8): the control's source group comes
     from the server-side formal manifest and each candidate's group from
     the server-side trial manifest; unknown or same-group rejects the
     batch. Client-claimed group strings are never trusted as identity.
  2. Trial generation is validated and persistently bound: the trial
     manifest (PHONE_PROBE_TRIAL_MANIFEST) supplies generation + TTL;
     batches store trial_generation / formal_generation / control_snapshot
     and each observation stores trial_generation + dual_target_ok.
     Legacy batches (no trial_generation in the payload) are accepted but
     their rows are legacy evidence (NULL generation, never counted by the
     new generation-bound gates). A->B->A same bytes cannot cross
     generations because the generation differs.
  3. The formal manifest carries a qualification_snapshot (SHA-256 of the
     canonical eligible-controls list); the receiver refuses a manifest
     whose snapshot does not match its list or whose updated_at is older
     than FORMAL_MANIFEST_MAX_AGE_S. Expired qualification lists are
     never consumed.
  4. Dual-target evidence is recorded per observation (dual_target_ok=1
     only when BOTH targets are reachable); the old single-target
     'success' status is kept for raw/status compatibility but is no
     longer sufficient proof for DIAGNOSTIC_PASS/READY (see
     verify_promotion.py v2).
  5. Rollback: restore the v1 receiver only; keep the v2 consumers
     (verify_promotion.py, auto_prune.py, importers) which treat NULL
     generation / dual_target_ok=0 rows as legacy. Never restore v1
     consumers while v2 rows exist; never whole-DB restore; never delete
     rows. Schema changes are additive only.
"""
from __future__ import annotations
import hashlib
import hmac
from datetime import date, datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time

MAX_BODY = 16384
MAX_OBSERVATIONS = 6
HEX64 = re.compile(r'^[a-f0-9]{64}$')
HEX32 = re.compile(r'^[a-f0-9]{32}$')
ALLOWED_RESULTS = frozenset({'reachable','timeout','transport_error','unknown'})
VALID_PROTOCOLS = frozenset({'trojan','vmess','ss'})
MAX_CLOCK_SKEW = 300
# Formal manifest freshness: the generator runs hourly; a manifest older
# than this is an expired qualification list and must not be consumed.
FORMAL_MANIFEST_MAX_AGE_S = 7200


def canonical_eligible_controls(eligible):
    """Canonical JSON of an eligible-controls list (snapshot binding).

    Only the identity + source_group fields enter the snapshot; health
    timestamps are deliberately excluded so a health-only refresh does
    not change the snapshot (A17). Both the generator (formal_manifest.py)
    and this receiver use this exact canonicalisation.
    """
    items = sorted(({
        "name": str(e.get("name", "")),
        "protocol": str(e.get("protocol", "")).lower(),
        "host": str(e.get("host", "")).lower(),
        "port": int(e["port"]),
        "source_group": str(e.get("source_group", "")),
    } for e in eligible), key=lambda d: (d["protocol"], d["host"], d["port"]))
    return json.dumps(items, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def qualification_snapshot_id(eligible):
    """SHA-256 of the canonical eligible-controls list."""
    return hashlib.sha256(
        canonical_eligible_controls(eligible).encode("utf-8")).hexdigest()


def manifest_ttl_status(manifest, now):
    """Return (ok, label) for a manifest TTL date string.

    ok=False when the TTL is missing/unparseable or the date has passed.
    The TTL date itself is the last valid day (inclusive).
    """
    try:
        ttl = date.fromisoformat(str(manifest.get("ttl")))
    except (ValueError, TypeError, AttributeError):
        return False, "TTL_INVALID"
    today = datetime.fromtimestamp(now, tz=timezone.utc).date()
    if today > ttl:
        return False, "TTL_EXPIRED"
    return True, "TTL_OK"

class InputRejected(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def parse_pool(raw: bytes, min_pool: int = 22):
    """Parse keys only, never store, return or log proxy secret text."""
    if not raw or len(raw) > 2 * 1024 * 1024:
        raise InputRejected('invalid_pool')
    try:
        text = raw.decode('utf-8')
    except UnicodeError as e:
        raise InputRejected('invalid_utf8') from e
    found = {}
    used = set()
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if '=' not in line:
            raise InputRejected('invalid_pool_line')
        name, declaration = (x.strip() for x in line.split('=',1))
        pieces = [x.strip() for x in declaration.split(',')]
        if len(pieces) < 3 or pieces[0].lower() not in VALID_PROTOCOLS:
            raise InputRejected('unrecognized_proxy_type')
        try:
            port = int(pieces[2])
        except (ValueError, TypeError) as e:
            raise InputRejected('invalid_port') from e
        if not (1 <= port <= 65535 and pieces[1] and name):
            raise InputRejected('invalid_identity')
        identity = (pieces[0].lower(), pieces[1].lower(), port)
        if name in found or identity in used:
            raise InputRejected('duplicate_identity')
        found[name] = identity
        used.add(identity)
    if len(found) < min_pool:
        raise InputRejected('pool_unexpectedly_short')
    return found


def classify(results):
    if not isinstance(results, list) or len(results) != 2:
        raise InputRejected('two_targets_required')
    urlids=set()
    classes=[]
    for r in results:
        if not isinstance(r, dict) or r.get('id') not in ('a','b'):
            raise InputRejected('invalid_result')
        if r.get('id') in urlids or r.get('state') not in ALLOWED_RESULTS:
            raise InputRejected('invalid_result')
        urlids.add(r['id']);classes.append(r['state'])
    if urlids != {'a','b'}:
        raise InputRejected('two_targets_required')
    if 'reachable' in classes:
        return 'success'
    if all(c in ('timeout','transport_error') for c in classes):
        return 'failure'
    return 'unknown'


def validate(payload, pool_bytes, now=None, *, descriptor_accepted=False,
             formal_pool_bytes=None, formal_manifest=None,
             trial_manifest=None,
             group: str = '\u514d\u8d39\u8282\u70b9\u6c60', min_pool: int = 22):
    """Validate one probe batch; returns (observations, batch_meta).

    observations: list of 11-tuples
      (protocol, host, port, status, probe_mode, trusted, reason,
       raw_status, raw_reason, control_verified, dual_target_ok).
    batch_meta: {"trial_generation": int|None,
                 "formal_generation": int|None,
                 "control_snapshot": dict|None} for persistent binding
      (record_batch stores it in the batches table).
    """
    now = int(time.time()) if now is None else now
    if not isinstance(payload, dict) or payload.get('schema')!=1:
        raise InputRejected('invalid_schema')
    if payload.get('group')!=group:
        raise InputRejected('invalid_group')
    if not isinstance(payload.get('pool_sha'),str) or not HEX64.fullmatch(payload['pool_sha']):
        raise InputRejected('invalid_pool_sha')
    if payload['pool_sha'] != hashlib.sha256(pool_bytes).hexdigest():
        raise InputRejected('stale_pool_sha')
    if not isinstance(payload.get('nonce'),str) or not HEX32.fullmatch(payload['nonce']):
        raise InputRejected('invalid_nonce')
    ts=payload.get('timestamp')
    if type(ts) is not int or abs(now-ts)>MAX_CLOCK_SKEW:
        raise InputRejected('invalid_timestamp')
    if payload.get('bearer') not in ('wifi','cellular','unknown'):
        raise InputRejected('invalid_bearer')
    version = payload.get('surge_version')
    if not isinstance(version,str) or not 1<=len(version)<=32 or not re.fullmatch(r'[0-9A-Za-z.\-]+',version):
        raise InputRejected('invalid_version')
    observations=payload.get('observations')
    if not isinstance(observations,list) or not 1<=len(observations)<=MAX_OBSERVATIONS:
        raise InputRejected('invalid_observations')
    names=parse_pool(pool_bytes, min_pool=min_pool)
    # --- Trial manifest binding (integration-01 v2, fix 2) ---
    # The trial manifest is the server-side binding for the trial pool:
    # pool_sha + generation + TTL + per-entry source_group. When it is
    # configured, a batch's trial_generation must match it and the TTL
    # must be live; otherwise the batch is rejected (fail-closed). A
    # payload WITHOUT trial_generation is a legacy batch: accepted, but
    # its rows are stored with trial_generation NULL and are legacy
    # evidence (never counted by the new generation-bound gates).
    # When no trial manifest is configured, no trial binding applies.
    trial_generation = None
    trial_groups = {}  # trial pool name -> source_group ("unknown" if absent)
    if trial_manifest is not None:
        if not isinstance(trial_manifest, dict):
            raise InputRejected('invalid_trial_manifest')
        if trial_manifest.get("pool_sha") != hashlib.sha256(pool_bytes).hexdigest():
            raise InputRejected('stale_trial_manifest')
        ttl_ok, _ttl_label = manifest_ttl_status(trial_manifest, now)
        if not ttl_ok:
            raise InputRejected('trial_ttl_expired')
        manifest_gen = trial_manifest.get("generation")
        if type(manifest_gen) is not int:
            raise InputRejected('trial_generation_missing')
        entries = trial_manifest.get("entries")
        if not isinstance(entries, list):
            raise InputRejected('invalid_trial_manifest')
        for entry in entries:
            if isinstance(entry, dict) and isinstance(entry.get("name"), str):
                trial_groups[entry["name"]] = entry.get("source_group") or "unknown"
        payload_gen = payload.get("trial_generation")
        if payload_gen is not None:
            if type(payload_gen) is not int or payload_gen != manifest_gen:
                raise InputRejected('stale_trial_generation')
            trial_generation = payload_gen
    # A same-batch control is independently probed through another group
    # member on this iPhone. Two unreachable controls cannot prove a phone
    # outage; one reachable control disproves the "all proxies down = phone
    # offline" assumption. Legacy v2 batches without controls remain safe.
    controls=payload.get('network_controls',[])
    if not isinstance(controls,list) or len(controls)>2:
        raise InputRejected('invalid_network_controls')
    sample_names={x.get('name') for x in observations if isinstance(x,dict)}
    controls_seen=set()
    control_verified=False
    formal_generation = None
    control_snapshot = None
    if formal_manifest is not None:
        # Formal-control mode (integration-01): controls are formal-pool
        # members validated against the formal pool file + formal manifest
        # snapshot. Any failure rejects the whole batch (fail-closed).
        # V2: formal pool SHA + manifest generation binding.
        # V3: control identity byte-identical to the formal pool entry.
        # V4: control not a trial member. V5: control not a batch candidate.
        # V6: control in the manifest's eligible_controls.
        # V7: probe_mode='external_policy_id' and at most 2 controls
        # (count checked above). Controls are never stored as observations.
        # V2 (integration-01 v2, fix 2/3): when this batch carries controls,
        # the formal manifest must carry a qualification_snapshot whose id
        # matches the canonical eligible-controls list, and updated_at must
        # be fresh; an expired or tampered qualification list is never
        # consumed. Batches without controls do not consume the list and
        # keep the legacy path (same as an unreadable formal manifest).
        # V8 (integration-01 v2, fix 1, C4): the control's source group
        # (from the server-side formal manifest) must be known and must
        # differ from EVERY candidate's source group in this batch
        # (candidate groups from the server-side trial manifest). Client
        # claims are never trusted as identity credentials.
        if controls:
            snap = formal_manifest.get('qualification_snapshot')
            if not isinstance(snap, dict):
                raise InputRejected('formal_manifest_snapshot_missing')
            eligible_raw_pre = formal_manifest.get('eligible_controls', [])
            if not isinstance(eligible_raw_pre, list):
                raise InputRejected('invalid_formal_manifest')
            try:
                if snap.get('snapshot_id') != qualification_snapshot_id(eligible_raw_pre):
                    raise InputRejected('formal_manifest_snapshot_mismatch')
            except (KeyError, TypeError, ValueError) as e:
                raise InputRejected('formal_manifest_snapshot_mismatch') from e
            updated_at = formal_manifest.get('updated_at')
            try:
                updated_ts = int(datetime.strptime(str(updated_at), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp())
            except (ValueError, TypeError):
                raise InputRejected('stale_formal_manifest')
            if updated_ts > now + MAX_CLOCK_SKEW or now - updated_ts > FORMAL_MANIFEST_MAX_AGE_S:
                raise InputRejected('stale_formal_manifest')
            if snap.get('generated_at') != updated_at:
                raise InputRejected('formal_manifest_snapshot_mismatch')
            if trial_manifest is None:
                # C4 cannot be verified without the server-side trial
                # manifest: no control can be trusted. Batches without
                # controls keep the legacy path below.
                raise InputRejected('trial_manifest_missing')
            formal_sha=payload.get('formal_pool_sha')
            if (not isinstance(formal_sha,str) or not HEX64.fullmatch(formal_sha)
                    or formal_sha!=hashlib.sha256(formal_pool_bytes).hexdigest()):
                raise InputRejected('stale_formal_pool_sha')
            if formal_manifest.get('pool_sha')!=hashlib.sha256(formal_pool_bytes).hexdigest():
                raise InputRejected('stale_formal_pool_sha')
            formal_gen=payload.get('formal_generation')
            manifest_gen=formal_manifest.get('generation')
            if (type(formal_gen) is not int or type(manifest_gen) is not int
                    or formal_gen!=manifest_gen):
                raise InputRejected('stale_formal_generation')
            formal_generation = formal_gen
            formal_names=parse_pool(formal_pool_bytes, min_pool=1)
            eligible_group_by_identity={}
            eligible_raw=formal_manifest.get('eligible_controls',[])
            if not isinstance(eligible_raw,list):
                raise InputRejected('invalid_formal_manifest')
            for item in eligible_raw:
                if not isinstance(item,dict):
                    raise InputRejected('invalid_formal_manifest')
                try:
                    ident=(str(item['protocol']).lower(),
                           str(item['host']).lower(), int(item['port']))
                except (KeyError,TypeError,ValueError) as e:
                    raise InputRejected('invalid_formal_manifest') from e
                # The group is part of the manifest entry; a missing group
                # is "unknown" and can never serve as a C4 control.
                eligible_group_by_identity[ident]=str(item.get('source_group') or 'unknown')
            trial_identities=set(names.values())
            sample_identities={names[x] for x in sample_names if x in names}
            # Candidate source groups, derived server-side from the trial
            # manifest (never from payload claims). Every candidate must
            # have a known group, or C4 cannot be decided (fail-closed).
            candidate_groups={}
            for cand_name in sample_names:
                cand_group=trial_groups.get(cand_name, 'unknown')
                if cand_group=='unknown':
                    raise InputRejected('candidate_group_unknown')
                candidate_groups[cand_name]=cand_group
            validated_controls=[]
            for control in controls:
                if not isinstance(control,dict):
                    raise InputRejected('invalid_network_control')
                control_name=control.get('name')
                control_protocol=control.get('protocol')
                control_host=control.get('host')
                control_port=control.get('port')
                if (not isinstance(control_name,str) or control_name not in formal_names
                        or not isinstance(control_protocol,str)
                        or not isinstance(control_host,str)
                        or type(control_port) is not int):
                    raise InputRejected('unknown_formal_control')
                control_identity=(control_protocol.lower(),control_host.lower(),control_port)
                if formal_names[control_name]!=control_identity:
                    raise InputRejected('unknown_formal_control')
                if control_identity in trial_identities:
                    raise InputRejected('control_is_trial_member')
                if control_identity in sample_identities:
                    raise InputRejected('unsafe_network_control_identity')
                if control_identity in controls_seen:
                    raise InputRejected('unsafe_network_control_identity')
                controls_seen.add(control_identity)
                if control_identity not in eligible_group_by_identity:
                    raise InputRejected('formal_control_not_eligible')
                if control.get('probe_mode')!='external_policy_id':
                    raise InputRejected('untrusted_network_control_mode')
                # V8 (C4): control group must be known and different from
                # every candidate group in this batch.
                control_group=eligible_group_by_identity[control_identity]
                if control_group=='unknown':
                    raise InputRejected('formal_control_group_unknown')
                if control_group in candidate_groups.values():
                    raise InputRejected('control_same_source_group')
                validated_controls.append({
                    "name": control_name,
                    "protocol": control_identity[0],
                    "host": control_identity[1],
                    "port": control_identity[2],
                    "source_group": control_group,
                })
                if classify(control.get('results'))=='success' and payload['bearer']!='unknown':
                    control_verified=True
            control_snapshot={
                "controls": validated_controls,
                "formal_generation": formal_generation,
                "formal_pool_sha": hashlib.sha256(formal_pool_bytes).hexdigest(),
                "trial_generation": trial_generation,
                "trial_pool_sha": hashlib.sha256(pool_bytes).hexdigest(),
            }
    else:
        # Legacy in-pool-control path (formal receiver unchanged).
        for control in controls:
            if not isinstance(control,dict):
                raise InputRejected('invalid_network_control')
            control_name=control.get('name')
            if (not isinstance(control_name,str) or control_name not in names
                    or control_name in sample_names or control_name in controls_seen):
                raise InputRejected('unsafe_network_control_identity')
            controls_seen.add(control_name)
            # Descriptor traffic is not an authoritative connectivity control
            # without a proven identical group-policy binding.
            if control.get('probe_mode')!='external_policy_id':
                raise InputRejected('untrusted_network_control_mode')
            if classify(control.get('results'))=='success' and payload['bearer']!='unknown':
                control_verified=True
    seen=set(); output=[]
    for obs in observations:
        if not isinstance(obs,dict):
            raise InputRejected('invalid_observation')
        name=obs.get('name')
        if not isinstance(name,str) or name not in names or name in seen:
            raise InputRejected('unknown_or_duplicate_name')
        seen.add(name)
        mode=obs.get('probe_mode')
        if mode not in ('external_policy_id','temporary_policy_descriptor'):
            raise InputRejected('invalid_probe_mode')
        results=obs.get('results')
        raw_status=classify(results)
        status=raw_status
        if status=='success':
            reason='target_reachable'
        elif status=='failure':
            reason='dual_transport_failure'
        elif any(x.get('hint')=='http_status' for x in results):
            reason='http_status_inconclusive'
        elif any(x.get('hint')=='other_error' for x in results):
            reason='unexpected_error'
        else:
            reason='target_inconclusive'
        raw_reason=reason
        if payload['bearer']=='unknown' and status=='failure':
            status='unknown'
            reason='unknown_network_bearer'
        # Temporary policy descriptors can diverge from group settings;
        # never admit their failures to permanent deletion without a later
        # explicit device-level capability/identity acceptance.
        trusted = ((mode=='external_policy_id' or (mode=='temporary_policy_descriptor' and descriptor_accepted))
                   and payload['bearer']!='unknown')
        if status=='failure' and not trusted:
            status='unknown'
            reason='untrusted_policy_descriptor' if mode=='temporary_policy_descriptor' else 'untrusted_probe'
        protocol,host,port=names[name]
        # Preserve the original per-node inference independent of any batch
        # safety downgrade, without retaining raw URLs, errors or credentials.
        # dual_target_ok (integration-01 v2, fix 4): 1 only when BOTH
        # targets are reachable. The old single-target 'success' status is
        # kept for raw/status compatibility, but dual_target_ok is the
        # auditable proof DIAGNOSTIC_PASS/READY require.
        dual_target_ok = 1 if all(r.get('state') == 'reachable' for r in results) else 0
        output.append((protocol,host,port,status,mode,1 if trusted else 0,
                       reason,raw_status,raw_reason,1 if control_verified else 0,
                       dual_target_ok))
    # All-nodes-failed is NOT evidence that the iPhone has lost connectivity.
    # Admit an all-failure batch only when a distinct policy identifier has
    # independently reached one of the two network control endpoints in
    # the SAME batch. Otherwise hold the normalized evidence as unknown but
    # preserve the observed transport failure in raw_status/raw_reason.
    if len(output)>=3 and all(x[3]=='failure' for x in output) and not control_verified:
        output=[(*x[:3],'unknown',x[4],x[5],'batch_unverified_network',
                 x[7],x[8],0,x[10]) for x in output]
    batch_meta={
        "trial_generation": trial_generation,
        "formal_generation": formal_generation,
        "control_snapshot": control_snapshot,
    }
    return output, batch_meta


def initialize_db(path):
    p=Path(path)
    p.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    conn=sqlite3.connect(p)
    try:
        conn.execute('PRAGMA journal_mode=WAL')
        conn.executescript('''
CREATE TABLE IF NOT EXISTS batches (nonce TEXT PRIMARY KEY, received_at INTEGER NOT NULL, payload_sha TEXT NOT NULL, trial_generation INTEGER, formal_generation INTEGER, control_snapshot TEXT);
CREATE TABLE IF NOT EXISTS phone_observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nonce TEXT NOT NULL REFERENCES batches(nonce),
  protocol TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('success','failure','unknown')),
  probe_mode TEXT NOT NULL, trusted INTEGER NOT NULL CHECK(trusted IN (0,1)),
  received_at INTEGER NOT NULL,
  bearer TEXT NOT NULL, pool_sha TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT 'legacy_unclassified',
  raw_status TEXT NOT NULL DEFAULT 'legacy_unknown',
  raw_reason TEXT NOT NULL DEFAULT 'legacy_unclassified',
  control_verified INTEGER NOT NULL DEFAULT 0 CHECK(control_verified IN (0,1)),
  trial_generation INTEGER,
  dual_target_ok INTEGER NOT NULL DEFAULT 0 CHECK(dual_target_ok IN (0,1))
);
CREATE INDEX IF NOT EXISTS phone_observations_by_identity ON phone_observations(protocol,host,port,received_at);
''')
        # Additive migration; existing importers select explicit legacy columns.
        # v2 (integration-01 v2, fix 2/4): trial_generation binds a row to
        # the trial manifest generation it was recorded under (NULL =
        # legacy, never counted by the new generation-bound gates);
        # dual_target_ok=1 proves BOTH targets were reachable.
        # batches gains the same generation binding + the control snapshot
        # (the validated control identities/groups + both manifest
        # generations/SHAs) for auditability.
        columns={row[1] for row in conn.execute('PRAGMA table_info(phone_observations)')}
        for column,definition in (
            ('reason',"TEXT NOT NULL DEFAULT 'legacy_unclassified'"),
            ('raw_status',"TEXT NOT NULL DEFAULT 'legacy_unknown'"),
            ('raw_reason',"TEXT NOT NULL DEFAULT 'legacy_unclassified'"),
            ('control_verified',"INTEGER NOT NULL DEFAULT 0"),
            ('trial_generation',"INTEGER"),
            ('dual_target_ok',"INTEGER NOT NULL DEFAULT 0"),
        ):
            if column not in columns:
                conn.execute("ALTER TABLE phone_observations ADD COLUMN "+column+" "+definition)
        bcolumns={row[1] for row in conn.execute('PRAGMA table_info(batches)')}
        for column,definition in (
            ('trial_generation',"INTEGER"),
            ('formal_generation',"INTEGER"),
            ('control_snapshot',"TEXT"),
        ):
            if column not in bcolumns:
                conn.execute("ALTER TABLE batches ADD COLUMN "+column+" "+definition)
        conn.commit()
    finally:
        conn.close()
    os.chmod(p, 0o600)


def record_batch(db_path, payload, observations, batch_meta=None, now=None):
    now=int(time.time()) if now is None else now
    meta = batch_meta or {}
    trial_generation = meta.get("trial_generation")
    formal_generation = meta.get("formal_generation")
    snapshot = meta.get("control_snapshot")
    snapshot_text = (json.dumps(snapshot, ensure_ascii=False, sort_keys=True)
                     if snapshot is not None else None)
    conn=sqlite3.connect(db_path,timeout=5)
    try:
        conn.execute('BEGIN IMMEDIATE')
        if conn.execute('SELECT 1 FROM batches WHERE nonce=?',(payload['nonce'],)).fetchone():
            conn.rollback();return 'duplicate'
        conn.execute('INSERT INTO batches VALUES(?,?,?,?,?,?)',
                     (payload['nonce'],now,payload['pool_sha'],
                      trial_generation, formal_generation, snapshot_text))
        conn.executemany('''INSERT INTO phone_observations
(nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified,trial_generation,dual_target_ok)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',[
 (payload['nonce'],proto,host,port,status,mode,trust,now,payload['bearer'],payload['pool_sha'],reason,raw_status,raw_reason,control_ok,trial_generation,dual_ok)
 for proto,host,port,status,mode,trust,reason,raw_status,raw_reason,control_ok,dual_ok in observations])
        conn.commit();return 'stored'
    except Exception:
        conn.rollback();raise
    finally: conn.close()

class Handler(BaseHTTPRequestHandler):
    server_version='PhoneProbe/1.0'
    def log_message(self,*args):
        # Never log auth, host identity or raw body.
        pass
    def respond(self, status, body):
        blob=json.dumps(body,ensure_ascii=True,separators=(',',':')).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type','application/json')
        self.send_header('Cache-Control','no-store')
        self.send_header('Content-Length',str(len(blob)))
        self.end_headers();self.wfile.write(blob)
    def do_POST(self):
        if self.path!='/v1/phone-observations':
            return self.respond(404,{'ok':False})
        expected=os.environ.get('PHONE_PROBE_TOKEN','')
        actual=self.headers.get('Authorization','')
        if len(expected)<32 or not hmac.compare_digest(actual,'Bearer '+expected):
            return self.respond(401,{'ok':False})
        size=self.headers.get('Content-Length','')
        if not size.isdecimal() or not 0<int(size)<=MAX_BODY:
            return self.respond(413,{'ok':False})
        try:
            body=self.rfile.read(int(size))
            payload=json.loads(body)
            pool=Path(os.environ['PHONE_PROBE_POOL']).read_bytes()
            _min_pool = 22
            try:
                _min_pool = int(os.environ.get('PHONE_PROBE_MIN_POOL', '22'))
            except ValueError:
                return self.respond(422,{'ok':False})
            # Formal-control mode (integration-01): both env vars must be
            # set together (enforced in main()). If the formal pool file
            # or manifest cannot be read, batches WITH controls fail closed
            # (422); batches without controls keep the legacy path.
            _formal_pool=None
            _formal_manifest=None
            if os.environ.get('PHONE_PROBE_FORMAL_POOL') or os.environ.get('PHONE_PROBE_FORMAL_MANIFEST'):
                try:
                    _formal_pool=Path(os.environ['PHONE_PROBE_FORMAL_POOL']).read_bytes()
                    _formal_manifest=json.loads(Path(os.environ['PHONE_PROBE_FORMAL_MANIFEST']).read_text(encoding='utf-8'))
                    if not isinstance(_formal_manifest,dict):
                        raise ValueError('formal manifest is not an object')
                except (OSError,ValueError,UnicodeError,KeyError):
                    _formal_pool=None
                    _formal_manifest=None
                    if payload.get('network_controls'):
                        return self.respond(422,{'ok':False})
            # Trial manifest (integration-01 v2, fix 2): when configured it
            # is the server-side binding for the trial pool (pool_sha +
            # generation + TTL + per-entry source_group). If it cannot be
            # read/parsed, every batch fails closed (422) because the trial
            # binding itself is broken. When unset, no trial binding
            # applies and rows are legacy evidence.
            _trial_manifest=None
            if os.environ.get('PHONE_PROBE_TRIAL_MANIFEST'):
                try:
                    _trial_manifest=json.loads(Path(os.environ['PHONE_PROBE_TRIAL_MANIFEST']).read_text(encoding='utf-8'))
                    if not isinstance(_trial_manifest,dict):
                        raise ValueError('trial manifest is not an object')
                except (OSError,ValueError,UnicodeError,KeyError):
                    return self.respond(422,{'ok':False})
            observations,batch_meta=validate(
                payload,pool,descriptor_accepted=(
                    os.environ.get('PHONE_PROBE_DESCRIPTOR_ACCEPTED')=='YES_AFTER_DEVICE_VALIDATION'),
                group=os.environ.get('PHONE_PROBE_GROUP', '\u514d\u8d39\u8282\u70b9\u6c60'),
                min_pool=_min_pool,
                formal_pool_bytes=_formal_pool, formal_manifest=_formal_manifest,
                trial_manifest=_trial_manifest)
            state=record_batch(os.environ['PHONE_PROBE_DB'],payload,observations,batch_meta)
        except (UnicodeError,ValueError,KeyError, OSError, sqlite3.Error):
            return self.respond(422,{'ok':False})
        self.respond(200,{'ok':True,'receipt':state,'accepted':len(observations)})

def main():
    for field in ('PHONE_PROBE_POOL','PHONE_PROBE_DB','PHONE_PROBE_TOKEN'):
        if not os.environ.get(field):raise SystemExit('missing environment variable '+field)
    if len(os.environ['PHONE_PROBE_TOKEN'])<32:raise SystemExit('token must be >=32 chars')
    _fp=os.environ.get('PHONE_PROBE_FORMAL_POOL')
    _fm=os.environ.get('PHONE_PROBE_FORMAL_MANIFEST')
    if bool(_fp)!=bool(_fm):
        raise SystemExit('PHONE_PROBE_FORMAL_POOL and PHONE_PROBE_FORMAL_MANIFEST must be set together')
    _tm=os.environ.get('PHONE_PROBE_TRIAL_MANIFEST')
    if _tm and not (_fp and _fm):
        raise SystemExit('PHONE_PROBE_TRIAL_MANIFEST requires PHONE_PROBE_FORMAL_POOL and PHONE_PROBE_FORMAL_MANIFEST')
    _g = os.environ.get('PHONE_PROBE_GROUP')
    if _g is not None and not (1 <= len(_g) <= 32):
        raise SystemExit('invalid PHONE_PROBE_GROUP')
    _m = os.environ.get('PHONE_PROBE_MIN_POOL')
    if _m is not None:
        try:
            _mi = int(_m)
        except ValueError:
            raise SystemExit('invalid PHONE_PROBE_MIN_POOL')
        if not (1 <= _mi <= 22):
            raise SystemExit('invalid PHONE_PROBE_MIN_POOL')
    initialize_db(os.environ['PHONE_PROBE_DB'])
    addr=('127.0.0.1', int(os.environ.get('PHONE_PROBE_PORT','8724')))
    print('Phone probe staging receiver listening on loopback only',flush=True)
    ThreadingHTTPServer(addr,Handler).serve_forever()

if __name__=='__main__':main()
