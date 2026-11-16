import test from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp,GeoPoint} from 'firebase-admin/firestore';
import {authorisedSelections,typedBackup,remainingBookings} from './reset_selected_test_packages.mjs';
test('cleanup uses an immutable explicit selection allowlist, not a user-wide delete',()=>{
  assert.equal(authorisedSelections.length,11);
  assert.equal(new Set(authorisedSelections).size,11);
  assert.equal(Object.isFrozen(authorisedSelections),true);
  assert.ok(authorisedSelections.every(id=>/^[a-f0-9]{28,32}$/.test(id)));
});
test('backup preserves full Firestore timestamp precision and GeoPoint',()=>{
  assert.deepEqual(typedBackup(new Timestamp(1760000000,123456789)),{t:'timestamp',seconds:1760000000,nanoseconds:123456789});
  assert.deepEqual(typedBackup(new GeoPoint(3.1,101.6)),{t:'geopoint',latitude:3.1,longitude:101.6});
});
test('backup preserves dates, binary fields, arrays, primitive and map tag collisions',()=>{
  const value=typedBackup({t:'timestamp',n:12,ok:true,empty:null,list:[Buffer.from('abc'),new Date('2026-10-16T00:00:00Z')]});
  assert.equal(value.t,'map');assert.deepEqual(value.v.t,{t:'string',v:'timestamp'});
  assert.deepEqual(value.v.list.v[0],{t:'bytes',v:'YWJj'});
  assert.deepEqual(value.v.list.v[1],{t:'date',v:'2026-10-16T00:00:00.000Z'});
  assert.deepEqual(value.v.empty,{t:'null'});assert.deepEqual(value.v.ok,{t:'boolean',v:true});
  assert.throws(()=>typedBackup(undefined));
});
test('slot cleanup removes only exact authorised appointment IDs and preserves staff exceptions',()=>{
  const record={revision:4,entries:{staff:{available:false}},bookings:{10:{appointmentId:'target',uid:'owner'},11:{appointmentId:'other',uid:'other'}}};
  const before=JSON.stringify(record),next=remainingBookings(record,new Set(['target']));
  assert.deepEqual(next,{11:{appointmentId:'other',uid:'other'}});
  assert.equal(JSON.stringify(record),before);
  assert.deepEqual(remainingBookings({},new Set(['target'])),{});
});
