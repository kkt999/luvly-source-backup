// Server-only adapter. Not an HTTP server and not an authenticated payment API.
// Sandbox is deliberately hard-coded: enabling live money needs a separate review.
import { createHash, timingSafeEqual } from 'node:crypto';

const BASE = 'https://dev.toyyibpay.com';
const codePattern = /^[A-Za-z0-9]{1,64}$/;
const referencePattern = /^[A-Za-z0-9_-]{1,100}$/;
// Official example uses FPX; the Sandbox transaction API also returns FPX B2C.
// Accept only these exact labels, never arbitrary FPX-prefixed channels.
const fpxChannels = new Set(['FPX', 'FPX B2C']);

export class PaymentError extends Error {
  constructor(code) {
    super(code); // Never include upstream bodies, payer details or secret keys.
    this.name = 'PaymentError';
    this.code = code;
  }
}

function requireValue(condition, code) {
  if (!condition) throw new PaymentError(code);
}

// Amounts returned by getBillTransactions are RM decimal strings, not cents.
export function ringgitToCents(value) {
  requireValue(typeof value === 'string' && /^\d{1,7}(?:\.\d{1,2})?$/.test(value), 'INVALID_AMOUNT');
  const [rm, fraction = ''] = value.split('.');
  const cents = Number(rm) * 100 + Number(fraction.padEnd(2, '0'));
  requireValue(Number.isSafeInteger(cents) && cents > 0, 'INVALID_AMOUNT');
  return cents;
}

export function verifyCallbackHash(secretKey, callback) {
  if (!callback || !['1', '2', '3'].includes(callback.status) ||
      typeof callback.order_id !== 'string' || !referencePattern.test(callback.order_id) ||
      typeof callback.refno !== 'string' || callback.refno.length === 0 || callback.refno.length > 150 ||
      typeof callback.hash !== 'string' || !/^[a-fA-F0-9]{32}$/.test(callback.hash)) return false;
  const expected = createHash('md5')
    .update(secretKey + callback.status + callback.order_id + callback.refno + 'ok')
    .digest();
  return timingSafeEqual(expected, Buffer.from(callback.hash, 'hex'));
}

function publicHttps(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password &&
      !url.hash && url.hostname.includes('.') &&
      !url.hostname.endsWith('.localhost') &&
      !/^([\d.]+|localhost)$/.test(url.hostname);
  } catch { return false; }
}

function validateExpected(expected) {
  requireValue(expected && codePattern.test(expected.billCode ?? '') &&
    referencePattern.test(expected.reference ?? '') &&
    Number.isSafeInteger(expected.amountCents) && expected.amountCents >= 100 &&
    expected.amountCents <= 100000000, 'INVALID_EXPECTED_PAYMENT');
}

export class ToyyibPaySandbox {
  #key;
  #category;
  #fetch;
  constructor({ secretKey, categoryCode, environment = 'sandbox', fetchImpl = globalThis.fetch }) {
    requireValue(environment === 'sandbox', 'SANDBOX_ONLY');
    requireValue(typeof secretKey === 'string' && secretKey.trim().length > 0, 'MISSING_SECRET_KEY');
    requireValue(typeof categoryCode === 'string' && codePattern.test(categoryCode), 'INVALID_CATEGORY');
    this.#key = secretKey.trim();
    this.#category = categoryCode;
    this.#fetch = fetchImpl;
  }

