#!/usr/bin/env python3
"""Isolated probe receiving service for Issue #73 P0 revised design.
Dynamic node discovery + fingerprint identity + persistent task queue.
Dynamic backfill + tiered rate limiting + auto circuit breaker.
Does NOT touch the production pool program (/opt/free-node-program).
Stdlib only. Listens on 127.0.0.1, exposed via nginx at a random path.
"""
import hashlib
import json
import os
import re
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

BASE = os.environ.get("PROBE_BASE", "/opt/probe-service")
DB_PATH = os.path.join(BASE, "data", "probe.db")
POOL_TXT = "/opt/free-node-program/publish/pool-new.txt"

# ---- tunables (initial trial values; adjust from real measurements) ----
INITIAL_BATCH = 4
EXPAND_BATCH = 8
MAX_PER_HOUR = 20
MAX_PER_DAY = 100
REPLENISH_TARGET = 3          # stop probing new nodes once this many newly qualified in a session/hour
VERIFY_TTL_SECONDS = 24 * 3600
MAX_QUEUE_STORE = 500
CIRCUIT_MIN_FAILS = 8         # distinct-host failures in window that trips the breaker
CIRCUIT_WINDOW_SECONDS = 600
CIRCUIT_COOLDOWN_SECONDS = 3600

# ---- fingerprint: stable identity from connection params, NOT display name ----
def fingerprint_of(proto, host, port, params):
    parts = [proto.lower(), host.lower().strip("[]"), str(int(port))]
    for k in sorted(params):
        parts.append(f"{k.lower()}={params[k]}")
    raw = "|".join(parts)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]

def parse_surge_line(line):
    try:
        if " = " not in line:
            return None
        name, rest = line.split(" = ", 1)
        parts = [p.strip() for p in rest.split(",")]
        if len(parts) < 3:
            return None
        proto = parts[0].strip().lower()
        host = parts[1].strip().strip("[]").lower()
        port = int(parts[2].strip())
        params = {}
        for p in parts[3:]:
            if "=" in p:
                k, v = p.split("=", 1)
                params[k.strip().lower()] = v.strip()
        if proto not in ("trojan", "vmess", "ss"):
            return None
        if not host or port <= 0:
            return None
        return (name.strip(), proto, host, port, params)
    except Exception:
        return None

