import test from 'node:test';
import assert from 'node:assert/strict';
import { PaymentService } from './payment_service.mjs';

class MemoryStore {
  constructor() {
    this.data = new Map(Object.entries({
      'staff/manager': { active: true, role: 'manager' },
      'staff/staff': { active: true, role: 'staff' },
      'staffScheduling/staff': { jobRole:'FrontDesk' },
      'staff/revoked': { active: false, role: 'manager' },
      'brides/bride': { name: 'Test Bride', phone: '+60 123456789', email: 'bride@example.com' },
      'brides/other': { name: 'Other Bride', phone: '0123456789', email: 'other@example.com' },
      'brides/revoked': { name: 'Revoked' },
      'appointments/booking': { uid: 'bride', status: 'Confirmed', dressId: 'dress' },
      'dresses/dress': { name: 'Ivory Gown', published: true, availability: 'Available' },
    }));
    this.queue = Promise.resolve();
  }
  async get(path) { return structuredClone(this.data.get(path)); }
  async list(collection, uid) {
    return [...this.data].filter(([key, data]) => key.startsWith(collection + '/') && (uid === undefined || data.uid === uid)).map(([, value]) => structuredClone(value));
  }
  atomic(update) {
    const run = this.queue.then(async () => {
      const writes = new Map();
      const value = await update({ get: path => this.get(path), set: (path, data) => writes.set(path, structuredClone(data)) });
      for (const [path, data] of writes) this.data.set(path, data);
      return value;
    });
    this.queue = run.catch(() => {});
    return run;
  }
}
function fixture() {
  const store = new MemoryStore();
  let bills = 0;
  const gateway = {
    async createBill(input) {
      bills++;
      return { reference: input.reference, amountCents: input.amountCents,
        billCode: 'sandbox1', checkoutUrl: 'https://dev.toyyibpay.com/sandbox1', environment: 'sandbox' };
    },
    async reconcile(invoice) {
      return { state: 'SandboxPaid', environment: 'sandbox', reference: invoice.reference,
        billCode: invoice.billCode, amountCents: invoice.amountCents, invoiceNo: 'TP_TEST' };
    },
    async reconcileCallback(body, invoice) { return this.reconcile(invoice); },
  };
  return { store, gateway, service: new PaymentService({ store, gateway, returnUrl: 'https://test.example/return', callbackUrl: 'https://test.example/callback' }), count: () => bills };
}
const quote = { appointmentId: 'booking', purpose: 'AppointmentDeposit', amountCents: 1000 };
test('pickup payment deadlines are owner-bound, read-only and follow current agreed dates',async()=>{
  const f=fixture(),i=await f.service.createQuote('manager',quote);
  Object.assign(f.store.data.get(`sandboxInvoices/${i.id}`),{purpose:'PackageBalance',rentalId:'rental-one'});
  const rental={uid:'bride',state:'Locked',balanceInvoiceId:i.id,pickupDate:'2026-10-24',notes:'private rental note'};
  f.store.data.set('rentals/rental-one',rental);
  const before=structuredClone(f.store.data);
  assert.deepEqual((await f.service.details('bride',i.id)).paymentDue,{kind:'BeforePickup',date:'2026-10-24'});
  assert.deepEqual((await f.service.list('bride')).invoices[0].paymentDue,{kind:'BeforePickup',date:'2026-10-24'});
  assert.deepEqual((await f.service.refresh('bride',i.id)).paymentDue,{kind:'BeforePickup',date:'2026-10-24'});
  assert.deepEqual(f.store.data,before);
  assert.doesNotMatch(JSON.stringify(await f.service.details('bride',i.id)),/private rental note/);
  rental.pickupDate='2026-10-22';
  assert.equal((await f.service.details('bride',i.id)).paymentDue.date,'2026-10-22');
  await assert.rejects(f.service.details('other',i.id),e=>e.code==='INVOICE_ACCESS_DENIED');
});
test('pickup deadline rejects wrong-owner, wrong-invoice, invalid-date and closed rentals',async()=>{
  const f=fixture(),i=await f.service.createQuote('manager',quote);
  Object.assign(f.store.data.get(`sandboxInvoices/${i.id}`),{purpose:'SecurityDeposit',rentalId:'rental-one'});
  for(const patch of [{uid:'other'},{securityInvoiceId:'wrong'},{pickupDate:'2026-02-30'},{pickupDate:'invalid'},{state:'Cancelled'},{collectedAt:1},{fulfilment:'Returned'}]){
    f.store.data.set('rentals/rental-one',{uid:'bride',state:'Locked',securityInvoiceId:i.id,pickupDate:'2026-10-24',...patch});
    assert.equal((await f.service.details('bride',i.id)).paymentDue,undefined);
  }
  f.store.data.set('rentals/rental-one',{uid:'bride',state:'Locked',securityInvoiceId:i.id,pickupDate:'2026-10-24'});
  assert.equal((await f.service.details('bride',i.id)).paymentDue.date,'2026-10-24');
});
const rejects = code => error => error.code === code;
async function ready(f) { const invoice = await f.service.createQuote('manager', quote); return f.service.checkout('bride', invoice.id); }

