import { createHash, randomUUID } from 'node:crypto';
import { HttpError } from './payment_service.mjs';
import { assistantLanguage, guideMatch, helpGuide } from './support_assistant.mjs';

const idPattern = /^[a-f0-9]{32}$/;
const languages = ['auto', 'en', 'zh', 'ms'];
const titleLimit = 64;
const leaseLength = 60_000;
const pageSize = 20;
const controls = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/;
const check = (condition, code = 'INVALID_ASSISTANT_CONVERSATION', status = 400) => {
  if (!condition) throw new HttpError(status, code);
};
const validID = id => typeof id === 'string' && idPattern.test(id);
const fingerprint = value => createHash('sha256').update(value).digest('hex');
const roomPath = (uid, id) => `assistantAccounts/${uid}/conversations/${id}`;
const accountPath = uid => `assistantAccounts/${uid}`;
const turnPath = (path, id) => `${path}/turns/${id}`;
const deletedPath = (uid, id) => `assistantAccounts/${uid}/deletedConversations/${id}`;
const visible = row => row && !row.deleting;

function normalize(value) {
  return value.normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{M}\p{N}]+/gu, ' ').trim();
}

function searchTerms(...values) {
  const terms = new Set();
  for (const value of values) {
    const chars = [...normalize(value)];
    for (let start = 0; start < chars.length; start++) {
      if (start > 0 && chars[start - 1] !== ' ' && !/\p{Script=Han}/u.test(chars[start])) continue;
      for (let end = start + 1; end <= Math.min(chars.length, start + 32); end++) {
        if (chars[end - 1] !== ' ') terms.add(chars.slice(start, end).join(''));
      }
    }
  }
  return [...terms];
}

function topic(question, language, history) {
  const { articleIds } = guideMatch(question, history);
  return helpGuide.articles.find(article => article.id === articleIds[0])?.title[language] ??
    { en: 'General question', zh: '一般问题', ms: 'Soalan umum' }[language];
}

function metadata(id, row) {
  return {
    id,
    title: row.deleting ? 'Conversation pending deletion' : row.title,
    preview: row.deleting ? null : row.preview,
    updatedAt: row.updatedAt,
    archived: row.state === 'archived',
    deleting: row.deleting === true,
    language: row.language ?? 'auto',
    turnCount: row.turnCount ?? 0,
  };
}

function turnView(id, row, now) {
  return {
    id,
    question: row.question,
    sequence: row.sequence,
    createdAt: row.createdAt,
    status: row.status === 'generating' && row.leaseUntil <= now ? 'failed' : row.status,
    reply: row.reply ?? null,
  };
}

function decodeCursor(value) {
  if (value === undefined) return null;
  check(typeof value === 'string' && /^[A-Za-z0-9_-]{1,180}$/.test(value));
  let parts;
  try { parts = JSON.parse(Buffer.from(value, 'base64url').toString()); } catch { /* Invalid cursor. */ }
  check(Array.isArray(parts) && parts.length === 2 && Number.isSafeInteger(parts[0]) &&
    parts[0] > 0 && validID(parts[1]));
  return parts;
}

export class AssistantConversations {
  constructor({ store, assistant, access, now = Date.now }) {
    Object.assign(this, { store, assistant, access, now });
  }

  async customer(uid) {
    check((await this.access(uid)).role === 'bride', 'ASSISTANT_CUSTOMER_REQUIRED', 403);
  }

  async list(uid, input) {
    await this.customer(uid);
    check(Object.keys(input).every(key => ['archived', 'query', 'cursor'].includes(key)) &&
      typeof input.archived === 'boolean' &&
      (input.query === undefined || typeof input.query === 'string' && input.query.length <= 100));
    const cursor = decodeCursor(input.cursor);
    const term = normalize(input.query ?? '');
    check([...term].length <= 32, 'ASSISTANT_SEARCH_TOO_LONG');
    if (input.query?.trim() && !term) return { records: [], nextCursor: null };
    const state = input.archived ? 'archived' : 'active';
    const rows = await this.store.conversationPage(uid, state, term, cursor, pageSize + 1);
    const records = rows.slice(0, pageSize).map(({ id, data }) => metadata(id, data));
    const last = records.at(-1);
    return {
      records,
      nextCursor: rows.length > pageSize
        ? Buffer.from(JSON.stringify([last.updatedAt, last.id])).toString('base64url')
        : null,
    };
  }

  async resume(uid) {
    await this.customer(uid);
    const account = await this.store.get(accountPath(uid));
    if (validID(account?.activeId)) {
      try {
        const page = await this.page(uid, account.activeId);
        if (!page.conversation.archived) return page;
      } catch (error) {
        if (error.code !== 'ASSISTANT_CONVERSATION_MISSING') throw error;
      }
    }
    return { conversation: null, turns: [], before: null, language: account?.language ?? 'auto' };
  }

