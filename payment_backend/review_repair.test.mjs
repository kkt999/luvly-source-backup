import test from 'node:test';
import assert from 'node:assert/strict';
import { repairLegacyFpxB2cReview } from './review_repair.mjs';

const id = 'a'.repeat(32);
function fixture() {
  const data = new Map([
    [`sandboxInvoices/${id}`, { id, uid: 'bride', appointmentId: 'booking',
      reference: `LV_${id}`, billCode: 'sandbox1', amountCents: 10000, updatedAt: 1,
      state: 'ReviewRequired', environment: 'sandbox', reviewReason: 'Transaction requires manager review' }],
    ['appointments/booking', { uid: 'bride', status: 'Confirmed' }],
  ]);
  let writes = 0;
  const store = { get: async path => structuredClone(data.get(path)),
    atomic: async work => work({ get: async path => structuredClone(data.get(path)),
      set: (path, value) => { writes++; data.set(path, structuredClone(value)); } }) };
  const gateway = { createBill: () => assert.fail('repair must never create a bill'),
    reconcile: async invoice => ({ state: 'SandboxPaid', environment: 'sandbox',
      billCode: invoice.billCode, reference: invoice.reference, amountCents: invoice.amountCents,
      invoiceNo: 'TP_TEST', paymentChannel: 'FPX B2C' }) };
  return { data, store, gateway, invoiceId: id, now: () => 123, writes: () => writes };
}
test('dry run verifies existing bill without writes', async () => {
  const f = fixture(); assert.equal((await repairLegacyFpxB2cReview(f)).applied, false);
  assert.equal(f.writes(), 0);
});
test('explicit repair settles one legacy B2C review with audit; no booking change or new bill', async () => {
  const f = fixture(); const booking = structuredClone(f.data.get('appointments/booking'));
  assert.equal((await repairLegacyFpxB2cReview({ ...f, apply: true })).applied, true);
  const saved = f.data.get(`sandboxInvoices/${id}`);
  assert.equal(saved.state, 'SandboxPaid'); assert.equal(saved.invoiceNo, 'TP_TEST');
  assert.equal(saved.reviewReason, undefined); assert.equal(saved.compatibilityRepair.verifiedAt, 123);
  assert.equal(f.writes(), 1); assert.deepEqual(f.data.get('appointments/booking'), booking);
  await assert.rejects(repairLegacyFpxB2cReview({ ...f, apply: true }));
  assert.equal(f.writes(), 1);
});
test('paid after cancellation remains flagged for manager', async () => {
  const f = fixture(); f.data.set('appointments/booking', { uid: 'bride', status: 'Cancelled' });
  await repairLegacyFpxB2cReview({ ...f, apply: true });
  assert.match(f.data.get(`sandboxInvoices/${id}`).reviewReason, /cancellation/);
});
for (const changes of [{ state: 'Pending' }, { environment: 'live' },
  { reviewReason: 'Bill creation needs review' }, { invoiceNo: 'TP_ALREADY' }, { billCode: '' }]) {
  test(`ineligible legacy review never repaired: ${JSON.stringify(changes)}`, async () => {
    const f = fixture(); Object.assign(f.data.get(`sandboxInvoices/${id}`), changes);
    await assert.rejects(repairLegacyFpxB2cReview({ ...f, apply: true })); assert.equal(f.writes(), 0);
  });
}
for (const changes of [{ state: 'ReviewRequired' }, { paymentChannel: 'FPX' },
  { amountCents: 9999 }, { reference: 'other' }, { billCode: 'other' }, { invoiceNo: '' }]) {
  test(`unverified repair cannot write: ${JSON.stringify(changes)}`, async () => {
    const f = fixture(); const original = f.gateway.reconcile;
    f.gateway.reconcile = async i => ({ ...await original(i), ...changes });
    await assert.rejects(repairLegacyFpxB2cReview({ ...f, apply: true })); assert.equal(f.writes(), 0);
  });
}
test('concurrent invoice change aborts repair', async () => {
  const f = fixture(); const original = f.gateway.reconcile;
  f.gateway.reconcile = async i => { f.data.get(`sandboxInvoices/${id}`).updatedAt++; return original(i); };
  await assert.rejects(repairLegacyFpxB2cReview({ ...f, apply: true })); assert.equal(f.writes(), 0);
});
test('wrong appointment owner aborts repair', async () => {
  const f = fixture(); f.data.set('appointments/booking', { uid: 'other', status: 'Confirmed' });
  await assert.rejects(repairLegacyFpxB2cReview({ ...f, apply: true })); assert.equal(f.writes(), 0);
});