# ---- db ----
def db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""CREATE TABLE IF NOT EXISTS probe_nodes(
        fingerprint TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        protocol TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        first_seen INTEGER NOT NULL,
        last_seen_in_pool INTEGER NOT NULL,
        last_phone_ts INTEGER,
        last_warm_ms INTEGER,
        last_second_ms INTEGER,
        last_status INTEGER,
        last_success INTEGER,
        last_error TEXT,
        last_interface TEXT,
        phone_ok INTEGER NOT NULL DEFAULT 0,
        phone_fail INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS probe_reports(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint TEXT NOT NULL,
        name TEXT NOT NULL,
        ts INTEGER NOT NULL,
        state TEXT NOT NULL,
        warm_ms INTEGER,
        second_ms INTEGER,
        second_status INTEGER,
        success INTEGER NOT NULL,
        error TEXT,
        interface TEXT,
        UNIQUE(fingerprint, ts)
    )""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_reports_fp_ts ON probe_reports(fingerprint, ts)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_reports_ts ON probe_reports(ts)")
    conn.execute("""CREATE TABLE IF NOT EXISTS probe_meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )""")
    conn.commit()
    return conn

def _meta_get(conn, key, default=None):
    row = conn.execute("SELECT value FROM probe_meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else default

def _meta_set(conn, key, value):
    conn.execute(
        "INSERT INTO probe_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, str(value)),
    )

def sync_pool():
    conn = db()
    now = int(time.time())
    try:
        lines = open(POOL_TXT, encoding="utf-8", errors="ignore").read().splitlines()
    except OSError:
        conn.close()
        return {"ok": False, "error": "pool file unreadable"}
    seen = set()
    added = 0
    renamed = 0
    for line in lines:
        parsed = parse_surge_line(line)
        if not parsed:
            continue
        name, proto, host, port, params = parsed
        fp = fingerprint_of(proto, host, port, params)
        seen.add(fp)
        row = conn.execute(
            "SELECT name, state FROM probe_nodes WHERE fingerprint=?", (fp,)
        ).fetchone()
        if row is None:
            conn.execute(
                """INSERT INTO probe_nodes(fingerprint,name,protocol,host,port,state,
                first_seen,last_seen_in_pool,updated_at) VALUES(?,?,?,?,?,'pending',?,?,?)""",
                (fp, name, proto, host, port, now, now, now),
            )
            added += 1
        else:
            old_name, old_state = row
            new_state = old_state
            if old_state == "retired":
                new_state = "pending"
            if old_name != name:
                renamed += 1
            conn.execute(
                """UPDATE probe_nodes SET name=?, protocol=?, host=?, port=?,
                state=?, last_seen_in_pool=?, updated_at=? WHERE fingerprint=?""",
                (name, proto, host, port, new_state, now, now, fp),
            )
    retired = 0
    for (fp,) in conn.execute("SELECT fingerprint FROM probe_nodes WHERE state!='retired'").fetchall():
        if fp not in seen:
            conn.execute(
                "UPDATE probe_nodes SET state='retired', updated_at=? WHERE fingerprint=?",
                (now, fp),
            )
            retired += 1
    conn.commit()
    counts = dict(conn.execute("SELECT state, COUNT(*) FROM probe_nodes GROUP BY state").fetchall())
    conn.close()
    return {"ok": True, "added": added, "renamed": renamed, "retired": retired, "states": counts}

def _hour_bounds(now):
    hour_start = now - (now % 3600)
    day_start = now - (now % 86400)
    return hour_start, day_start

def _circuit_open(conn, now):
    """True if a network-failure pattern was recently detected (cooldown active)."""
    until = _meta_get(conn, "circuit_until")
    if until:
        try:
            if now < int(until):
                return True
        except ValueError:
            pass
    return False

def _maybe_trip_circuit(conn, now):
    """Trip the breaker when many distinct hosts fail in a short window.
    Returns True if tripped by this call."""
    window_start = now - CIRCUIT_WINDOW_SECONDS
    rows = conn.execute(
        """SELECT DISTINCT n.host FROM probe_reports r
        JOIN probe_nodes n ON n.fingerprint = r.fingerprint
        WHERE r.ts >= ? AND r.success = 0""",
        (window_start,),
    ).fetchall()
    distinct_hosts = len(rows)
    total_fail = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ? AND success=0",
        (window_start,),
    ).fetchone()[0]
    total = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ?",
        (window_start,),
    ).fetchone()[0]
    if total >= CIRCUIT_MIN_FAILS and total_fail == total and distinct_hosts >= 4:
        _meta_set(conn, "circuit_until", now + CIRCUIT_COOLDOWN_SECONDS)
        conn.commit()
        return True
    return False

def quality_score(row):
    """Rank candidates: phone history first, then newness, then recency.
    row: (fingerprint, name, protocol, state, first_seen, last_phone_ts, phone_ok, phone_fail)."""
    _fp, _name, _proto, state, first_seen, last_phone_ts, ok_c, fail_c = row
    score = 0
    score += ok_c * 3 - fail_c * 2
    if state == "pending":
        score += 10
    elif state == "expired":
        score += 5
    # prefer nodes not tested recently (avoid re-testing the same failing node back-to-back)
    if last_phone_ts:
        hours_since = (int(time.time()) - last_phone_ts) / 3600.0
        score += min(hours_since, 24) * 0.2
    else:
        score += 5
    return score

