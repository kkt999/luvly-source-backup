import { randomBytes, createHash, createCipheriv, createDecipheriv } from 'node:crypto';
import { OAuth2Client } from 'google-auth-library';
import { HttpError } from './payment_service.mjs';
import {effectiveVisitTime} from './booking_dates.mjs';
import {appointmentTypes} from './workforce.mjs';

export const calendarScope = 'https://www.googleapis.com/auth/calendar.app.created';
const hash = value => createHash('sha256').update(value).digest('hex');
const fail = code => { throw new HttpError(400, code); };

export function tokenVault(key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) throw Error('CALENDAR_KEY_REQUIRED');
  return {
    seal(uid, value) {
      const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, iv);
      cipher.setAAD(Buffer.from(uid));
      const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
      return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64');
    },
    open(uid, value) {
      const bytes = Buffer.from(value, 'base64');
      const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(0, 12));
      decipher.setAAD(Buffer.from(uid)); decipher.setAuthTag(bytes.subarray(12, 28));
      return Buffer.concat([decipher.update(bytes.subarray(28)), decipher.final()]).toString('utf8');
    },
  };
}

export function appointmentEvent(uid, id, appointment) {
  const value = effectiveVisitTime(appointment);
  const date = value instanceof Date ? value : value?.toDate?.();
  if (appointment.uid !== uid || !(date instanceof Date) || !Number.isFinite(date.getTime())) {
    fail('INVALID_CALENDAR_APPOINTMENT');
  }
  const marker = hash(`${uid}:${id}`);
  return {
    id: marker,
    summary: `Luvly · ${appointmentTypes.includes(appointment.type) ? appointment.type : 'Appointment'}`,
    description: 'Your confirmed Luvly appointment. Open Luvly for the latest details. Payment status is separate.',
    start: { dateTime: date.toISOString(), timeZone: 'Asia/Kuala_Lumpur' },
    end: { dateTime: new Date(date.getTime() + 3600000).toISOString(), timeZone: 'Asia/Kuala_Lumpur' },
    extendedProperties: { private: { luvlyAppointment: marker } },
  };
}

export class GoogleCalendarGateway {
  constructor({ credential, redirectUri }) {
    if (credential?.project_id !== 'luvly-44c77' || !credential.client_secret ||
        !credential.client_id?.endsWith('.apps.googleusercontent.com')) throw Error('CALENDAR_CONFIG_REQUIRED');
    const url = new URL(redirectUri);
    if (url.protocol !== 'https:' || url.pathname !== '/oauth/google/calendar/callback' || url.search || url.hash || url.username) throw Error('CALENDAR_CALLBACK_REQUIRED');
    this.credential = credential; this.redirectUri = redirectUri;
  }
  client() { return new OAuth2Client(this.credential.client_id, this.credential.client_secret, this.redirectUri); }
  authorization(state, verifier) {
    return this.client().generateAuthUrl({ access_type: 'offline', prompt: 'consent select_account',
      scope: ['openid', calendarScope], state,
      code_challenge: createHash('sha256').update(verifier).digest('base64url'), code_challenge_method: 'S256' });
  }
  async exchange(code, verifier) {
    const client = this.client();
    const { tokens } = await client.getToken({ code, codeVerifier: verifier });
    if (!tokens.refresh_token || !tokens.id_token || !tokens.scope?.split(' ').includes(calendarScope)) fail('CALENDAR_CONSENT_REQUIRED');
    const ticket = await client.verifyIdToken({ idToken: tokens.id_token, audience: this.credential.client_id });
    return { subject: ticket.getPayload()?.sub, refresh: tokens.refresh_token };
  }
  async request(refresh, path, method = 'GET', data) {
    const client = this.client(); client.setCredentials({ refresh_token: refresh });
    return (await client.request({ url: `https://www.googleapis.com/calendar/v3${path}`, method, data,
      timeout: 15000, retry: false })).data;
  }
}

