import { priceAccessories, accessoryCatalogue } from './accessory_catalogue.mjs';
import {fittingBeforeRental,fittingFitsRental,effectiveVisitTime,malaysiaDay} from './booking_dates.mjs';
import {packageDates} from './package_rentals.mjs';
import {stockStatus,requireSelectedAvailability} from './rental_availability.mjs';
import {variantId} from './rental_service.mjs';
import {BookingService} from './booking_service.mjs';
import {hasBoutiqueOperationsAccess,hasPackageFittingAccess,isAssignedFitting} from './appointment_access.mjs';
import { createHash } from 'node:crypto';
import { HttpError, publicInvoice } from './payment_service.mjs';
import {promotionQuote} from './promotions.mjs';
import {fittingPresentation} from './fitting_proposals.mjs';
import {finalFittingComplete} from './final_fitting.mjs';
import {FITTING_FEE} from './bridal_payment_policy.mjs';
import {packageServiceTypes,requiresServiceTiming,requiresAccessorySelection,addsRentalDay} from './package_service_types.mjs';
import {MAX_PACKAGE_GOWNS, rentableSizes, packageGownRows, countStockedGowns} from './package_gown_catalogue.mjs';

const ensure = (ok, code, status = 400) => { if (!ok) throw new HttpError(status, code); };
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(value);
const amount = value => Number.isSafeInteger(value) && value >= 0 && value <= 100000000;
const text = (value, min, max) => typeof value === 'string' && value === value.trim() &&
  value.length >= min && value.length <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value);
const keys = (value, allowed) => value && !Array.isArray(value) && typeof value === 'object' && Object.keys(value).every(k => allowed.includes(k));
const hash = value => createHash('sha256').update(value).digest('hex').slice(0, 32);
const activeStaff = value => value?.active === true && ['staff', 'manager'].includes(value.role);

function canUseCompletedFitting(selection) {
  return !!selection.rentalPlan&&selection.selectedGowns?.length>0&&!selection.invoiceId&&!selection.rentalId&&
    !selection.fittingDecision&&!selection.reusedFittingAppointmentId;
}

function fittingBlocksLink(visit, now) {
  return ['Requested','Confirmed'].includes(visit?.status)||
    visit?.status==='AwaitingPayment'&&visit.paymentExpiresAt>now||
    visit?.type==='Dress Trial'&&visit.status==='Completed';
}

async function unusedFittingCredit(reader, uid, appointmentId, visit, plan, now) {
  if(visit?.uid!==uid||visit.type!=='Dress Trial'||visit.status!=='Completed'||!visit.actualAttendedAt||
      visit.feeIncluded===true||visit.refundReviewRequired||!validId(visit.fittingInvoiceId)||
      !fittingFitsRental(visit,plan,now))return false;
  const [credit, fee]=await Promise.all([
    reader.get(`fittingCredits/${appointmentId}`),
    reader.get(`sandboxInvoices/${visit.fittingInvoiceId}`),
  ]);
  return credit?.uid===uid&&credit.invoiceId===visit.fittingInvoiceId&&credit.amountCents===FITTING_FEE&&
    !credit.consumedBy&&!credit.voidedAt&&(!credit.reservedBy||credit.reservedUntil<=now)&&
    fee?.uid===uid&&fee.appointmentId===appointmentId&&fee.amountCents===FITTING_FEE&&fee.purpose==='FittingFee'&&
    fee.environment==='sandbox'&&fee.state==='SandboxPaid'&&!fee.reviewReason&&typeof fee.invoiceNo==='string'&&!!fee.invoiceNo.trim();
}

export function validatePackage(input) {
  ensure(keys(input, ['id', 'revision', 'name', 'description', 'basePriceCents', 'services', 'active', 'includedGownCount', 'eligibleDressIds', 'allCatalogueGowns']), 'INVALID_PACKAGE');
  const count = input.includedGownCount ?? 0, eligible = input.eligibleDressIds ?? [];
  ensure(Number.isInteger(count) && count >= 0 && count <= MAX_PACKAGE_GOWNS && Array.isArray(eligible) && eligible.length <= 100 &&
    eligible.every(validId) && new Set(eligible).size === eligible.length &&
    (input.allCatalogueGowns === undefined || (input.allCatalogueGowns === true && eligible.length === 0)) &&
    (count > 0 || eligible.length === 0), 'INVALID_PACKAGE_GOWNS');
  ensure(validId(input.id) && Number.isInteger(input.revision) && input.revision >= 0, 'INVALID_PACKAGE');
  ensure(text(input.name, 3, 100) && /\p{L}/u.test(input.name) && text(input.description, 10, 1500), 'INVALID_PACKAGE_TEXT');
  ensure(amount(input.basePriceCents) && input.basePriceCents >= 100 && typeof input.active === 'boolean', 'INVALID_PACKAGE_PRICE');
  ensure(Array.isArray(input.services) && input.services.length > 0 && input.services.length <= 12, 'INVALID_PACKAGE_SERVICES');
  const ids = new Set(), names = new Set();
  let removable = 0;
  for (const s of input.services) {
    ensure(keys(s, ['id', 'name', 'description', 'kind', 'priceCents', 'serviceType', 'accessoryAllowanceCents']) && validId(s.id) && text(s.name, 2, 100) &&
      text(s.description, 0, 300) && ['Required', 'Optional', 'Add-on'].includes(s.kind) && amount(s.priceCents), 'INVALID_PACKAGE_SERVICES');
    ensure(s.serviceType === undefined || packageServiceTypes.has(s.serviceType), 'INVALID_PACKAGE_SERVICES');
    if (s.serviceType !== undefined && requiresAccessorySelection(s)) {
      ensure(amount(s.accessoryAllowanceCents), 'INVALID_PACKAGE_ACCESSORY_ALLOWANCE');
    } else {
      ensure(s.accessoryAllowanceCents === undefined, 'INVALID_PACKAGE_ACCESSORY_ALLOWANCE');
    }
    ensure(!ids.has(s.id) && !names.has(s.name.toLowerCase()), 'DUPLICATE_SERVICE');
    ids.add(s.id); names.add(s.name.toLowerCase());
    if (s.kind === 'Required') ensure(s.priceCents === 0, 'INVALID_PACKAGE_PRICE');
    if (s.kind === 'Optional') removable += s.priceCents;
  }
  ensure(input.services.some(s => s.kind === 'Required'), 'REQUIRED_SERVICE_NEEDED');
  const minimum = input.active && count > 0 ? 200 : 100;
  ensure(input.basePriceCents - removable >= minimum, 'INVALID_PACKAGE_PRICE');
  ensure(input.basePriceCents + input.services.filter(s => s.kind === 'Add-on').reduce((n, s) => n + s.priceCents, 0) <= 100000000, 'PACKAGE_PRICE_LIMIT');
  if (input.active && count === 0) {
    ensure(!input.services.some(s => s.serviceType !== undefined &&
      (requiresServiceTiming(s) || requiresAccessorySelection(s) || addsRentalDay(s))), 'PACKAGE_LINKED_GOWN_REQUIRED');
  }
  return input;
}