def next_tasks():
    """Dynamic backfill scheduler.
    Returns (tasks, info). tasks is a list of {fingerprint,name,protocol}.
    info explains the decision: batch_size, reason, caps, circuit state."""
    sync_pool()
    conn = db()
    now = int(time.time())
    hour_start, day_start = _hour_bounds(now)
    # expire verified nodes whose last phone test is older than TTL
    conn.execute(
        "UPDATE probe_nodes SET state='expired', updated_at=? WHERE state='verified' AND (last_phone_ts IS NULL OR last_phone_ts < ?)",
        (now, now - VERIFY_TTL_SECONDS),
    )
    conn.commit()
    if _circuit_open(conn, now):
        conn.close()
        return [], {"reason": "circuit_open_network_suspected", "batch_size": 0}
    tested_hour = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ?", (hour_start,)
    ).fetchone()[0]
    tested_day = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ?", (day_start,)
    ).fetchone()[0]
    qualified_hour = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ? AND success=1 AND second_ms IS NOT NULL AND second_ms < 300",
        (hour_start,),
    ).fetchone()[0]
    if tested_day >= MAX_PER_DAY:
        conn.close()
        return [], {"reason": "day_cap_reached", "tested_day": tested_day, "batch_size": 0}
    if tested_hour >= MAX_PER_HOUR:
        conn.close()
        return [], {"reason": "hour_cap_reached", "tested_hour": tested_hour, "batch_size": 0}
    if qualified_hour >= REPLENISH_TARGET:
        # target met: stop probing NEW nodes this hour; remaining budget is for re-tests,
        # but only if there are expired nodes waiting. Otherwise stop.
        expired_waiting = conn.execute(
            "SELECT COUNT(*) FROM probe_nodes WHERE state='expired'"
        ).fetchone()[0]
        if expired_waiting == 0:
            conn.close()
            return [], {"reason": "target_met", "qualified_hour": qualified_hour, "batch_size": 0}
    # decide batch size: expand when the most recent batch all failed
    batch_size = INITIAL_BATCH
    recent = conn.execute(
        "SELECT success FROM probe_reports WHERE ts >= ? ORDER BY ts DESC LIMIT ?",
        (hour_start, INITIAL_BATCH),
    ).fetchall()
    if len(recent) >= INITIAL_BATCH and all(r[0] == 0 for r in recent):
        batch_size = EXPAND_BATCH
    remaining_hour = MAX_PER_HOUR - tested_hour
    remaining_day = MAX_PER_DAY - tested_day
    batch_size = min(batch_size, remaining_hour, remaining_day)
    if batch_size <= 0:
        conn.close()
        return [], {"reason": "cap_reached", "batch_size": 0}
    # gather candidates by priority group, ranked by quality score within each group.
    # Exclude nodes already tested this hour (do not re-offer just-failed nodes
    # in the next backfill batch; expansion must test DIFFERENT nodes).
    tasks = []
    for state in ("pending", "expired", "quarantined"):
        if len(tasks) >= batch_size:
            break
        rows = conn.execute(
            """SELECT fingerprint, name, protocol, state, first_seen, last_phone_ts,
            phone_ok, phone_fail FROM probe_nodes WHERE state=?
            AND NOT EXISTS (SELECT 1 FROM probe_reports r
                WHERE r.fingerprint = probe_nodes.fingerprint AND r.ts >= ?)""",
            (state, hour_start),
        ).fetchall()
        rows.sort(key=quality_score, reverse=True)
        for r in rows:
            if len(tasks) >= batch_size:
                break
            tasks.append({"fingerprint": r[0], "name": r[1], "protocol": r[2]})
    conn.close()
    return tasks, {
        "reason": "ok",
        "batch_size": len(tasks),
        "tested_hour": tested_hour,
        "tested_day": tested_day,
        "qualified_hour": qualified_hour,
    }

