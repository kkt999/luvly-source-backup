import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';
import { calibrateDressModel, DressArService, TripoDressGateway } from './tripo_dress_models.mjs';
import { createHandler } from './http_app.mjs';

function sampleModel(matrix) {
  const parts = [[-1,0,-1], [1,2,-1], [-1,2,1], [1,2,1]];
  const bin = Buffer.alloc(12 * parts.length);
  parts.flat().forEach((x, i) => bin.writeFloatLE(x, 4 * i));
  const doc = {
    asset: { version: '2.0' }, scenes: [{ nodes: [0] }],
    nodes: [{ mesh: 0, ...(matrix && { matrix }) }],
    meshes: [{ primitives: [{ attributes: { POSITION: 0 } }] }],
    accessors: [{ type: 'VEC3', componentType: 5126, count: parts.length, bufferView: 0 }],
    bufferViews: [{ buffer: 0, byteLength: bin.length }], buffers: [{ byteLength: bin.length }],
  };
  const json = JSON.stringify(doc);
  const header = Buffer.alloc(20);
  header.write('glTF'); header.writeUInt32LE(2, 4); header.write('JSON', 16);
  const jsonBytes = Buffer.from(json.padEnd(Math.ceil(json.length / 4) * 4));
  const binHeader = Buffer.alloc(8);
  binHeader.writeUInt32LE(bin.length); binHeader.write('BIN', 4);
  header.writeUInt32LE(jsonBytes.length, 12);
  header.writeUInt32LE(28 + jsonBytes.length + bin.length, 8);
  return Buffer.concat([header, jsonBytes, binHeader, bin]);
}
const png = Buffer.from('89504e470d0a1a0a', 'hex');

function setup() {
  const rows = new Map([
    ['dresses/dress-1', { published: false, photoRevision: 1 }],
    ['dressPhotos/dress-1', { revision: 1, mime: 'image/jpeg', data: Buffer.from('ffd8ffd9', 'hex').toString('base64') }],
    ['staff/manager', { role: 'manager', active: true }],
    ['staff/staff', { role: 'staff', active: true }],
    ['brides/customer', {}],
  ]);
  let queue = Promise.resolve();
  const store = {
    get: async path => rows.get(path),
    atomic(action) {
      const next = queue.then(() => action({
        get: async path => rows.get(path),
        set: (path, row) => rows.set(path, row),
      }));
      queue = next.catch(() => {});
      return next;
    },
  };
  let starts = 0;
  const gateway = {
    enabled: true,
    balance: async () => ({ balance: 30 }),
    upload: async () => 'file-1',
    generate: async () => { starts++; return 'task-1'; },
    task: async () => ({ status: 'success', progress: 100, credits_consumed: 30,
      output: { model_url: 'model', rendered_image_url: 'preview' } }),
    download: async url => url === 'model' ? sampleModel() : png,
  };
  const files = new Map();
  const storage = {
    save: async (path, bytes) => files.set(path, bytes),
    download: async path => files.get(path),
  };
  return { rows, gateway, starts: () => starts, service: new DressArService({ store, gateway, storage }) };
}

test('calibration rotates the same embedded mesh and grounds the virtual gown', () => {
  const raw = sampleModel();
  const turned = calibrateDressModel(raw, '+X');
  const size = turned.readUInt32LE(12);
  const node = JSON.parse(turned.toString('utf8', 20, 20 + size)).nodes[0];
  assert.ok(Math.abs(node.rotation[1] + Math.SQRT1_2) < 1e-6);
  assert.deepEqual(node.scale, [.68, .68, .68]);
  assert.deepEqual(turned.subarray(20 + size), raw.subarray(20 + raw.readUInt32LE(12)));
  assert.throws(() => calibrateDressModel(Buffer.alloc(42)), { code: 'TRIPO_UNSUPPORTED_MODEL' });
});

test('calibration accepts an explicit identity matrix and preserves authored transforms', () => {
  const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  const original = sampleModel();
  assert.deepEqual(calibrateDressModel(sampleModel(identity)), calibrateDressModel(original));
  const authored = [...identity];
  authored[5] = 2;
  authored[13] = 5;
  const calibrated = calibrateDressModel(sampleModel(authored));
  const doc = JSON.parse(calibrated.toString('utf8', 20, 20 + calibrated.readUInt32LE(12)));
  assert.deepEqual(doc.scenes[0].nodes, [1]);
  assert.deepEqual(doc.nodes[0].matrix, authored);
  assert.deepEqual(doc.nodes[1].children, [0]);
  assert.equal(doc.nodes[1].scale[1], .34);
  assert.ok(Math.abs(doc.nodes[1].translation[1] + 1.7) < 1e-8);
  assert.throws(() => calibrateDressModel(sampleModel([1, 0])), { code: 'TRIPO_UNSUPPORTED_MODEL' });
});

