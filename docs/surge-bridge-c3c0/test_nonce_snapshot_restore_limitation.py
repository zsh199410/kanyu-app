"""Round 7 negative control: DB snapshot restore resurrects a consumed nonce.

This is a KNOWN LIMITATION demonstration, not a failure: it proves that
GPT's DURABLE_NONCE_LEDGER_GATE.md limitation #3 is real — restoring an
older SQLite snapshot brings back a consumed nonce, so the ledger alone is
NOT end-to-end replay protection. Production needs a rollback-resistant
epoch / high-water mark / audit anchor plus a tested consistent-backup
process. This script exits 0 while reporting the limitation; a nonzero
exit means the demonstration itself broke (setup error), not that the
limitation went away.

Deterministic WAL handling: after registering, run
PRAGMA wal_checkpoint(TRUNCATE) so all pages live in the main DB file,
then copy only that file. Before restoring, remove any -wal/-shm sidecars
so the restored main file is the sole source of truth.
"""
import hashlib
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

from nonce_ledger_sqlite import NonceLedger, new_nonce

ISSUED = 1800000000000
EXPIRES = ISSUED + 60000
FP = hashlib.sha256(b"synthetic-candidate").hexdigest()
TOKEN_ID = "synthetic-id"


def checkpoint(db: Path) -> None:
    con = sqlite3.connect(str(db))
    try:
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        con.commit()
    finally:
        con.close()


def remove_sidecars(db: Path) -> None:
    for suffix in ("-wal", "-shm"):
        sidecar = Path(str(db) + suffix)
        if sidecar.exists():
            sidecar.unlink()


def main() -> int:
    checks = []

    def check(name: str, ok: bool) -> None:
        checks.append(ok)
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            print("SUMMARY 0 PASS, 1 FAIL")
            return 1

    with tempfile.TemporaryDirectory() as td:
        db = Path(td) / "nonce.sqlite"
        snapshot = Path(td) / "nonce.snapshot.sqlite"
        ledger = NonceLedger(db)
        nonce = new_nonce()
        binding = dict(kind="dev", candidate_fingerprint=FP, token_id=TOKEN_ID)

        # 1. Register, then snapshot the DB while the nonce is still issued.
        if not ledger.register(nonce, **binding,
                               issued_ms=ISSUED, expires_ms=EXPIRES):
            return check("register nonce before snapshot", False)
        check("register nonce before snapshot", True)
        checkpoint(db)
        remove_sidecars(db)
        shutil.copy2(db, snapshot)

        # 2. Consume exactly once; a second consume is rejected (ledger works).
        if not ledger.consume(nonce, **binding, now_ms=ISSUED):
            return check("first consume succeeds", False)
        check("first consume succeeds", True)
        if ledger.consume(nonce, **binding, now_ms=ISSUED):
            return check("second consume rejected before restore", False)
        check("second consume rejected before restore", True)
        if ledger.counts() != (1, 1):
            return check("counts (1,1) before restore", False)
        check("counts (1,1) before restore", True)

        # 3. Restore the pre-consume snapshot over the live DB and reopen.
        remove_sidecars(db)
        shutil.copy2(snapshot, db)
        remove_sidecars(db)
        restored = NonceLedger(db)
        if restored.counts() != (1, 0):
            return check("restored DB shows nonce issued again", False)
        check("restored DB shows nonce issued again", True)

        # 4. The same nonce consumes again: RESURRECTION. This is the
        # documented limitation — asserted as happening, not as a pass of
        # replay protection.
        resurrected = restored.consume(nonce, **binding, now_ms=ISSUED)
        if not resurrected:
            print("FAIL snapshot restore did NOT resurrect nonce "
                  "(limitation not reproduced)")
            print("SUMMARY 0 PASS, 1 FAIL")
            return 1
        print("PASS snapshot restore resurrects consumed nonce "
              "(KNOWN LIMITATION, not replay protection)")
        print("SUMMARY 1 PASS, 0 FAIL, 1 KNOWN LIMITATION "
              "(snapshot restore resurrects consumed nonce)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
