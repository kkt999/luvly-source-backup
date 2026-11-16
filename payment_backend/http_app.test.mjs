import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHandler } from './http_app.mjs';

async function withServer(run, calendar) {
  const calls = [];
  const service = { list: async uid => { calls.push(uid); return { invoices: [] }; },
    createQuote: async (uid, body) => { calls.push(body); return body; },
    callback: async body => { calls.push(body); },
    checkout: async (uid, id) => { calls.push(id); return { state: 'Unpaid' }; } };
  const server = createServer(createHandler({ service, calendar, verifyToken: async token => {
    if (token !== 'test-token') throw new Error('bad'); return { uid: 'bride' };
  }, allowedOrigins: ['http://localhost:5000'] }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try { await run(`http://127.0.0.1:${server.address().port}`, calls); }
  finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
}
const headers = { Authorization: 'Bearer test-token', 'Content-Type': 'application/json' };

test('Calendar routes require authentication and reject client-supplied UID', () => withServer(async (base) => {
  assert.equal((await fetch(base + '/v1/calendar')).status, 401);
  const result = await fetch(base + '/v1/calendar', { headers });
  assert.deepEqual(await result.json(), { uid: 'bride' });
  assert.equal((await fetch(base + '/v1/calendar/connect', { method: 'POST', headers, body: '{"uid":"other"}' })).status, 400);
}, { status: async uid => ({ uid }), connect: async () => { throw Error('must not reach'); } }));

test('disabled Calendar reports setup required without breaking service', () => withServer(async base => {
  const result = await fetch(base + '/v1/calendar', { headers });
  assert.equal((await result.json()).configured, false);
  assert.equal((await fetch(base + '/v1/calendar/connect', { method: 'POST', headers, body: '{}' })).status, 503);
}));

test('failed OAuth callback does not echo code or errors to HTML', () => withServer(async base => {
  const result = await fetch(base + '/oauth/google/calendar/callback?code=private-code');
  assert.equal(result.status, 400);
  assert.equal(result.headers.get('referrer-policy'), 'no-referrer');
  assert.doesNotMatch(await result.text(), /private-code|private-error/);
}, { callback: async () => { throw Error('private-error'); } }));
test('missing or invalid bearer tokens cannot reach invoice service', () => withServer(async (base, calls) => {
  assert.equal((await fetch(base + '/v1/invoices')).status, 401);
  assert.equal((await fetch(base + '/v1/invoices', { headers: { Authorization: 'Bearer wrong' } })).status, 401);
  assert.equal(calls.length, 0);
}));
test('authenticated list and exact allowed origin work; hostile origin does not', () => withServer(async (base, calls) => {
  const result = await fetch(base + '/v1/invoices', { headers: { ...headers, Origin: 'http://localhost:5000' } });
  assert.equal(result.status, 200); assert.equal(result.headers.get('Access-Control-Allow-Origin'), 'http://localhost:5000');
  assert.equal((await fetch(base + '/v1/invoices', { headers: { ...headers, Origin: 'https://evil.example' } })).status, 403);
  assert.deepEqual(calls, ['bride']);
}));
test('forged successful return GET performs no payment writes', () => withServer(async (base, calls) => {
  const result = await fetch(base + '/return?status_id=1&order_id=forged');
  assert.equal(result.status, 200);
  const body = await result.text();
  assert.match(body, /Check status to confirm your payment/);
  assert.doesNotMatch(body, /demo|sandbox|test transaction/i);
  assert.doesNotMatch(body, /payment successful|payment verified/i);
  assert.equal(calls.length, 0);
}));
test('checkout rejects client amount overrides', () => withServer(async (base, calls) => {
  const result = await fetch(base + '/v1/invoices/test/checkout', { method: 'POST', headers, body: '{"amountCents":1}' });
  assert.equal(result.status, 400); assert.equal(calls.length, 0);
}));
test('oversized, malformed and wrong-content bodies are rejected', () => withServer(async (base, calls) => {
  for (const [body, content, status] of [['x'.repeat(9000), 'application/json', 413], ['{', 'application/json', 400], ['[]', 'application/json', 400], ['{}', 'text/plain', 415]]) {
    assert.equal((await fetch(base + '/v1/invoices', { method: 'POST', headers: { ...headers, 'Content-Type': content }, body })).status, status);
  }
  assert.equal(calls.length, 0);
}));
test('duplicate callback fields are rejected before callback verification', () => withServer(async (base, calls) => {
  assert.equal((await fetch(base + '/callback', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'status=1&status=3' })).status, 400);
  assert.equal(calls.length, 0);
}));
