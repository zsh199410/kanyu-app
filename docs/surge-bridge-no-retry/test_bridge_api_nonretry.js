'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/bridge_api_nonretry.js', 'utf8');

function fixture({ available = true, behavior = 'ok' } = {}) {
  let apiCalls = 0;
  let directCalls = 0;
  let timer;
  let httpCallback;
  const context = {
    APIKEY: 'test-only',
    http: async (_method, _url, _headers, _body) => {
      directCalls++;
      return { status: 200, err: null, data: '{"ok":true}' };
    },
    setTimeout(fn) { timer = fn; return 1; },
    clearTimeout() {},
    $httpClient: {
      get(_opts, cb) { directCalls++; cb(null, { status: 200 }, '{"ok":true}'); },
      post(_opts, cb) { directCalls++; cb(null, { status: 200 }, '{"ok":true}'); }
    }
  };
  if (available) {
    context.$httpAPI = (_method, _path, _body, cb) => {
      apiCalls++;
      httpCallback = cb;
      if (behavior === 'ok') cb({ ok: true });
      if (behavior === 'throws') throw new Error('transport interrupted');
    };
  }
  vm.runInNewContext(source, context, { filename: 'bridge_api_nonretry.js' });
  return { context, get apiCalls() { return apiCalls; },
    get directCalls() { return directCalls; },
    timeout() { timer(); }, callback(data) { httpCallback(data); } };
}

async function main() {
  let f = fixture();
  let result = await f.context.api('POST', '/v1/scripting/cron/evaluate', { script_name: 'fixture' });
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);
  assert.equal(result.via, 'httpAPI');

  f = fixture({ behavior: 'hang' });
  const p = f.context.api('POST', '/v1/scripting/cron/evaluate', {});
  f.timeout(); result = await p;
  assert.equal(result.err, 'outcome_unknown_no_retry');
  assert.equal(result.pending, true); assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);
  f.callback({ ok: true });
  assert.equal(f.directCalls, 0);

  f = fixture({ available: false });
  result = await f.context.api('POST', '/v1/scripting/cron/evaluate', {});
  assert.equal(f.apiCalls, 0); assert.equal(f.directCalls, 1);
  assert.equal(result.status, 200);

  f = fixture({ behavior: 'hang' });
  const getPromise = f.context.api('GET', '/v1/test', undefined);
  f.timeout(); result = await getPromise;
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 1);
  assert.equal(result.status, 200);

  f = fixture({ behavior: 'throws' });
  result = await f.context.api('POST', '/v1/scripting/cron/evaluate', {});
  assert.equal(result.err, 'outcome_unknown_no_retry');
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);

  f = fixture({ behavior: 'ok' });
  result = await f.context.api('GET', '/v1/test');
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);
  f = fixture({ behavior: 'hang' });
  const deletePromise = f.context.api('DELETE', '/v1/mutation', {});
  f.timeout(); result = await deletePromise;
  assert.equal(result.err, 'outcome_unknown_no_retry');
  assert.equal(result.pending, true);
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);

  f = fixture({ behavior: 'hang' });
  const emptyCallback = f.context.api('POST', '/v1/mutation', {});
  f.callback(null); result = await emptyCallback;
  assert.equal(result.err, 'outcome_unknown_no_retry');
  assert.equal(result.pending, true);
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);

  f = fixture({ available: false });
  result = await f.context.api('PUT', '/v1/mutation', {});
  assert.equal(result.err, 'unsupported_http_fallback');
  assert.equal(f.apiCalls, 0); assert.equal(f.directCalls, 0);

  f = fixture({ behavior: 'hang' });
  const headPromise = f.context.api('HEAD', '/v1/test', undefined);
  f.timeout(); result = await headPromise;
  assert.equal(result.err, 'unsupported_http_fallback');
  assert.equal(result.pending, true);
  assert.equal(f.apiCalls, 1); assert.equal(f.directCalls, 0);

  console.log('10/10 bridge API non-retry cases passed');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