  async #post(operation, values) {
    try {
      const response = await this.#fetch(`${BASE}/index.php/api/${operation}`, {
        method: 'POST', redirect: 'error',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(values),
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw new PaymentError('GATEWAY_UNAVAILABLE');
      // Limit untrusted upstream responses, including chunked response bodies.
      const chunks = [];
      let size = 0;
      for await (const chunk of response.body) {
        size += chunk.byteLength;
        if (size > 262144) throw new PaymentError('INVALID_GATEWAY_RESPONSE');
        chunks.push(Buffer.from(chunk));
      }
      const body = Buffer.concat(chunks).toString('utf8').trim();
      let data;
      try { data = JSON.parse(body); } catch {
        const known = /^\[(KEY-DID-NOT-EXIST|CATEGORY-NOT-MATCH|CATEGORY-IS-INACTIVE|BILL-INFO-NOT-EXIST|INVALID-EMAIL-FORMAT|FALSE)\]$/;
        throw new PaymentError(known.test(body) ? `GATEWAY_${body.slice(1, -1)}` : 'INVALID_GATEWAY_RESPONSE');
      }
      requireValue(Array.isArray(data), 'GATEWAY_REJECTED');
      return data;
    } catch (error) {
      if (error instanceof PaymentError) throw error;
      // Creation may have reached ToyyibPay: never retry createBill automatically.
      throw new PaymentError(operation === 'createBill' ? 'BILL_CREATION_UNCERTAIN' : 'GATEWAY_UNAVAILABLE');
    }
  }

  // The eventual authenticated server must supply a stored quote, not client money.
  // Persist a creation intent BEFORE this call and the returned bill BEFORE redirect.
  async createBill({ reference, amountCents, name, email, phone, returnUrl, callbackUrl,paymentMethod='FPX' }) {
    requireValue(paymentMethod==='FPX','PAYMENT_METHOD_UNAVAILABLE');
    requireValue(typeof reference === 'string' && referencePattern.test(reference), 'INVALID_REFERENCE');
    requireValue(Number.isSafeInteger(amountCents) && amountCents >= 100 && amountCents <= 100000000, 'INVALID_AMOUNT');
    requireValue(typeof name === 'string' && name.trim().length > 0 && name.trim().length <= 100 && !/[\x00-\x1f\x7f]/.test(name), 'INVALID_PAYER_NAME');
    requireValue(typeof email === 'string' && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), 'INVALID_PAYER_EMAIL');
    requireValue(typeof phone === 'string' && /^\+?\d{9,15}$/.test(phone), 'INVALID_PAYER_PHONE');
    requireValue(publicHttps(returnUrl) && publicHttps(callbackUrl), 'PUBLIC_HTTPS_URLS_REQUIRED');
    const result = await this.#post('createBill', {
      userSecretKey: this.#key, categoryCode: this.#category,
      billName: 'Luvly Bridal Boutique', billDescription: 'Luvly bridal services payment',
      billPriceSetting: '1', billPayorInfo: '1', billAmount: String(amountCents),
      billReturnUrl: returnUrl, billCallbackUrl: callbackUrl,
      billExternalReferenceNo: reference, billTo: name.trim(), billEmail: email,
      billPhone: phone.replace(/^\+/, ''), billPaymentChannel: '0',
      billChargeToCustomer: '', billExpiryDays: '1',
    });
    requireValue(result.length === 1 && typeof result[0]?.BillCode === 'string' && codePattern.test(result[0].BillCode), 'BILL_CREATION_UNCERTAIN');
    const billCode = result[0].BillCode;
    return { billCode, checkoutUrl: `${BASE}/${billCode}`, reference, amountCents, environment: 'sandbox' };
  }

  // Query the stored bill, not a bill code supplied by a return-link visitor.
  // Still NOT a receipt or database write: the host must apply this idempotently.
  async reconcile(expected, { invoiceNo } = {}) {
    validateExpected(expected);
    const rows = await this.#post('getBillTransactions', { billCode: expected.billCode });
    const matching = rows.filter(row => row?.billExternalReferenceNo === expected.reference);
    const successful = matching.filter(row => row.billpaymentStatus === '1');
    if (successful.length) {
      // Repeated payment needs human review, not a silently overpaid invoice.
      if (successful.length !== 1) return { state: 'ReviewRequired', environment: 'sandbox' };
      const row = successful[0];
      let amount;
      try { amount = ringgitToCents(row.billpaymentAmount); } catch {
        return { state: 'ReviewRequired', environment: 'sandbox' };
      }
      if (amount !== expected.amountCents || !fpxChannels.has(row.billpaymentChannel) ||
          typeof row.billpaymentInvoiceNo !== 'string' || !/^[A-Za-z0-9_-]{1,150}$/.test(row.billpaymentInvoiceNo) ||
          (invoiceNo !== undefined && row.billpaymentInvoiceNo !== invoiceNo)) {
        return { state: 'ReviewRequired', environment: 'sandbox' };
      }
      return { state: 'SandboxPaid', environment: 'sandbox', amountCents: amount,
        reference: expected.reference, billCode: expected.billCode, invoiceNo: row.billpaymentInvoiceNo,
        paymentChannel: row.billpaymentChannel };
    }
    // A failed attempt doesn't prove the bill can no longer be paid.
    return { state: matching.some(row => ['2', '4'].includes(row.billpaymentStatus)) ? 'Pending' : 'Unpaid', environment: 'sandbox' };
  }

  async reconcileCallback(callback, expected) {
    validateExpected(expected);
    requireValue(verifyCallbackHash(this.#key, callback), 'INVALID_CALLBACK_HASH');
    requireValue(callback.billcode === expected.billCode && callback.order_id === expected.reference, 'CALLBACK_PAYMENT_MISMATCH');
    // Callback amount units are not unambiguously documented. Use the gateway's
    // transaction amount and invoice instead of guessing or trusting return GETs.
    // The docs label refno as a payment reference, not necessarily the invoice
    // number. Verify the signed reference, then independently query the stored
    // bill. Never guess that these two gateway identifiers are interchangeable.
    return this.reconcile(expected);
  }
}