// Local UID queues plus optional durable cloud coordination serialize changes.
export class CalendarService {
  constructor({ db, auth, gateway, key, coordination=null, now = Date.now }) {
    Object.assign(this, { db, auth, gateway, coordination, now });
    this.vault = tokenVault(key); this.states = new Map(); this.locks = new Map();
  }
  async locked(uid, action) {
    const previous = this.locks.get(uid) ?? Promise.resolve();
    const running = previous.catch(() => {}).then(()=>this.coordination?this.coordination.locked(uid,action):action());
    this.locks.set(uid, running);
    try { return await running; } finally { if (this.locks.get(uid) === running) this.locks.delete(uid); }
  }
  ref(uid) { return this.db.collection('calendarConnections').doc(uid); }
  async identity(uid) {
    const user = await this.auth.getUser(uid);
    if (user.disabled) fail('CALENDAR_ACCOUNT_UNAVAILABLE');
    const subject = user.providerData.find(p => p.providerId === 'google.com')?.uid;
    if (!subject) fail('CALENDAR_GOOGLE_LINK_REQUIRED');
    return subject;
  }
  async status(uid) {
    const value = (await this.ref(uid).get()).data();
    return { configured: true, connected: value?.connected === true,
      state: value?.state ?? 'Not connected', lastSyncedAt: value?.lastSyncedAt ?? null };
  }
  async connect(uid) {
    await this.identity(uid);
    const now = this.now();
    for (const [id, state] of this.states) if (state.expires <= now || state.uid === uid) this.states.delete(id);
    if (this.states.size >= 500) throw new HttpError(429, 'TRY_LATER');
    const state = randomBytes(32).toString('base64url'), verifier = randomBytes(48).toString('base64url');
    if(this.coordination)await this.coordination.put(hash(state),{uid,verifier:this.vault.seal(uid,verifier),expires:now+600000});
    else this.states.set(hash(state), { uid, verifier, expires: now + 600000 });
    return { url: this.gateway.authorization(state, verifier) };
  }
  async callback(params) {
    if (['state', 'code', 'error'].some(k => params.getAll(k).length > 1)) fail('CALENDAR_INVALID_STATE');
    const raw = params.get('state');
    if (!raw || !/^[A-Za-z0-9_-]{43}$/.test(raw)) fail('CALENDAR_INVALID_STATE');
    const state = this.coordination?await this.coordination.take(hash(raw)):this.states.get(hash(raw)); this.states.delete(hash(raw));
    if (!state || state.expires <= this.now()) fail('CALENDAR_INVALID_STATE');
    if (params.has('error')) fail('CALENDAR_CONSENT_REQUIRED');
    const code = params.get('code');
    if (!code || code.length > 4096) fail('CALENDAR_CONSENT_REQUIRED');
    return this.locked(state.uid, async () => {
      const grant = await this.gateway.exchange(code, this.coordination?this.vault.open(state.uid,state.verifier):state.verifier);
      if (!grant.subject || grant.subject !== await this.identity(state.uid)) fail('CALENDAR_WRONG_GOOGLE_ACCOUNT');
      const ref = this.ref(state.uid), old = (await ref.get()).data();
      // Reusing a calendar is safe only for the same Google subject.
      if (old?.subject && old.subject !== grant.subject) fail('CALENDAR_WRONG_GOOGLE_ACCOUNT');
      await ref.set({ uid: state.uid, subject: grant.subject, connected: true,
        token: this.vault.seal(state.uid, grant.refresh), state: 'Pending', updatedAt: this.now() }, { merge: true });
    });
  }
  async disconnect(uid) {
    return this.locked(uid, async () => {
      if(this.coordination)await this.coordination.clear(uid);
      for (const [id, state] of this.states) if (state.uid === uid) this.states.delete(id);
      const ref = this.ref(uid), old = (await ref.get()).data();
      // Forget credentials locally. Do not revoke a shared Google-client grant
      // used by Firebase login, or delete the user's existing calendar/events.
      if (old) { const { token, ...retained } = old; await ref.set({ ...retained, connected: false, state: 'Not connected' }); }
      return this.status(uid);
    });
  }
  async sync(uid) {
    return this.locked(uid, async () => {
      const ref = this.ref(uid), connection = (await ref.get()).data();
      if (!connection?.connected) return this.status(uid);
      try {
        if (connection.subject !== await this.identity(uid)) fail('CALENDAR_WRONG_GOOGLE_ACCOUNT');
        const refresh = this.vault.open(uid, connection.token);
        let calendarId = connection.calendarId;
        if (!calendarId) {
          // Persist intent before this non-idempotent operation. An ambiguous
          // timeout/crash needs operator reconciliation, not another calendar.
          if (connection.provisioningStarted) throw Error('CALENDAR_CREATION_NEEDS_REVIEW');
          await ref.set({ provisioningStarted: true }, { merge: true });
          const calendar = await this.gateway.request(refresh, '/calendars', 'POST', { summary: 'Luvly appointments', timeZone: 'Asia/Kuala_Lumpur' });
          if (!calendar.id) throw Error('CALENDAR_CREATE_FAILED');
          calendarId = calendar.id; await ref.set({ calendarId }, { merge: true });
        }
        const base = `/calendars/${encodeURIComponent(calendarId)}/events`;
        const appointments = await this.db.collection('appointments').where('uid', '==', uid).get();
        for (const doc of appointments.docs) {
          const value = doc.data();
          if (!['Confirmed', 'Completed', 'Cancelled', 'Declined', 'NoShow'].includes(value.status)) continue;
          const event = appointmentEvent(uid, doc.id, value), record = ref.collection('events').doc(event.id);
          const prior = (await record.get()).data();
          const fingerprint = hash(JSON.stringify([value.status, event]));
          if (prior?.fingerprint === fingerprint) continue;
          // Check the deterministic remote ID even without a local record: a
          // previous insert may have succeeded before its Firestore write failed.
          let remote;
          try { remote = await this.gateway.request(refresh, `${base}/${event.id}`); }
          catch (error) { if (![404, 410].includes(error.response?.status)) throw error; }
          if (remote && remote.status !== 'cancelled' && remote.extendedProperties?.private?.luvlyAppointment !== event.id) throw Error('CALENDAR_EVENT_NOT_OWNED');
          if (['Cancelled', 'Declined', 'NoShow'].includes(value.status)) {
            if (remote && remote.status !== 'cancelled') {
              try { await this.gateway.request(refresh, `${base}/${event.id}`, 'DELETE'); }
              catch (error) { if (![404, 410].includes(error.response?.status)) throw error; }
            }
          } else if (remote?.status === 'cancelled') {
            // Respect a user's manual deletion rather than recreating it.
            await record.set({ fingerprint, manuallyRemoved: true }); continue;
          } else if (remote) {
            const { id, ...patch } = event;
            await this.gateway.request(refresh, `${base}/${event.id}`, 'PATCH', patch);
          } else {
            await this.gateway.request(refresh, base, 'POST', event);
          }
          await record.set({ fingerprint });
        }
        await ref.set({ state: 'Synced', lastSyncedAt: this.now() }, { merge: true });
      } catch (error) {
        const code = error.response?.data?.error;
        const reconnect = code === 'invalid_grant' || error.response?.status === 401 || error.code === 'CALENDAR_WRONG_GOOGLE_ACCOUNT';
        await ref.set({ state: reconnect ? 'Reconnect required' : 'Sync failed', connected: !reconnect }, { merge: true });
      }
      return this.status(uid);
    });
  }
  start() {
    let busy = false;
    const tick = async () => {
      if (busy) return; busy = true;
      try {
        const rows = await this.db.collection('calendarConnections').where('connected', '==', true).get();
        for (const doc of rows.docs) await this.sync(doc.id);
      } catch { /* Backend offline: next tick retries; no credentials in logs. */ }
      finally { busy = false; }
    };
    const timer = setInterval(tick, 60000); timer.unref();
    void tick(); return () => clearInterval(timer);
  }
}