  async page(uid, id, before = null) {
    const path = roomPath(uid, id);
    const { room, rows } = await this.store.conversationWithTurns(path, before, pageSize + 1);
    check(visible(room), 'ASSISTANT_CONVERSATION_MISSING', 404);
    const turns = rows.slice(0, pageSize).reverse().map(({ id, data }) => turnView(id, data, this.now()));
    return {
      conversation: metadata(id, room),
      turns,
      before: rows.length > pageSize ? turns[0].sequence : null,
      language: room.language,
    };
  }

  async read(uid, id, before) {
    await this.customer(uid);
    check(before === null || /^[1-9]\d{0,9}$/.test(before));
    return this.page(uid, id, before === null ? null : Number(before));
  }

  async select(uid, id, input = {}) {
    await this.customer(uid);
    check(Object.keys(input).every(key => key === 'language') &&
      (input.language === undefined || !id && languages.includes(input.language)));
    const account = accountPath(uid);
    await this.store.atomic(async tx => {
      const prefs = await tx.get(account) ?? {};
      const row = id ? await tx.get(roomPath(uid, id)) : null;
      if (id) check(visible(row), 'ASSISTANT_CONVERSATION_MISSING', 404);
      if (!row || row.state === 'active') {
        tx.set(account, { ...prefs, activeId: id, ...(input.language ? { language: input.language } : {}) });
      }
    });
    return id ? this.page(uid, id) : { saved: true };
  }

  async update(uid, id, input) {
    await this.customer(uid);
    const keys = Object.keys(input);
    check(keys.length === 1 && ['title', 'archived', 'language'].includes(keys[0]));
    let change;
    if ('title' in input) {
      check(id && typeof input.title === 'string' && input.title.length <= 200 && !controls.test(input.title));
      const title = input.title.trim().replace(/\s+/gu, ' ');
      check(title && [...title].length <= titleLimit && this.assistant.safeInput(title) === title,
        'INVALID_ASSISTANT_TITLE');
      change = { title };
    }
    if ('archived' in input) {
      check(id && typeof input.archived === 'boolean');
      change = { state: input.archived ? 'archived' : 'active' };
    }
    if ('language' in input) {
      check(languages.includes(input.language));
      change = { language: input.language };
    }
    return this.store.atomic(async tx => {
      const account = accountPath(uid);
      const prefs = await tx.get(account) ?? {};
      if (!id) {
        tx.set(account, { ...prefs, ...change });
        return { saved: true };
      }
      const path = roomPath(uid, id);
      const row = await tx.get(path);
      check(visible(row), 'ASSISTANT_CONVERSATION_MISSING', 404);
      check(!('language' in change) || row.state === 'active', 'ASSISTANT_CONVERSATION_ARCHIVED', 409);
      const next = { ...row, ...change };
      if ('title' in change) next.searchTerms = searchTerms(next.title, next.preview);
      if (input.archived === true && prefs.activeId === id) tx.set(account, { ...prefs, activeId: null });
      tx.set(path, next);
      return metadata(id, next);
    });
  }

  async remove(uid, id) {
    await this.customer(uid);
    const path = roomPath(uid, id);
    const account = accountPath(uid);
    const tombstone = deletedPath(uid, id);
    const purge = await this.store.atomic(async tx => {
      const [row, deleted, prefs] = await Promise.all([tx.get(path), tx.get(tombstone), tx.get(account)]);
      if (!row && deleted) return false;
      check(row, 'ASSISTANT_CONVERSATION_MISSING', 404);
      if (!row.deleting) {
        tx.set(path, { state: row.state, updatedAt: this.now(), deleting: true });
        if (prefs?.activeId === id) tx.set(account, { ...prefs, activeId: null });
      }
      return true;
    });
    if (purge) {
      // Keep the locked parent while purging. A failed purge remains retryable.
      await this.store.purgeConversationTurns(path);
      await this.store.atomic(async tx => {
        tx.set(tombstone, { deleted: true });
        tx.delete(path);
      });
    }
    return { deleted: true };
  }

