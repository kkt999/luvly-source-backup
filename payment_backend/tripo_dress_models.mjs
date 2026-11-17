import { createHash, randomUUID } from 'node:crypto';
import { HttpError } from './payment_service.mjs';

export const modelLimit = 12 * 1024 * 1024;
const previewLimit = 2 * 1024 * 1024;
export const generationCredits = 30;
const modelVersion = 'v3.1-20260211';
const idPattern = /^[A-Za-z0-9_-]{1,150}$/;
const failedTasks = new Set(['failed', 'cancelled', 'banned', 'expired']);
const frontAngles = { '+Z': 0, '+X': -90, '-Z': 180, '-X': 90 };
const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const fail = (status, code) => new HttpError(status, code);
const recoverable = job => job?.state === 'failed' && job.error === 'TRIPO_UNSUPPORTED_MODEL' &&
  typeof job.taskId === 'string' && idPattern.test(job.taskId);

/** Give a self-contained, static Tripo GLB the origin used by the AR renderer. */
export function calibrateDressModel(bytes, front = '+Z') {
  const bad = () => { throw fail(422, 'TRIPO_UNSUPPORTED_MODEL'); };
  if (!Object.hasOwn(frontAngles, front) || bytes.length < 32 || bytes.length > modelLimit ||
      bytes.toString('ascii', 0, 4) !== 'glTF' || bytes.readUInt32LE(4) !== 2 ||
      bytes.readUInt32LE(8) !== bytes.length || bytes.toString('ascii', 16, 20) !== 'JSON') bad();
  const jsonLength = bytes.readUInt32LE(12);
  const binOffset = jsonLength + 20;
  if (jsonLength > 1024 * 1024 || jsonLength % 4 || binOffset + 8 > bytes.length ||
      bytes.readUInt32LE(binOffset) + binOffset + 8 !== bytes.length ||
      bytes.toString('hex', binOffset + 4, binOffset + 8) !== '42494e00') bad();
  let doc;
  try { doc = JSON.parse(bytes.toString('utf8', 20, binOffset)); } catch { bad(); }
  const node = doc?.nodes?.[0];
  const primitive = doc?.meshes?.[0]?.primitives?.[0];
  const access = doc?.accessors?.[primitive?.attributes?.POSITION];
  const view = doc?.bufferViews?.[access?.bufferView];
  if (doc?.scenes?.length !== 1 || (doc.scene ?? 0) !== 0 || doc.scenes[0]?.nodes?.length !== 1 ||
      doc.scenes[0].nodes[0] !== 0 || doc.nodes?.length !== 1 || node?.mesh !== 0 ||
      ['rotation', 'scale', 'translation', 'skin', 'children'].some(key => key in node) ||
      !primitive || doc.meshes[0].primitives.length !== 1 || doc.meshes.length !== 1 || primitive.targets ||
      (primitive.mode ?? 4) !== 4 || doc.animations?.length || doc.extensionsRequired?.length ||
      doc.buffers?.length !== 1 || doc.buffers[0].uri || doc.images?.some(image => image.uri || image.bufferView == null) ||
      access?.type !== 'VEC3' || access.componentType !== 5126 || access.sparse ||
      !Number.isInteger(access.count) || access.count < 3 || access.count > 165000 ||
      view?.buffer !== 0) bad();
  const start = (view.byteOffset ?? 0) + (access.byteOffset ?? 0);
  const stride = view.byteStride ?? 12;
  const bin = bytes.subarray(binOffset + 8);
  if (![start, stride].every(Number.isSafeInteger) || start < 0 || stride < 12 ||
      start + (access.count - 1) * stride + 12 > bin.length) bad();
  const matrix = node.matrix === undefined ? identity : node.matrix;
  if (!Array.isArray(matrix) || matrix.length !== 16 || !matrix.every(Number.isFinite) ||
      matrix[3] !== 0 || matrix[7] !== 0 || matrix[11] !== 0 || matrix[15] !== 1) bad();
  const [xx, xy, xz, , yx, yy, yz, , zx, zy, zz, , tx, ty, tz] = matrix;
  const positions = new Float64Array(access.count * 3);
  let bottom = Infinity, top = -Infinity;
  for (let i = 0; i < access.count; i++) {
    const offset = start + i * stride;
    const x = bin.readFloatLE(offset), y = bin.readFloatLE(offset + 4), z = bin.readFloatLE(offset + 8);
    const worldX = xx*x + yx*y + zx*z + tx;
    const worldY = xy*x + yy*y + zy*z + ty;
    const worldZ = xz*x + yz*y + zz*z + tz;
    if (!Number.isFinite(worldX) || !Number.isFinite(worldY) || !Number.isFinite(worldZ) ||
        Math.max(Math.abs(worldX), Math.abs(worldY), Math.abs(worldZ)) > 1000) bad();
    positions[i*3] = worldX; positions[i*3+1] = worldY; positions[i*3+2] = worldZ;
    bottom = Math.min(bottom, worldY); top = Math.max(top, worldY);
  }
  const height = top - bottom;
  if (height < 1e-5 || height > 1000) bad();
  let left = Infinity, right = -Infinity, back = Infinity, forward = -Infinity;
  for (let i = 0; i < positions.length; i += 3) {
    const x = positions[i], y = positions[i+1], z = positions[i+2];
    if (y < bottom + height * .76) continue;
    left = Math.min(left, x); right = Math.max(right, x);
    back = Math.min(back, z); forward = Math.max(forward, z);
  }
  if (right <= left || forward <= back) bad();
  const x = (left + right) / 2, z = (back + forward) / 2;
  const angle = frontAngles[front] * Math.PI / 180;
  const scale = 1.36 / height;
  const rotateX = x * Math.cos(angle) + z * Math.sin(angle);
  const rotateZ = -x * Math.sin(angle) + z * Math.cos(angle);
  const transform = {
    rotation: [0, Math.sin(angle / 2), 0, Math.cos(angle / 2)],
    scale: [scale, scale, scale],
    translation: [-rotateX * scale, -bottom * scale, -rotateZ * scale],
  };
  if (matrix.every((value, index) => value === identity[index])) {
    delete node.matrix;
    Object.assign(node, transform);
  } else {
    doc.nodes.push({ ...transform, children: [0] });
    doc.scenes[0].nodes = [1];
  }
  const json = Buffer.from(JSON.stringify(doc));
  const padding = Buffer.alloc((4 - json.length % 4) % 4, 0x20);
  const header = Buffer.from(bytes.subarray(0, 20));
  const size = 20 + json.length + padding.length + bytes.length - binOffset;
  if (size > modelLimit) bad();
  header.writeUInt32LE(size, 8);
  header.writeUInt32LE(json.length + padding.length, 12);
  return Buffer.concat([header, json, padding, bytes.subarray(binOffset)]);
}

