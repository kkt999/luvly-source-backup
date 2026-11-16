import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { ToyyibPaySandbox, verifyCallbackHash, ringgitToCents } from './toyyibpay.mjs';

const secretKey = 'test-only-not-a-real-key';
const expected = { billCode: 'sandbox1', reference: 'LV_TEST_001', amountCents: 1000 };
const input = { ...expected, name: 'Test Bride', email: 'bride@example.com',
  phone: '+60123456789', returnUrl: 'https://payments.example.com/return',
  callbackUrl: 'https://payments.example.com/callback' };
const paid = { billExternalReferenceNo: expected.reference, billpaymentStatus: '1',
  billpaymentAmount: '10.00', billpaymentChannel: 'FPX', billpaymentInvoiceNo: 'TP_TEST_001' };
const response = value => new Response(typeof value === 'string' ? value : JSON.stringify(value));
const make = fetchImpl => new ToyyibPaySandbox({ secretKey, categoryCode: 'w8n5i4lf', fetchImpl });
const errorCode = code => error => error.code === code && !error.message.includes(secretKey);
function signed(changes = {}) {
  const callback = { status: '1', order_id: expected.reference,
    refno: paid.billpaymentInvoiceNo, billcode: expected.billCode, ...changes };
  callback.hash = createHash('md5').update(secretKey + callback.status + callback.order_id + callback.refno + 'ok').digest('hex');
  return callback;
}

test('sandbox-only configuration rejects live and missing secrets', () => {
  assert.throws(() => new ToyyibPaySandbox({ secretKey, categoryCode: 'w8n5i4lf', environment: 'live' }), errorCode('SANDBOX_ONLY'));
  assert.throws(() => new ToyyibPaySandbox({ secretKey: '', categoryCode: 'w8n5i4lf' }), errorCode('MISSING_SECRET_KEY'));
});

test('fixed amount bill targets sandbox and returns only safe checkout fields', async () => {
  const gateway = make(async (url, options) => {
    assert.equal(url, 'https://dev.toyyibpay.com/index.php/api/createBill');
    assert.equal(options.method, 'POST');
    assert.equal(options.redirect, 'error');
    const data = options.body;
    assert.equal(data.get('categoryCode'), 'w8n5i4lf');
    assert.equal(data.get('billAmount'), '1000');
    assert.equal(data.get('billPriceSetting'), '1');
    assert.equal(data.get('billPaymentChannel'), '0');
    assert.equal(data.get('billPhone'), '60123456789');
    assert.equal(data.get('billName'),'Luvly Bridal Boutique');
    assert.doesNotMatch(data.get('billDescription'),/sandbox|university|test|demo/i);
    return response([{ BillCode: 'sandbox1' }]);
  });
  const result = await gateway.createBill(input);
  assert.deepEqual(result, { ...expected, checkoutUrl: 'https://dev.toyyibpay.com/sandbox1', environment: 'sandbox' });
  assert.ok(!JSON.stringify(result).includes(secretKey));
  assert.ok(!Object.hasOwn(result, 'state')); // Bill creation is not payment.
});

for (const [field, value] of [
  ['amountCents', 0], ['amountCents', 99], ['amountCents', 1000.5],
  ['amountCents', '1000'], ['amountCents', 100000001], ['reference', '../other'],
  ['name', ''], ['email', 'broken'], ['phone', 'abc'],
  ['returnUrl', 'http://payments.example.com'], ['callbackUrl', 'https://localhost/callback'],
  ['callbackUrl', 'https://127.0.0.1/callback'], ['callbackUrl', 'https://user:pass@example.com/callback'],
]) {
  test(`invalid ${field} (${value}) cannot contact gateway`, async () => {
    let contacted = false;
    const gateway = make(async () => { contacted = true; return response([]); });
    await assert.rejects(gateway.createBill({ ...input, [field]: value }));
    assert.equal(contacted, false);
  });
}

for (const value of ['[KEY-DID-NOT-EXIST]', '[CATEGORY-NOT-MATCH]',
  { status: 'error', msg: secretKey }, '<html>error</html>', [], [{ BillCode: '../redirect' }]]) {
  test(`HTTP 200 with invalid body is never bill success: ${JSON.stringify(value)}`, async () => {
    await assert.rejects(make(async () => response(value)).createBill(input), error =>
      error.name === 'PaymentError' && !error.message.includes(secretKey));
  });
}

test('ambiguous create failure is surfaced without automatic retry', async () => {
  let count = 0;
  await assert.rejects(make(async () => { count++; throw new Error('timeout ' + secretKey); }).createBill(input), errorCode('BILL_CREATION_UNCERTAIN'));
  assert.equal(count, 1);
});

test('oversized upstream body is rejected', async () => {
  await assert.rejects(make(async () => response('x'.repeat(262145))).createBill(input), errorCode('INVALID_GATEWAY_RESPONSE'));
});

test('RM amount conversion is exact and rejects malformed strings', () => {
  assert.equal(ringgitToCents('10.01'), 1001);
  assert.equal(ringgitToCents('10'), 1000);
  assert.equal(ringgitToCents('10.1'), 1010);
  for (const value of ['0.00', '-1', '1e3', '1.001', 'NaN', 10]) assert.throws(() => ringgitToCents(value));
});

