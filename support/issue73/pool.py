#!/usr/bin/env python3
"""Issue #73 reference implementation. Python 3.10+, standard library only.

The service does NOT replace the existing collector or sing-box checker. It accepts
candidate snapshots and phone observations, and only publishes phone-verified nodes.
"""
import argparse
import hashlib
import hmac
import json
import os
import sqlite3
import statistics
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

MAX_BODY = 131072
PHONE_TTL = 24 * 3600
MIN_VPS_CHECKS = 3
MAX_LATENCY = 300


def connect(path):
    cx = sqlite3.connect(path, timeout=15)
    cx.row_factory = sqlite3.Row
    cx.execute('PRAGMA journal_mode=WAL')
    cx.executescript('''
    CREATE TABLE IF NOT EXISTS nodes (
      name TEXT PRIMARY KEY, line TEXT NOT NULL, protocol TEXT NOT NULL,
      class TEXT NOT NULL, seen_at INTEGER NOT NULL,
      vps_ratio REAL, vps_p90 REAL, vps_last INTEGER,
      vps_count INTEGER NOT NULL DEFAULT 0, vps_http_ratio REAL
    );
    CREATE TABLE IF NOT EXISTS phone (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      ts INTEGER NOT NULL, latency_ms REAL, passed INTEGER NOT NULL,
      network TEXT NOT NULL, device TEXT NOT NULL,
      UNIQUE(name, ts, device)
    );
    CREATE INDEX IF NOT EXISTS phone_idx ON phone(name, ts DESC);
    ''')
    return cx


def extract_protocol(line):
    if not isinstance(line, str) or '=' not in line or '\n' in line or '\r' in line:
        raise ValueError('invalid Surge line')
    # Split the value exactly, never grep for 'ss,' (which matches 'vmess,').
    return line.split('=', 1)[1].strip().split(',', 1)[0].strip().lower()


def valid_name(name):
    return isinstance(name, str) and 1 <= len(name) <= 140 and '\n' not in name and '\r' not in name