export class TripoDressGateway {
  constructor(key, fetchImpl = fetch) {
    this.key = key;
    this.fetch = fetchImpl;
  }
  get enabled() { return typeof this.key === 'string' && /^\S+$/.test(this.key); }
  async request(path, body) {
    if (!this.enabled) throw fail(503, 'TRIPO_NOT_CONFIGURED');
    const isJson = body && !(body instanceof FormData);
    let response;
    try {
      response = await this.fetch('https://openapi.tripo3d.ai/v3' + path, {
        method: body ? 'POST' : 'GET',
        redirect: 'error',
        headers: { Authorization: 'Bearer ' + this.key, ...(isJson && { 'Content-Type': 'application/json' }) },
        body: isJson ? JSON.stringify(body) : body,
        signal: AbortSignal.timeout(10000),
      });
    } catch { throw fail(503, 'TRIPO_UNAVAILABLE'); }
    const envelope = await response.json().catch(() => null);
    if (response.ok && envelope?.code === 0 && envelope.data) return envelope.data;
    if (envelope?.code === 2010) throw fail(409, 'TRIPO_INSUFFICIENT_CREDITS');
    // A timeout, unreadable response or upstream 5xx can occur after acceptance.
    if ([400, 401, 403, 404, 422, 429].includes(response.status) &&
        Number.isInteger(envelope?.code) && envelope.code !== 0) throw fail(422, 'TRIPO_REJECTED');
    throw fail(503, 'TRIPO_UNAVAILABLE');
  }
  async upload(photo) {
    const form = new FormData();
    form.append('file', new Blob([photo], { type: 'image/jpeg' }), 'gown.jpg');
    const data = await this.request('/files', form);
    if (typeof data.file_token !== 'string' || !data.file_token) throw fail(503, 'TRIPO_UNAVAILABLE');
    return data.file_token;
  }
  balance() { return this.request('/account/balance'); }
  async generate(input) {
    const row = await this.request('/generation/image-to-model', {
      input, model: modelVersion, texture: true, texture_quality: 'standard',
      orientation: 'align_image', face_limit: 50000,
    });
    if (typeof row.task_id !== 'string' || !idPattern.test(row.task_id)) throw fail(503, 'TRIPO_UNAVAILABLE');
    return row.task_id;
  }
  task(id) { return this.request('/tasks/' + encodeURIComponent(id)); }
  async download(url, limit) {
    const source = typeof url === 'string' && URL.parse(url);
    if (!source || source.protocol !== 'https:' || source.username || source.password || source.port ||
        !/(^|\.)tripo3d\.(ai|com)$/i.test(source.hostname)) throw fail(422, 'TRIPO_UNSUPPORTED_MODEL');
    const response = await this.fetch(source, { redirect: 'error', signal: AbortSignal.timeout(18000) });
    if (!response.ok || !response.body) throw fail(503, 'TRIPO_UNAVAILABLE');
    if (Number(response.headers.get('content-length')) > limit) {
      await response.body.cancel();
      throw fail(422, 'TRIPO_UNSUPPORTED_MODEL');
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > limit) throw fail(422, 'TRIPO_UNSUPPORTED_MODEL');
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  }
}