def ingest(results):
    conn = db()
    now = int(time.time())
    accepted = 0
    duplicates = 0
    rejected = 0
    for r in results if isinstance(results, list) else []:
        if not isinstance(r, dict):
            rejected += 1
            continue
        fp = r.get("fingerprint")
        name = r.get("name")
        ts = r.get("ts")
        state = r.get("state")
        if not isinstance(fp, str) or not re.fullmatch(r"[0-9a-f]{32}", fp):
            rejected += 1
            continue
        if not isinstance(name, str) or not name or len(name) > 120:
            rejected += 1
            continue
        if not isinstance(ts, int) or ts <= 0 or ts > now + 600:
            rejected += 1
            continue
        if state not in ("measured", "first_failed"):
            rejected += 1
            continue
        success = 1 if r.get("success") is True else 0
        warm = r.get("warm_ms")
        second = r.get("second_request_ms")
        status = r.get("second_status")
        err = r.get("error")
        iface = r.get("interface")
        warm = warm if isinstance(warm, int) and 0 <= warm <= 60000 else None
        second = second if isinstance(second, int) and 0 <= second <= 60000 else None
        status = status if isinstance(status, int) and 100 <= status <= 599 else None
        err = err if isinstance(err, str) and len(err) <= 300 else None
        iface = iface if isinstance(iface, str) and len(iface) <= 40 else None
        try:
            conn.execute(
                """INSERT INTO probe_reports(fingerprint,name,ts,state,warm_ms,second_ms,
                second_status,success,error,interface) VALUES(?,?,?,?,?,?,?,?,?,?)""",
                (fp, name, ts, state, warm, second, status, success, err, iface),
            )
            accepted += 1
        except sqlite3.IntegrityError:
            duplicates += 1
            continue
        row = conn.execute(
            "SELECT state, phone_ok, phone_fail FROM probe_nodes WHERE fingerprint=?", (fp,)
        ).fetchone()
        if row is None:
            continue
        old_state, ok_c, fail_c = row
        if success:
            new_ok, new_fail = ok_c + 1, fail_c
            # Verified ONLY when the phone measurement is both successful AND
            # fast (second request < 300ms). A responsive-but-slow node is
            # recorded but does NOT count as verified and does not satisfy
            # the replenishment target.
            is_fast = second is not None and second < 300
            if is_fast:
                new_state = "verified"
            elif old_state == "verified":
                new_state = "expired"
            else:
                new_state = old_state
        else:
            new_ok, new_fail = ok_c, fail_c + 1
            new_state = "quarantined" if new_fail >= 3 and ok_c == 0 else old_state
            if old_state == "verified":
                new_state = "expired"
        conn.execute(
            """UPDATE probe_nodes SET name=?, state=?, last_phone_ts=?, last_warm_ms=?,
            last_second_ms=?, last_status=?, last_success=?, last_error=?, last_interface=?,
            phone_ok=?, phone_fail=?, updated_at=? WHERE fingerprint=?""",
            (name, new_state, ts, warm, second, status, success, err, iface,
             new_ok, new_fail, now, fp),
        )
        conn.execute(
            """DELETE FROM probe_reports WHERE fingerprint=? AND id NOT IN
            (SELECT id FROM probe_reports WHERE fingerprint=? ORDER BY ts DESC LIMIT ?)""",
            (fp, fp, MAX_QUEUE_STORE),
        )
    conn.commit()
    tripped = _maybe_trip_circuit(conn, now)
    conn.commit()
    conn.close()
    out = {"ok": True, "accepted": accepted, "duplicates": duplicates, "rejected": rejected}
    if tripped:
        out["circuit_tripped"] = True
        out["note"] = "many distinct hosts failed at once; possible network issue, backing off"
    return out

