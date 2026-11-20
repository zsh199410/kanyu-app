"use strict";
/* C3-C0 Round 4 — Item 3: server dual-token and revocation (isolated sample).
 *
 * A mock server token table + mock bridge auth check, implementing
 * DUAL_TOKEN_DESIGN.md. Synthetic tokens only. No network, no phone,
 * no real server change. The table stores FINGERPRINTS (a stand-in
 * hash function is used here because the sample must not depend on
 * the real token values), never token values.
 *
 * Rules implemented:
 * - Two tokens active during a bounded window (old exposed + new).
 * - authorize(): 200 for an active token; 403 token_revoked for a
 *   revoked token; 403 window_expired for the old token after the
 *   window ends even without explicit revocation; 401 unknown_token
 *   for a token not in the table; 401 token_missing for an empty one.
 * - Revocation is a status change, never a delete (append-only audit).
 * - Rollback never revives the old token: rollbackToBackup() refuses
 *   any backup value equal to the old token value.
 * - The mailbox (old command 1795063030, OUTCOME_UNKNOWN) is never
 *   touched by any operation here.
 *
 * Usage:
 *   const { DualTokenServer } = require("./dual_token_server");
 *   const server = new DualTokenServer({ windowMs: 48*60*60*1000 });
 *   server.addToken(OLD_TOKEN, "old-id");
 *   server.addToken(NEW_TOKEN, "new-id");
 *   server.authorize(OLD_TOKEN); // { status: 200, reason: "ok" }
 */
const crypto = require("node:crypto");

const OLD_CMD_ID = 1795063030;
const OLD_RESULT_ID = 1795055213880;

/* Stand-in fingerprint: SHA-256 hex of the token value. The real
 * server compares the same way; the sample never stores the value. */
function fingerprint(token) {
  return crypto.createHash("sha256").update(token, "utf8").digest("hex");
}

class DualTokenServer {
  constructor({ windowMs = 48 * 60 * 60 * 1000, now = Date.now } = {}) {
    this.windowMs = windowMs;
    this.now = now;
    this.windowOpenedAt = now();
    this.windowEndsAt = this.windowOpenedAt + windowMs;
    /* fingerprint -> row. Rows are never deleted (append-only audit). */
    this.table = new Map();
    /* The old token's fingerprint, recorded once at addToken time so
     * the window-expiry rule can identify it without the value. */
    this.oldFingerprint = null;
    this.mailbox = {
      cmd: { id: OLD_CMD_ID },
      result: { id: OLD_RESULT_ID },
      polls: 2439,
      pins: ["synthetic-pin-a", "synthetic-pin-b"],
      timers: ["t1", "t2", "t3", "t4", "t5"],
    };
  }

  /* Adds a token row. The first token added is the OLD (exposed) one
   * for window purposes; later tokens are new/backup tokens. */
  addToken(token, id) {
    if (typeof token !== "string" || !token) {
      return { ok: false, reason: "invalid_token" };
    }
    const fp = fingerprint(token);
    if (this.table.has(fp)) {
      return { ok: false, reason: "duplicate_fingerprint" };
    }
    const row = {
      id,
      fingerprint: fp,
      status: "active",
      issued_at: this.now(),
      revoked_at: null,
      revoked_reason: null,
    };
    this.table.set(fp, row);
    if (this.oldFingerprint === null) this.oldFingerprint = fp;
    return { ok: true, id };
  }

  /* The bridge's auth check for one /poll request. */
  authorize(token) {
    if (typeof token !== "string" || !token) {
      return { status: 401, reason: "token_missing" };
    }
    const row = this.table.get(fingerprint(token));
    if (!row) {
      return { status: 401, reason: "unknown_token" };
    }
    if (row.status === "revoked") {
      return { status: 403, reason: "token_revoked" };
    }
    if (row.fingerprint === this.oldFingerprint &&
        this.now() > this.windowEndsAt) {
      return { status: 403, reason: "window_expired" };
    }
    return { status: 200, reason: "ok" };
  }

  /* Revokes one token row by id. A status change, never a delete. */
  revoke(tokenId, reason) {
    for (const row of this.table.values()) {
      if (row.id === tokenId) {
        if (row.status === "revoked") {
          return { ok: false, reason: "already_revoked" };
        }
        row.status = "revoked";
        row.revoked_at = this.now();
        row.revoked_reason = reason || "revoked";
        return { ok: true, id: tokenId };
      }
    }
    return { ok: false, reason: "unknown_token_id" };
  }

  /* Rollback after a failed new token: activate a NEW backup token.
   * Refuses any backup value equal to the old token value — the old
   * exposed token is never re-enabled. */
  rollbackToBackup(backupToken, backupId, oldTokenValue) {
    if (typeof backupToken !== "string" || !backupToken) {
      return { ok: false, reason: "invalid_token" };
    }
    if (backupToken === oldTokenValue) {
      return { ok: false, reason: "refuses_old_token" };
    }
    return this.addToken(backupToken, backupId);
  }

  mailboxSnapshot() {
    return JSON.stringify(this.mailbox);
  }
}

module.exports = { DualTokenServer, fingerprint, OLD_CMD_ID, OLD_RESULT_ID };