export function priceSelection(packageData, removedIds, addonIds) {
  ensure(Array.isArray(removedIds) && Array.isArray(addonIds) && removedIds.length <= 12 && addonIds.length <= 12, 'INVALID_SELECTION');
  ensure(new Set(removedIds).size === removedIds.length && new Set(addonIds).size === addonIds.length, 'DUPLICATE_SERVICE');
  ensure(removedIds.every(id => packageData.services.some(s => s.id === id && s.kind === 'Optional')), 'MANDATORY_SERVICE');
  ensure(addonIds.every(id => packageData.services.some(s => s.id === id && s.kind === 'Add-on')), 'INVALID_ADDON');
  const services = packageData.services.filter(s => s.kind === 'Add-on' ? addonIds.includes(s.id) : !removedIds.includes(s.id));
  const totalCents = packageData.basePriceCents - packageData.services.filter(s => removedIds.includes(s.id)).reduce((n, s) => n + s.priceCents, 0) +
    packageData.services.filter(s => addonIds.includes(s.id)).reduce((n, s) => n + s.priceCents, 0);
  ensure(amount(totalCents) && totalCents >= 100, 'INVALID_PACKAGE_PRICE');
  return { services, totalCents };
}

// Package collections stay closed to direct client writes. Every request uses a
// verified Firebase identity and trusted transactions, like the payment API.
export class PackageService {
  constructor({ store, paymentService, now = Date.now, bookings }) { Object.assign(this, { store, paymentService, now }); this.bookings=bookings ?? new BookingService({store,now}); }
  async gowns(uid) {
    await this.paymentService.access(uid);
    const rows = await this.store.listDresses();
    return { dresses: rows.filter(d => d.published === true && d.availability === 'Available').map(d => ({
      id: d.id, name: d.name, category: d.category, description: d.description, colour: d.colour, sizes: d.sizes,
      productDetails: d.productDetails ?? {},
      priceCents: d.priceCents, imageUrl: d.imageUrl ?? '', photoRevision: d.photoRevision ?? 0,
      availability: d.availability, published: true, revision: d.revision, arModelId: d.arModelId ?? '',
    })), limited: rows.length >= 100 };
  }
  async catalogue(uid, supportsServiceTypes = false) {
    const actor = await this.paymentService.access(uid);
    const rows = await this.store.list('servicePackages');
    const packages = rows.filter(p => actor.role !== 'bride' ||
      (p.active && (supportsServiceTypes || !(p.services ?? []).some(s => s.serviceType !== undefined))))
      .sort((a, b) => a.name.localeCompare(b.name));
    if (actor.role === 'bride' && packages.some(p => p.allCatalogueGowns && p.includedGownCount > 0)) {
      // Earlier customer apps still read a list of eligible IDs from this response.
      const eligibleDressIds = (await this.store.listDresses()).filter(d => rentableSizes(d).length > 0).map(d => d.id);
      return {packages: packages.map(p => p.allCatalogueGowns && p.includedGownCount > 0 ? {...p, eligibleDressIds} : p), limited: rows.length >= 100};
    }
    return {packages, limited: rows.length >= 100};
  }
  async gownLimit(uid) {
    return this.store.atomic(async tx => {
      const actor = await tx.get(`staff/${uid}`);
      ensure(actor?.active === true && actor.role === 'manager', 'MANAGER_REQUIRED', 403);
      return {maxGowns: await countStockedGowns(tx, await tx.listDresses())};
    });
  }
  async availability(uid, input) {
    ensure(keys(input,['packageId','revision','removedIds','addonIds','rentalPlan']) && validId(input.packageId) && Number.isInteger(input.revision),'INVALID_SELECTION');
    return this.store.atomic(async tx => {
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`);
      ensure(!staff&&bride,'BRIDE_REQUIRED',403);
      const p=await tx.get(`servicePackages/${input.packageId}`);
      ensure(p?.active===true&&p.revision===input.revision,'PACKAGE_CHANGED',409);
      const priced=priceSelection(p,input.removedIds,input.addonIds),now=this.now();
      const dates=packageDates(priced,input.rentalPlan,now);
      const gowns=await Promise.all((await packageGownRows(tx,p)).map(async d=>{
        const dressId=d.id;
        if(d?.published!==true||d.availability!=='Available'||typeof d.sizes!=='string')return null;
        const sizes=await Promise.all((p.allCatalogueGowns?rentableSizes(d):d.sizes.split(', ')).map(async size=>({size,
          status:stockStatus(await tx.get(`rentalVariants/${variantId(dressId,size)}`),dates,now)})));
        return {dressId,revision:d.revision,sizes};
      }));
      const accessories=await Promise.all(accessoryCatalogue.items.map(async item=>({itemId:item.id,
        status:stockStatus(await tx.get(`accessoryStock/${item.id}`),dates,now)})));
      return {rentalPlan:input.rentalPlan,checkedAt:now,reserved:false,gowns:gowns.filter(Boolean),accessories};
    });
  }
  async save(uid, input) {
    validatePackage(input);
    return this.store.atomic(async tx => {
      const actor = await tx.get(`staff/${uid}`);
      ensure(actor?.active === true && actor.role === 'manager', 'MANAGER_REQUIRED', 403);
      const current = await tx.get(`servicePackages/${input.id}`);
      ensure((current?.revision ?? 0) === input.revision, 'PACKAGE_CHANGED', 409);
      // Old clients must not silently remove a configured gown entitlement.
      ensure(!current?.includedGownCount || Object.hasOwn(input, 'includedGownCount'), 'PACKAGE_CLIENT_UPDATE_REQUIRED', 409);
      ensure(!current?.allCatalogueGowns || input.allCatalogueGowns === true, 'PACKAGE_CLIENT_UPDATE_REQUIRED', 409);
      const typedIds = new Set((current?.services ?? []).filter(s => s.serviceType !== undefined).map(s => s.id));
      ensure(input.services.every(s => !typedIds.has(s.id) || s.serviceType !== undefined), 'PACKAGE_CLIENT_UPDATE_REQUIRED', 409);
      const deactivating = !input.active && current?.active && current.allCatalogueGowns &&
        current.includedGownCount === input.includedGownCount;
      if (input.allCatalogueGowns && input.includedGownCount > 0 && !deactivating) {
        const count = await countStockedGowns(tx, await tx.listDresses(), input.includedGownCount);
        ensure(count >= input.includedGownCount, 'PACKAGE_GOWN_LIMIT_CHANGED', 409);
      } else if (!input.allCatalogueGowns && input.active && input.includedGownCount > 0) {
        const ids = input.eligibleDressIds ?? [];
        ensure(ids.length >= input.includedGownCount, 'PACKAGE_GOWNS_NOT_READY', 409);
        const gowns = await packageGownRows(tx, input);
        ensure(gowns.length === ids.length, 'PACKAGE_GOWN_UNAVAILABLE', 409);
        ensure(await countStockedGowns(tx, gowns, input.includedGownCount) >= input.includedGownCount, 'PACKAGE_GOWNS_NOT_READY', 409);
      }
      const next = { ...input, revision: input.revision + 1, createdAt: current?.createdAt ?? this.now(),
        createdBy: current?.createdBy ?? uid, updatedAt: this.now(), updatedBy: uid,
        draft: !input.active && (!current || current.draft === true) };
      tx.set(`servicePackages/${input.id}`, next);
      return next;
    });
  }
  async remove(uid, id, input) {
    ensure(validId(id) && keys(input, ['revision']) && Number.isInteger(input.revision) && input.revision > 0, 'INVALID_PACKAGE');
    return this.store.atomic(async tx => {
      const actor = await tx.get(`staff/${uid}`);
      ensure(actor?.active === true && actor.role === 'manager', 'MANAGER_REQUIRED', 403);
      const current = await tx.get(`servicePackages/${id}`);
      ensure(!!current, 'PACKAGE_UNAVAILABLE', 404);
      ensure(current.revision === input.revision, 'PACKAGE_CHANGED', 409);
      // Query inside the transaction: never delete a catalogue item referenced
      // by a saved customer plan, including one created concurrently.
      ensure(!await tx.hasPackageSelections(id), 'PACKAGE_IN_USE', 409);
      tx.delete(`servicePackages/${id}`);
      tx.set(`packageCatalogueAudit/${hash(`${id}:${input.revision}:delete`)}`, {
        action: 'Deleted', packageId: id, snapshot: current, actorId: uid, createdAt: this.now(),
      });
      return { deleted: true, packageId: id };
    });
  }
  async assignedFitting(uid, selectionId) {
    ensure(validId(selectionId), 'SELECTION_ACCESS_DENIED', 404);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`);
      ensure(activeStaff(staff), 'STAFF_REQUIRED', 403);
      const selection = await tx.get(`packageSelections/${selectionId}`);
      ensure(selection, 'SELECTION_ACCESS_DENIED', 403);
      const rental = selection.rentalId ? await tx.get(`rentals/${selection.rentalId}`) : null;
      const progress = rental ? await tx.get(`rentalServiceProgress/${selectionId}`) : null;
      const finalFitting = rental?.uid === selection.uid && rental.packageSelectionId === selectionId &&
        rental.fittingQuote?.adjustmentPlan?.followUp === 'Required';
      const appointments = [];
      for (const id of selection.appointmentIds ?? []) {
        const booking = await tx.get(`appointments/${id}`);
        const link = await tx.get(`packageAppointments/${id}`);
        if (!isAssignedFitting(uid, selection, booking) || link?.selectionId !== selectionId ||
            !['Confirmed','Completed'].includes(booking.status) ||
            (rental && (!finalFitting || id===rental.appointmentId || !booking.feeIncluded || booking.fittingInvoiceId))) continue;
        const fee=booking.fittingInvoiceId?await tx.get(`sandboxInvoices/${booking.fittingInvoiceId}`):null;
        const feeVerified = fee?.state==='SandboxPaid' && fee.environment==='sandbox' &&
          !fee.reviewReason && fee.uid===selection.uid && fee.appointmentId===id &&
          fee.purpose==='FittingFee' && fee.amountCents===FITTING_FEE &&
          typeof fee.invoiceNo==='string' && !!fee.invoiceNo.trim();
        const time = effectiveVisitTime(booking);
        appointments.push({id, type:booking.type, status:booking.status,
          startAt:time.toMillis?.()??+time, scheduledStartAt:booking.startAt.toMillis?.()??+booking.startAt,
          feeIncluded:booking.feeIncluded===true, feeVerified, feeRequired:!!booking.fittingInvoiceId});
      }
      ensure(appointments.length>0, 'SELECTION_ACCESS_DENIED', 403);
      const {id,name,customerName,selectedGowns,rentalPlan,selectionRevision,
        rentalPlanRevision,fittingDecisionRevision}=selection;
      const result = {id,name,customerName,selectedGowns,rentalPlan,selectionRevision,
        rentalPlanRevision,fittingDecisionRevision,appointments,fittingOnly:true};
      if (!finalFitting) return result;
      const recorded = rental.finalFitting;
      return {...result, rentalId:selection.rentalId,
        rental:{appointmentId:rental.appointmentId,state:rental.state,
          collectedAt:rental.collectedAt,returnedAt:rental.returnedAt,
          fittingQuote:{adjustmentPlan:{followUp:'Required'}},
          finalFitting:recorded&&appointments.some(a=>a.id===recorded.appointmentId)
            ? {state:recorded.state,note:recorded.note,alterationVersion:recorded.alterationVersion} : null},
        serviceProgress:progress?.rentalId===selection.rentalId
          ? {alteration:progress.alteration,alterationVersion:progress.alterationVersion??progress.revision} : null};
    });
  }
  async selections(uid) {
    const actor = await this.paymentService.access(uid);
    const customer = actor.role === 'bride';
    const operations = !customer && await hasBoutiqueOperationsAccess(
      this.store, uid, await this.store.get(`staff/${uid}`),
    );
    if (!customer && !operations) return {selections:[],limited:false};
    const rows = await this.store.list('packageSelections', customer ? uid : undefined);
    const selections = await Promise.all(rows.map(async row => {
      const visits = await Promise.all((row.appointmentIds ?? []).map(async id => ({
        id, booking: await this.store.get(`appointments/${id}`),
      })));
      const visibleVisits = visits.filter(({booking}) =>
        booking?.uid === row.uid);
      const appointments = await Promise.all(visibleVisits.map(async ({id,booking:b}) => {
        const credit=await this.store.get(`fittingCredits/${id}`);
        return { id, type:b.type, status: b.status, startAt: effectiveVisitTime(b).toMillis?.() ?? +effectiveVisitTime(b),
          scheduledStartAt:b.startAt.toMillis?.()??+b.startAt,actualAttendedAt:b.actualAttendedAt?.toMillis?.()??(b.actualAttendedAt?+b.actualAttendedAt:null),
          fittingInvoiceId:b.fittingInvoiceId ?? null,paymentExpiresAt:b.paymentExpiresAt ?? null,
          feeIncluded:b.feeIncluded===true,
          availableCreditCents:b.status==='Completed' && credit && !credit.voidedAt && !credit.consumedBy && (!credit.reservedBy || credit.reservedUntil<=this.now()) ? credit.amountCents : 0};
      }));
      const progress=operations?await this.store.get(`rentalServiceProgress/${row.id}`):null;
      const invoiceFor = async id => {
        const invoice = id ? await this.store.get(`sandboxInvoices/${id}`) : null;
        return invoice?.uid === row.uid ? publicInvoice(invoice) : null;
      };
      return { ...row,...(row.fittingWorkflowVersion===2?fittingPresentation(row):{}),
      ...(customer ? {fittingQuoteHistory:undefined,selectionHistory:undefined,fittingDecisionHistory:undefined}:{}),
      ...(operations ? {serviceProgress:progress?.rentalId===(row.rentalId??null)?progress:null,
        serviceProgressRevision:progress?.revision??0} : {}),
      appointments,
      invoice: await invoiceFor(row.invoiceId),
      balanceInvoice: await invoiceFor(row.balanceInvoiceId),
      rental: row.rentalId ? await this.store.get(`rentals/${row.rentalId}`) : null,
      paymentPolicyVersion:this.bookings.feePolicy ? 1 : null,
    };}));
    return { selections: selections.sort((a, b) => b.createdAt - a.createdAt), limited: rows.length >= 100 };
  }
  async serviceProgress(uid, selectionId, input) {
    ensure(validId(selectionId) && keys(input,['requestId','revision','alteration','preparation','note']) && validId(input.requestId) &&
      Number.isSafeInteger(input.revision) && input.revision >= 0 &&
      ['NotAssessed','NotRequired','Pending','InProgress','Completed'].includes(input.alteration) &&
      ['NotStarted','Preparing','Ready'].includes(input.preparation) && text(input.note,1,700), 'INVALID_SERVICE_PROGRESS');
    return this.store.atomic(async tx => {
      const actor=await tx.get(`staff/${uid}`), selection=await tx.get(`packageSelections/${selectionId}`);
      ensure(activeStaff(actor),'STAFF_REQUIRED',403);
      ensure(!!selection,'SELECTION_ACCESS_DENIED',404);
      ensure(await hasPackageFittingAccess(tx, uid, actor, selection),'SELECTION_ACCESS_DENIED',403);
      const previous=await tx.get(`rentalServiceProgress/${selectionId}`);
      const fingerprint=JSON.stringify([input.alteration,input.preparation,input.note]);
      if(previous?.requestId===input.requestId){
        ensure(previous.fingerprint===fingerprint && previous.by===uid,'REQUEST_CONFLICT',409);
        return previous;
      }
      ensure((previous?.revision??0)===input.revision,'SERVICE_PROGRESS_CHANGED',409);
      const rental=selection.rentalId?await tx.get(`rentals/${selection.rentalId}`):null;
      ensure(!selection.rentalId || !!rental,'SERVICE_PROGRESS_CLOSED',409);
      ensure(!rental || !['Cancelled','Expired','PaymentReview'].includes(rental.state) &&
        !['Collected','Returned'].includes(rental.fulfilment) && !rental.collectedAt && !rental.returnedAt,'SERVICE_PROGRESS_CLOSED',409);
      ensure((selection.selectedGowns??[]).length>0 || (selection.selectedAccessories??[]).length>0,'SERVICE_ITEMS_REQUIRED',409);
      if(input.preparation==='Ready') {
        ensure(selection.fittingDecision?.state==='Approved' && rental?.state==='Locked' &&
          ['NotRequired','Completed'].includes(input.alteration),'SERVICE_NOT_READY',409);
        ensure(!rental.fittingAdjustmentsRequired||input.alteration==='Completed','FITTING_ADJUSTMENTS_PENDING',409);
        ensure(finalFittingComplete(rental,previous),'FINAL_FITTING_PENDING',409);
      }
      const next={selectionId,rentalId:selection.rentalId??null,revision:input.revision+1,alteration:input.alteration,preparation:input.preparation,
        alterationVersion:previous?.rentalId===(selection.rentalId??null)&&previous.alteration===input.alteration?(previous.alterationVersion??previous.revision):input.revision+1,
        alterationChangedAt:previous?.rentalId===(selection.rentalId??null)&&previous.alteration===input.alteration?(previous.alterationChangedAt??previous.updatedAt):this.now(),
        note:input.note,by:uid,byName:actor.name??'Staff',updatedAt:this.now(),requestId:input.requestId,fingerprint};
      tx.set(`rentalServiceProgress/${selectionId}`,next);
      if(rental?.finalFitting?.state==='Completed'&&next.alterationVersion!==rental.finalFitting.alterationVersion)
        tx.set(`rentals/${rental.id}`,{...rental,finalFitting:{...rental.finalFitting,state:'NeedsReview'}});
      tx.set(`rentalServiceProgressAudit/${selectionId}_${next.revision}`,{...next,previous:previous??null});
      return next;
    });
  }
  async select(uid, input) {
    ensure(keys(input, ['requestId', 'packageId', 'revision', 'removedIds', 'addonIds', 'gowns', 'accessories', 'accessoryCatalogueVersion','rentalPlan','expectedTotalCents']) && validId(input.requestId) && validId(input.packageId) && Number.isInteger(input.revision) &&
      (input.expectedTotalCents === undefined || amount(input.expectedTotalCents)), 'INVALID_SELECTION');
    ensure(Array.isArray(input.removedIds) && Array.isArray(input.addonIds) && input.removedIds.length <= 12 && input.addonIds.length <= 12, 'INVALID_SELECTION');
    const gowns = input.gowns ?? [];
    ensure(Array.isArray(gowns) && gowns.length <= MAX_PACKAGE_GOWNS && gowns.every(g => keys(g, ['dressId', 'size', 'revision']) &&
      validId(g.dressId) && text(g.size, 1, 40) && Number.isInteger(g.revision) && g.revision >= 0) &&
      new Set(gowns.map(g => g.dressId)).size === gowns.length, 'INVALID_GOWN_SELECTION');
    const accessories = input.accessories ?? [];
    ensure(Array.isArray(accessories) && accessories.length <= 24, 'INVALID_ACCESSORY_SELECTION');
    const id = hash(`${uid}:${input.requestId}`);
    const fingerprintParts = [input.packageId, input.revision, [...input.removedIds].sort(), [...input.addonIds].sort()];
    // Retain the old fingerprint for no-gown selections so existing retries stay safe.
    if (gowns.length) fingerprintParts.push([...gowns].sort((a, b) => a.dressId.localeCompare(b.dressId)).map(g => [g.dressId, g.size, g.revision]));
    if (accessories.length) fingerprintParts.push(input.accessoryCatalogueVersion, accessories);
    if (input.rentalPlan !== undefined) fingerprintParts.push(['rentalPlan',input.rentalPlan]);
    if (input.expectedTotalCents !== undefined) fingerprintParts.push(['expectedTotalCents', input.expectedTotalCents]);
    const fingerprint = JSON.stringify(fingerprintParts);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`), bride = await tx.get(`brides/${uid}`);
      ensure(!staff && !!bride, 'BRIDE_REQUIRED', 403);
      const previous = await tx.get(`packageSelections/${id}`);
      if (previous) { ensure(previous.fingerprint === fingerprint, 'REQUEST_CONFLICT', 409); return previous; }
      const p = await tx.get(`servicePackages/${input.packageId}`);
      ensure(p?.active === true, 'PACKAGE_UNAVAILABLE', 409);
      ensure(p.revision === input.revision, 'PACKAGE_CHANGED', 409);
      const priced = priceSelection(p, input.removedIds, input.addonIds);
      const accessoryPrice = priceAccessories(priced.services, accessories, input.accessoryCatalogueVersion);
      priced.totalCents += accessoryPrice.accessoryExtraCents;
      ensure(amount(priced.totalCents), 'INVALID_PACKAGE_PRICE');
      if (p.services.some(s => s.serviceType !== undefined)) {
        ensure(input.expectedTotalCents !== undefined, 'PACKAGE_CLIENT_UPDATE_REQUIRED', 409);
      }
      if ((p.allCatalogueGowns || p.services.some(s => s.serviceType !== undefined)) && p.includedGownCount > 0) {
        ensure(input.rentalPlan !== undefined, 'INVALID_RENTAL_DATE');
      }
      ensure(input.expectedTotalCents === undefined || input.expectedTotalCents === priced.totalCents, 'PACKAGE_CHANGED', 409);
      ensure(gowns.length === (p.includedGownCount ?? 0), 'PACKAGE_GOWN_COUNT', 409);
      const selectedGowns = [];
      for (const g of gowns) {
        ensure(p.allCatalogueGowns || (p.eligibleDressIds ?? []).includes(g.dressId), 'PACKAGE_GOWN_NOT_ELIGIBLE', 409);
        const dress = await tx.get(`dresses/${g.dressId}`);
        ensure(dress?.published === true && dress.availability === 'Available', 'PACKAGE_GOWN_UNAVAILABLE', 409);
        ensure(dress.revision === g.revision, 'PACKAGE_GOWN_CHANGED', 409);
        ensure(typeof dress.sizes === 'string' &&
          (p.allCatalogueGowns ? rentableSizes(dress) : dress.sizes.split(', ')).includes(g.size), 'PACKAGE_GOWN_SIZE', 409);
        selectedGowns.push({ dressId: g.dressId, size: g.size, revision: dress.revision, name: dress.name, category: dress.category, colour: dress.colour });
      }
      const selection = { id, uid, customerName: bride.name, packageId: p.id, packageRevision: p.revision,
        name: p.name, description: p.description, basePriceCents: p.basePriceCents, ...priced, ...accessoryPrice,
        includedGownCount: p.includedGownCount ?? 0, selectedGowns,
        removedServices: p.services.filter(s => input.removedIds.includes(s.id)),
        status: 'Confirmed', createdAt: this.now(), fingerprint, appointmentIds: [], invoiceId: null };
      if(input.rentalPlan!==undefined) {
        const dates=packageDates(selection,input.rentalPlan,this.now());
        await requireSelectedAvailability(tx,selection,dates,this.now());
        Object.assign(selection,{rentalPlan:input.rentalPlan,rentalPlanRevision:1,selectionFlowVersion:1});
      }
      tx.set(`packageSelections/${id}`, selection);
      return selection;
    });
  }
  async revise(uid, selectionId, input) {
    ensure(validId(selectionId)&&keys(input,['requestId','revision','packageId','packageRevision','removedIds','addonIds','gowns','accessories','accessoryCatalogueVersion','previewOnly','expectedTotalCents','rentalPlan','planRevision'])&&validId(input.requestId)&&Number.isSafeInteger(input.revision)&&typeof input.previewOnly==='boolean'&&(input.packageId===undefined||validId(input.packageId)),'INVALID_SELECTION');
    ensure(Array.isArray(input.gowns)&&input.gowns.length<=MAX_PACKAGE_GOWNS&&input.gowns.every(g=>keys(g,['dressId','size','revision'])&&validId(g.dressId)&&text(g.size,1,40)&&Number.isInteger(g.revision))&&new Set(input.gowns.map(g=>g.dressId)).size===input.gowns.length,'INVALID_GOWN_SELECTION');
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
      ensure(!staff&&bride&&s?.uid===uid,'SELECTION_ACCESS_DENIED',403);
      ensure(!s.rentalId&&!s.invoiceId,'FITTING_ORDER_LOCKED',409);
      const fingerprint=JSON.stringify([input.revision,input.packageRevision,input.removedIds,input.addonIds,input.gowns,input.accessories,input.accessoryCatalogueVersion,input.expectedTotalCents,...(input.packageId===undefined?[]:[input.packageId]),...(input.rentalPlan===undefined?[]:[input.rentalPlan,input.planRevision])]);
      if(!input.previewOnly&&s.lastSelectionChange?.requestId===input.requestId){ensure(s.lastSelectionChange.fingerprint===fingerprint,'REQUEST_CONFLICT',409);return {totalCents:s.totalCents,saved:true};}
      ensure((s.selectionRevision??0)===input.revision,'FITTING_SELECTION_CHANGED',409);
      const switching=input.packageId!==undefined&&input.packageId!==s.packageId;
      const p=await tx.get(`servicePackages/${input.packageId??s.packageId}`);
      ensure(p?.active&&p.revision===input.packageRevision,'PACKAGE_CHANGED',409);
      ensure(!switching||p.includedGownCount>0,'PACKAGE_GOWN_COUNT',409);
      const priced=priceSelection(p,input.removedIds,input.addonIds),accessories=priceAccessories(priced.services,input.accessories,input.accessoryCatalogueVersion);
      priced.totalCents+=accessories.accessoryExtraCents;
      ensure(amount(priced.totalCents)&&priced.totalCents>=200,'INVALID_PACKAGE_PRICE');
      ensure(input.gowns.length===(p.includedGownCount??0),'PACKAGE_GOWN_COUNT',409);
      const selectedGowns=[];
      for(const g of input.gowns){
        ensure(p.allCatalogueGowns || p.eligibleDressIds?.includes(g.dressId),'PACKAGE_GOWN_NOT_ELIGIBLE',409);
        const d=await tx.get(`dresses/${g.dressId}`);
        ensure(d?.published&&d.availability==='Available'&&d.revision===g.revision&&typeof d.sizes==='string'&&
          (p.allCatalogueGowns ? rentableSizes(d) : d.sizes.split(', ')).includes(g.size),'PACKAGE_GOWN_CHANGED',409);
        selectedGowns.push({dressId:g.dressId,size:g.size,revision:d.revision,name:d.name,category:d.category,colour:d.colour});
      }
      const campaign=!switching&&s.promotion?await tx.get(`campaigns/${s.promotion.id}`):null;
      const promotion=campaign?promotionQuote(campaign,s.packageId,priced.totalCents,this.now()):null;
      ensure(switching||!s.promotion||promotion,'PROMOTION_UNAVAILABLE',409);
      const totalCents=promotion?.totalCents??priced.totalCents;
      const rentalPlan=input.rentalPlan??s.rentalPlan;
      if (p.allCatalogueGowns && p.includedGownCount > 0) ensure(rentalPlan, 'INVALID_RENTAL_DATE');
      if(input.rentalPlan!==undefined)ensure(input.planRevision===(s.rentalPlanRevision??0),'RENTAL_PLAN_CHANGED',409);
      if(rentalPlan) {
        const dates=packageDates(priced,rentalPlan,this.now());
        for(const id of s.appointmentIds??[]) {
          const visit=await tx.get(`appointments/${id}`);
          if(visit?.uid===uid&&(['Requested','Confirmed','Completed'].includes(visit.status)||visit.status==='AwaitingPayment'&&visit.paymentExpiresAt>this.now()))
            ensure(fittingFitsRental(visit,rentalPlan,this.now()),'FITTING_DATE_CONFLICT',409);
        }
        // Legacy records retain their dates; explicit date-first revisions fail closed.
        if(input.rentalPlan!==undefined||s.selectionFlowVersion===1||p.allCatalogueGowns)
          await requireSelectedAvailability(tx,{selectedGowns,selectedAccessories:accessories.selectedAccessories},dates,this.now());
      }
      if(input.previewOnly)return {totalCents,subtotalCents:priced.totalCents,promotion,selectedGowns,accessoryExtraCents:accessories.accessoryExtraCents};
      ensure(input.expectedTotalCents===totalCents,'DEPOSIT_QUOTE_CHANGED',409);
      ensure((s.selectionHistory??[]).length<50,'FITTING_SELECTION_LIMIT',409);
      const next={...s,packageId:p.id,name:p.name,description:p.description,basePriceCents:p.basePriceCents,packageRevision:p.revision,...priced,...accessories,totalCents,promotion,promotionRevision:(s.promotionRevision??0)+1,
        ...(input.rentalPlan===undefined?{}:{rentalPlan,rentalPlanRevision:(s.rentalPlanRevision??0)+1,selectionFlowVersion:1}),
        includedGownCount:p.includedGownCount??0,selectedGowns,removedServices:p.services.filter(v=>input.removedIds.includes(v.id)),selectionRevision:input.revision+1,
        lastSelectionChange:{requestId:input.requestId,fingerprint,by:uid,at:this.now()},selectionHistory:[...(s.selectionHistory??[]),{packageId:s.packageId,name:s.name,rentalPlan:s.rentalPlan??null,selectedGowns:s.selectedGowns??[],selectedAccessories:s.selectedAccessories??[],services:s.services??[],totalCents:s.totalCents,at:this.now()}],
        fittingWorkflowVersion:2,fittingQuote:null,fittingQuoteHistory:[...(s.fittingQuoteHistory??[]),...(s.fittingQuote?[s.fittingQuote]:[])].slice(-20),
        fittingDecisionHistory:[...(s.fittingDecisionHistory??[]),...(s.fittingDecision?[s.fittingDecision]:[])].slice(-20),
        fittingDecision:s.fittingDecision?{...s.fittingDecision,state:'AwaitingReview',outcome:'Reselect'}:null,fittingDecisionRevision:(s.fittingDecisionRevision??0)+1};
      tx.set(`packageSelections/${selectionId}`,next);return {totalCents,saved:true};
    });
  }
  async completedFittings(uid, selectionId) {
    const [staff,bride,selection]=await Promise.all([
      this.store.get(`staff/${uid}`),this.store.get(`brides/${uid}`),this.store.get(`packageSelections/${selectionId}`),
    ]);
    ensure(!staff&&bride&&selection?.uid===uid,'SELECTION_ACCESS_DENIED',403);
    const now=this.now();
    if(!canUseCompletedFitting(selection)||selection.appointmentIds.length>=10)return {visits:[]};
    packageDates(selection,selection.rentalPlan,now);
    const attached=await Promise.all(selection.appointmentIds.map(id=>this.store.get(`appointments/${id}`)));
    if(attached.some(visit=>fittingBlocksLink(visit,now)))return {visits:[]};
    const visits=await this.store.completedDressTrials(uid);
    const eligible=await Promise.all(visits.map(async visit=>{
      if(!validId(visit.id)||await this.store.get(`packageAppointments/${visit.id}`)||
         !await unusedFittingCredit(this.store,uid,visit.id,visit,selection.rentalPlan,now))return null;
      const attendedAt=visit.actualAttendedAt.toMillis?.()??+visit.actualAttendedAt;
      return {id:visit.id,attendedAt,creditCents:FITTING_FEE};
    }));
    return {visits:eligible.filter(Boolean).sort((a,b)=>b.attendedAt-a.attendedAt)};
  }
  async linkCompletedFitting(uid, selectionId, input) {
    ensure(validId(selectionId)&&keys(input,['appointmentId','planRevision','selectionRevision'])&&validId(input.appointmentId)&&
      Number.isSafeInteger(input.planRevision)&&input.planRevision>=0&&Number.isSafeInteger(input.selectionRevision)&&
      input.selectionRevision>=0,'INVALID_COMPLETED_FITTING');
    const appointmentId=input.appointmentId;
    return this.store.atomic(async tx=>{
      const [staff,bride,selection,link,visit]=await Promise.all([
        tx.get(`staff/${uid}`),tx.get(`brides/${uid}`),tx.get(`packageSelections/${selectionId}`),
        tx.get(`packageAppointments/${appointmentId}`),tx.get(`appointments/${appointmentId}`),
      ]);
      ensure(!staff&&bride&&selection?.uid===uid&&visit?.uid===uid,'SELECTION_ACCESS_DENIED',403);
      if(link?.selectionId===selectionId&&link.uid===uid&&selection.reusedFittingAppointmentId===appointmentId&&
          selection.appointmentIds.includes(appointmentId))return {linked:true};
      ensure(!link&&canUseCompletedFitting(selection),'COMPLETED_FITTING_UNAVAILABLE',409);
      ensure((selection.rentalPlanRevision??0)===input.planRevision,'RENTAL_PLAN_CHANGED',409);
      ensure((selection.selectionRevision??0)===input.selectionRevision,'FITTING_SELECTION_CHANGED',409);
      const now=this.now();
      packageDates(selection,selection.rentalPlan,now);
      ensure(selection.appointmentIds.length<10,'TOO_MANY_APPOINTMENTS',409);
      const attached=await Promise.all(selection.appointmentIds.map(id=>tx.get(`appointments/${id}`)));
      ensure(!attached.some(previous=>fittingBlocksLink(previous,now)),'COMPLETED_FITTING_UNAVAILABLE',409);
      ensure(await unusedFittingCredit(tx,uid,appointmentId,visit,selection.rentalPlan,now),'COMPLETED_FITTING_UNAVAILABLE',409);
      tx.set(`packageAppointments/${appointmentId}`,{selectionId,uid});
      tx.set(`packageSelections/${selectionId}`,{...selection,
        appointmentIds:[...selection.appointmentIds,appointmentId],reusedFittingAppointmentId:appointmentId,
        ...(selection.fittingChoice?.mode==='SkipFitting'?{
          fittingChoice:{mode:'TryOn',accepted:false,acceptedAt:now,by:uid},
          fittingChoiceRevision:(selection.fittingChoiceRevision??0)+1,
        }:{})});
      return {linked:true};
    });
  }
  async book(uid, selectionId, input) {
    ensure(validId(selectionId) && keys(input, ['requestId', 'type', 'startAt', 'notes','feePolicyVersion']) && validId(input.requestId), 'INVALID_BOOKING');
    const start = input.startAt, now = this.now();
    ensure(Number.isSafeInteger(start) && start > now && start < now + 180 * 86400000 && start % 3600000 === 0 &&
      [2, 3, 4, 6, 7, 8].includes(new Date(start).getUTCHours()) && ['Dress Trial', 'Bridal Consultation'].includes(input.type) && text(input.notes, 0, 700), 'INVALID_BOOKING');
    const id = hash(`${uid}:${selectionId}:${input.requestId}`);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`), bride = await tx.get(`brides/${uid}`);
      const selection = await tx.get(`packageSelections/${selectionId}`);
      const existing = await tx.get(`appointments/${id}`);
      ensure(!staff && !!bride && selection?.uid === uid, 'SELECTION_ACCESS_DENIED', 403);
      ensure(selection.fittingChoice?.mode!=='SkipFitting','FITTING_CHOICE_CONFLICT',409);
      ensure(text(bride.name, 1, 100) && text(bride.phone, 9, 25), 'CUSTOMER_PROFILE_REQUIRED', 409);
      const notes = `Package: ${selection.name}\nSelection: ${selectionId}${input.notes ? '\n' + input.notes : ''}`;
      if (existing) {
        ensure((existing.startAt.toMillis?.() ?? +existing.startAt) === start && existing.type === input.type && existing.notes === notes, 'REQUEST_CONFLICT', 409);
        return this.bookings.outcome(id,existing);
      }
      const rental=selection.rentalId ? await tx.get(`rentals/${selection.rentalId}`) : null;
      const included=rental?.state==='Locked' && ['DepositPaid','Paid'].includes(rental.paymentState)&&!rental.collectedAt&&!rental.returnedAt;
      ensure(included||!selection.reusedFittingAppointmentId||!!selection.fittingDecision,'COMPLETED_FITTING_ALREADY_LINKED',409);
      if(selection.selectionFlowVersion===1&&!included)
        await requireSelectedAvailability(tx,selection,packageDates(selection,selection.rentalPlan,now),now);
      if(selection.selectedGowns?.length || selection.selectedAccessories?.length) {
        ensure(selection.rentalPlan,'RENTAL_PLAN_REQUIRED',409);
        ensure(included?malaysiaDay(start)<=rental.pickupDate&&malaysiaDay(start)<rental.eventDate:fittingBeforeRental(start,selection.rentalPlan),'FITTING_DATE_CONFLICT',409);
      }
      ensure(selection.appointmentIds.length < 10, 'TOO_MANY_APPOINTMENTS', 409);
      const previous = await Promise.all(selection.appointmentIds.map(value => tx.get(`appointments/${value}`)));
      ensure(!previous.some(b => ['Requested', 'Confirmed'].includes(b?.status) || (b?.status==='AwaitingPayment' && b.paymentExpiresAt>now)), 'PACKAGE_BOOKING_EXISTS', 409);
      for(const g of selection.selectedGowns ?? []) {
        const dress=await tx.get(`dresses/${g.dressId}`);
        ensure(dress?.published===true && dress.availability==='Available' && dress.sizes.split(', ').includes(g.size),'PACKAGE_GOWN_UNAVAILABLE',409);
      }
      const reservation=await this.bookings.prepare(tx,start,id,uid,input.type);
      let booking = { uid, name: bride.name, phone: bride.phone, type: input.type, startAt: new Date(start),
        slotKey: String(start), notes,
        dressId: '', dressName: '', status: 'Confirmed', response: '', revision: 1, updatedBy: uid,
        assignedStaffId:reservation.staffId,confirmation:'Automatic',
        createdAt: new Date(now), updatedAt: new Date(now) };
      const fee=await this.bookings.fee(tx,id,booking,bride,{included,consent:input.feePolicyVersion});booking=fee.booking;
      tx.set(`appointments/${id}`, booking);
      tx.set(`packageAppointments/${id}`, { selectionId, uid });
      tx.set(`packageSelections/${selectionId}`, { ...selection, appointmentIds: [...selection.appointmentIds, id] });
      reservation.commit();fee.commit();if(booking.status==='Confirmed')this.bookings.email(tx,id,booking,bride,'Confirmed');
      return this.bookings.outcome(id,booking);
    });
  }
  async invoice(uid, selectionId, input) {
    ensure(validId(selectionId) && keys(input, ['appointmentId']) && validId(input.appointmentId), 'INVALID_QUOTE');
    const id = hash(`package:${selectionId}`);
    return this.store.atomic(async tx => {
      const staff = await tx.get(`staff/${uid}`);
      ensure(activeStaff(staff), 'STAFF_REQUIRED', 403);
      ensure(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      const selection = await tx.get(`packageSelections/${selectionId}`);
      ensure(!!selection, 'SELECTION_NOT_FOUND', 404);
      const booking = await tx.get(`appointments/${input.appointmentId}`);
      const existing = await tx.get(`sandboxInvoices/${id}`);
      if (existing) return publicInvoice(existing);
      ensure(!(selection.includedGownCount > 0) && !(selection.selectedAccessories?.length > 0), 'PACKAGE_RENTAL_CONFIRMATION_REQUIRED',409);
      ensure(booking?.status === 'Confirmed' && booking.uid === selection.uid && selection.appointmentIds.includes(input.appointmentId), 'CONFIRMED_APPOINTMENT_REQUIRED', 409);
      const invoice = { id, uid: selection.uid, customerName: selection.customerName, purpose: 'PackagePayment',
        title: `Package: ${selection.name}`, appointmentId: input.appointmentId, packageSelectionId: selectionId,
        amountCents: selection.totalCents, state: 'Quoted', environment: 'sandbox', createdAt: this.now(), createdBy: uid };
      tx.set(`sandboxInvoices/${id}`, invoice);
      tx.set(`packageSelections/${selectionId}`, { ...selection, invoiceId: id });
      return publicInvoice(invoice);
    });
  }
}