test('valid callback retrieves stored bill and matching success', async () => {
  let count = 0;
  const result = await make(async (url, options) => {
    count++;
    assert.equal(url, 'https://dev.toyyibpay.com/index.php/api/getBillTransactions');
    assert.equal(options.body.get('billCode'), expected.billCode);
    return response([paid]);
  }).reconcileCallback(signed(), expected);
  assert.equal(result.state, 'SandboxPaid');
  assert.equal(result.amountCents, 1000);
  assert.equal(result.invoiceNo, paid.billpaymentInvoiceNo);
  assert.equal(count, 1);
});

test('observed Sandbox FPX B2C transaction passes refresh and signed callback checks', async () => {
  const gateway = make(async () => response([{ ...paid, billpaymentChannel: 'FPX B2C' }]));
  for (const result of [await gateway.reconcile(expected), await gateway.reconcileCallback(signed(), expected)]) {
    assert.equal(result.state, 'SandboxPaid');
    assert.equal(result.paymentChannel, 'FPX B2C');
    assert.equal(result.amountCents, expected.amountCents);
    assert.equal(result.reference, expected.reference);
    assert.equal(result.invoiceNo, paid.billpaymentInvoiceNo);
  }
});

for (const channel of ['FPX B2B', 'FPX B2C fake', 'fpx b2c', 'FPX B2C ', 'DuitNow QR', '0', null]) {
  test(`unknown channel is not accepted as FPX B2C: ${channel}`, async () => {
    assert.equal((await make(async () => response([{ ...paid, billpaymentChannel: channel }])).reconcile(expected)).state, 'ReviewRequired');
  });
}

test('FPX B2C does not bypass amount, reference, invoice or duplicate-payment checks', async () => {
  const b2c = { ...paid, billpaymentChannel: 'FPX B2C' };
  for (const changes of [{ billpaymentAmount: '9.00' }, { billpaymentInvoiceNo: '' }]) {
    assert.equal((await make(async () => response([{ ...b2c, ...changes }])).reconcile(expected)).state, 'ReviewRequired');
  }
  assert.equal((await make(async () => response([{ ...b2c, billExternalReferenceNo: 'other' }])).reconcile(expected)).state, 'Unpaid');
  assert.equal((await make(async () => response([b2c, { ...b2c, billpaymentInvoiceNo: 'TP_SECOND' }])).reconcile(expected)).state, 'ReviewRequired');
});

test('forged hash and return-link parameters never authorize payment', async () => {
  const gateway = make(async () => { assert.fail('must not contact gateway'); });
  await assert.rejects(gateway.reconcileCallback({ ...signed(), hash: '0'.repeat(32) }, expected), errorCode('INVALID_CALLBACK_HASH'));
  await assert.rejects(gateway.reconcileCallback({ status_id: '1', billcode: expected.billCode, order_id: expected.reference }, expected), errorCode('INVALID_CALLBACK_HASH'));
  assert.equal(verifyCallbackHash(secretKey, { ...signed(), status: '3' }), false);
});

test('valid hash cannot be replayed against another stored bill or reference', async () => {
  const gateway = make(async () => { assert.fail('must not contact gateway'); });
  await assert.rejects(gateway.reconcileCallback(signed(), { ...expected, billCode: 'otherbill' }), errorCode('CALLBACK_PAYMENT_MISMATCH'));
  await assert.rejects(gateway.reconcileCallback(signed(), { ...expected, reference: 'otherref' }), errorCode('CALLBACK_PAYMENT_MISMATCH'));
});

for (const changes of [{ billpaymentAmount: '9.00' }, { billpaymentAmount: '1000' },
  { billpaymentAmount: 'NaN' }, { billpaymentInvoiceNo: '' }, { billpaymentChannel: 'Card' }]) {
  test(`mismatched success requires review: ${JSON.stringify(changes)}`, async () => {
    assert.equal((await make(async () => response([{ ...paid, ...changes }])).reconcile(expected)).state, 'ReviewRequired');
  });
}

test('signed callback reference does not substitute for authoritative invoice number', async () => {
  const gateway = make(async () => response([paid]));
  const result = await gateway.reconcileCallback(signed({ refno: 'FPX_REFERENCE' }), expected);
  assert.equal(result.state, 'SandboxPaid');
  assert.equal(result.invoiceNo, paid.billpaymentInvoiceNo);
});

test('another reference, no transactions, pending and failed are not paid', async () => {
  for (const [rows, state] of [
    [[{ ...paid, billExternalReferenceNo: 'someone_else' }], 'Unpaid'],
    [[], 'Unpaid'], [[{ ...paid, billpaymentStatus: '2' }], 'Pending'],
    [[{ ...paid, billpaymentStatus: '4' }], 'Pending'], [[{ ...paid, billpaymentStatus: '3' }], 'Unpaid'],
  ]) assert.equal((await make(async () => response(rows)).reconcile(expected)).state, state);
});

test('multiple successful transactions require overpayment review', async () => {
  assert.equal((await make(async () => response([paid, { ...paid, billpaymentInvoiceNo: 'TP_SECOND' }])).reconcile(expected)).state, 'ReviewRequired');
});

test('late failed callback cannot hide authoritative successful transaction', async () => {
  assert.equal((await make(async () => response([paid])).reconcileCallback(signed({ status: '3' }), expected)).state, 'SandboxPaid');
});
