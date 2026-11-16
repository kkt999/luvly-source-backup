import { createHash, randomUUID } from 'node:crypto';
import {hasBoutiqueOperationsAccess} from './appointment_access.mjs';
import { PaymentError } from './toyyibpay.mjs';
import {hasFittingWaiver} from './booking_dates.mjs';
import {resolvePaymentReview,reviewablePayment} from './payment_review.mjs';

export class HttpError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const check = (condition, status, code) => { if (!condition) throw new HttpError(status, code); };
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(id);
const collection = 'sandboxInvoices';
const path = id => `${collection}/${id}`;
const activeStaff = data => data?.active === true && ['staff', 'manager'].includes(data.role);
const quoteId = (bookingId, purpose) => createHash('sha256').update(`${bookingId}:${purpose}`).digest('hex').slice(0, 32);
export function publicInvoice(invoice) {
  const { id, uid, customerName, purpose, title, appointmentId, amountCents, state, environment,
    createdAt, invoiceNo, checkoutUrl, reviewReason, rentalId, packageSelectionId, holdExpiresAt, paymentMethod, paymentChannel, paidAt, paymentPhase, paymentBlocked,extensionId,extensionDetails,reviewResolution } = invoice;
  return { id, uid, customerName, purpose, title, appointmentId, amountCents, state, environment,
    createdAt, ...(invoiceNo ? { invoiceNo } : {}), ...(reviewReason ? { reviewReason } : {}),
    ...(checkoutUrl ? { checkoutUrl } : {}), ...(rentalId ? { rentalId } : {}),...(packageSelectionId?{packageSelectionId}:{}),...(holdExpiresAt?{holdExpiresAt}:{}),
    ...(extensionId?{extensionId,extensionDetails}:{}),...(paymentMethod?{paymentMethod}:{}),...(paymentChannel?{paymentChannel}:{}),
    ...(paidAt?{paidAt}:{}),...(paymentPhase?{paymentPhase}:{}),...(paymentBlocked?{paymentBlocked:true}:{}),
    ...(reviewResolution?{reviewResolution:{state:reviewResolution.state,refundCents:reviewResolution.refundCents,retainedCents:reviewResolution.retainedCents,reference:reviewResolution.reference,recordedAt:reviewResolution.recordedAt}}:{}) };
}

