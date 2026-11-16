import { createHash } from 'node:crypto';
import {preparePromotionPaid} from './promotions.mjs';
import { HttpError } from './payment_service.mjs';
import { hasBoutiqueOperationsAccess } from './appointment_access.mjs';
import { validateMeasurements } from './gown_measurements.mjs';
import {hasFittingWaiver} from './booking_dates.mjs';
import {settleRentalExtension,prepareExtensionClose} from './rental_extensions.mjs';
import {finalFittingComplete} from './final_fitting.mjs';

export const HOLD_MS = 15 * 60 * 1000;
const DAY = 86400000;
const hash = value => createHash('sha256').update(value).digest('hex').slice(0, 32);
const requireValue = (ok, code, status = 400) => { if (!ok) throw new HttpError(status, code); };
const idValid = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(v);
const exact = (v, fields) => v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).every(k => fields.includes(k));
const staffActive = v => v?.active === true && ['staff', 'manager'].includes(v.role);
export const variantId = (dressId, size) => hash(JSON.stringify([dressId, size]));
export const rentalResources = rental => [
  ...(rental.gowns ?? []).map(g => ({path: `rentalVariants/${variantId(g.dressId,g.size)}`, name: `${g.name ?? g.dressId} / ${g.size}`})),
  ...(rental.accessories ?? []).map(a => ({path: `accessoryStock/${a.id}`, name: a.name})),
];

function dateOnly(value) {
  requireValue(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value), 'INVALID_RENTAL_DATE');
  const ms = Date.parse(`${value}T00:00:00Z`);
  requireValue(Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 10) === value, 'INVALID_RENTAL_DATE');
  return ms;
}
export function rentalDates(input, now) {
  const pickup = dateOnly(input.pickupDate), event = dateOnly(input.eventDate), returned = dateOnly(input.returnDate);
  const today = dateOnly(new Date(now + 8 * 3600000).toISOString().slice(0, 10));
  requireValue(pickup >= today && pickup <= event && event <= returned, 'INVALID_RENTAL_DATE_ORDER');
  requireValue(returned - pickup <= 30 * DAY && pickup - today <= 365 * DAY, 'RENTAL_DATE_RANGE');
  // Inclusive return date plus THREE complete cleaning dates. End is exclusive.
  return { startDay: pickup / DAY, endDay: returned / DAY + 4,
    availableAgain: new Date(returned + 4 * DAY).toISOString().slice(0, 10) };
}
export function consumesStock(allocation, now) {
  return allocation.state === 'Locked' || (allocation.state === 'Held' && allocation.expiresAt > now);
}
export function peakUsage(allocations, startDay, endDay, now) {
  const points = [];
  for (const a of Object.values(allocations ?? {})) {
    if (!consumesStock(a, now) || a.startDay >= endDay || a.endDay <= startDay) continue;
    points.push([Math.max(startDay, a.startDay), a.quantity], [Math.min(endDay, a.endDay), -a.quantity]);
  }
  points.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  let used = 0, peak = 0;
  for (const [, delta] of points) { used += delta; peak = Math.max(peak, used); }
  return peak;
}