test('payment search snapshot includes records beyond the old 100-row list and still isolates the owner',async()=>{
  const f=fixture();let queriedOwner;
  const rows=Array.from({length:101},(_,n)=>({id:n.toString(16).padStart(32,'0'),uid:'bride',title:'Payment',appointmentId:'booking',state:'Quoted',amountCents:100,environment:'sandbox'}));
  f.store.paymentInvoiceSnapshot=async owner=>{queriedOwner=owner;return {rows:[...rows,{...rows[0],uid:'other'}],limited:false};};
  f.store.list=async()=>{throw Error('Old capped list must not be used');};
  const result=await f.service.list('bride');assert.equal(result.invoices.length,101);assert.equal(result.limited,false);assert.equal(queriedOwner,'bride');
  await f.service.list('staff');assert.equal(queriedOwner,undefined);
  queriedOwner='not-read';await assert.rejects(f.service.list('revoked'),rejects('ACCOUNT_ACCESS_REQUIRED'));assert.equal(queriedOwner,'not-read');
});

test('specialists cannot use the payment list, known invoice detail or refresh endpoint', async()=>{
  const f=fixture(), {id}=await f.service.createQuote('manager',quote);
  f.store.data.set('staff/artist',{active:true,role:'staff'});
  f.store.data.set('staffScheduling/artist',{jobRole:'MakeupArtist'});
  f.store.data.get('appointments/booking').assignedStaffId='artist';
  for(const request of [()=>f.service.list('artist'),()=>f.service.details('artist',id),
    ()=>f.service.refresh('artist',id)]) {
    await assert.rejects(request(),rejects('OPERATIONS_ACCESS_REQUIRED'));
  }
  assert.equal((await f.service.details('staff',id)).id,id);
  assert.equal((await f.service.details('bride',id)).id,id);
});
test('oversized payment history cannot return silently incomplete search results',async()=>{
  const f=fixture();f.store.paymentInvoiceSnapshot=async()=>({rows:[],limited:true});
  await assert.rejects(f.service.list('bride'),rejects('PAYMENT_HISTORY_LIMIT'));
});

test('customer invoice details show only an owner-bound appointment summary, with no contacts or raw booking fields',async()=>{
  const f=fixture(),startAt=new Date('2026-10-24T06:00:00Z');
  Object.assign(f.store.data.get('appointments/booking'),{type:'Dress Trial',startAt,phone:'private-phone',notes:'private-note'});
  const invoice=await f.service.createQuote('manager',quote),before=structuredClone(f.store.data);
  const summary={startAt:+startAt,type:'Dress Trial',durationMinutes:60};
  assert.deepEqual((await f.service.details('bride',invoice.id)).appointmentSummary,summary);
  assert.deepEqual((await f.service.list('bride')).invoices[0].appointmentSummary,summary);
  assert.deepEqual((await f.service.refresh('bride',invoice.id)).appointmentSummary,summary);
  assert.deepEqual(f.store.data,before);
  assert.doesNotMatch(JSON.stringify(await f.service.details('bride',invoice.id)),/private-phone|private-note/);
  await assert.rejects(f.service.details('other',invoice.id),rejects('INVOICE_ACCESS_DENIED'));
  f.store.data.get('appointments/booking').uid='other';
  assert.equal((await f.service.details('bride',invoice.id)).appointmentSummary,undefined);
});

