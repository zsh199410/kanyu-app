/* Adapter tests (isolated, synthetic fixtures only). Run: node test_trial_adapter.js */
const assert = require('node:assert/strict');
const {adaptTrialBatch} = require('./trial_adapter');

const A = 'a'.repeat(64), B = 'b'.repeat(64), C = 'c'.repeat(64);
const SHA = 'f'.repeat(64);

function snap(nodes, observations, sha = SHA, gen = 7) {
  return {manifestSha: sha, generation: gen, nodes, observations};
}
const nA = {id: A, name: 'trial-a'};
const nB = {id: B, name: 'trial-b'};
const nC = {id: C, name: 'trial-c'};

const cases = [
  ['one node diagnostic-only', () => {
    const out = adaptTrialBatch(snap([nA], [{id: A, rawStatus: 'success'}]), 0);
    assert.equal(out.mode, 'small_diagnostic_only');
    assert.deepEqual(out.ids, [A]);
    assert.equal(out.diagnostics[0].diagnostic_status, 'observed_reachable');
    assert.equal(out.diagnostics[0].promotion_allowed, false);
    assert.equal(out.diagnostics[0].prune_allowed, false);
    assert.equal(out.valid, true);
  }],
  ['two nodes, one missing observation is unknown', () => {
    const out = adaptTrialBatch(snap([nA, nB], [{id: A, rawStatus: 'failure'}]), 0);
    assert.equal(out.mode, 'small_diagnostic_only');
    assert.equal(out.diagnostics.length, 2);
    assert.equal(out.diagnostics[0].diagnostic_status, 'unknown');
    assert.equal(out.diagnostics[0].reason, 'small_trial_failure_unverified');
    assert.equal(out.diagnostics[1].diagnostic_status, 'unknown');
    assert.equal(out.diagnostics[1].reason, 'small_trial_inconclusive');
  }],
  ['three nodes delegate to receiver rules', () => {
    const out = adaptTrialBatch(snap([nA, nB, nC], [
      {id: A, rawStatus: 'success'},
      {id: B, rawStatus: 'unknown'},
      {id: C, rawStatus: 'failure'},
    ]), 0);
    assert.equal(out.mode, 'existing_receiver_rules');
    assert.equal(out.diagnostics.length, 3);
    assert.equal(out.diagnostics.every(d => d.promotion_allowed === false && d.prune_allowed === false), true);
  }],
  ['empty trial, no batch', () => {
    const out = adaptTrialBatch(snap([], []), 0);
    assert.equal(out.mode, 'empty_no_batch');
    assert.deepEqual(out.ids, []);
    assert.deepEqual(out.diagnostics, []);
  }],
  ['reject observation for unknown identity', () => {
    assert.throws(() => adaptTrialBatch(snap([nA], [{id: B, rawStatus: 'success'}])), /invalid_observation/);
  }],
  ['reject bad manifest sha', () => {
    assert.throws(() => adaptTrialBatch(snap([nA], [], 'not-a-sha')), /invalid_trial_snapshot/);
  }],
  ['reject negative generation', () => {
    assert.throws(() => adaptTrialBatch(snap([nA], [], SHA, -1)), /invalid_trial_snapshot/);
  }],
  ['reject duplicate node id', () => {
    assert.throws(() => adaptTrialBatch(snap([nA, nA], [])), /invalid_trial_snapshot/);
  }],
  ['reject seven nodes', () => {
    const seven = [nA, nB, nC,
      {id: 'd'.repeat(64), name: 'd'}, {id: 'e'.repeat(64), name: 'e'},
      {id: '0'.repeat(64), name: 'f'}, {id: '1'.repeat(64), name: 'g'}];
    assert.throws(() => adaptTrialBatch(snap(seven, [])), /invalid_trial_snapshot/);
  }],
  ['reject invalid raw status', () => {
    assert.throws(() => adaptTrialBatch(snap([nA], [{id: A, rawStatus: 'pass'}])), /invalid_observation/);
  }],
  ['cursor rotates within small pool', () => {
    const out = adaptTrialBatch(snap([nA, nB], []), 1);
    assert.deepEqual(out.ids, [B, A]);
    assert.equal(out.nextCursor, 1);
  }],
  ['success never permits promotion even in small pool', () => {
    const out = adaptTrialBatch(snap([nA], [{id: A, rawStatus: 'success'}]), 0);
    assert.equal(out.diagnostics[0].promotion_allowed, false);
    assert.equal(out.diagnostics[0].prune_allowed, false);
  }],
];

let passed = 0;
for (const [name, fn] of cases) { fn(); passed++; }
console.log('trial adapter: ' + passed + '/' + cases.length + ' PASS');
