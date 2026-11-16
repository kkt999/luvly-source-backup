import test from 'node:test';
import assert from 'node:assert/strict';
import { CalendarService, tokenVault, appointmentEvent } from './calendar_service.mjs';

function fixture() {
  const rows = new Map(), remote = new Map(), calls = [];
  const collection = path => ({
    doc: id => ({
      get: async () => ({ data: () => rows.get(`${path}/${id}`) }),
      set: async (data, options) => rows.set(`${path}/${id}`, options?.merge ? { ...rows.get(`${path}/${id}`), ...data } : data),
      collection: name => collection(`${path}/${id}/${name}`),
    }),
    where: (field, op, expected) => ({ get: async () => ({ docs: [...rows.entries()]
      .filter(([key, value]) => key.startsWith(`${path}/`) && key.split('/').length === path.split('/').length + 1 && value[field] === expected)
      .map(([key, value]) => ({ id: key.split('/').at(-1), data: () => value })) }) }),
  });
  let now = 1000;
  const gateway = {
    authorization: state => `https://accounts.google.com/?state=${state}`,
    exchange: async () => ({ subject: 'google-user', refresh: 'private-refresh' }),
    request: async (token, path, method = 'GET', body) => {
      calls.push({ path, method, body });
      if (path === '/calendars') return { id: 'calendar-id' };
      if (method === 'GET') {
        if (!remote.has(path)) throw { response: { status: 404 } };
        return remote.get(path);
      }
      if (method === 'POST') remote.set(`${path}/${body.id}`, body);
      if (method === 'PATCH') remote.set(path, body);
      if (method === 'DELETE') remote.delete(path);
      return {};
    },
  };
  const service = new CalendarService({ db: { collection },
    auth: { getUser: async () => ({ providerData: [{ providerId: 'google.com', uid: 'google-user' }] }) },
    gateway, key: Buffer.alloc(32, 7), now: () => now });
  const connect = async () => {
    const { url } = await service.connect('u');
    const params = new URL(url).searchParams; params.set('code', 'code');
    await service.callback(params); return params;
  };
  const appointment = (status = 'Confirmed') => ({ uid: 'u', status, type: 'Dress Trial', startAt: { toDate: () => new Date('2026-10-15T06:00:00Z') } });
  return { rows, remote, calls, gateway, service, connect, appointment, advance: () => { now += 600001; } };
}

test('vault encrypts with randomized IV and rejects another UID and tampering', () => {
  const vault = tokenVault(Buffer.alloc(32, 9));
  const encrypted = vault.seal('u', 'secret');
  assert.equal(vault.open('u', encrypted), 'secret');
  assert.notEqual(vault.seal('u', 'secret'), encrypted);
  assert.throws(() => vault.open('other', encrypted));
  const bytes = Buffer.from(encrypted, 'base64'); bytes[30] ^= 1;
  assert.throws(() => vault.open('u', bytes.toString('base64')));
});

test('event uses stable IDs, Malaysia timezone, one-hour duration and excludes personal notes', () => {
  const f = fixture(), event = appointmentEvent('u', 'a', { ...f.appointment(), notes: 'private', phone: 'secret' });
  assert.match(event.id, /^[a-f0-9]{64}$/);
  assert.equal(event.start.timeZone, 'Asia/Kuala_Lumpur');
  assert.equal(Date.parse(event.end.dateTime) - Date.parse(event.start.dateTime), 3600000);
  assert.doesNotMatch(JSON.stringify(event), /secret/);
  assert.throws(() => appointmentEvent('other', 'a', f.appointment()));
});

test('OAuth state is single-use and persisted refresh credential is encrypted', async () => {
  const f = fixture(), params = await f.connect();
  assert.equal((await f.service.status('u')).connected, true);
  assert.doesNotMatch(JSON.stringify(f.rows.get('calendarConnections/u')), /private-refresh/);
  await assert.rejects(f.service.callback(params));
  assert.equal((await f.service.status('other')).connected, false);
});

