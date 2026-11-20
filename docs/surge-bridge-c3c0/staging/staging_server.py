#!/usr/bin/env python3
"""C3-C0 staging HTTPS proof service (loopback only, synthetic creds only).

Reads /opt/c3c0-staging/config.json (0600), loads the synthetic Ed25519 test
key, and serves HTTPSProofService on 127.0.0.1:18443 with the staging TLS
cert. Writes its PID to server.pid and logs startup to server.log.
Never logs request bodies, auth headers, nonces, or token IDs.
"""
import json
import os
import signal
import ssl
import sys
import threading
import time

BASE = "/opt/c3c0-staging"
sys.path.insert(0, BASE)

from nonce_ledger_sqlite import NonceLedger
from token_registry_sqlite import TokenRegistry
from credential_proof_https import HTTPSProofService, LoopbackTLSServer

CONFIG = os.path.join(BASE, "config.json")
PID_FILE = os.path.join(BASE, "server.pid")
LOG_FILE = os.path.join(BASE, "server.log")


def log(msg):
    line = "%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    with open(LOG_FILE, "a") as f:
        f.write(line)
    print(line, end="", flush=True)


def main():
    with open(CONFIG) as f:
        cfg = json.load(f)
    from cryptography.hazmat.primitives import serialization
    with open(cfg["ed25519_key"], "rb") as f:
        signer = serialization.load_pem_private_key(f.read(), password=None)
    ledger = NonceLedger(cfg["db_path"])
    registry = TokenRegistry(ledger)
    service = HTTPSProofService(
        registry, ledger, signer,
        pairing_secret=cfg["pairing_secret"],
        old_token_id=cfg["old_token_id"])
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(cfg["tls_cert"], cfg["tls_key"])
    server = LoopbackTLSServer(
        service, ctx, (cfg["host"], cfg["port"]))
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
    log("STAGING SERVER START pid=%d host=%s port=%d db=%s" % (
        os.getpid(), cfg["host"], cfg["port"], cfg["db_path"]))
    log("ledger counts (total, consumed): %s" % (ledger.counts(),))
    log("registry audit: %s" % (registry.audit_counts(),))

    def _stop(signum, frame):
        # NEVER call server.shutdown() directly from a signal handler: it
        # blocks waiting for serve_forever() to return, but serve_forever()
        # is suspended inside this handler -> deadlock. Shut down from a
        # separate thread so the main loop can notice the flag and exit.
        log("STAGING SERVER STOP signal=%d" % signum)
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        log("STAGING SERVER EXITED")
        try:
            os.remove(PID_FILE)
        except OSError:
            pass


if __name__ == "__main__":
    main()