test('one paid submission survives concurrent starts; customers require approval and publication', async () => {
  const { service, rows, starts } = setup();
  const id = 'dress-1', rev = 1;
  await assert.rejects(service.start('staff', id, rev), { code: 'MANAGER_REQUIRED' });
  await assert.rejects(service.start('customer', id, rev), { code: 'MANAGER_REQUIRED' });
  const results = await Promise.all([
    service.start('manager', id, rev), service.start('manager', id, rev),
  ]);
  assert.ok(results.some(x => x.state === 'running'));
  assert.equal(starts(), 1);
  const ready = await service.status('manager', id, rev);
  assert.equal(ready.state, 'ready');
  assert.equal(ready.credits, 30);
  assert.equal((await service.media('manager', id, rev, 'preview')).mime, 'image/png');
  await assert.rejects(service.media('customer', id, rev, 'preview'), { code: 'MANAGER_REQUIRED' });
  assert.equal(await service.available('customer', id, rev), false);
  await service.approve('manager', id, rev, true, '+X');
  assert.equal(await service.available('customer', id, rev), false);
  rows.set('dresses/dress-1', { published: true, photoRevision: 1 });
  assert.equal(await service.available('customer', id, rev), true);
  assert.deepEqual((await service.media('customer', id, rev, 'model')).bytes, calibrateDressModel(sampleModel(), '+X'));
  await service.approve('manager', id, rev, false, '+X');
  await assert.rejects(service.media('customer', id, rev, 'model'), { code: 'TRIPO_MODEL_UNAVAILABLE' });
  rows.set('dresses/dress-1', { published: true, photoRevision: 2 });
  await assert.rejects(service.available('customer', id, rev), { code: 'TRIPO_PHOTO_CHANGED' });
  assert.equal(starts(), 1);
});

test('an ambiguous submission is never charged again by reloading the dress', async () => {
  const { gateway, service } = setup();
  let calls = 0;
  gateway.generate = async () => { calls++; throw new Error('connection lost'); };
  assert.equal((await service.start('manager', 'dress-1', 1)).state, 'submission_unknown');
  assert.equal((await service.start('manager', 'dress-1', 1)).state, 'submission_unknown');
  assert.equal(calls, 1);
});

test('a completed paid task with a format rejection is recovered in place', async () => {
  const { service, rows, starts } = setup();
  const path = 'dressArJobs/dress-1/photos/1';
  rows.set(path, { attempt: 'already-paid', photoRevision: 1, taskId: 'task-1',
    state: 'failed', error: 'TRIPO_UNSUPPORTED_MODEL', approved: false });
  const ready = await service.start('manager', 'dress-1', 1);
  assert.equal(starts(), 0);
  assert.equal(ready.state, 'ready');
  assert.equal(ready.error, null);
  assert.equal(ready.approved, false);
  assert.equal(rows.get(path).attempt, 'already-paid');
  assert.equal(rows.get(path).taskId, 'task-1');
});

test('the Manager can recover a WebP preview for an already-ready model', async () => {
  const { service, rows, starts, gateway } = setup();
  const path = 'dressArJobs/dress-1/photos/1';
  rows.set(path, { attempt: 'already-paid', photoRevision: 1, taskId: 'task-1',
    state: 'ready', front: '+X', approved: true });
  const webp = Buffer.alloc(20);
  webp.write('RIFF'); webp.writeUInt32LE(12, 4); webp.write('WEBP', 8);
  gateway.download = async () => webp;
  const status = await service.status('manager', 'dress-1', 1);
  assert.equal(status.preview, true);
  assert.equal(status.approved, true);
  assert.equal(status.front, '+X');
  assert.equal((await service.media('manager', 'dress-1', 1, 'preview')).mime, 'image/webp');
  assert.equal(starts(), 0);
});

test('only a manager can check Tripo connectivity and a balance check does not generate', async () => {
  const { service, gateway, starts } = setup();
  await assert.rejects(service.connection('staff'), { code: 'MANAGER_REQUIRED' });
  await assert.rejects(service.connection('customer'), { code: 'MANAGER_REQUIRED' });
  assert.deepEqual(await service.connection('manager'), { connected: true, canGenerate: true });
  gateway.balance = async () => ({ balance: 12 });
  assert.deepEqual(await service.connection('manager'), { connected: true, canGenerate: false });
  assert.equal(starts(), 0);
});

test('route requires sign-in and explicit confirmation before requesting generation', async () => {
  const { service, starts } = setup();
  const app = createServer(createHandler({ dressAr: service, verifyToken: async uid => ({ uid }) }));
  await new Promise(resolve => app.listen(0, '127.0.0.1', resolve));
  try {
    const url = `http://127.0.0.1:${app.address().port}/v1/dresses/dress-1/ar/1/generate`;
    const send = (uid, confirmed) => fetch(url, { method: 'POST', body: JSON.stringify({ confirmed }),
      headers: { 'Content-Type': 'application/json', ...(uid && { Authorization: 'Bearer ' + uid }) } });
    assert.equal((await send(null, true)).status, 401);
    assert.equal((await send('manager', false)).status, 400);
    assert.equal((await send('staff', true)).status, 403);
    assert.equal(starts(), 0);
    const generated = await send('manager', true);
    assert.equal(generated.status, 200);
    assert.equal((await generated.json()).state, 'running');
    assert.equal(starts(), 1);
  } finally { await new Promise(resolve => app.close(resolve)); }
});

test('gateway uses confirmed H-Series parameters and keeps credentials off media requests', async () => {
  const calls = [];
  const gateway = new TripoDressGateway('fake-key', async (url, init) => {
    calls.push({ url: String(url), init });
    return new Response(JSON.stringify({ code: 0, data: { task_id: 'task-1' } }));
  });
  assert.equal(await gateway.generate('upload-token'), 'task-1');
  const call = calls[0];
  assert.equal(call.init.headers.Authorization, 'Bearer fake-key');
  assert.deepEqual(JSON.parse(call.init.body), {
    input: 'upload-token', model: 'v3.1-20260211', texture: true, texture_quality: 'standard',
    orientation: 'align_image', face_limit: 50000,
  });
  await gateway.download('https://cdn.tripo3d.ai/test.glb', 100);
  assert.equal(calls[1].init.headers, undefined);
  await assert.rejects(gateway.download('https://cdn.tripo3d.ai.example.com/test.glb', 100), { code: 'TRIPO_UNSUPPORTED_MODEL' });
});
