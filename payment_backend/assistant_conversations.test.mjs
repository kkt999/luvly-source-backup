import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { AssistantConversations } from './assistant_conversations.mjs';
import { FirestoreStore } from './firestore_store.mjs';
import { createHandler } from './http_app.mjs';
import { PaymentService } from './payment_service.mjs';
import { SupportAssistant } from './support_assistant.mjs';

const projectId = 'demo-luvly';
const id = number => number.toString(16).padStart(32, '0');
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const local = host => /^(localhost|127\.0\.0\.1):\d+$/.test(host ?? '');

test('authenticated assistant CRUD, bounded context, retry, deletion and Rules against Firebase Emulator', {
  skip: !(local(firestoreHost) && local(authHost)),
  timeout: 120_000,
}, async () => {
  const app = initializeApp({ projectId }, 'assistant-conversations-test');
  const db = getFirestore(app);
  const auth = getAuth(app);
  const store = new FirestoreStore(db);
  const payments = new PaymentService({ store });
  const access = uid => payments.access(uid);
  const calls = [];
  let now = 1_800_000_000_000;
  let blockProvider;
  const assistant = new SupportAssistant({
    store, access, now: () => now, provider: 'Gemini', consentVersion: 3,
    config: () => ({ provider: 'Gemini', dailyRequestLimit: 100, perUserDailyLimit: 100 }),
    gateway: () => ({
      async route(message, history, language) {
        calls.push({ message, history, language });
        if (blockProvider) await blockProvider;
        return {
          articleIds: [],
          handoff: false,
          answer: history.length ? `Related to: ${history.at(-1)}` : 'Fixture answer',
        };
      },
    }),
  });
  let chats = new AssistantConversations({ store, assistant, access, now: () => now });
  const server = createServer((req, res) => createHandler({
    service: payments, assistant, assistantConversations: chats,
    verifyToken: token => auth.verifyIdToken(token),
  })(req, res));
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const api = `http://127.0.0.1:${server.address().port}/v1/assistant-conversations`;
  const firestore = `http://${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents`;

  async function user(role) {
    const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: `assistant-${role}-${Date.now()}@example.com`,
        password: 'Assistant1!test', returnSecureToken: true,
      }),
    });
    assert.equal(response.status, 200);
    return response.json();
  }

  async function request(base, path, token, body, method = body ? 'POST' : 'GET') {
    const response = await fetch(base + path, {
      method,
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    return { status: response.status, data: await response.json() };
  }

  try {
    const alice = await user('alice');
    const bob = await user('bob');
    const staff = await user('staff');
    const customerPath = `assistantAccounts/${alice.localId}/conversations`;
    await Promise.all([
      db.doc(`brides/${alice.localId}`).set({ role: 'bride' }),
      db.doc(`brides/${bob.localId}`).set({ role: 'bride' }),
      db.doc(`staff/${staff.localId}`).set({ role: 'manager', active: true }),
    ]);
    const get = (path = '', token = alice.idToken) => request(api, path, token);
    const post = (path, body = {}, token = alice.idToken) => request(api, path, token, body);
    const a = `/${id(1)}`;
    const b = `/${id(2)}`;
    const c = `/${id(3)}`;
    const send = (room, number, message, extra = {}) => post(room + '/send', {
      requestId: id(number), language: 'en', mode: 'AI', consentVersion: 3,
      ...(message ? { message, create: true } : {}), ...extra,
    });

    assert.equal((await get('', null)).status, 401);
    assert.equal((await get('', staff.idToken)).status, 403);
    assert.equal((await get()).data.conversation, null);
    assert.equal((await post('/new', { language: 'ms' })).status, 200);
    assert.equal((await get()).data.language, 'ms');
    assert.equal((await db.collection(customerPath).get()).size, 0);
    const rejected = await send(a, 100, 'otp: 123456');
    assert.equal(rejected.data.privacy.notice, 'Privacy');
    assert.equal((await db.collection(customerPath).get()).size, 0);
    assert.equal(calls.length, 0);

    const firstMessage = 'How much is a fitting? My email is person@example.com.';
    const first = await send(a, 101, firstMessage);
    assert.equal(first.status, 200);
    assert.match(first.data.turn.question, /\[email removed\]/);
    assert.doesNotMatch(first.data.conversation.title, /person|email/i);
    assert.equal(first.data.turn.sequence, 1);
    assert.equal(calls.length, 1);
    assert.deepEqual((await send(a, 101, firstMessage)).data.turn, first.data.turn);
    assert.equal(calls.length, 1);
    assert.equal((await send(a, 101, 'New text under an old ID')).status, 409);
    assert.equal((await send(a, 102, 'Fitting?', { uid: bob.localId })).status, 400);

    // A new service instance uses the same Firestore data after a restart.
    chats = new AssistantConversations({ store: new FirestoreStore(db), assistant, access, now: () => now });
    assert.equal((await get()).data.conversation.id, id(1));
    assert.equal((await get()).data.turns.length, 1);
    assert.equal((await post(a + '/update', { language: 'zh' })).data.language, 'zh');
    assert.equal((await get()).data.language, 'zh');
    const followUp = await send(a, 102, 'Can I use it towards my package?', { language: 'zh' });
    assert.equal(followUp.data.turn.sequence, 2);
    assert.deepEqual(calls.at(-1).history, [first.data.turn.question]);
    assert.equal(calls.at(-1).language, 'zh');

    await post('/new', { language: 'auto' });
    assert.equal((await get()).data.conversation, null);
    assert.equal((await send(b, 201, 'Can I rent earrings?')).status, 200);
    assert.deepEqual(calls.at(-1).history, []);
    assert.equal((await get()).data.conversation.id, id(2));
    assert.deepEqual((await post(a + '/open')).data.turns.map(turn => turn.sequence), [1, 2]);
    assert.equal((await get()).data.conversation.id, id(1));

    assert.equal((await post(a + '/update', { title: '  Fitting Fee Questions  ' })).data.title, 'Fitting Fee Questions');
    assert.equal((await post(a + '/update', { title: 'person@example.com' })).status, 400);
    const results = await post('/list', { archived: false, query: 'fee que' });
    assert.deepEqual(results.data.records.map(row => row.id), [id(1)]);
    assert.equal((await post(a + '/update', { archived: true })).data.archived, true);
    assert.equal((await get()).data.conversation, null);
    assert.equal((await post('/list', { archived: false })).data.records.length, 1);
    assert.deepEqual((await post('/list', { archived: true })).data.records.map(row => row.id), [id(1)]);
    assert.equal((await post(a + '/open')).data.turns.length, 2);
    assert.equal((await send(a, 103, 'How soon?')).status, 409);
    assert.equal((await post(a + '/update', { archived: false })).data.archived, false);
    assert.equal((await post(a + '/open')).data.turns.length, 2);

    assert.equal((await get(a, bob.idToken)).status, 404);
    assert.equal((await post(a + '/open', {}, bob.idToken)).status, 404);
    assert.equal((await post(a + '/update', { title: 'Cross-account' }, bob.idToken)).status, 404);
    assert.equal((await post(a + '/delete', {}, bob.idToken)).status, 404);
    assert.equal((await post(a + '/send', {
      requestId: id(101), language: 'en', mode: 'Guide', message: 'Change a turn',
    }, bob.idToken)).status, 404);
    assert.equal((await post('/list', { archived: false }, bob.idToken)).data.records.length, 0);
    const direct = `/${customerPath}/${id(1)}`;
    for (const token of [null, alice.idToken, bob.idToken, staff.idToken]) {
      for (const path of [direct, direct + `/turns/${id(101)}`, `/${customerPath}`]) {
        assert.equal((await request(firestore, path, token)).status, 403);
      }
    }
    assert.equal((await request(firestore, direct + `/turns/${id(999)}`, alice.idToken, {
      fields: { question: { stringValue: 'Forged' }, status: { stringValue: 'complete' } },
    }, 'PATCH')).status, 403);

    let release;
    blockProvider = new Promise(resolve => { release = resolve; });
    const pending = send(c, 301, 'How do I choose a dress?');
    for (let i = 0; i < 100 && calls.at(-1).message !== 'How do I choose a dress?'; i++) {
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    assert.equal(calls.at(-1).message, 'How do I choose a dress?');
    assert.equal((await send(c, 301, 'How do I choose a dress?')).data.turn.status, 'generating');
    assert.equal((await send(c, 302, 'A concurrent question')).data.error, 'ASSISTANT_TURN_PENDING');
    const nested = db.doc(`${customerPath}/${id(3)}/turns/${id(301)}/fixture/nested`);
    await nested.set({ value: 1 });
    assert.equal((await post(c + '/delete')).status, 200);
    blockProvider = null;
    release();
    assert.equal((await pending).status, 404);
    assert.equal((await nested.get()).exists, false);
    assert.equal((await db.doc(`${customerPath}/${id(3)}`).get()).exists, false);
    assert.equal((await send(c, 301, 'How do I choose a dress?')).status, 404);
    assert.equal((await post(c + '/delete')).status, 200);

    // Simulate an interrupted worker without waiting an actual minute.
    const bRef = db.doc(`${customerPath}/${id(2)}`);
    const pendingID = id(202);
    await bRef.update({ pendingId: pendingID, turnCount: 2 });
    await bRef.collection('turns').doc(pendingID).set({
      sequence: 2, question: 'How much is the deposit?', status: 'generating',
      createdAt: now, lease: 'abandoned', leaseUntil: now - 1,
    });
    assert.equal((await get(b)).data.turns.at(-1).status, 'failed');
    assert.equal((await send(b, 202)).data.turn.status, 'complete');
    assert.equal((await get(b)).data.turns.length, 2);

    const batch = db.batch();
    const existing = db.doc(`${customerPath}/${id(1)}`);
    const original = (await existing.collection('turns').doc(id(101)).get()).data();
    for (let i = 3; i <= 24; i++) {
      batch.set(existing.collection('turns').doc(id(1000 + i)), {
        ...original, sequence: i, question: `Fitting question ${i}`,
      });
    }
    batch.update(existing, { turnCount: 24 });
    for (let i = 30; i < 54; i++) {
      batch.set(db.doc(`${customerPath}/${id(i)}`), {
        title: 'Other fitting history', preview: 'Fitting history', state: 'active', updatedAt: now,
        language: 'en', turnCount: 1, searchTerms: ['fit'],
      });
    }
    await batch.commit();
    const latest = (await get(a)).data;
    assert.deepEqual(latest.turns.map(turn => turn.sequence), Array.from({ length: 20 }, (_, i) => i + 5));
    const older = (await get(a + '?before=' + latest.before)).data;
    assert.deepEqual(older.turns.map(turn => turn.sequence), [1, 2, 3, 4]);
    assert.equal(older.before, null);
    const history = (await post('/list', { archived: false, query: 'fit' })).data;
    const more = (await post('/list', { archived: false, query: 'fit', cursor: history.nextCursor })).data;
    assert.equal(history.records.length, 20);
    assert.equal(more.records.length, 5);
    assert.equal(new Set([...history.records, ...more.records].map(row => row.id)).size, 25);

    now += 1;
    assert.equal((await send(a, 103, 'What next?')).status, 200);
    assert.deepEqual(calls.at(-1).history, [21, 22, 23, 24].map(n => `Fitting question ${n}`));
    assert.equal((await get(a)).data.conversation.title, 'Fitting Fee Questions');
    assert.equal((await post(a + '/delete')).status, 200);
    assert.equal((await existing.collection('turns').get()).size, 0);
    assert.equal((await get()).data.conversation, null);

    const retryDelete = '/'+id(30);
    const purge = chats.store.purgeConversationTurns;
    chats.store.purgeConversationTurns = async () => { throw Error('fixture purge interruption'); };
    assert.equal((await post(retryDelete + '/delete')).status, 503);
    assert.equal((await get(retryDelete)).status, 404);
    const deleting = (await post('/list', { archived: false })).data.records
      .find(row => row.id === id(30));
    assert.equal(deleting.deleting, true);
    assert.equal(deleting.title, 'Conversation pending deletion');
    assert.equal(deleting.preview, null);
    chats.store.purgeConversationTurns = purge;
    assert.equal((await post(retryDelete + '/delete')).status, 200);
    assert.equal((await db.doc(`${customerPath}/${id(30)}`).get()).exists, false);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await db.terminate();
    await deleteApp(app);
  }
});
