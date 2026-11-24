/* Deterministic synthetic fixtures. Run: node test_small_trial.js */
const assert=require('node:assert/strict');
const {planTrialBatch,smallTrialDiagnostic}=require('./small_trial');
const A='a'.repeat(64),B='b'.repeat(64),C='c'.repeat(64),D='d'.repeat(64),E='e'.repeat(64),F='f'.repeat(64);
const cases=[
  ["empty",()=>planTrialBatch([],12),{"ids":[],"nextCursor":0,"mode":"empty_no_batch"}],
  ["one",()=>planTrialBatch([A],100),{"ids":["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"nextCursor":0,"mode":"small_diagnostic_only"}],
  ["two rotate",()=>planTrialBatch([A,B],1),{"ids":["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"nextCursor":1,"mode":"small_diagnostic_only"}],
  ["three delegates",()=>planTrialBatch([A,B,C],2),{"ids":["cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],"nextCursor":2,"mode":"existing_receiver_rules"}],
  ["six rotate",()=>planTrialBatch([A,B,C,D,E,F],4),{"ids":["eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],"nextCursor":2,"mode":"existing_receiver_rules"}],
  ["reject duplicate",()=>planTrialBatch([A,A]),"invalid_trial_snapshot"],
  ["reject seven",()=>planTrialBatch([A,B,C,D,E,F,"0".repeat(64)]),"invalid_trial_snapshot"],
  ["reject invalid fingerprint",()=>planTrialBatch(["trial-name"]),"invalid_trial_snapshot"],
  ["reject malformed cursor",()=>planTrialBatch([A],-1),"invalid_trial_snapshot"],
  ["reject NaN cursor",()=>planTrialBatch([A],NaN),"invalid_trial_snapshot"],
  ["success diagnostic only",()=>smallTrialDiagnostic("success"),{"raw_status":"success","diagnostic_status":"observed_reachable","reason":"small_trial_reachable","promotion_allowed":false,"prune_allowed":false}],
  ["failure is inconclusive",()=>smallTrialDiagnostic("failure"),{"raw_status":"failure","diagnostic_status":"unknown","reason":"small_trial_failure_unverified","promotion_allowed":false,"prune_allowed":false}],
  ["unknown retained",()=>smallTrialDiagnostic("unknown"),{"raw_status":"unknown","diagnostic_status":"unknown","reason":"small_trial_inconclusive","promotion_allowed":false,"prune_allowed":false}],
  ["reject invalid status",()=>smallTrialDiagnostic("pass"),"invalid_raw_status"]
];
let passed=0;
for(const [name,fn,expected] of cases){let got;try{got=fn()}catch(e){got=e.message}assert.deepEqual(got,expected,name);passed++;}
console.log('small trial: '+passed+'/'+cases.length+' PASS');