// Trusted server-only collections. A shared variant document serializes all
// overlapping reservations, including reservations made through different UIs.
export class RentalService {
  constructor({ store, now = Date.now }) { Object.assign(this, { store, now }); }
  async access(uid) {
    requireValue(idValid(uid), 'SIGN_IN_REQUIRED', 401);
    const staff = await this.store.get(`staff/${uid}`);
    if (staffActive(staff)) return 'staff';
    requireValue(!staff && !!await this.store.get(`brides/${uid}`), 'ACCOUNT_ACCESS_REQUIRED', 403);
    return 'bride';
  }
  async list(uid) {
    const role = await this.access(uid);
    if (role === 'staff') {
      requireValue(await hasBoutiqueOperationsAccess(this.store, uid, await this.store.get(`staff/${uid}`)),
        'OPERATIONS_ACCESS_REQUIRED', 403);
    }
    const rows = await this.store.list('rentals', role === 'bride' ? uid : undefined);
    return { serverNow: this.now(), rentals: rows.map(({ fingerprint, ...value }) => ({ ...value,
      state: value.state === 'Held' && value.expiresAt <= this.now() ? 'Expired' : value.state })), limited: rows.length >= 100 };
  }
  async get(uid,id){
    requireValue(idValid(id),'INVALID_RENTAL');
    const role=await this.access(uid);
    if (role === 'staff') {
      requireValue(await hasBoutiqueOperationsAccess(this.store, uid, await this.store.get(`staff/${uid}`)),
        'OPERATIONS_ACCESS_REQUIRED', 403);
    }
    const r=await this.store.get(`rentals/${id}`);
    requireValue(r&&(role==='staff'||r.uid===uid),'RENTAL_NOT_FOUND',404);return r;
  }
  async variants(uid, dressId) {
    const role = await this.access(uid);
    requireValue(idValid(dressId), 'INVALID_VARIANT');
    const dress = await this.store.get(`dresses/${dressId}`);
    requireValue(dress && (role === 'staff' || dress.published === true), 'DRESS_UNAVAILABLE', 404);
    const variants = [];
    for (const size of dress.sizes.split(', ')) {
      const v = await this.store.get(`rentalVariants/${variantId(dressId, size)}`);
      variants.push({ dressId, size, quantity: v?.quantity ?? null, revision: v?.revision ?? 0, measurements: v?.measurements ?? null, measurementSource: v?.measurementSource ?? null });
    }
    return { variants };
  }
  start() {
    let busy = false;
    const tick = async () => {
      if (busy) return; busy = true;
      try {
        for (const id of await this.store.expiredRentalIds(this.now())) await this.expire(id);
        if(this.store.expiredExtensionIds)for(const id of await this.store.expiredExtensionIds(this.now()))await this.expireExtension(id);
        if (this.store.activeRentalIds) for (const id of await this.store.activeRentalIds()) await this.audit(id);
      }
      catch { /* Availability checks still enforce expiry transactionally. */ }
      finally { busy = false; }
    };
    const timer = setInterval(tick, 10000); timer.unref(); void tick();
    return () => clearInterval(timer);
  }
  async saveVariant(uid, input) {
    requireValue(exact(input, ['dressId', 'size', 'quantity', 'revision', 'measurements']) && idValid(input.dressId) &&
      typeof input.size === 'string' && Number.isInteger(input.quantity) && input.quantity >= 0 && input.quantity <= 100 &&
      Number.isInteger(input.revision) && input.revision >= 0, 'INVALID_VARIANT');
    const id = variantId(input.dressId, input.size);
    if (Object.hasOwn(input, 'measurements')) validateMeasurements(input.measurements);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`), dress = await tx.get(`dresses/${input.dressId}`);
      const old = await tx.get(`rentalVariants/${id}`);
      requireValue(staffActive(staff), 'STAFF_REQUIRED', 403);
      requireValue(dress?.sizes?.split(', ').includes(input.size) && input.size !== 'Made to measure', 'INVALID_VARIANT_SIZE');
      requireValue((old?.revision ?? 0) === input.revision, 'VARIANT_CHANGED', 409);
      requireValue(peakUsage(old?.allocations, Math.floor((this.now() + 8 * 3600000) / DAY), Infinity, this.now()) <= input.quantity, 'QUANTITY_BELOW_RESERVED', 409);
      const next = { ...old, ...input, id, revision: input.revision + 1, allocations: old?.allocations ?? {}, updatedBy: uid };
      if (Object.hasOwn(input, 'measurements')) {
        next.measurementSource = input.measurements == null ? null : 'staff-entered';
        next.measurementNote = null;
      }
      tx.set(`rentalVariants/${id}`, next);
      const { allocations, ...publicValue } = next; return publicValue;
    });
  }
  async hold(uid, input) {
    requireValue(exact(input, ['requestId', 'appointmentId', 'pickupDate', 'eventDate', 'returnDate', 'gowns', 'depositCents']) &&
      idValid(input.requestId) && idValid(input.appointmentId) && Number.isSafeInteger(input.depositCents) &&
      input.depositCents >= 100 && input.depositCents <= 100000000, 'INVALID_RENTAL');
    requireValue(Array.isArray(input.gowns) && input.gowns.length >= 1 && input.gowns.length <= 3 && input.gowns.every(g =>
      exact(g, ['dressId', 'size']) && idValid(g.dressId) && typeof g.size === 'string' && g.size.length <= 40) &&
      new Set(input.gowns.map(g => g.dressId)).size === input.gowns.length, 'INVALID_RENTAL_GOWNS');
    const id = hash(`${uid}:${input.requestId}`), invoiceId = hash(`rental:${id}`);
    const fingerprint = JSON.stringify([input.appointmentId, input.pickupDate, input.eventDate, input.returnDate,
      input.depositCents, [...input.gowns].sort((a, b) => a.dressId.localeCompare(b.dressId))]);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`), previous = await tx.get(`rentals/${id}`);
      requireValue(staffActive(staff), 'STAFF_REQUIRED', 403);
      requireValue(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      const booking = await tx.get(`appointments/${input.appointmentId}`);
      if (previous) { requireValue(previous.fingerprint === fingerprint, 'REQUEST_CONFLICT', 409); return previous; }
      const now = this.now(), dates = rentalDates(input, now);
      requireValue(booking && ['Confirmed', 'Completed'].includes(booking.status), 'CONFIRMED_APPOINTMENT_REQUIRED', 409);
      // Package rental/invoicing needs its own entitlement integration. Never
      // silently create a second deposit against an existing package selection.
      requireValue(!await tx.get(`packageAppointments/${input.appointmentId}`), 'PACKAGE_RENTAL_INTEGRATION_REQUIRED', 409);
      const existing = await tx.get(`appointmentRentals/${input.appointmentId}`);
      const priorRental = existing ? await tx.get(`rentals/${existing.rentalId}`) : null;
      requireValue(!priorRental || ['Cancelled', 'Expired'].includes(priorRental.state) ||
        (priorRental.state === 'Held' && priorRental.expiresAt <= now), 'RENTAL_ALREADY_EXISTS', 409);
      const bride = await tx.get(`brides/${booking.uid}`);
      requireValue(!!bride, 'CUSTOMER_PROFILE_REQUIRED', 409);
      const variants = [], selectedGowns = [];
      for (const gown of input.gowns) {
        const dress = await tx.get(`dresses/${gown.dressId}`);
        requireValue(dress?.published === true && dress.availability === 'Available' && dress.sizes.split(', ').includes(gown.size), 'DRESS_UNAVAILABLE', 409);
        selectedGowns.push({ ...gown, name: dress.name ?? gown.dressId });
        const variant = await tx.get(`rentalVariants/${variantId(gown.dressId, gown.size)}`);
        requireValue(variant && variant.quantity > 0, 'INVENTORY_NOT_CONFIGURED', 409);
        requireValue(peakUsage(variant.allocations, dates.startDay, dates.endDay, now) + 1 <= variant.quantity, 'RENTAL_STOCK_UNAVAILABLE', 409);
        variants.push(variant);
      }
      const rental = { id, uid: booking.uid, appointmentId: input.appointmentId, invoiceId, fingerprint,
        gowns: selectedGowns, pickupDate: input.pickupDate, eventDate: input.eventDate, returnDate: input.returnDate,
        ...dates, depositCents: input.depositCents, state: 'Held', createdBy: uid, createdAt: now, expiresAt: now + HOLD_MS };
      for (const v of variants) {
        const allocations = Object.fromEntries(Object.entries(v.allocations).filter(([, a]) => consumesStock(a, now) && a.endDay > Math.floor((now + 8 * 3600000) / DAY)));
        requireValue(Object.keys(allocations).length < 1000, 'INVENTORY_REVIEW_REQUIRED', 409);
        allocations[id] = { ...dates, quantity: 1, state: 'Held', expiresAt: rental.expiresAt };
        tx.set(`rentalVariants/${v.id}`, { ...v, allocations });
      }
      tx.set(`rentals/${id}`, rental);
      tx.set(`appointmentRentals/${input.appointmentId}`, { rentalId: id });
      tx.set(`sandboxInvoices/${invoiceId}`, { id: invoiceId, uid: booking.uid, customerName: bride.name,
        appointmentId: input.appointmentId, rentalId: id, purpose: 'BookingDeposit', title: 'Gown booking deposit',
        amountCents: input.depositCents, state: 'Quoted', environment: 'sandbox', holdExpiresAt: rental.expiresAt, createdAt: now, createdBy: uid });
      return rental;
    });
  }
  async expire(id) {
    requireValue(idValid(id), 'INVALID_RENTAL');
    return this.store.atomic(async tx => {
      const rental = await tx.get(`rentals/${id}`);
      if (rental?.state === 'Held' && rental.expiresAt <= this.now()) {
        const credit=rental.fittingCreditId ? await tx.get(`fittingCredits/${rental.fittingCreditId}`) : null;
        const resources = [];
        for (const r of rentalResources(rental)) resources.push({...r,v:await tx.get(r.path)});
        for (const {path,v} of resources) if (v?.allocations?.[id]) {
          const allocations={...v.allocations};delete allocations[id];tx.set(path,{...v,allocations});
        }
        tx.set(`rentals/${id}`, { ...rental, state: 'Expired', updatedAt: this.now() });
        if(credit?.reservedBy===id && !credit.consumedBy)tx.set(`fittingCredits/${rental.fittingCreditId}`,{...credit,reservedBy:null,reservedUntil:0});
        return true;
      }
      return false;
    });
  }
  async audit(id) {
    const rental=await this.store.get(`rentals/${id}`);
    if (!rental || !['Held','Locked'].includes(rental.state)) return;
    const booking=rental.appointmentId?await this.store.get(`appointments/${rental.appointmentId}`):null;
    if (['Cancelled','Declined'].includes(booking?.status)) await this.cancel(null,id,true);
  }
  async expireExtension(id){
    return this.store.atomic(async tx=>{
      const e=await tx.get(`rentalExtensions/${id}`);
      if(!e||e.state!=='AwaitingPayment'||e.expiresAt>this.now())return false;
      const r=await tx.get(`rentals/${e.rentalId}`);if(!r)return false;
      const close=await prepareExtensionClose(tx,r,e,'Expired',this.now());close();return true;
    });
  }
  async cancel(uid, id, automatic = false) {
    requireValue(idValid(id), 'INVALID_RENTAL');
    return this.store.atomic(async tx => {
      const staff = uid ? await tx.get(`staff/${uid}`) : null, rental = await tx.get(`rentals/${id}`);
      requireValue(automatic || staffActive(staff), 'STAFF_REQUIRED', 403);
      requireValue(automatic || await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      requireValue(!!rental, 'RENTAL_NOT_FOUND', 404);
      requireValue(!(rental.pendingExtension?.expiresAt>this.now()),'EXTENSION_PENDING',409);
      if (automatic) {
        const booking=rental.appointmentId?await tx.get(`appointments/${rental.appointmentId}`):null;
        if (!['Cancelled','Declined'].includes(booking?.status)) return rental;
      }
      if (rental.state === 'Cancelled') return rental;
      requireValue(!rental.collectedAt,'RETURN_INSPECTION_REQUIRED',409);
      const credit=rental.fittingCreditId ? await tx.get(`fittingCredits/${rental.fittingCreditId}`) : null;
      const invoices=[];
      for(const invoiceId of new Set([rental.invoiceId,rental.balanceInvoiceId,rental.securityInvoiceId,...(rental.extensionInvoiceIds??[])].filter(Boolean))) {
        const invoice=await tx.get(`sandboxInvoices/${invoiceId}`);if(invoice)invoices.push({invoiceId,invoice});
      }
      const variants = [];
      for (const r of rentalResources(rental)) {
        const v = await tx.get(r.path);
        if (v?.allocations?.[id]) variants.push({...v,resourcePath:r.path});
      }
      for (const v of variants) {
        const allocations = { ...v.allocations }; delete allocations[id];
        const {resourcePath,...record}=v;
        tx.set(resourcePath, { ...record, allocations });
      }
      const next = { ...rental, state: 'Cancelled', cancelledBy: uid ?? 'appointment-cancellation', updatedAt: this.now(),
        refundReviewRequired: rental.refundReviewRequired === true || ['Locked', 'PaymentReview'].includes(rental.state) };
      tx.set(`rentals/${id}`, next);
      for(const {invoiceId,invoice} of invoices)tx.set(`sandboxInvoices/${invoiceId}`,{...invoice,paymentBlocked:true,
        ...(invoice.state==='SandboxPaid'&&!invoice.reviewResolution?{reviewReason:invoice.reviewReason??'Rental cancelled; manager review of paid amount required'}:{})});
      if(credit?.reservedBy===id && !credit.consumedBy)tx.set(`fittingCredits/${rental.fittingCreditId}`,{...credit,reservedBy:null,reservedUntil:0});
      return next;
    });
  }
  // Called ONLY inside verified payment reconciliation, before invoice writes.
  async settle(tx, invoice, result, booking) {
    if (!invoice.rentalId || result.state !== 'SandboxPaid') return null;
    const rental = await tx.get(`rentals/${invoice.rentalId}`);
    if(invoice.paymentPhase==='Extension')return settleRentalExtension(tx,invoice,result,booking,rental,this.now());
    if(invoice.paymentPhase==='Security') {
      requireValue(rental?.securityInvoiceId===invoice.id && rental.uid===invoice.uid && rental.securityCents===result.amountCents,'RENTAL_PAYMENT_BINDING',409);
      if(rental.state!=='Locked'){tx.set(`rentals/${rental.id}`,{...rental,refundReviewRequired:true});return 'Security deposit paid after rental cancellation; staff refund review required';}
      tx.set(`rentals/${rental.id}`,{...rental,securityState:'Paid',updatedAt:this.now()});return null;
    }
    if(invoice.paymentPhase==='Balance') {
      requireValue(rental?.balanceInvoiceId===invoice.id && rental.uid===invoice.uid && rental.balanceCents===result.amountCents,'RENTAL_PAYMENT_BINDING',409);
      if(rental.state!=='Locked' || !(hasFittingWaiver(rental)||['Confirmed','Completed'].includes(booking?.status))){tx.set(`rentals/${rental.id}`,{...rental,refundReviewRequired:true});return 'Balance paid after rental cancellation; staff review required';}
      tx.set(`rentals/${rental.id}`,{...rental,paymentState:'Paid',updatedAt:this.now()});
      return null;
    }
    requireValue(rental?.invoiceId === invoice.id && rental.uid === invoice.uid && rental.depositCents === result.amountCents, 'RENTAL_PAYMENT_BINDING', 409);
    if (rental.state === 'Locked') return null;
    const now = this.now();
    if (rental.state !== 'Held' || rental.expiresAt <= now || !(hasFittingWaiver(rental)||['Confirmed', 'Completed'].includes(booking?.status))) {
      tx.set(`rentals/${rental.id}`, { ...rental, state: 'PaymentReview', reviewReason: 'Payment verified after hold ended', updatedAt: now });
      return 'Payment verified after rental hold ended; staff review required';
    }
    const variants = [];
    for (const r of rentalResources(rental)) {
      const v = await tx.get(r.path);
      requireValue(v?.allocations?.[rental.id]?.state === 'Held', 'RENTAL_ALLOCATION_MISSING', 409);
      variants.push({...v,resourcePath:r.path});
    }
    const selection=rental.packageSelectionId ? await tx.get(`packageSelections/${rental.packageSelectionId}`) : null;
    const credit=rental.fittingCreditId ? await tx.get(`fittingCredits/${rental.fittingCreditId}`) : null;
    const promotionPaid=await preparePromotionPaid(tx,rental,now);
    if(!promotionPaid.ok){
      tx.set(`rentals/${rental.id}`,{...rental,state:'PaymentReview',reviewReason:'Promotion requires review',updatedAt:now});
      return 'Promotion could not be applied; staff review required';
    }
    if(rental.fittingCreditCents>0 && (credit?.reservedBy!==rental.id || credit.consumedBy || credit.amountCents!==rental.fittingCreditCents)) {
      tx.set(`rentals/${rental.id}`,{...rental,state:'PaymentReview',reviewReason:'Fitting credit requires review',updatedAt:now});
      return 'Fitting credit could not be applied; staff review required';
    }
    const balanceInvoiceId=rental.balanceCents>0 ? hash(`balance:${rental.id}`) : null;
    const securityInvoiceId=rental.securityCents>0 ? hash(`security:${rental.id}`) : null;
    promotionPaid.commit();
    for (const {resourcePath,...v} of variants) tx.set(resourcePath, { ...v, allocations: { ...v.allocations,
      [rental.id]: { ...v.allocations[rental.id], state: 'Locked' } } });
    if(credit)tx.set(`fittingCredits/${rental.fittingCreditId}`,{...credit,consumedBy:rental.id,consumedAt:now});
    tx.set(`rentals/${rental.id}`, { ...rental, state: 'Locked', ...(selection ? {balanceInvoiceId,securityInvoiceId,securityState:securityInvoiceId?'AwaitingPayment':'NotRequired',paymentState:balanceInvoiceId?'DepositPaid':'Paid'} : {}), updatedAt: now });
    if (selection) {
      if (balanceInvoiceId) tx.set(`sandboxInvoices/${balanceInvoiceId}`,{id:balanceInvoiceId,uid:rental.uid,customerName:selection.customerName,
        appointmentId:rental.appointmentId,rentalId:rental.id,packageSelectionId:rental.packageSelectionId,paymentPhase:'Balance',
        purpose:'PackageBalance',title:`Remaining balance: ${selection.name}`,amountCents:rental.balanceCents,state:'Quoted',environment:'sandbox',createdAt:now});
      if(securityInvoiceId)tx.set(`sandboxInvoices/${securityInvoiceId}`,{id:securityInvoiceId,uid:rental.uid,customerName:selection.customerName,
        appointmentId:rental.appointmentId,rentalId:rental.id,packageSelectionId:rental.packageSelectionId,paymentPhase:'Security',purpose:'SecurityDeposit',
        title:`Refundable gown security deposit: ${selection.name}`,amountCents:rental.securityCents,state:'Quoted',environment:'sandbox',createdAt:now});
      tx.set(`packageSelections/${rental.packageSelectionId}`,{...selection,balanceInvoiceId});
    }
    return null;
  }
  async fulfil(uid,id,input) {
    requireValue(idValid(id) && exact(input,['action','damageCents','lateCents','reason','allReturned','reference']) &&
      ['collect','return','record-refund','report-return-issue'].includes(input.action),'INVALID_FULFILMENT');
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),r=await tx.get(`rentals/${id}`);
      requireValue(staffActive(staff),'STAFF_REQUIRED',403);
      requireValue(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      requireValue(r?.policyVersion===1 && r.state==='Locked','ACTIVE_POLICY_RENTAL_REQUIRED',409);
      const rows=[];for(const resource of rentalResources(r))rows.push({...resource,v:await tx.get(resource.path)});
      const now=this.now(),today=Math.floor((now+8*3600000)/DAY);
      let next={...r,updatedAt:now};
      if(input.action==='collect'){
        requireValue(Object.keys(input).length===1,'INVALID_FULFILMENT');
        if(r.collectedAt)return r;
        requireValue(!(r.pendingExtension?.expiresAt>now),'EXTENSION_PENDING',409);
        requireValue(today===r.startDay,'PICKUP_DATE_REQUIRED',409);
        const balance=r.balanceInvoiceId?await tx.get(`sandboxInvoices/${r.balanceInvoiceId}`):null;
        const security=r.securityInvoiceId?await tx.get(`sandboxInvoices/${r.securityInvoiceId}`):null;
        const deposit=await tx.get(`sandboxInvoices/${r.invoiceId}`);
        const credit=r.fittingCreditId?await tx.get(`fittingCredits/${r.fittingCreditId}`):null;
        const fitting=credit?await tx.get(`sandboxInvoices/${credit.invoiceId}`):null;
        const progress=await tx.get(`rentalServiceProgress/${r.packageSelectionId}`);
        if(r.fittingAdjustmentsRequired){
          requireValue(progress?.rentalId===r.id&&progress.alteration==='Completed','FITTING_ADJUSTMENTS_PENDING',409);
        }
        requireValue(finalFittingComplete(r,progress),'FINAL_FITTING_PENDING',409);
        requireValue(deposit?.state==='SandboxPaid' && !deposit.reviewReason &&
          (!r.fittingCreditCents || fitting?.state==='SandboxPaid' && !fitting.reviewReason && credit.consumedBy===id) &&
          (!r.balanceCents || balance?.state==='SandboxPaid' && !balance.reviewReason) &&
          (!r.securityCents || security?.state==='SandboxPaid' && !security.reviewReason),'PICKUP_PAYMENT_REQUIRED',409);
        for(const {v} of rows)requireValue(v && peakUsage(v.allocations,today,today+1,now)<=v.quantity &&
          Object.keys(v.outstanding ?? {}).filter(k=>k!==id).length<v.quantity,'UNRETURNED_ITEMS_REVIEW_REQUIRED',409);
        for(const {path,v} of rows)tx.set(path,{...v,outstanding:{...v.outstanding,[id]:true}});
        next={...next,collectedAt:now,collectedBy:uid,fulfilment:'Collected'};
      }else if(input.action==='report-return-issue'){
        requireValue(r.collectedAt&&!r.returnedAt&&Object.keys(input).length===2&&typeof input.reason==='string'&&
          input.reason.trim().length>=10&&input.reason.length<=1000,'INVALID_RETURN_ISSUE',409);
        if(r.returnIssue?.state==='Open'&&r.returnIssue.note===input.reason.trim())return r;
        next={...next,returnIssue:{state:'Open',note:input.reason.trim(),by:uid,at:now},
          returnIssueHistory:[...(r.returnIssueHistory??[]),...(r.returnIssue?[r.returnIssue]:[])].slice(-20)};
      }else if(input.action==='return'){
        requireValue(r.collectedAt,'COLLECTED_RENTAL_REQUIRED',409);
        requireValue(input.allReturned===true && Number.isSafeInteger(input.damageCents) && input.damageCents>=0 &&
          Number.isSafeInteger(input.lateCents) && input.lateCents>=0 && typeof input.reason==='string' && input.reason.length<=1000 &&
          input.damageCents+input.lateCents<=r.securityCents && (!input.damageCents && !input.lateCents || input.reason.trim().length>=5),'INVALID_INSPECTION');
        if(r.returnedAt){requireValue(r.damageCents===input.damageCents && r.lateCents===input.lateCents && r.inspectionNote===input.reason.trim(),'INSPECTION_ALREADY_RECORDED',409);return r;}
        for(const {path,v} of rows){
          requireValue(!!v,'INVENTORY_REVIEW_REQUIRED',409);
          const outstanding={...v.outstanding};delete outstanding[id];
          const allocation=v.allocations?.[id];
          requireValue(!!allocation,'INVENTORY_REVIEW_REQUIRED',409);
          tx.set(path,{...v,outstanding,allocations:{...v.allocations,[id]:{...allocation,endDay:Math.max(allocation.endDay,today+4)}}});
        }
        next={...next,returnedAt:now,inspectedBy:uid,fulfilment:'Returned',damageCents:input.damageCents,lateCents:input.lateCents,
          inspectionNote:input.reason.trim(),refundDueCents:r.securityCents-input.damageCents-input.lateCents,
          securityState:r.securityCents-input.damageCents-input.lateCents>0?'RefundDue':'Deducted',refundReviewRequired:false,
          ...(r.returnIssue?{returnIssue:{...r.returnIssue,state:'ClosedAfterInspection',closedBy:uid,closedAt:now}}:{})};
      }else{
        requireValue(staff.role==='manager','MANAGER_REQUIRED',403);
        requireValue(r.returnedAt && r.refundDueCents>0,'REFUND_NOT_DUE',409);
        requireValue(typeof input.reference==='string' && input.reference.trim().length>=5 && input.reference.length<=100,'REFUND_REFERENCE_REQUIRED');
        if(r.securityState==='RefundRecorded'){requireValue(r.refundReference===input.reference.trim(),'REFUND_ALREADY_RECORDED',409);return r;}
        requireValue(r.securityState==='RefundDue','REFUND_REVIEW_REQUIRED',409);
        next={...next,securityState:'RefundRecorded',refundReference:input.reference.trim(),refundRecordedBy:uid,refundRecordedAt:now,
          refundEnvironment:'sandbox-record-only'};
      }
      tx.set(`rentals/${id}`,next);return next;
    });
  }
}