test('paid refresh preserves receipt and appointment metadata without inventing absent dates',async()=>{
  const f=fixture();Object.assign(f.store.data.get('appointments/booking'),{type:'Dress Trial',startAt:new Date('2026-10-24T06:00:00Z')});
  const bill=await ready(f),paid=await f.service.refresh('bride',bill.id);
  assert.equal(paid.state,'SandboxPaid');assert.equal(paid.invoiceNo,'TP_TEST');assert.equal(paid.appointmentSummary.durationMinutes,60);
  f.store.data.get('appointments/booking').startAt=null;
  assert.equal((await f.service.details('bride',bill.id)).appointmentSummary,undefined);
});
test('unsupported payment methods cannot create bills; FPX is persisted before gateway creation',async()=>{
 const f=fixture(),invoice=await f.service.createQuote('manager',quote);
 for(const paymentMethod of ['Card','DuitNow','Cash',null])await assert.rejects(f.service.checkout('bride',invoice.id,{paymentMethod}),rejects('PAYMENT_METHOD_UNAVAILABLE'));
 await assert.rejects(f.service.checkout('bride',invoice.id,{paymentMethod:'FPX',amountCents:1}),rejects('PAYMENT_METHOD_UNAVAILABLE'));
 assert.equal(f.count(),0);
 const bill=await f.service.checkout('bride',invoice.id,{paymentMethod:'FPX'});assert.equal(bill.paymentMethod,'FPX');assert.equal(f.count(),1);
 const paid=await f.service.refresh('bride',invoice.id);assert.ok(Number.isSafeInteger(paid.paidAt));
 assert.equal((await f.service.refresh('bride',invoice.id)).paidAt,paid.paidAt);
});

test('a mismatched gateway bill needs review and checkout cannot issue another bill', async () => {
  const f = fixture();
  const invoice = await f.service.createQuote('manager', quote);
  const createBill = f.gateway.createBill;
  f.gateway.createBill = async input => ({
    ...await createBill(input),
    amountCents: input.amountCents + 100,
  });

  await assert.rejects(f.service.checkout('bride', invoice.id), rejects('BILL_CREATION_REQUIRES_REVIEW'));
  const stored = await f.store.get(`sandboxInvoices/${invoice.id}`);
  assert.equal(stored.state, 'ReviewRequired');
  assert.equal(stored.amountCents, invoice.amountCents);
  assert.equal(stored.checkoutUrl, undefined);
  await assert.rejects(f.service.checkout('bride', invoice.id), rejects('INVOICE_ALREADY_SETTLED_OR_REVIEW'));
  assert.equal(f.count(), 1);
});