// Store interface: get(path), list(collection, uid?), atomic(async tx => {...}).
// tx.get/tx.set use trusted server access. No client is granted Firestore writes.
export class PaymentService {
  constructor({ store, gateway, returnUrl, callbackUrl, rentals, bookings, now = Date.now }) {
    Object.assign(this, { store, gateway, returnUrl, callbackUrl, rentals, bookings, now });
  }
  async access(uid) {
    check(validId(uid), 401, 'SIGN_IN_REQUIRED');
    const staff = await this.store.get(`staff/${uid}`);
    if (activeStaff(staff)) return { uid, role: staff.role };
    // A revoked/inactive staff account cannot fall back to a bride profile.
    check(!staff && !!await this.store.get(`brides/${uid}`), 403, 'ACCOUNT_ACCESS_REQUIRED');
    return { uid, role: 'bride' };
  }
  async list(uid) {
    const actor = await this.access(uid);
    if (actor.role !== 'bride') {
      check(await hasBoutiqueOperationsAccess(this.store, uid, await this.store.get(`staff/${uid}`)),
        403, 'OPERATIONS_ACCESS_REQUIRED');
    }
    const owner=actor.role==='bride'?uid:undefined;
    const snapshot=this.store.paymentInvoiceSnapshot?await this.store.paymentInvoiceSnapshot(owner):{rows:await this.store.list(collection,owner),limited:false};
    check(!snapshot.limited,409,'PAYMENT_HISTORY_LIMIT');
    const rows = snapshot.rows.filter(row=>owner===undefined||row.uid===owner);
    const appointments=new Map(),rentals=new Map();
    return { invoices: await Promise.all(rows.map(row=>this.present(row,appointments,rentals))), limited:false };
  }
  async present(invoice,appointments=new Map(),rentals=new Map()) {
    const result=publicInvoice(invoice);
    if(validId(invoice.appointmentId)&&!appointments.has(invoice.appointmentId))appointments.set(invoice.appointmentId,this.store.get(`appointments/${invoice.appointmentId}`));
    if(validId(invoice.rentalId)&&!rentals.has(invoice.rentalId))rentals.set(invoice.rentalId,this.store.get(`rentals/${invoice.rentalId}`));
    const booking=await appointments.get(invoice.appointmentId),rentalReview=await rentals.get(invoice.rentalId);
    if(reviewablePayment(invoice,booking,rentalReview,this.now()))result.canResolveReview=true;
    if(validId(invoice.appointmentId)){
      if(!appointments.has(invoice.appointmentId))appointments.set(invoice.appointmentId,this.store.get(`appointments/${invoice.appointmentId}`));
      const b=await appointments.get(invoice.appointmentId),startAt=b?.startAt?.toMillis?.()??+b?.startAt;
      if(b?.uid===invoice.uid&&Number.isSafeInteger(startAt)&&startAt>0&&['Dress Trial','Bridal Consultation'].includes(b.type))
        result.appointmentSummary={startAt,type:b.type,durationMinutes:60};
    }
    if(['PackageBalance','SecurityDeposit'].includes(invoice.purpose)&&validId(invoice.rentalId)){
      if(!rentals.has(invoice.rentalId))rentals.set(invoice.rentalId,this.store.get(`rentals/${invoice.rentalId}`));
      const rental=await rentals.get(invoice.rentalId),day=rental?.pickupDate;
      const binding=invoice.purpose==='PackageBalance'?'balanceInvoiceId':'securityInvoiceId';
      if(rental?.uid===invoice.uid&&rental[binding]===invoice.id&&rental.state==='Locked'&&
        !rental.collectedAt&&!['Collected','Returned'].includes(rental.fulfilment)&&
        typeof day==='string'&&day>='2000-01-01'&&day<='2100-12-31'&&/^\d{4}-\d\d-\d\d$/.test(day)&&Number.isFinite(Date.parse(day+'T00:00:00Z'))&&
        new Date(day+'T00:00:00Z').toISOString().slice(0,10)===day){
        result.paymentDue={kind:'BeforePickup',date:day};
      }
    }
    return result;
  }
  async details(uid,id){return this.present(await this.owned(uid,id));}
  async resolveReview(uid,id,input){return this.present(await resolvePaymentReview(this,uid,id,input));}
  async createQuote(uid, input) {
    check(input && Object.keys(input).every(k => ['appointmentId', 'purpose', 'amountCents'].includes(k)), 400, 'INVALID_QUOTE');
    const { appointmentId, purpose, amountCents } = input;
    check(validId(appointmentId) && ['AppointmentDeposit', 'DressPayment'].includes(purpose), 400, 'INVALID_QUOTE');
    check(Number.isSafeInteger(amountCents) && amountCents >= 100 && amountCents <= 100000000, 400, 'INVALID_AMOUNT');
    const id = quoteId(appointmentId, purpose);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`);
      check(activeStaff(staff) && staff.role === 'manager', 403, 'MANAGER_REQUIRED');
      const booking = await tx.get(`appointments/${appointmentId}`);
      check(booking && booking.status === 'Confirmed', 409, 'CONFIRMED_APPOINTMENT_REQUIRED');
      check(!(booking.feePolicyVersion===1 && purpose==='AppointmentDeposit'),409,'FITTING_FEE_ALREADY_ISSUED');
      check(!await tx.get(`packageAppointments/${appointmentId}`), 409, 'APPOINTMENT_HAS_PACKAGE');
      const bride = await tx.get(`brides/${booking.uid}`);
      check(!!bride, 409, 'CUSTOMER_PROFILE_REQUIRED');
      let title = 'Appointment deposit';
      if (purpose === 'DressPayment') {
        check(validId(booking.dressId), 409, 'APPOINTMENT_DRESS_REQUIRED');
        const dress = await tx.get(`dresses/${booking.dressId}`);
        check(dress?.published === true && dress.availability === 'Available', 409, 'DRESS_UNAVAILABLE');
        title = `Dress payment: ${dress.name}`;
      }
      const existing = await tx.get(path(id));
      if (existing) {
        check(existing.uid === booking.uid && existing.amountCents === amountCents, 409, 'QUOTE_ALREADY_EXISTS');
        return publicInvoice(existing);
      }
      const invoice = { id, uid: booking.uid, customerName: bride.name, purpose, title, appointmentId,
        amountCents, state: 'Quoted', environment: 'sandbox', createdAt: this.now(), createdBy: uid };
      tx.set(path(id), invoice);
      return publicInvoice(invoice);
    });
  }
  async owned(uid, id, { payerOnly = false } = {}) {
    check(validId(id), 400, 'INVALID_INVOICE');
    const actor = await this.access(uid);
    if (!payerOnly && actor.role !== 'bride') {
      check(await hasBoutiqueOperationsAccess(this.store, uid, await this.store.get(`staff/${uid}`)),
        403, 'OPERATIONS_ACCESS_REQUIRED');
    }
    const invoice = await this.store.get(path(id));
    check(invoice && invoice.environment === 'sandbox', 404, 'INVOICE_NOT_FOUND');
    check(payerOnly ? invoice.uid === uid && actor.role === 'bride' : actor.role !== 'bride' || invoice.uid === uid, 403, 'INVOICE_ACCESS_DENIED');
    return invoice;
  }
  async checkout(uid, id, input={}) {
    check(input && Object.keys(input).every(k=>k==='paymentMethod') &&
      (input.paymentMethod===undefined || input.paymentMethod==='FPX'),400,'PAYMENT_METHOD_UNAVAILABLE');
    await this.owned(uid, id, { payerOnly: true });
    const operation = randomUUID();
    const intent = await this.store.atomic(async tx => {
      const invoice = await tx.get(path(id));
      check(invoice?.uid === uid, 403, 'INVOICE_ACCESS_DENIED');
      const staff = await tx.get(`staff/${uid}`);
      check(!staff, 403, 'INVOICE_ACCESS_DENIED');
      const booking = invoice.appointmentId?await tx.get(`appointments/${invoice.appointmentId}`):null;
      check(invoice.purpose==='FittingFee' ? booking?.status==='AwaitingPayment' && booking.paymentExpiresAt>this.now() : invoice.rentalId ? true : booking?.status === 'Confirmed', 409, 'CONFIRMED_APPOINTMENT_REQUIRED');
      if (invoice.rentalId) {
        const rental = await tx.get(`rentals/${invoice.rentalId}`);
        check(hasFittingWaiver(rental)||['Confirmed','Completed'].includes(booking?.status),409,'CONFIRMED_APPOINTMENT_REQUIRED');
        if(invoice.paymentPhase==='Extension'){
          const e=invoice.extensionId?await tx.get(`rentalExtensions/${invoice.extensionId}`):null;
          check(!invoice.paymentBlocked&&rental?.uid===uid&&e?.invoiceId===id&&e.uid===uid&&e.rentalId===rental.id&&e.amountCents===invoice.amountCents&&
            e.state==='AwaitingPayment'&&e.expiresAt>this.now()&&rental.pendingExtension?.id===e.id&&rental.state==='Locked'&&!rental.collectedAt,409,'EXTENSION_EXPIRED');
          check(invoice.extensionAcceptedBy===uid&&Number.isFinite(invoice.extensionAcceptedAt),409,'EXTENSION_CONSENT_REQUIRED');
        }else check(['Balance','Security'].includes(invoice.paymentPhase)
          ? rental?.[invoice.paymentPhase==='Balance'?'balanceInvoiceId':'securityInvoiceId']===id && rental.uid===uid && rental.state==='Locked' && !rental.collectedAt
          : rental?.invoiceId === id && rental.uid === uid && rental.state === 'Held' && rental.expiresAt > this.now(), 409, 'RENTAL_HOLD_EXPIRED');
      }
      check(!['SandboxPaid', 'ReviewRequired'].includes(invoice.state), 409, 'INVOICE_ALREADY_SETTLED_OR_REVIEW');
      if (invoice.billCode && invoice.checkoutUrl) return { invoice };
      check(invoice.state === 'Quoted', 409, 'BILL_CREATION_REQUIRES_REVIEW');
      const bride = await tx.get(`brides/${uid}`);
      check(bride?.name && bride?.phone && bride?.email, 409, 'CUSTOMER_PROFILE_REQUIRED');
      const next = { ...invoice, paymentMethod:'FPX',state: 'Creating', operation, reference: `LV_${id}`, updatedAt: this.now() };
      tx.set(path(id), next);
      return { invoice: next, payer: bride };
    });
    if (!intent.payer) return publicInvoice(intent.invoice);
    let bill;
    try {
      bill = await this.gateway.createBill({ reference: intent.invoice.reference,
        amountCents: intent.invoice.amountCents, name: intent.payer.name,
        email: intent.payer.email, phone: intent.payer.phone.replace(/[\s()-]/g, ''),
        returnUrl: this.returnUrl, callbackUrl: this.callbackUrl,paymentMethod:intent.invoice.paymentMethod });
      if (bill?.reference !== intent.invoice.reference ||
          bill.amountCents !== intent.invoice.amountCents || bill.environment !== 'sandbox') {
        throw new PaymentError('BILL_CREATION_REQUIRES_REVIEW');
      }
    } catch (error) {
      // Never automatically make a second bill after an ambiguous first request.
      // Retain the creation intent for manual reconciliation even for validation errors.
      await this.store.atomic(async tx => {
        const current = await tx.get(path(id));
        if (current?.operation === operation && current.state === 'Creating') {
          tx.set(path(id), { ...current, state: 'ReviewRequired', reviewReason: 'Bill creation needs review', updatedAt: this.now() });
        }
      });
      throw error instanceof PaymentError ? new HttpError(409, error.code) : new HttpError(503, 'BILL_CREATION_REQUIRES_REVIEW');
    }
    return this.store.atomic(async tx => {
      const current = await tx.get(path(id));
      check(current?.operation === operation && current.state === 'Creating', 409, 'BILL_CREATION_REQUIRES_REVIEW');
      const next = { ...current, ...bill, state: 'Unpaid', updatedAt: this.now() };
      tx.set(path(id), next);
      return publicInvoice(next);
    });
  }
  async acceptExtension(uid,id,input){
    check(input&&Object.keys(input).length===1&&input.accepted===true,400,'EXTENSION_CONSENT_REQUIRED');
    await this.owned(uid,id,{payerOnly:true});
    return this.store.atomic(async tx=>{
      const i=await tx.get(path(id)),staff=await tx.get(`staff/${uid}`);
      check(!staff&&i?.uid===uid&&i.purpose==='RentalExtension',403,'INVOICE_ACCESS_DENIED');
      const r=await tx.get(`rentals/${i.rentalId}`),e=await tx.get(`rentalExtensions/${i.extensionId}`);
      check(r?.uid===uid&&r.state==='Locked'&&!r.collectedAt&&r.pendingExtension?.id===e?.id&&e?.invoiceId===id&&e.state==='AwaitingPayment'&&e.expiresAt>this.now()&&!i.paymentBlocked,409,'EXTENSION_EXPIRED');
      tx.set(path(id),{...i,extensionAcceptedBy:uid,extensionAcceptedAt:i.extensionAcceptedAt??this.now()});return {accepted:true};
    });
  }
  async refresh(uid, id) {
    const invoice = await this.owned(uid, id);
    if (!invoice.billCode) return this.present(invoice);
    const result = await this.gateway.reconcile(invoice);
    return this.present(await this.applyResult(id, invoice.billCode, result));
  }
  async callback(body) {
    check(typeof body?.order_id === 'string' && /^LV_[a-f0-9]{32}$/.test(body.order_id), 400, 'INVALID_CALLBACK');
    const id = body.order_id.slice(3);
    const invoice = await this.store.get(path(id));
    check(invoice?.billCode && invoice.environment === 'sandbox', 409, 'BILL_NOT_READY');
    const result = await this.gateway.reconcileCallback(body, invoice);
    await this.applyResult(id, invoice.billCode, result);
  }
  async applyResult(id, billCode, result) {
    return this.store.atomic(async tx => {
      const current = await tx.get(path(id));
      check(current?.billCode === billCode && result.environment === 'sandbox', 409, 'PAYMENT_BINDING_MISMATCH');
      const booking = current.appointmentId?await tx.get(`appointments/${current.appointmentId}`):null;
      if (result.state === 'SandboxPaid') {
        check(result.billCode === billCode && result.reference === current.reference &&
          result.amountCents === current.amountCents && !!result.invoiceNo, 409, 'PAYMENT_BINDING_MISMATCH');
      }
      if (current.state === 'ReviewRequired') return publicInvoice(current);
      if (current.state === 'SandboxPaid' && result.state !== 'ReviewRequired') return publicInvoice(current);
      check(current.purpose!=='FittingFee' || !!this.bookings,503,'BOOKING_SERVICE_REQUIRED');
      const fittingReview=this.bookings ? await this.bookings.settle(tx,current,result,booking) : null;
      const rentalReview = this.rentals ? await this.rentals.settle(tx, current, result, booking) : null;
      check(!current.rentalId || !!this.rentals, 503, 'RENTAL_SERVICE_REQUIRED');
      const reviewReason = fittingReview ?? rentalReview ?? (result.state === 'SandboxPaid' && booking?.status === 'Cancelled'
        ? 'Paid after appointment cancellation; contact manager' : result.state === 'ReviewRequired' ? 'Transaction requires manager review' : undefined);
      const next = { ...current, ...result, updatedAt: this.now(),
        ...(result.state==='SandboxPaid' ? {paidAt:current.paidAt ?? this.now()}:{}),
        ...(reviewReason ? { reviewReason } : {}) };
      tx.set(path(id), next);
      return publicInvoice(next);
    });
  }
}
