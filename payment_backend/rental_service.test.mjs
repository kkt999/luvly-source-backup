import test from 'node:test';
import assert from 'node:assert/strict';
import { RentalService, HOLD_MS, rentalDates, variantId, peakUsage } from './rental_service.mjs';
import { PaymentService } from './payment_service.mjs';

class Store {
  data = new Map(); queue = Promise.resolve();
  async get(path) { return structuredClone(this.data.get(path)); }
  atomic(fn) {
    const promise = this.queue.then(async () => {
      const writes = new Map();
      const result = await fn({ get: path => { assert.equal(writes.size, 0, 'Read after write'); return this.get(path); },
        set: (path, value) => writes.set(path, structuredClone(value)) });
      for (const [path, value] of writes) this.data.set(path, value);
      return result;
    });
    this.queue = promise.catch(() => {}); return promise;
  }
}
async function fixture(quantity = 1) {
  let now = Date.parse('2026-10-13T02:00:00Z');
  const store = new Store();
  for (const [path, value] of Object.entries({
    'staff/staff': { active: true, role: 'staff' },
    'staffScheduling/staff': { jobRole:'FrontDesk' },
    'staff/revoked': { active: false, role: 'staff' },
    'dresses/gown': { published: true, availability: 'Available', sizes: 'S, M' },
    'brides/customer': { name: 'Test', phone: '0123456789', email: 'test@example.com' },
    'appointments/a': { uid: 'customer', status: 'Confirmed', assignedStaffId: 'staff' },
    'appointments/b': { uid: 'customer', status: 'Confirmed', assignedStaffId: 'staff' },
  })) store.data.set(path, value);
  const rentals = new RentalService({ store, now: () => now });
  const payments = new PaymentService({ store, rentals, now: () => now, gateway: {} });
  await rentals.saveVariant('staff', { dressId: 'gown', size: 'M', quantity, revision: 0 });
  const input = { requestId: 'request-a', appointmentId: 'a', pickupDate: '2026-10-16', eventDate: '2026-10-17', returnDate: '2026-10-18',
    gowns: [{ dressId: 'gown', size: 'M' }], depositCents: 10000 };
  async function pay(rental) {
    const path = `sandboxInvoices/${rental.invoiceId}`;
    store.data.set(path, { ...store.data.get(path), billCode: 'bill', reference: 'reference' });
    return payments.applyResult(rental.invoiceId, 'bill', { state: 'SandboxPaid', billCode: 'bill', reference: 'reference',
      amountCents: rental.depositCents, invoiceNo: 'sandbox-receipt', environment: 'sandbox' });
  }
  return { store, rentals, payments, input, pay, advance: ms => { now += ms; } };
}
const fails = code => e => e.code === code;
test('measurements are staff-controlled, versioned, preserved by quantity-only edits and explicitly clearable', async () => {
  const f = await fixture();
  const input = {dressId:'gown',size:'M',quantity:1,revision:1,
    measurements:{bustMin:80,bustMax:90,waistMin:60,waistMax:70,hipMin:90,hipMax:100,lengthCm:150}};
  await assert.rejects(f.rentals.saveVariant('customer',input), fails('STAFF_REQUIRED'));
  await f.rentals.saveVariant('staff',input);
  assert.deepEqual((await f.rentals.variants('customer','gown')).variants.find(v => v.size === 'M').measurements,input.measurements);
  await assert.rejects(f.rentals.saveVariant('staff',input), fails('VARIANT_CHANGED'));
  await f.rentals.saveVariant('staff',{dressId:'gown',size:'M',quantity:2,revision:2});
  assert.deepEqual((await f.rentals.variants('customer','gown')).variants.find(v => v.size === 'M').measurements,input.measurements);
  await f.rentals.saveVariant('staff',{dressId:'gown',size:'M',quantity:2,revision:3,measurements:null});
  assert.equal((await f.rentals.variants('customer','gown')).variants.find(v => v.size === 'M').measurements,null);
  assert.equal((await f.rentals.variants('customer','gown')).variants.find(v => v.size === 'S').quantity,null);
});