def stats():
    sync_pool()
    conn = db()
    now = int(time.time())
    hour_start, day_start = _hour_bounds(now)
    states = dict(conn.execute("SELECT state, COUNT(*) FROM probe_nodes GROUP BY state").fetchall())
    new_today = conn.execute(
        "SELECT COUNT(*) FROM probe_nodes WHERE first_seen >= ?", (day_start,)
    ).fetchone()[0]
    total = sum(states.values())
    verified = states.get("verified", 0)
    covered = conn.execute(
        "SELECT COUNT(*) FROM probe_nodes WHERE last_phone_ts IS NOT NULL AND last_phone_ts >= ?",
        (day_start,),
    ).fetchone()[0]
    tested_hour = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ?", (hour_start,)
    ).fetchone()[0]
    tested_day = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ?", (day_start,)
    ).fetchone()[0]
    qualified_day = conn.execute(
        "SELECT COUNT(*) FROM probe_reports WHERE ts >= ? AND success=1 AND second_ms IS NOT NULL AND second_ms < 300",
        (day_start,),
    ).fetchone()[0]
    backlog = states.get("pending", 0) + states.get("expired", 0)
    avg_alive = conn.execute(
        "SELECT AVG(? - first_seen) FROM probe_nodes WHERE state!='retired'",
        (now,),
    ).fetchone()[0]
    circuit = _circuit_open(conn, now)
    conn.close()
    return {
        "ok": True,
        "total": total,
        "states": states,
        "new_today": new_today,
        "verified": verified,
        "coverage_24h": covered,
        "coverage_ratio": round(covered / total, 3) if total else 0,
        "qualified_ratio": round(verified / total, 3) if total else 0,
        "backlog": backlog,
        "tested_hour": tested_hour,
        "tested_day": tested_day,
        "qualified_day": qualified_day,
        "avg_alive_seconds": int(avg_alive) if avg_alive else 0,
        "circuit_open": circuit,
    }

# ---- http ----
def load_secret(name):
    p = os.path.join(BASE, "config", name)
    try:
        with open(p) as f:
            return f.read().strip()
    except OSError:
        return ""

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        # No Bearer token: the token would have to live inside the phone script,
        # which is fetched over a public URL, so it would not be a secret.
        # Protection is the unguessable random path (like winner-report) plus
        # strict validation, fingerprint allow-listing and rate limits.
        return True

    def _path_ok(self):
        seg = load_secret("probe-path.txt")
        if not seg or not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", seg):
            return False
        return urlparse(self.path).path == "/" + seg

    def do_GET(self):
        if not self._path_ok():
            return self._send(404, {"ok": False, "error": "not found"})
        if not self._auth():
            return self._send(401, {"ok": False, "error": "unauthorized"})
        act = self.headers.get("X-Probe-Action", "")
        if act == "tasks":
            try:
                tasks, info = next_tasks()
                return self._send(200, {"ok": True, "tasks": tasks, "info": info})
            except Exception as e:
                return self._send(500, {"ok": False, "error": str(e)[:200]})
        if act == "stats":
            try:
                return self._send(200, stats())
            except Exception as e:
                return self._send(500, {"ok": False, "error": str(e)[:200]})
        return self._send(400, {"ok": False, "error": "unknown action"})

    def do_POST(self):
        if not self._path_ok():
            return self._send(404, {"ok": False, "error": "not found"})
        if not self._auth():
            return self._send(401, {"ok": False, "error": "unauthorized"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = 0
        if n <= 0 or n > 65536:
            return self._send(400, {"ok": False, "error": "bad length"})
        try:
            body = json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return self._send(400, {"ok": False, "error": "bad json"})
        results = body.get("results") if isinstance(body, dict) else None
        if not isinstance(results, list) or len(results) > 8:
            return self._send(400, {"ok": False, "error": "bad results"})
        try:
            return self._send(200, ingest(results))
        except Exception as e:
            return self._send(500, {"ok": False, "error": str(e)[:200]})

def main():
    import sys
    port = int(os.environ.get("PROBE_PORT", "18081"))
    if len(sys.argv) > 1 and sys.argv[1] == "sync":
        print(json.dumps(sync_pool(), ensure_ascii=False))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "stats":
        print(json.dumps(stats(), ensure_ascii=False, indent=2))
        return
    if len(sys.argv) > 1 and sys.argv[1] == "tasks":
        tasks, info = next_tasks()
        print(json.dumps({"tasks": tasks, "info": info}, ensure_ascii=False, indent=2))
        return
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"probe service on 127.0.0.1:{port} base={BASE}", flush=True)
    server.serve_forever()

if __name__ == "__main__":
    main()