test('only active manager can issue an invoice; appointment remains unchanged', async () => {
  const f = fixture();
  for (const uid of ['bride', 'other', 'staff', 'revoked']) await assert.rejects(f.service.createQuote(uid, quote), rejects('MANAGER_REQUIRED'));
  const invoice = await f.service.createQuote('manager', quote);
  assert.equal(invoice.state, 'Quoted');
  assert.equal((await f.store.get('appointments/booking')).status, 'Confirmed');
  assert.equal(f.count(), 0);
});
for (const amountCents of [0, 99, 1.2, '1000', 100000001]) {
  test(`invalid invoice amount rejected: ${amountCents}`, async () => {
    await assert.rejects(fixture().service.createQuote('manager', { ...quote, amountCents }), rejects('INVALID_AMOUNT'));
  });
}
test('package invoices and arbitrary quote fields are rejected', async () => {
  await assert.rejects(fixture().service.createQuote('manager', { ...quote, purpose: 'Package' }), rejects('INVALID_QUOTE'));
  await assert.rejects(fixture().service.createQuote('manager', { ...quote, uid: 'other' }), rejects('INVALID_QUOTE'));
});
test('requested or cancelled bookings cannot get a quote', async () => {
  for (const status of ['Requested', 'Cancelled', 'Completed']) {
    const f = fixture(); f.store.data.set('appointments/booking', { uid: 'bride', status });
    await assert.rejects(f.service.createQuote('manager', quote), rejects('CONFIRMED_APPOINTMENT_REQUIRED'));
  }
});
test('dress invoice requires an available published linked dress', async () => {
  const f = fixture();
  const invoice = await f.service.createQuote('manager', { ...quote, purpose: 'DressPayment' });
  assert.equal(invoice.title, 'Dress payment: Ivory Gown');
  f.store.data.set('dresses/dress', { published: false, availability: 'Available' });
  await assert.rejects(f.service.createQuote('manager', { ...quote, purpose: 'DressPayment' }), rejects('DRESS_UNAVAILABLE'));
});
test('repeat manager quote is idempotent; changing money requires review, not overwrite', async () => {
  const f = fixture();
  const first = await f.service.createQuote('manager', quote);
  assert.deepEqual(await f.service.createQuote('manager', quote), first);
  await assert.rejects(f.service.createQuote('manager', { ...quote, amountCents: 2000 }), rejects('QUOTE_ALREADY_EXISTS'));
});
test('bride only sees own invoices, staff can read, inactive staff cannot fall back', async () => {
  const f = fixture(); await f.service.createQuote('manager', quote);
  assert.equal((await f.service.list('bride')).invoices.length, 1);
  assert.equal((await f.service.list('other')).invoices.length, 0);
  assert.equal((await f.service.list('staff')).invoices.length, 1);
  await assert.rejects(f.service.list('revoked'), rejects('ACCOUNT_ACCESS_REQUIRED'));
});
test('other bride, manager and staff cannot pay a bride invoice', async () => {
  const f = fixture(); const invoice = await f.service.createQuote('manager', quote);
  for (const uid of ['other', 'manager', 'staff']) await assert.rejects(f.service.checkout(uid, invoice.id), rejects('INVOICE_ACCESS_DENIED'));
  await assert.rejects(f.service.refresh('other', invoice.id), rejects('INVOICE_ACCESS_DENIED'));
});
test('checkout uses stored quote and profile, not client money', async () => {
  const f = fixture();
  f.gateway.createBill = async input => {
    assert.equal(input.amountCents, 1000); assert.equal(input.email, 'bride@example.com');
    assert.equal(input.phone, '+60123456789');
    return { ...input, billCode: 'sandbox1', checkoutUrl: 'https://dev.toyyibpay.com/sandbox1', environment: 'sandbox' };
  };
  const result = await ready(f);
  assert.equal(result.state, 'Unpaid');
  assert.ok(!Object.hasOwn(result, 'email')); assert.ok(!Object.hasOwn(result, 'phone'));
});
test('two concurrent checkouts create at most one bill; retry reuses saved bill', async () => {
  const f = fixture(); const invoice = await f.service.createQuote('manager', quote);
  const results = await Promise.allSettled([f.service.checkout('bride', invoice.id), f.service.checkout('bride', invoice.id)]);
  assert.ok(results.some(result => result.status === 'fulfilled'));
  assert.equal(f.count(), 1);
  await f.service.checkout('bride', invoice.id); assert.equal(f.count(), 1);
});
test('uncertain gateway failure is retained for review and never auto-retried', async () => {
  const f = fixture(); let count = 0;
  f.gateway.createBill = async () => { count++; throw new Error('timeout'); };
  const invoice = await f.service.createQuote('manager', quote);
  await assert.rejects(f.service.checkout('bride', invoice.id));
  await assert.rejects(f.service.checkout('bride', invoice.id));
  assert.equal(count, 1);
  assert.equal((await f.store.get('sandboxInvoices/' + invoice.id)).state, 'ReviewRequired');
});
test('cancellation prevents a checkout even if a bill already exists', async () => {
  const f = fixture(); const invoice = await ready(f);
  f.store.data.set('appointments/booking', { uid: 'bride', status: 'Cancelled' });
  await assert.rejects(f.service.checkout('bride', invoice.id), rejects('CONFIRMED_APPOINTMENT_REQUIRED'));
});
test('verified success persists once and cannot be downgraded by late pending result', async () => {
  const f = fixture(); const invoice = await ready(f);
  assert.equal((await f.service.refresh('bride', invoice.id)).state, 'SandboxPaid');
  f.gateway.reconcile = async () => ({ state: 'Pending', environment: 'sandbox' });
  assert.equal((await f.service.refresh('bride', invoice.id)).state, 'SandboxPaid');
});
test('mismatched payment amount cannot settle invoice', async () => {
  const f = fixture(); const invoice = await ready(f);
  const old = f.gateway.reconcile;
  f.gateway.reconcile = async i => ({ ...await old(i), amountCents: 2000 });
  await assert.rejects(f.service.refresh('bride', invoice.id), rejects('PAYMENT_BINDING_MISMATCH'));
  assert.equal((await f.store.get('sandboxInvoices/' + invoice.id)).state, 'Unpaid');
});

test('normal refresh does not unlock existing reviews after channel compatibility fix', async () => {
  const f = fixture(); const invoice = await ready(f);
  f.store.data.set('sandboxInvoices/' + invoice.id, { ...await f.store.get('sandboxInvoices/' + invoice.id),
    state: 'ReviewRequired', reviewReason: 'Transaction requires manager review' });
  assert.equal((await f.service.refresh('manager', invoice.id)).state, 'ReviewRequired');
  assert.equal(f.count(), 1);
});
test('duplicate verified callbacks are idempotent and paid cancellation is flagged', async () => {
  const f = fixture(); const invoice = await ready(f);
  f.store.data.set('appointments/booking', { uid: 'bride', status: 'Cancelled' });
  const body = { order_id: `LV_${invoice.id}` };
  await f.service.callback(body); await f.service.callback(body);
  const saved = await f.store.get('sandboxInvoices/' + invoice.id);
  assert.equal(saved.state, 'SandboxPaid'); assert.match(saved.reviewReason, /cancellation/);
});