def import_candidates(cx, items, now=None):
    now = int(now or time.time())
    if not isinstance(items, list) or len(items) > 3000:
        raise ValueError('candidates must be a list of <=3000 entries')
    count = 0
    with cx:
        for item in items:
            name = item.get('name')
            line = item.get('line')
            if not valid_name(name) or not isinstance(line, str):
                raise ValueError('candidate missing name / line')
            if line.split('=', 1)[0].strip() != name:
                raise ValueError('node name differs from Surge line')
            proto = extract_protocol(line)
            if proto not in ('trojan', 'vmess', 'ss'):  # VLESS remains gated off
                continue
            node_class = item.get('class', 'rotating')
            if node_class not in ('pinned', 'rotating'):
                raise ValueError('invalid candidate class')
            checks = item.get('vps_checks', [])
            if not isinstance(checks, list) or len(checks) > 2000:
                raise ValueError('invalid vps_checks')
            recent = [c for c in checks if isinstance(c, dict) and
                      isinstance(c.get('ts'), (int, float)) and now-86400 <= c['ts'] <= now+60]
            success = [c for c in recent if c.get('handshake_ok') is True and
                       isinstance(c.get('latency_ms'), (int, float)) and
                       0 < c['latency_ms'] <= 8000]
            ratio = len(success)/len(recent) if recent else None
            http_ratio = (sum(c.get('http_ok') is True for c in recent) / len(recent)) if recent else None
            lats = sorted(float(c['latency_ms']) for c in success)
            p90 = lats[max(0, (9 * len(lats) + 9)//10-1)] if lats else None
            vps_last = int(max(c['ts'] for c in recent)) if recent else None
            cx.execute('''INSERT INTO nodes
              (name,line,protocol,class,seen_at,vps_ratio,vps_p90,vps_last,vps_count,vps_http_ratio)
              VALUES(?,?,?,?,?,?,?,?,?,?)
              ON CONFLICT(name) DO UPDATE SET
                line=excluded.line,protocol=excluded.protocol,class=excluded.class,
                seen_at=excluded.seen_at,vps_ratio=excluded.vps_ratio,
                vps_p90=excluded.vps_p90,vps_last=excluded.vps_last,
                vps_count=excluded.vps_count,vps_http_ratio=excluded.vps_http_ratio''',
                (name,line,proto,node_class,now,ratio,p90,vps_last,len(recent),http_ratio))
            count += 1
    return count


def ingest(cx, payload, now=None):
    now = int(now or time.time())
    if not isinstance(payload, dict) or payload.get('group') != '免费节点池':
        raise ValueError('wrong group')
    device = payload.get('device', 'ios')
    if not valid_name(device):
        raise ValueError('invalid device')
    network = payload.get('network', 'unknown')
    if network not in ('cellular', 'wifi', 'unknown'):
        raise ValueError('invalid network')
    observations = payload.get('observations')
    if not isinstance(observations, list) or len(observations) > 150:
        raise ValueError('invalid observations')
    accepted = 0
    with cx:
        for obs in observations:
            if not isinstance(obs, dict) or not valid_name(obs.get('name')):
                continue
            # Reject unknown names; the server owns the canonical inventory.
            if not cx.execute('SELECT 1 FROM nodes WHERE name=?', (obs['name'],)).fetchone():
                continue
            ts = obs.get('ts')
            if not isinstance(ts, (int, float)) or ts > now + 60 or ts < now-3600:
                continue  # cached results cannot be relabelled as fresh
            latency = obs.get('latency_ms')
            if latency is not None and (not isinstance(latency, (int, float)) or
                                        isinstance(latency, bool) or latency < 0 or latency > 30000):
                continue
            passed = latency is not None and 0 < latency < MAX_LATENCY and obs.get('ok') is True
            cx.execute('INSERT OR IGNORE INTO phone(name,ts,latency_ms,passed,network,device) VALUES(?,?,?,?,?,?)',
                       (obs['name'],int(ts),latency,int(passed),network,device))
            accepted += 1
    return accepted


def vps_gate(node, now=None):
    """Gate new unverified candidates, never overwrite genuine phone evidence."""
    now = int(time.time() if now is None else now)
    if (node['vps_last'] is None or now-node['vps_last'] > 86400
            or node['vps_last'] > now+60):
        return 'UNKNOWN'
    if node['vps_count'] < MIN_VPS_CHECKS or node['vps_ratio'] is None:
        return 'UNKNOWN'
    if (node['vps_ratio'] >= 0.7 and node['vps_http_ratio'] is not None
            and node['vps_http_ratio'] >= 0.7 and node['vps_p90'] is not None
            and node['vps_p90'] <= 500):
        return 'PASS'
    return 'FAIL'


def state(cx, node, now):
    # The phone's latest test must be cellular and below 300 ms to qualify.
    results = cx.execute('''SELECT * FROM phone WHERE name=? ORDER BY ts DESC LIMIT 10''',
                         (node['name'],)).fetchall()
    if not results:
        return 'PENDING', None
    last = results[0]
    recent_fails = 0
    for item in results:
        if item['passed']:
            break
        recent_fails += 1
    if recent_fails >= 3 and (results[0]['ts'] - results[2]['ts']) >= 1800:
        return 'RETIRED', last['latency_ms']
    if recent_fails >= 2:
        return 'QUARANTINED', last['latency_ms']
    if not last['passed']:
        return 'PROBATION', last['latency_ms']
    if last['network'] != 'cellular' or now - last['ts'] > PHONE_TTL:
        return 'PROBATION', last['latency_ms']
    # A phone success has priority over a failed US VPS check.
    return 'VERIFIED', last['latency_ms']


def publish(cx, output, now=None):
    now = int(now or time.time())
    nodes = cx.execute('SELECT * FROM nodes ORDER BY name').fetchall()
    verified, stats = [], {'VERIFIED':0,'PENDING':0,'PROBATION':0,'QUARANTINED':0,'RETIRED':0}
    for node in nodes:
        status, delay = state(cx, node, now)
        stats[status] += 1
        if status == 'VERIFIED':
            verified.append((float(delay), node['line']))
    verified.sort(key=lambda x:x[0])
    if not verified:
        # DO NOT publish an empty url-test group: Surge could fall back to DIRECT.
        return {'updated':False,'reason':'no fresh mobile-verified nodes; previous feed unchanged', 'stats':stats}
    payload = '# Mobile verified (cellular, <300ms, fresh <=24h)\n' + '\n'.join(x[1] for x in verified) + '\n'
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.'+output.name+'.',dir=output.parent)
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as f:
            f.write(payload); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,output)
    finally:
        if os.path.exists(tmp): os.remove(tmp)
    return {'updated':True,'published':len(verified),'sha256':hashlib.sha256(payload.encode()).hexdigest(),'stats':stats}


def shortlist(cx, now=None):
    """Feed for the old collector's trial-candidate decision, NOT production."""
    now = int(time.time() if now is None else now)
    return [{'name': n['name'], 'class': n['class'], 'protocol': n['protocol']}
            for n in cx.execute('SELECT * FROM nodes ORDER BY name')
            if vps_gate(n, now) == 'PASS']


def handler_factory(db_path, token):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if urlsplit(self.path).path != '/api/v1/phone':
                self.send_error(404); return
            auth = self.headers.get('Authorization','')
            if not token or not hmac.compare_digest(auth, 'Bearer ' + token):
                self.send_error(401); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if length < 1 or length > MAX_BODY: raise ValueError('body too large')
                body = json.loads(self.rfile.read(length).decode('utf-8'))
                with connect(db_path) as cx:
                    count = ingest(cx, body)
                result = json.dumps({'accepted':count}).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.send_header('Content-Length',str(len(result)))
                self.end_headers(); self.wfile.write(result)
            except (ValueError, UnicodeError, json.JSONDecodeError) as exc:
                self.send_error(400, str(exc))
        def log_message(self, fmt, *args):
            pass  # prevent observations/tokens from leaking to access logs
    return Handler


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--db',default='pool.sqlite3')
    sub=p.add_subparsers(dest='command',required=True)
    i=sub.add_parser('import'); i.add_argument('file')
    o=sub.add_parser('publish'); o.add_argument('output')
    s=sub.add_parser('serve'); s.add_argument('--host',default='127.0.0.1'); s.add_argument('--port',type=int,default=8765)
    sub.add_parser('shortlist')
    q=sub.add_parser('status')
    args=p.parse_args()
    with connect(args.db) as cx:
        if args.command == 'import':
            data=json.loads(Path(args.file).read_text(encoding='utf-8'))
            print(json.dumps({'imported':import_candidates(cx,data)},ensure_ascii=False)); return
        if args.command == 'publish':
            print(json.dumps(publish(cx,args.output),ensure_ascii=False)); return
        if args.command == 'shortlist':
            print(json.dumps(shortlist(cx),ensure_ascii=False)); return
        if args.command == 'status':
            entries=[dict(name=n['name'],state=state(cx,n,int(time.time()))[0],
                          vps_ratio=n['vps_ratio'],vps_p90=n['vps_p90'],vps_gate=vps_gate(n))
                     for n in cx.execute('SELECT * FROM nodes')]
            print(json.dumps(entries,ensure_ascii=False)); return
    if args.command == 'serve':
        token=os.environ.get('SURGE_REPORT_TOKEN','')
        if len(token)<32: raise SystemExit('SURGE_REPORT_TOKEN must contain >=32 random chars')
        server=ThreadingHTTPServer((args.host,args.port), handler_factory(args.db,token))
        print(f'Listening on {args.host}:{args.port} (place behind HTTPS reverse proxy)',flush=True)
        server.serve_forever()

if __name__=='__main__':main()

