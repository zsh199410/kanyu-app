"use strict";
/* C3-C0 Round 4 — Item 3 test: server dual-token and revocation.
 *
 * Synthetic tokens only, mock server, no network, no phone. A
 * controllable clock is injected so the window-expiry cases are
 * deterministic. A mock mailbox (cmd 1795063030, OUTCOME_UNKNOWN)
 * is snapshotted before and after EVERY operation — revocation,
 * expiry, and rollback must never touch it.
 */
const assert = require("node:assert/strict");
const { DualTokenServer, OLD_CMD_ID, OLD_RESULT_ID } = require("./dual_token_server");

const OLD_TOKEN = "TEST-ACTIVE-OLD-DEV-0123456789ABCDEF";
const NEW_TOKEN = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const BACKUP_TOKEN = "TEST-BACKUP-DEV-0123456789ABCDEF0123";
const UNKNOWN_TOKEN = "TEST-UNKNOWN-TOKEN-0123456789ABCDEF";
const OLD_ID = "TEST-OLD-TOKEN-ID-001";
const NEW_ID = "TEST-NEW-TOKEN-ID-002";
const BACKUP_ID = "TEST-BACKUP-TOKEN-ID-003";
const ALL_SYNTHETIC = [OLD_TOKEN, NEW_TOKEN, BACKUP_TOKEN, UNKNOWN_TOKEN,
  OLD_ID, NEW_ID, BACKUP_ID];

const WINDOW_MS = 48 * 60 * 60 * 1000;

/* A server with a controllable clock (milliseconds since start). */
function makeServer() {
  let t = 0;
  const server = new DualTokenServer({
    windowMs: WINDOW_MS,
    now: () => t,
  });
  return {
    server,
    advance: (ms) => { t += ms; },
    now: () => t,
  };
}

let count = 0;
function check(name, fn) {
  fn();
  count += 1;
  console.log("PASS", name);
}

check("old token accepted before revocation", () => {
  const { server } = makeServer();
  assert.deepEqual(server.addToken(OLD_TOKEN, OLD_ID), { ok: true, id: OLD_ID });
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 200, reason: "ok" });
});

check("new token accepted", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  assert.deepEqual(server.addToken(NEW_TOKEN, NEW_ID), { ok: true, id: NEW_ID });
  assert.deepEqual(server.authorize(NEW_TOKEN), { status: 200, reason: "ok" });
});

check("both tokens accepted during the window", () => {
  const { server, advance } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  advance(60 * 60 * 1000); // 1h into the window
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 200, reason: "ok" });
  assert.deepEqual(server.authorize(NEW_TOKEN), { status: 200, reason: "ok" });
});

check("old token rejected (403) after revocation; new token still accepted", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  assert.deepEqual(server.revoke(OLD_ID, "exposed-rotation"), { ok: true, id: OLD_ID });
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 403, reason: "token_revoked" });
  assert.deepEqual(server.authorize(NEW_TOKEN), { status: 200, reason: "ok" });
});

check("request with no token is rejected (401 token_missing)", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  assert.deepEqual(server.authorize(""), { status: 401, reason: "token_missing" });
  assert.deepEqual(server.authorize(null), { status: 401, reason: "token_missing" });
  assert.deepEqual(server.authorize(undefined), { status: 401, reason: "token_missing" });
});

check("unknown token is rejected (401 unknown_token), not 403", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  assert.deepEqual(server.authorize(UNKNOWN_TOKEN), { status: 401, reason: "unknown_token" });
});

check("window expiry fails closed: old token 403 window_expired even without explicit revocation", () => {
  const { server, advance } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  advance(WINDOW_MS + 1000); // past the 48h window, no revoke() called
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 403, reason: "window_expired" });
  assert.deepEqual(server.authorize(NEW_TOKEN), { status: 200, reason: "ok" });
});

check("window expiry does not affect the new token, and the window never silently extends", () => {
  const { server, advance } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  advance(WINDOW_MS - 1000); // just inside the window
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 200, reason: "ok" });
  advance(2000); // just past it
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 403, reason: "window_expired" });
});

check("revocation is a status change, never a delete (append-only audit)", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  server.revoke(OLD_ID, "exposed-rotation");
  const rows = [...server.table.values()];
  assert.equal(rows.length, 2);
  const old = rows.find((r) => r.id === OLD_ID);
  assert.equal(old.status, "revoked");
  assert.equal(typeof old.revoked_at, "number");
  assert.equal(old.revoked_reason, "exposed-rotation");
  assert.equal(typeof old.fingerprint, "string");
  /* A second revoke of the same row is refused, not double-applied. */
  assert.deepEqual(server.revoke(OLD_ID, "again"), { ok: false, reason: "already_revoked" });
  /* Revoking an unknown id is refused. */
  assert.deepEqual(server.revoke("no-such-id", "x"), { ok: false, reason: "unknown_token_id" });
});

check("rollback activates a NEW backup token; rollback with the OLD token value is refused", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  server.revoke(OLD_ID, "exposed-rotation");
  assert.deepEqual(
    server.rollbackToBackup(BACKUP_TOKEN, BACKUP_ID, OLD_TOKEN),
    { ok: true, id: BACKUP_ID });
  assert.deepEqual(server.authorize(BACKUP_TOKEN), { status: 200, reason: "ok" });
  assert.deepEqual(server.authorize(NEW_TOKEN), { status: 200, reason: "ok" });
  assert.deepEqual(server.authorize(OLD_TOKEN), { status: 403, reason: "token_revoked" });
  /* The old exposed token can never be the rollback token. */
  assert.deepEqual(
    server.rollbackToBackup(OLD_TOKEN, "another-id", OLD_TOKEN),
    { ok: false, reason: "refuses_old_token" });
});

check("revocation, expiry, and rollback never touch the old command id", () => {
  const { server, advance } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  const before = server.mailboxSnapshot();
  server.revoke(OLD_ID, "exposed-rotation");
  server.authorize(OLD_TOKEN);
  server.authorize(NEW_TOKEN);
  advance(WINDOW_MS + 1000);
  server.authorize(OLD_TOKEN);
  server.rollbackToBackup(BACKUP_TOKEN, BACKUP_ID, OLD_TOKEN);
  server.authorize(BACKUP_TOKEN);
  assert.equal(server.mailboxSnapshot(), before);
  const m = JSON.parse(before);
  assert.equal(m.cmd.id, OLD_CMD_ID);
  assert.equal(m.result.id, OLD_RESULT_ID);
  assert.equal(m.timers.length, 5);
  assert.equal(m.pins.length, 2);
});

check("no token value is stored in the table (fingerprints only)", () => {
  const { server } = makeServer();
  server.addToken(OLD_TOKEN, OLD_ID);
  server.addToken(NEW_TOKEN, NEW_ID);
  const rows = [...server.table.values()];
  const blob = JSON.stringify(rows);
  /* Token VALUES must be absent. Token IDs are non-secret identifiers
   * and are meant to be stored (they are how the server refers to a
   * row); they are deliberately NOT in this list. */
  for (const value of [OLD_TOKEN, NEW_TOKEN, BACKUP_TOKEN, UNKNOWN_TOKEN]) {
    assert.equal(blob.includes(value), false, "table stores a token value");
  }
  /* What IS stored is a 64-hex-char SHA-256 fingerprint per row. */
  for (const row of rows) {
    assert.match(row.fingerprint, /^[0-9a-f]{64}$/);
  }
});

console.log("SUMMARY", count, "PASS, 0 FAIL");