test('Malaysia dates include return day and three full cleaning days', () => {
  const result = rentalDates({ pickupDate: '2026-10-16', eventDate: '2026-10-17', returnDate: '2026-10-18' }, Date.parse('2026-10-13Z'));
  assert.equal(result.availableAgain, '2026-10-22');
  assert.equal(result.endDay - result.startDay, 6);
  for (const pickupDate of ['2026-02-30', '2026-10-12', '2026-10-19']) {
    assert.throws(() => rentalDates({ pickupDate, eventDate: '2026-10-17', returnDate: '2026-10-18' }, Date.parse('2026-10-13T02:00:00Z')));
  }
});
test('overlap uses peak concurrent stock, not sum of non-overlapping bookings', () => {
  assert.equal(peakUsage({ a: { state: 'Locked', startDay: 1, endDay: 3, quantity: 1 }, b: { state: 'Locked', startDay: 3, endDay: 5, quantity: 1 } }, 1, 5, 0), 1);
});
test('unconfigured sizes, revoked staff and forged input cannot reserve stock', async () => {
  const f = await fixture();
  await assert.rejects(f.rentals.hold('customer', f.input), fails('STAFF_REQUIRED'));
  await assert.rejects(f.rentals.hold('revoked', f.input), fails('STAFF_REQUIRED'));
  await assert.rejects(f.rentals.hold('staff', { ...f.input, gowns: [{ dressId: 'gown', size: 'S' }] }), fails('INVENTORY_NOT_CONFIGURED'));
  await assert.rejects(f.rentals.hold('staff', { ...f.input, paid: true }), fails('INVALID_RENTAL'));
});
test('concurrent attempts cannot reserve the last variant twice', async () => {
  const f = await fixture();
  const results = await Promise.allSettled([f.rentals.hold('staff', f.input),
    f.rentals.hold('staff', { ...f.input, requestId: 'b', appointmentId: 'b' })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, 'RENTAL_STOCK_UNAVAILABLE');
});
test('idempotent confirmation does not extend the payment deadline', async () => {
  const f = await fixture(), rental = await f.rentals.hold('staff', f.input);
  f.advance(5000);
  assert.equal((await f.rentals.hold('staff', f.input)).expiresAt, rental.expiresAt);
  await assert.rejects(f.rentals.hold('staff', { ...f.input, depositCents: 1 }), fails('INVALID_RENTAL'));
});
test('exactly fifteen minutes releases capacity even before expiration worker runs', async () => {
  const f = await fixture(), rental = await f.rentals.hold('staff', f.input);
  f.advance(HOLD_MS);
  await assert.rejects(f.payments.checkout('customer', rental.invoiceId), fails('RENTAL_HOLD_EXPIRED'));
  const next = await f.rentals.hold('staff', { ...f.input, requestId: 'b', appointmentId: 'b' });
  assert.equal(next.state, 'Held');
  assert.equal(await f.rentals.expire(rental.id), true);
});
test('verified deposit locks inventory and duplicate callbacks are safe', async () => {
  const f = await fixture(), rental = await f.rentals.hold('staff', f.input);
  await f.pay(rental); f.advance(HOLD_MS * 2); await f.pay(rental);
  assert.equal((await f.store.get(`rentals/${rental.id}`)).state, 'Locked');
  assert.equal(await f.rentals.expire(rental.id), false);
  await assert.rejects(f.rentals.hold('staff', { ...f.input, requestId: 'b', appointmentId: 'b' }), fails('RENTAL_STOCK_UNAVAILABLE'));
  await assert.rejects(f.rentals.saveVariant('staff', { dressId: 'gown', size: 'M', quantity: 0, revision: 1 }), fails('QUANTITY_BELOW_RESERVED'));
});
test('late payment is recorded for review and never steals a new hold', async () => {
  const f = await fixture(), first = await f.rentals.hold('staff', f.input);
  f.advance(HOLD_MS);
  const second = await f.rentals.hold('staff', { ...f.input, requestId: 'b', appointmentId: 'b' });
  const invoice = await f.pay(first);
  assert.equal(invoice.state, 'SandboxPaid'); assert.match(invoice.reviewReason, /staff review/);
  assert.equal((await f.store.get(`rentals/${first.id}`)).state, 'PaymentReview');
  assert.equal((await f.store.get(`rentals/${second.id}`)).state, 'Held');
});
test('paid cancellation releases stock but requires refund review, no refund is fabricated', async () => {
  const f = await fixture(), rental = await f.rentals.hold('staff', f.input);
  await f.pay(rental);
  const cancelled = await f.rentals.cancel('staff', rental.id);
  assert.equal(cancelled.refundReviewRequired, true);
  const v = await f.store.get(`rentalVariants/${variantId('gown', 'M')}`);
  assert.equal(v.allocations[rental.id], undefined);
  assert.equal((await f.store.get(`sandboxInvoices/${rental.invoiceId}`)).state, 'SandboxPaid');
});
test('payment after appointment cancellation does not lock the rental', async () => {
  const f = await fixture(), rental = await f.rentals.hold('staff', f.input);
  f.store.data.set('appointments/a', { uid: 'customer', status: 'Cancelled' });
  await f.pay(rental);
  assert.equal((await f.store.get(`rentals/${rental.id}`)).state, 'PaymentReview');
});
