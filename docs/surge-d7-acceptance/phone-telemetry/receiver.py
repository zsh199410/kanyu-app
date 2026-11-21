#!/usr/bin/env python3
"""Fail-closed PHONE probe ingress. Staging evidence ONLY; not a publisher.

Loopback listener behind separately configured authenticated HTTPS reverse proxy.
No real proxy URI/secret is included in outputs or log entries.
"""
from __future__ import annotations
import hashlib
import hmac
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

class InputRejected(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def parse_pool(raw: bytes):
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
    if len(found) < 22:
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


def validate(payload, pool_bytes, now=None, *, descriptor_accepted=False):
    now = int(time.time()) if now is None else now
    if not isinstance(payload, dict) or payload.get('schema')!=1:
        raise InputRejected('invalid_schema')
    if payload.get('group')!='免费节点池':
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
    names=parse_pool(pool_bytes)
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
        status=classify(results)
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
        output.append((protocol,host,port,status,mode,1 if trusted else 0,
                       reason,status,reason,1 if control_verified else 0))
    # All-nodes-failed is NOT evidence that the iPhone has lost connectivity.
    # Admit an all-failure batch only when a distinct policy identifier has
    # independently reached one of the two network control endpoints in
    # the SAME batch. Otherwise hold the normalized evidence as unknown but
    # preserve the observed transport failure in raw_status/raw_reason.
    if len(output)>=3 and all(x[3]=='failure' for x in output) and not control_verified:
        output=[(*x[:3],'unknown',x[4],x[5],'batch_unverified_network',
                 x[7],x[8],0) for x in output]
    return output


def initialize_db(path):
    p=Path(path)
    p.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    conn=sqlite3.connect(p)
    try:
        conn.execute('PRAGMA journal_mode=WAL')
        conn.executescript('''
CREATE TABLE IF NOT EXISTS batches (nonce TEXT PRIMARY KEY, received_at INTEGER NOT NULL, payload_sha TEXT NOT NULL);
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
  control_verified INTEGER NOT NULL DEFAULT 0 CHECK(control_verified IN (0,1))
);
CREATE INDEX IF NOT EXISTS phone_observations_by_identity ON phone_observations(protocol,host,port,received_at);
''')
        # Additive migration; existing importers select explicit legacy columns.
        columns={row[1] for row in conn.execute('PRAGMA table_info(phone_observations)')}
        for column,definition in (
            ('reason',"TEXT NOT NULL DEFAULT 'legacy_unclassified'"),
            ('raw_status',"TEXT NOT NULL DEFAULT 'legacy_unknown'"),
            ('raw_reason',"TEXT NOT NULL DEFAULT 'legacy_unclassified'"),
            ('control_verified',"INTEGER NOT NULL DEFAULT 0"),
        ):
            if column not in columns:
                conn.execute("ALTER TABLE phone_observations ADD COLUMN "+column+" "+definition)
        conn.commit()
    finally:
        conn.close()
    os.chmod(p, 0o600)


def record_batch(db_path, payload, observations, now=None):
    now=int(time.time()) if now is None else now
    conn=sqlite3.connect(db_path,timeout=5)
    try:
        conn.execute('BEGIN IMMEDIATE')
        if conn.execute('SELECT 1 FROM batches WHERE nonce=?',(payload['nonce'],)).fetchone():
            conn.rollback();return 'duplicate'
        conn.execute('INSERT INTO batches VALUES(?,?,?)',(payload['nonce'],now,payload['pool_sha']))
        conn.executemany('''INSERT INTO phone_observations
(nonce,protocol,host,port,status,probe_mode,trusted,received_at,bearer,pool_sha,reason,raw_status,raw_reason,control_verified)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',[
 (payload['nonce'],proto,host,port,status,mode,trust,now,payload['bearer'],payload['pool_sha'],reason,raw_status,raw_reason,control_ok)
 for proto,host,port,status,mode,trust,reason,raw_status,raw_reason,control_ok in observations])
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
            observations=validate(
                payload,pool,descriptor_accepted=(
                    os.environ.get('PHONE_PROBE_DESCRIPTOR_ACCEPTED')=='YES_AFTER_DEVICE_VALIDATION'))
            state=record_batch(os.environ['PHONE_PROBE_DB'],payload,observations)
        except (UnicodeError,ValueError,KeyError, OSError, sqlite3.Error):
            return self.respond(422,{'ok':False})
        self.respond(200,{'ok':True,'receipt':state,'accepted':len(observations)})

def main():
    for field in ('PHONE_PROBE_POOL','PHONE_PROBE_DB','PHONE_PROBE_TOKEN'):
        if not os.environ.get(field):raise SystemExit('missing environment variable '+field)
    if len(os.environ['PHONE_PROBE_TOKEN'])<32:raise SystemExit('token must be >=32 chars')
    initialize_db(os.environ['PHONE_PROBE_DB'])
    addr=('127.0.0.1', int(os.environ.get('PHONE_PROBE_PORT','8724')))
    print('Phone probe staging receiver listening on loopback only',flush=True)
    ThreadingHTTPServer(addr,Handler).serve_forever()

if __name__=='__main__':main()