export class DressArStorage {
  constructor(bucket) { this.bucket = bucket; }
  async save(path, bytes, contentType) {
    const file = this.bucket.file(path);
    const hash = createHash('sha256').update(bytes).digest('hex');
    try {
      await file.save(bytes, { resumable: false, validation: 'crc32c',
        preconditionOpts: { ifGenerationMatch: 0 },
        metadata: { contentType, cacheControl: 'private, no-store', metadata: { sha256: hash } } });
    } catch (error) {
      if (error.code !== 412 || (await file.getMetadata())[0].metadata?.sha256 !== hash) throw error;
    }
  }
  async download(path) { return (await this.bucket.file(path).download())[0]; }
}

function jobPath(dressId, rev) { return `dressArJobs/${dressId}/photos/${rev}`; }
function objectPath(id, job) { return `dress-ar/${id}/${job.photoRevision}/${job.attempt}`; }
function imageType(bytes) {
  if (bytes.length >= 8 && bytes.toString('hex', 0, 8) === '89504e470d0a1a0a') return 'image/png';
  if (bytes.length >= 4 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'image/jpeg';
  if (bytes.length >= 20 && bytes.toString('ascii', 0, 4) === 'RIFF' &&
      bytes.readUInt32LE(4) === bytes.length - 8 &&
      bytes.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return null;
}
function storedPhoto(photo) {
  if (photo?.mime !== 'image/jpeg' || typeof photo.data !== 'string' || photo.data.length > 273068) {
    throw fail(409, 'TRIPO_PHOTO_REQUIRED');
  }
  const bytes = Buffer.from(photo.data, 'base64');
  if (imageType(bytes) !== 'image/jpeg' || bytes.length > 200 * 1024) throw fail(409, 'TRIPO_PHOTO_REQUIRED');
  return bytes;
}

export class DressArService {
  constructor({ store, gateway, storage, now = Date.now }) {
    Object.assign(this, { store, gateway, storage, now });
  }
  async manager(tx, uid) {
    const actor = await tx.get(`staff/${uid}`);
    if (actor?.active !== true || actor.role !== 'manager') throw fail(403, 'MANAGER_REQUIRED');
  }
  async connection(uid) {
    await this.manager(this.store, uid);
    const balance = await this.gateway.balance();
    if (!Number.isFinite(balance.balance)) throw fail(503, 'TRIPO_UNAVAILABLE');
    return { connected: true, canGenerate: balance.balance >= generationCredits };
  }
  async snapshot(tx, id, rev) {
    const dress = await tx.get(`dresses/${id}`);
    if (!dress || !Number.isSafeInteger(rev) || rev < 1 || dress.photoRevision !== rev) throw fail(404, 'TRIPO_PHOTO_CHANGED');
    return { dress, job: await tx.get(jobPath(id, rev)) };
  }
  view(job) {
    const state = job?.state ?? 'idle';
    return { configured: this.gateway.enabled, estimateCredits: generationCredits,
      state: state === 'submitting' && this.now() - job.updatedAt > 45000 ? 'submission_unknown' : state,
      progress: job?.progress ?? 0, credits: job?.credits ?? null, error: job?.error ?? null,
      approved: job?.approved === true, front: job?.front ?? '+Z', preview: !!job?.previewType };
  }
  async start(uid, id, rev) {
    const path = jobPath(id, rev);
    const existing = await this.store.atomic(async tx => {
      await this.manager(tx, uid);
      const { dress, job } = await this.snapshot(tx, id, rev);
      if (dress.arModelId) throw fail(409, 'TRIPO_BUNDLED_MODEL_SELECTED');
      if (job && (job.state !== 'failed' || recoverable(job))) return { job };
      if (!this.gateway.enabled) throw fail(503, 'TRIPO_NOT_CONFIGURED');
      const photo = await tx.get(`dressPhotos/${id}`);
      if (photo?.revision !== rev) throw fail(409, 'TRIPO_PHOTO_REQUIRED');
      const bytes = storedPhoto(photo);
      const pending = { state: 'preparing', attempt: randomUUID(), photoRevision: rev, updatedAt: this.now() };
      tx.set(path, pending);
      return { pending, bytes };
    });
    if (existing.job) return recoverable(existing.job)
      ? this.status(uid, id, rev) : this.view(existing.job);
    const { pending, bytes } = existing;
    let committed = false;
    try {
      const balance = await this.gateway.balance();
      if (!Number.isFinite(balance.balance)) throw fail(503, 'TRIPO_UNAVAILABLE');
      if (balance.balance < generationCredits) throw fail(409, 'TRIPO_INSUFFICIENT_CREDITS');
      const token = await this.gateway.upload(bytes);
      // Persist the paid boundary before submitting. Recheck access and photo
      // in case either changed during upload.
      await this.store.atomic(async tx => {
        await this.manager(tx, uid);
        const { job, dress } = await this.snapshot(tx, id, rev);
        if (job?.attempt !== pending.attempt || job.state !== 'preparing' || dress.arModelId) {
          throw fail(409, 'TRIPO_PHOTO_CHANGED');
        }
        tx.set(path, { ...pending, state: 'submitting', updatedAt: this.now() });
      });
      committed = true;
      const taskId = await this.gateway.generate(token);
      const row = { ...pending, state: 'running', taskId, updatedAt: this.now() };
      await this.update(path, pending, row);
      return this.view(row);
    } catch (error) {
      const definite = !committed || ['TRIPO_REJECTED', 'TRIPO_INSUFFICIENT_CREDITS'].includes(error.code);
      const row = { ...pending, state: definite ? 'failed' : 'submission_unknown',
        error: error instanceof HttpError ? error.code : 'TRIPO_UNAVAILABLE', updatedAt: this.now() };
      await this.update(path, pending, row);
      return this.view(row);
    }
  }
  async update(path, previous, row) {
    await this.store.atomic(async tx => {
      const current = await tx.get(path);
      if (current?.attempt !== previous.attempt) return;
      if (!['ready', 'failed'].includes(current.state) ||
          recoverable(current) && recoverable(previous) && current.taskId === previous.taskId) tx.set(path, row);
    });
  }
  async downloadPreview(url) {
    const bytes = url ? await this.gateway.download(url, previewLimit).catch(() => null) : null;
    return { bytes, mime: bytes && imageType(bytes) };
  }
  async restorePreview(id, rev, job) {
    const task = await this.gateway.task(job.taskId);
    const preview = await this.downloadPreview(task.output?.rendered_image_url);
    if (preview.mime) {
      await this.storage.save(objectPath(id, job) + '.preview', preview.bytes, preview.mime);
    }
    return this.store.atomic(async tx => {
      const path = jobPath(id, rev);
      const current = await tx.get(path);
      if (current?.state !== 'ready' || current.attempt !== job.attempt || current.previewType) return current;
      const row = { ...current, previewType: preview.mime, previewExamined: true };
      tx.set(path, row);
      return row;
    });
  }
  async status(uid, id, rev) {
    const { job } = await this.store.atomic(async tx => {
      await this.manager(tx, uid);
      return this.snapshot(tx, id, rev);
    });
    if (job?.state === 'preparing' && this.now() - job.updatedAt > 45000) {
      const row = { ...job, state: 'failed', error: 'TRIPO_UNAVAILABLE' };
      // Only preparation can expire into a retry. Keep an unknown paid submission locked.
      await this.store.atomic(async tx => {
        const path = jobPath(id, rev);
        const current = await tx.get(path);
        if (current?.attempt === job.attempt && current.state === 'preparing') tx.set(path, row);
      });
      return this.view(row);
    }
    if (!this.gateway.enabled) return this.view(job);
    if (job?.state === 'ready' && !job.previewType && !job.previewExamined && job.taskId) {
      return this.view(await this.restorePreview(id, rev, job));
    }
    if (job?.state !== 'running' && !recoverable(job)) return this.view(job);
    const result = await this.gateway.task(job.taskId);
    const credits = Number.isFinite(result.credits_consumed) ? result.credits_consumed : null;
    let row = { ...job, credits, progress: Math.max(0, Math.min(100, Number(result.progress) || 0)) };
    if (result.status === 'success') {
      try {
        const [model, preview] = await Promise.all([
          this.gateway.download(result.output?.model_url, modelLimit),
          this.downloadPreview(result.output?.rendered_image_url),
        ]);
        calibrateDressModel(model);
        const base = objectPath(id, job);
        await this.storage.save(base + '.glb', model, 'model/gltf-binary');
        if (preview.mime) await this.storage.save(base + '.preview', preview.bytes, preview.mime);
        row = { ...row, state: 'ready', progress: 100, error: null, previewType: preview.mime,
          previewExamined: true, approved: false, front: '+Z' };
      } catch (error) {
        if (error.code !== 'TRIPO_UNSUPPORTED_MODEL') throw error;
        row = { ...row, state: 'failed', error: error.code };
      }
    } else if (failedTasks.has(result.status)) row = { ...row, state: 'failed', error: 'TRIPO_TASK_FAILED' };
    if (row.state !== 'running') await this.update(jobPath(id, rev), job, row);
    return this.view(row);
  }
  async approve(uid, id, rev, approved, front) {
    if (typeof approved !== 'boolean' || !Object.hasOwn(frontAngles, front)) throw fail(400, 'TRIPO_INVALID_REQUEST');
    return this.store.atomic(async tx => {
      await this.manager(tx, uid);
      const { dress, job } = await this.snapshot(tx, id, rev);
      if (job?.state !== 'ready' || dress.arModelId) throw fail(409, 'TRIPO_MODEL_UNAVAILABLE');
      const row = { ...job, approved, front };
      tx.set(jobPath(id, rev), row);
      return this.view(row);
    });
  }
  async available(uid, id, rev) {
    return this.store.atomic(async tx => {
      if (!await tx.get(`brides/${uid}`) || await tx.get(`staff/${uid}`)) return false;
      const { dress, job } = await this.snapshot(tx, id, rev);
      return dress.published === true && !dress.arModelId && job?.state === 'ready' && job.approved === true;
    });
  }
  async media(uid, id, rev, kind) {
    const job = await this.store.atomic(async tx => {
      if (kind === 'preview') await this.manager(tx, uid);
      else if (!await tx.get(`brides/${uid}`) || await tx.get(`staff/${uid}`)) throw fail(403, 'ACCOUNT_ACCESS_REQUIRED');
      const { dress, job } = await this.snapshot(tx, id, rev);
      if (job?.state !== 'ready' || (kind === 'preview' ? !job.previewType :
        !job.approved || !dress.published || dress.arModelId)) throw fail(404, 'TRIPO_MODEL_UNAVAILABLE');
      return job;
    });
    const base = objectPath(id, job);
    if (kind === 'preview') return { bytes: await this.storage.download(base + '.preview'), mime: job.previewType };
    const bytes = await this.storage.download(base + '.glb');
    return { bytes: calibrateDressModel(bytes, job.front), mime: 'model/gltf-binary' };
  }
}