  async send(uid, id, input) {
    await this.customer(uid);
    check(Object.keys(input).every(key => ['requestId', 'message', 'language', 'mode', 'consentVersion', 'create'].includes(key)) &&
      validID(input.requestId) && languages.includes(input.language) &&
      ['AI', 'Guide'].includes(input.mode) &&
      (input.create === undefined || typeof input.create === 'boolean') &&
      (input.mode !== 'AI' || input.consentVersion === this.assistant.consentVersion));
    const hasMessage = 'message' in input;
    if (hasMessage) check(typeof input.message === 'string' && input.message.trim() &&
      input.message.length <= 800 && [...input.message].length <= 256 && !controls.test(input.message));
    const question = hasMessage ? this.assistant.safeInput(input.message.trim()) : undefined;
    if (question === null) {
      // Validate ownership for existing chats without storing a rejected question.
      await this.store.atomic(async tx => {
        const room = await tx.get(roomPath(uid, id));
        const deleted = await tx.get(deletedPath(uid, id));
        check(!deleted && !room?.deleting && (room || input.create === true),
          'ASSISTANT_CONVERSATION_MISSING', 404);
        check(room?.state !== 'archived', 'ASSISTANT_CONVERSATION_ARCHIVED', 409);
      });
      return { privacy: this.assistant.privacy(input.language, input.message) };
    }
    const path = roomPath(uid, id);
    const account = accountPath(uid);
    const idOfTurn = input.requestId;
    const key = turnPath(path, idOfTurn);
    const lease = randomUUID().replaceAll('-', '');
    const claimed = await this.store.atomic(async tx => {
      const [room, prior, prefs] = await Promise.all([tx.get(path), tx.get(key), tx.get(account)]);
      check(!room?.deleting, 'ASSISTANT_CONVERSATION_MISSING', 404);
      if (!room) {
        check(input.create === true && question !== undefined && !await tx.get(deletedPath(uid, id)),
          'ASSISTANT_CONVERSATION_MISSING', 404);
      }
      if (prior && question !== undefined) {
        check(prior.fingerprint === fingerprint(question), 'ASSISTANT_REQUEST_CONFLICT', 409);
      }
      if (prior?.status === 'complete' || prior?.leaseUntil > this.now()) {
        return { room, turn: prior, generate: false };
      }
      check(room?.state !== 'archived', 'ASSISTANT_CONVERSATION_ARCHIVED', 409);
      if (!prior) {
        check(question !== undefined, 'ASSISTANT_MESSAGE_MISSING', 404);
        check(!room?.pendingId, 'ASSISTANT_TURN_PENDING', 409);
      }
      const now = this.now();
      const message = prior?.question ?? question;
      const preview = topic(message, assistantLanguage(input.language, message), []);
      const row = room ?? { title: preview, state: 'active', createdAt: now, turnCount: 0 };
      const sequence = prior?.sequence ?? row.turnCount + 1;
      const turn = {
        sequence, question: message, fingerprint: fingerprint(message),
        status: 'generating', lease, leaseUntil: now + leaseLength,
        createdAt: prior?.createdAt ?? now,
      };
      const next = {
        ...row, preview, language: input.language, updatedAt: Math.max(row.updatedAt ?? 0, now),
        pendingId: idOfTurn, turnCount: sequence, searchTerms: searchTerms(row.title, preview),
      };
      tx.set(path, next);
      tx.set(key, turn);
      if (prefs?.activeId !== id) tx.set(account, { ...prefs, activeId: id });
      return { room: next, turn, generate: true };
    });
    const response = (room, turn) => ({
      conversation: metadata(id, room),
      turn: turnView(idOfTurn, turn, this.now()),
    });
    if (!claimed.generate) return response(claimed.room, claimed.turn);

    let reply;
    let context;
    try {
      const rows = await this.store.conversationTurns(path, claimed.turn.sequence, 4);
      context = rows.reverse().filter(({ data }) => data.status === 'complete').map(({ data }) => data.question);
      reply = await this.assistant.ask(uid, {
        message: claimed.turn.question, history: context, language: input.language,
        mode: input.mode, requestId: lease, ...(input.mode === 'AI' ? { consentVersion: input.consentVersion } : {}),
      }, { conversationId: id });
    } catch {
      return this.finish(path, key, lease, ({ room, turn }) => response(room, turn));
    }
    return this.finish(path, key, lease, ({ room, turn }) => response(room, turn), reply, context);
  }

  async finish(path, key, lease, result, reply, context = []) {
    return this.store.atomic(async tx => {
      const [room, turn] = await Promise.all([tx.get(path), tx.get(key)]);
      check(visible(room), 'ASSISTANT_CONVERSATION_MISSING', 404);
      check(turn, 'ASSISTANT_MESSAGE_MISSING', 404);
      if (turn.lease !== lease) return result({ room, turn });
      const { lease: _, leaseUntil: __, ...saved } = turn;
      const next = { ...saved, status: reply ? 'complete' : 'failed', ...(reply ? { reply } : {}) };
      tx.set(key, next);
      if (!reply) return result({ room, turn: next });
      const preview = topic(turn.question, reply.language, context);
      const updated = {
        ...room, preview, pendingId: null, updatedAt: Math.max(room.updatedAt, this.now()),
        searchTerms: searchTerms(room.title, preview),
      };
      tx.set(path, updated);
      return result({ room: updated, turn: next });
    });
  }
}
