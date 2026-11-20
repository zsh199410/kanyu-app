# s1/ — Secret-free distribution isolated verification

Run: `node test_s1.js` (Node.js, no dependencies, no network).
Output: `s1_out.json` + PASS/FAIL lines on stdout.

Rev 1 (2026-11-19, addresses GPT review 7010615307). 11 tests, 0 fail.

What it simulates (all synthetic — tokens are `TEST-DEV-OLD-0001` /
`TEST-DEV-NEW-0002` / `TEST-DEV-BACKUP-0004`, IPs are TEST-NET
documentation ranges):

- A desensitised bridge script that reads its DEV token and local HTTP API
  key from a mock `$persistentStore` (keys `sgbridge_cred_dev`,
  `sgbridge_cred_localkey`). The script source contains only placeholders
  (`<DEV_TOKEN>`, `<API_KEY>`, `<BRIDGE_BASE>`). A read that throws is
  treated as missing: 0 network calls, `credential_read_failed`.
- A mock server with a token table (accept/revoke), a parallel window
  (both old and new accepted), an action-free `/credential-proof`
  endpoint (proves a token is accepted without touching the mailbox),
  and an audit log that records only a truncated SHA-256 fingerprint of
  the token — never the full token.
- The mock mailbox holds the legacy pending command 1795063030
  (OUTCOME_UNKNOWN) by default. The script FENCES it (never dispatches,
  never posts a result for it) — mirroring the v2 fence.
- The rotation cutover: old token works, new token is provisioned,
  acceptance is proven by /poll + /credential-proof (never by posting a
  /result for the legacy command), old token is revoked (403).
- Rollback (Rev 1): the leaked old token is NEVER re-enabled. Rollback
  uses a pre-issued NEW BACKUP token, or fails closed when no backup
  token is available.

Tests (11):

| ID | Check |
|---|---|
| S1-T1 | Static scan: the distributed (v2) script contains no credential (no 32+ hex run, no real URL; placeholders present). |
| S1-T2 | Fail-closed with no credential: 0 network calls, `credential_missing`, $done exactly once. |
| S1-T3 | Normal operation: credential from $persistentStore, dispatch + result posted, no full token in the audit log. |
| S1-T4 | Rotation cutover (Rev 1): parallel window, 3 new-token rounds of poll + credential-proof, legacy command fenced and untouched, old token revoked → 403. |
| S1-T5 | Old token rejected after revocation: `auth_forbidden`, nothing executed, $done once. |
| S1-T6 | Rollback via pre-issued backup token (Rev 1): backup token works, old (leaked) token stays 403. |
| S1-T9 | Rollback with no backup token → fail-closed (Rev 1, new): revoked-token run and empty-store run both send nothing; leaked token not re-enabled. |
| S1-T7 | Anomalous-access audit: unknown-IP requests flagged; no full token in the log. |
| S1-T8 | Local key absent → direct-HTTP fallback skipped, no blind retry. |
| S1-T10 | Credential read throws → 0 network calls (Rev 1, new): `credential_read_failed`, $done once, server sees nothing. |
| S1-T11 | Rotation acceptance never touches the mailbox (Rev 1, new): 3 rounds of poll + credential-proof leave pending 1795063030 unchanged, 0 results posted, 0 dispatches. |