test('expired state and different Google account cannot connect', async () => {
  const f = fixture();
  const params = new URL((await f.service.connect('u')).url).searchParams;
  params.set('code', 'code'); f.advance();
  await assert.rejects(f.service.callback(params));
  f.gateway.exchange = async () => ({ subject: 'wrong', refresh: 'secret' });
  await assert.rejects(f.connect());
  assert.equal(f.rows.size, 0);
});

test('sync creates once, updates changes and removes cancelled events', async () => {
  const f = fixture(); await f.connect();
  f.rows.set('appointments/a', f.appointment());
  f.rows.set('appointments/requested', f.appointment('Requested'));
  assert.equal((await f.service.sync('u')).state, 'Synced');
  assert.equal(f.remote.size, 1);
  const count = f.calls.length;
  await f.service.sync('u'); assert.equal(f.calls.length, count);
  f.rows.set('appointments/a', { ...f.appointment(), type: 'Bridal Consultation' });
  await f.service.sync('u'); assert.equal(f.calls.at(-1).method, 'PATCH');
  f.rows.set('appointments/a', f.appointment('Cancelled'));
  await f.service.sync('u'); assert.equal(f.remote.size, 0);
});

test('rescheduling patches the same Google event instead of creating a second appointment event',async()=>{
  const f=fixture();await f.connect();
  f.rows.set('appointments/appointment',{...f.appointment(),startAt:new Date('2026-10-15T02:00:00Z')});
  await f.service.sync('u');
  f.rows.set('appointments/appointment',{...f.appointment(),startAt:new Date('2026-10-16T03:00:00Z')});
  await f.service.sync('u');
  const events=f.calls.filter(c=>c.path.includes('/events'));
  assert.equal(events.filter(c=>c.method==='POST').length,1);assert.equal(events.filter(c=>c.method==='PATCH').length,1);
  const patch=events.find(c=>c.method==='PATCH');assert.equal(patch.body.start.dateTime,'2026-10-16T03:00:00.000Z');
});
test('cancellation recovers a successful remote insert with missing local sync record', async () => {
  const f = fixture(); await f.connect(); f.rows.set('appointments/a', f.appointment());
  await f.service.sync('u');
  for (const key of f.rows.keys()) if (key.includes('/events/')) f.rows.delete(key);
  f.rows.set('appointments/a', f.appointment('Cancelled'));
  await f.service.sync('u'); assert.equal(f.remote.size, 0);
});

test('sync refuses to overwrite a remote event not owned by Luvly', async () => {
  const f = fixture(); await f.connect(); f.rows.set('appointments/a', f.appointment());
  const event = appointmentEvent('u', 'a', f.appointment());
  f.remote.set(`/calendars/calendar-id/events/${event.id}`, { summary: 'Personal' });
  assert.equal((await f.service.sync('u')).state, 'Sync failed');
  assert.equal([...f.remote.values()][0].summary, 'Personal');
});

test('disconnect forgets credentials and stops writes without deleting events', async () => {
  const f = fixture(); await f.connect(); f.rows.set('appointments/a', f.appointment());
  await f.service.sync('u'); await f.service.disconnect('u');
  assert.equal(f.rows.get('calendarConnections/u').token, undefined);
  const count = f.calls.length; await f.service.sync('u');
  assert.equal(f.calls.length, count); assert.equal(f.remote.size, 1);
});

test('revoked refresh grant reports reconnect required', async () => {
  const f = fixture(); await f.connect();
  f.gateway.request = async () => { throw { response: { data: { error: 'invalid_grant' } } }; };
  assert.equal((await f.service.sync('u')).state, 'Reconnect required');
  assert.equal((await f.service.status('u')).connected, false);
});

test('ambiguous calendar creation is not blindly retried on the next sync', async () => {
  const f = fixture(); await f.connect(); let count = 0;
  f.gateway.request = async () => { count++; throw Error('timeout after possible creation'); };
  await f.service.sync('u'); await f.service.sync('u');
  assert.equal(count, 1);
  assert.equal((await f.service.status('u')).state, 'Sync failed');
});
