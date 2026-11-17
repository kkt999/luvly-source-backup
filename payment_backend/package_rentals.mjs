import { createHash } from 'node:crypto';
import { HttpError, publicInvoice } from './payment_service.mjs';
import { hasBoutiqueOperationsAccess } from './appointment_access.mjs';
import { HOLD_MS, rentalDates, peakUsage, consumesStock, rentalResources } from './rental_service.mjs';
import { accessoryCatalogue } from './accessory_catalogue.mjs';
import {fittingFitsRental,hasFittingWaiver} from './booking_dates.mjs';
import {packagePaymentQuote} from './bridal_payment_policy.mjs';
import {preparePromotion} from './promotions.mjs';
import {extensionHolds,prepareExtensionClose} from './rental_extensions.mjs';
import {agreedFittingTotal,fittingPresentation} from './fitting_proposals.mjs';
import {checkMakeupTrialReferences} from './fitting_makeup.mjs';
import {selectedAvailability,requireSelectedAvailability} from './rental_availability.mjs';
import {addsRentalDay} from './package_service_types.mjs';
const id = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(v);
const check = (v, code, status = 409) => { if (!v) throw new HttpError(status, code); };
const exact = (v, keys) => v && !Array.isArray(v) && Object.keys(v).every(k => keys.includes(k));
const hash = v => createHash('sha256').update(v).digest('hex').slice(0,32);
export const allowedRentalDays=selection=>3+(selection.services??[]).filter(addsRentalDay).length;
export function packageDates(selection, input, now) {
  check(exact(input,['pickupDate','eventDate','returnDate']), 'INVALID_RENTAL_DATE');
  const dates = rentalDates(input,now);
  // A selected extra-day service adds one day to the standard three-day period.
  check(dates.endDay - dates.startDay - 3 <= allowedRentalDays(selection), 'PACKAGE_RENTAL_PERIOD');
  return dates;
}
export class PackageRentals {
  constructor({store, rentals, now = Date.now,paymentPolicy=false}) { Object.assign(this,{store,rentals,now,paymentPolicy}); }
  async changeDates(uid,rentalId,input){
    check(id(rentalId)&&exact(input,['requestId','revision','pickupDate','returnDate','reason','customerAgreed','previewOnly','quoteRateCents','quotePackageRevision'])&&
      id(input.requestId)&&Number.isInteger(input.revision)&&input.revision>=0&&typeof input.previewOnly==='boolean'&&
      typeof input.customerAgreed==='boolean'&&typeof input.reason==='string'&&input.reason.trim().length>=10&&input.reason.length<=700,'INVALID_DATE_CHANGE',400);
    if(!input.previewOnly)check(input.customerAgreed,'DATE_CHANGE_CONSENT_REQUIRED',400);
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),r=await tx.get(`rentals/${rentalId}`);
      check(staff?.active===true&&['staff','manager'].includes(staff.role),'STAFF_REQUIRED',403);
      check(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      check(r?.id===rentalId&&r.policyVersion===1&&!!r.packageSelectionId,'PACKAGE_DATE_CHANGE_REQUIRED');
      const receiptPath=`rentalDateChanges/${hash(`${rentalId}:${input.requestId}`)}`;
      const receipt=await tx.get(receiptPath);
      const fingerprint=JSON.stringify([rentalId,input.revision,input.pickupDate,input.returnDate,input.reason.trim(),...(input.quoteRateCents===undefined?[]:[input.quoteRateCents,input.quotePackageRevision])]);
      if(receipt&&!input.previewOnly){check(receipt.by===uid&&receipt.fingerprint===fingerprint,'REQUEST_CONFLICT');return r;}
      check(r.state==='Locked'&&!r.collectedAt&&!r.returnedAt&&!r.reviewReason,'DATE_CHANGE_BEFORE_PICKUP_ONLY');
      check(!(r.pendingExtension?.expiresAt>this.now()),'EXTENSION_PENDING');
      check((r.dateRevision??0)===input.revision,'RENTAL_DATES_CHANGED');
      const s=await tx.get(`packageSelections/${r.packageSelectionId}`);
      check(s?.uid===r.uid&&s.rentalId===r.id,'RENTAL_PLAN_CHANGED');
      const deposit=await tx.get(`sandboxInvoices/${r.invoiceId}`);
      check(deposit?.state==='SandboxPaid'&&deposit.environment==='sandbox'&&!deposit.reviewReason&&deposit.uid===r.uid&&deposit.rentalId===r.id&&deposit.amountCents===r.depositCents,'PACKAGE_PAYMENT_REVIEW_REQUIRED');
      for(const invoiceId of [r.balanceInvoiceId,r.securityInvoiceId].filter(Boolean)){const i=await tx.get(`sandboxInvoices/${invoiceId}`);check(i&&!i.reviewReason&&i.state!=='ReviewRequired','PACKAGE_PAYMENT_REVIEW_REQUIRED');}
      const plan={pickupDate:input.pickupDate,eventDate:r.eventDate,returnDate:input.returnDate};
      const now=this.now(),dates=rentalDates(plan,now),days=dates.endDay-dates.startDay-3,allowed=allowedRentalDays(s)+(r.extensionDaysPaid??0);
      check(plan.pickupDate!==r.pickupDate||plan.returnDate!==r.returnDate,'RENTAL_DATES_UNCHANGED');
      let preview={preview:true,canConfirm:days<=allowed,...plan,previous:{pickupDate:r.pickupDate,returnDate:r.returnDate},
        rentalDays:days,allowedRentalDays:allowed,extraDaysRequired:Math.max(0,days-allowed),additionalChargeCents:days>allowed?null:0,
        availableAgain:dates.availableAgain,revision:r.dateRevision??0};
      if(days>allowed){
        const p=s.packageId?await tx.get(`servicePackages/${s.packageId}`):null;
        const rates=(p?.services??[]).filter(v=>v.kind==='Add-on'&&addsRentalDay(v));
        const rate=p?.active===true&&rates.length===1&&Number.isInteger(rates[0].priceCents)&&rates[0].priceCents>=100?rates[0].priceCents:null;
        if(!rate){if(input.previewOnly)return {...preview,code:'EXTENSION_PRICE_REQUIRED'};check(false,'EXTENSION_PRICE_REQUIRED');}
        const amount=(days-allowed)*rate;check(Number.isSafeInteger(amount)&&amount<=100000000,'INVALID_AMOUNT');
        preview={...preview,canConfirm:true,requiresPayment:true,additionalChargeCents:amount,dayRateCents:rate,quotePackageRevision:p.revision};
        if(!input.previewOnly)check(input.quoteRateCents===rate&&input.quotePackageRevision===p.revision,'EXTENSION_QUOTE_CHANGED');
      }
      const visits=new Map();
      for(const appointmentId of new Set([...(s.appointmentIds??[]),...(r.appointmentId?[r.appointmentId]:[])])){
        const visit=await tx.get(`appointments/${appointmentId}`);visits.set(appointmentId,visit);
        if(visit?.uid===r.uid&&(['Confirmed','Requested','Completed'].includes(visit.status)||visit.status==='AwaitingPayment'&&visit.paymentExpiresAt>now))
          check(fittingFitsRental(visit,plan,now),'FITTING_DATE_CONFLICT');
      }
      const linked=visits.get(r.appointmentId);
      check(hasFittingWaiver(r)||linked?.uid===r.uid&&['Confirmed','Completed'].includes(linked.status),'CONFIRMED_APPOINTMENT_REQUIRED');
      const rows=[];
      for(const resource of rentalResources(r)){
        const v=await tx.get(resource.path),own=v?.allocations?.[r.id];
        check(Number.isInteger(v?.quantity)&&v.quantity>0,'INVENTORY_NOT_CONFIGURED');
        check(own?.state==='Locked'&&own.quantity===1&&own.startDay===r.startDay&&own.endDay===r.endDay&&!v.outstanding?.[r.id],'INVENTORY_REVIEW_REQUIRED');
        const others=Object.fromEntries(Object.entries(v.allocations).filter(([key])=>key!==r.id));
        check(peakUsage(others,dates.startDay,dates.endDay,now)+1<=v.quantity,'RENTAL_STOCK_UNAVAILABLE');
        rows.push({...resource,v});
      }
      check(rows.length>0,'PACKAGE_RENTAL_ITEMS_REQUIRED');
      if(input.previewOnly)return {...preview,stockChecked:true,items:rows.map(row=>row.name)};
      check((r.dateChangesCount??0)<50,'DATE_CHANGE_LIMIT_REACHED');
      const change={by:uid,at:now,requestId:input.requestId,fingerprint,reason:input.reason.trim(),customerAgreed:true,
        consentMethod:'StaffRecordedConsent',before:{pickupDate:r.pickupDate,eventDate:r.eventDate,returnDate:r.returnDate},after:plan};
      if(preview.requiresPayment){
        const extensionId=hash(`extension:${r.id}:${input.requestId}`),invoiceId=hash(`extension-invoice:${extensionId}`),expiresAt=now+HOLD_MS;
        const holds=extensionHolds(r,dates,extensionId,expiresAt);
        const e={id:extensionId,rentalId:r.id,uid:r.uid,invoiceId,state:'AwaitingPayment',revision:input.revision,plan,dates,holds,receiptPath,change,
          extraDays:days-allowed,amountCents:preview.additionalChargeCents,dayRateCents:preview.dayRateCents,expiresAt,createdAt:now};
        for(const {path,v}of rows){const allocations={...v.allocations};for(const h of holds){const {key,...a}=h;allocations[key]=a;}check(Object.keys(allocations).length<=1000,'INVENTORY_REVIEW_REQUIRED');tx.set(path,{...v,allocations});}
        const pendingExtension={id:extensionId,invoiceId,expiresAt,amountCents:e.amountCents,extraDays:e.extraDays,dayRateCents:e.dayRateCents,...plan,state:'AwaitingPayment'};
        const next={...r,pendingExtension,updatedAt:now};
        tx.set(`rentals/${r.id}`,next);tx.set(`rentalExtensions/${extensionId}`,e);tx.set(receiptPath,{...change,state:'AwaitingPayment',extensionId,rentalId:r.id,uid:r.uid});
        tx.set(`sandboxInvoices/${invoiceId}`,{id:invoiceId,uid:r.uid,customerName:s.customerName,appointmentId:r.appointmentId,rentalId:r.id,packageSelectionId:r.packageSelectionId,
          extensionId,paymentPhase:'Extension',purpose:'RentalExtension',title:`Additional rental days: ${s.name}`,amountCents:e.amountCents,state:'Quoted',environment:'sandbox',createdAt:now,
          holdExpiresAt:expiresAt,extensionDetails:{...plan,oldPickupDate:r.pickupDate,oldReturnDate:r.returnDate,extraDays:e.extraDays,dayRateCents:e.dayRateCents}});
        return next;
      }
      const next={...r,...plan,...dates,dateRevision:input.revision+1,dateChangesCount:(r.dateChangesCount??0)+1,
        originalRentalPlan:r.originalRentalPlan??change.before,dateChangeHistory:[...(r.dateChangeHistory??[]),change].slice(-20),updatedAt:now};
      for(const {path,v}of rows)tx.set(path,{...v,allocations:{...v.allocations,[r.id]:{...v.allocations[r.id],...dates}}});
      tx.set(`rentals/${r.id}`,next);
      tx.set(`packageSelections/${r.packageSelectionId}`,{...s,rentalPlan:plan,rentalPlanRevision:(s.rentalPlanRevision??0)+1,
        lastRentalDateChange:change,rentalDateRevision:input.revision+1});
      tx.set(receiptPath,{...change,rentalId:r.id,uid:r.uid,revision:input.revision+1});
      return next;
    });
  }
  async cancelExtension(uid,rentalId,input){
    check(exact(input,['extensionId'])&&id(input.extensionId),'INVALID_DATE_CHANGE',400);
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),r=await tx.get(`rentals/${rentalId}`),e=await tx.get(`rentalExtensions/${input.extensionId}`);
      check(staff?.active===true&&['staff','manager'].includes(staff.role),'STAFF_REQUIRED',403);
      check(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      check(e?.rentalId===rentalId&&r?.id===rentalId,'EXTENSION_CHANGED');
      if(['Cancelled','Expired'].includes(e.state))return r;
      check(e.state==='AwaitingPayment'&&r.pendingExtension?.id===e.id,'EXTENSION_CHANGED');
      const close=await prepareExtensionClose(tx,r,e,'Cancelled',this.now());close();return {...r,pendingExtension:null,lastExtensionOutcome:'Cancelled'};
    });
  }
  async stock(uid) {
    check(await this.rentals.access(uid) === 'staff','STAFF_REQUIRED',403);
    return {items: await Promise.all(accessoryCatalogue.items.map(async a => {
      const v = await this.store.get(`accessoryStock/${a.id}`);
      return {id:a.id,name:a.name,category:a.category,image:a.image,sample:true,quantity:v?.quantity ?? null,revision:v?.revision ?? 0};
    }))};
  }
  async saveStock(uid,input) {
    check(exact(input,['id','quantity','revision']) && id(input.id) && Number.isInteger(input.quantity) && input.quantity >= 0 && input.quantity <= 100 && Number.isInteger(input.revision),'INVALID_VARIANT',400);
    check(accessoryCatalogue.items.some(a=>a.id===input.id),'INVALID_ACCESSORY_SELECTION');
    return this.store.atomic(async tx => {
      const staff=await tx.get(`staff/${uid}`),old=await tx.get(`accessoryStock/${input.id}`);
      check(staff?.active===true && ['staff','manager'].includes(staff.role),'STAFF_REQUIRED',403);
      check((old?.revision??0)===input.revision,'VARIANT_CHANGED');
      check(peakUsage(old?.allocations, Math.floor((this.now()+8*3600000)/86400000),Infinity,this.now())<=input.quantity,'QUANTITY_BELOW_RESERVED');
      const next={...old,...input,revision:input.revision+1,allocations:old?.allocations??{},updatedBy:uid};
      tx.set(`accessoryStock/${input.id}`,next);
      return {id:next.id,quantity:next.quantity,revision:next.revision};
    });
  }
  async checkResources(tx,selection,dates,now,{strict=false}={}) {
    const resources=rentalResources({gowns:selection.selectedGowns,accessories:selection.selectedAccessories});
    const rows=[];
    for (const resource of resources) {
      const v=await tx.get(resource.path);
      const configured=Number.isInteger(v?.quantity) && v.quantity>=0;
      const remaining=configured ? Math.max(0,v.quantity-peakUsage(v.allocations,dates.startDay,dates.endDay,now)) : null;
      if (strict) check(configured,'INVENTORY_NOT_CONFIGURED');
      check(remaining===null || remaining>0,'RENTAL_STOCK_UNAVAILABLE');
      rows.push({...resource,variant:v,remaining});
    }
    return rows;
  }
  async plan(uid,selectionId,input) {
    check(id(selectionId) && exact(input,['pickupDate','eventDate','returnDate','revision']) && Number.isInteger(input.revision),'INVALID_RENTAL',400);
    return this.store.atomic(async tx => {
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
      check(!staff && bride && s?.uid===uid,'SELECTION_ACCESS_DENIED',403);
      check((s.rentalPlanRevision??0)===input.revision,'RENTAL_PLAN_CHANGED');
      const current=s.rentalId ? await tx.get(`rentals/${s.rentalId}`) : null;
      check(!current || ['Cancelled','Expired'].includes(current.state) || (current.state==='Held' && current.expiresAt<=this.now()),'RENTAL_ALREADY_EXISTS');
      const rentalPlan={pickupDate:input.pickupDate,eventDate:input.eventDate,returnDate:input.returnDate};
      const dates=packageDates(s,rentalPlan,this.now());
      for(const appointmentId of s.appointmentIds??[]) {
        const booking=await tx.get(`appointments/${appointmentId}`);
        if(booking?.uid===s.uid && ['Requested','Confirmed','Completed','AwaitingPayment'].includes(booking.status)) check(fittingFitsRental(booking,rentalPlan,this.now()),'FITTING_DATE_CONFLICT');
      }
      for (const g of s.selectedGowns ?? []) {
        const dress=await tx.get(`dresses/${g.dressId}`);
        check(dress?.published && dress.availability==='Available' && dress.sizes.split(', ').includes(g.size),'DRESS_UNAVAILABLE');
      }
      if(s.selectionFlowVersion===1)await requireSelectedAvailability(tx,s,dates,this.now());
      const resources=await this.checkResources(tx,s,dates,this.now());
      tx.set(`packageSelections/${selectionId}`,{...s,rentalPlan,rentalPlanRevision:input.revision+1});
      return {rentalPlan,revision:input.revision+1,availableAgain:dates.availableAgain,
        availability:resources.map(({name,remaining})=>({name,remaining})),reserved:false};
    });
  }
  async checkPlan(uid,selectionId,input) {
    check(id(selectionId)&&exact(input,['pickupDate','eventDate','returnDate','revision'])&&Number.isInteger(input.revision),'INVALID_RENTAL',400);
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
      check(!staff&&bride&&s?.uid===uid,'SELECTION_ACCESS_DENIED',403);
      check(!s.rentalId&&!s.invoiceId,'RENTAL_ALREADY_EXISTS');
      check((s.rentalPlanRevision??0)===input.revision,'RENTAL_PLAN_CHANGED');
      const plan={pickupDate:input.pickupDate,eventDate:input.eventDate,returnDate:input.returnDate};
      const dates=packageDates(s,plan,this.now());
      const items=await selectedAvailability(tx,s,dates,this.now());
      return {available:items.every(r=>r.status==='Available'),items,reserved:false};
    });
  }
  async confirm(uid,selectionId,input) {
    check(id(selectionId) && exact(input,['appointmentId','requestId','depositCents','planRevision','fittingRevision']) && (id(input.appointmentId)||input.appointmentId==='') && id(input.requestId) && Number.isSafeInteger(input.depositCents) && input.depositCents>=100 && Number.isInteger(input.planRevision),'INVALID_RENTAL',400);
    const rentalId=hash(`package:${selectionId}:${input.requestId}`),invoiceId=hash(`rental:${rentalId}`);
    const fingerprint=JSON.stringify([selectionId,input.appointmentId,input.depositCents,input.planRevision,...(input.fittingRevision===undefined?[]:[input.fittingRevision])]);
    return this.store.atomic(async tx => {
      const staff=await tx.get(`staff/${uid}`),s=await tx.get(`packageSelections/${selectionId}`),previous=await tx.get(`rentals/${rentalId}`);
      check(staff?.active===true && ['staff','manager'].includes(staff.role),'STAFF_REQUIRED',403);
      check(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      const booking = input.appointmentId ? await tx.get(`appointments/${input.appointmentId}`) : null;
      if(previous) {check(previous.fingerprint===fingerprint,'REQUEST_CONFLICT');return previous;}
      check(s && s.rentalPlan && s.rentalPlanRevision===input.planRevision,'RENTAL_PLAN_CHANGED');
      const agreedTotal=agreedFittingTotal(s);
      await checkMakeupTrialReferences(tx,s);
      check(s.selectedGowns.length+s.selectedAccessories.length>0,'PACKAGE_RENTAL_ITEMS_REQUIRED');
      check(input.depositCents<=agreedTotal && (agreedTotal-input.depositCents===0 || agreedTotal-input.depositCents>=100),'INVALID_AMOUNT');
      const waived=s.fittingChoice?.mode==='SkipFitting'&&s.fittingChoice.accepted===true&&s.fittingDecision?.mode==='Waived'&&s.fittingDecision.state==='Approved';
      if(s.fittingWorkflowVersion===1)check(s.fittingDecision?.state==='Approved','FITTING_RESULT_REQUIRED');
      if(s.fittingDecision){check(s.fittingDecision.state==='Approved','FITTING_RESULT_REQUIRED');check(s.fittingDecisionRevision===input.fittingRevision,'FITTING_CHANGED');}
      check(waived||s.fittingChoice?.mode!=='SkipFitting','FITTING_RESULT_REQUIRED');
      const link=input.appointmentId?await tx.get(`packageAppointments/${input.appointmentId}`):null;
      check(waived?!input.appointmentId:['Confirmed','Completed'].includes(booking?.status)&&booking.uid===s.uid&&link?.selectionId===selectionId,'CONFIRMED_APPOINTMENT_REQUIRED');
      if(this.paymentPolicy&&!waived)check(booking.status==='Completed','COMPLETED_FITTING_REQUIRED');
      let creditId=null,credit=null,policy={};
      if(this.paymentPolicy){
        for(const appointmentId of s.appointmentIds ?? []){
          const candidate=await tx.get(`fittingCredits/${appointmentId}`),visit=await tx.get(`appointments/${appointmentId}`);
          if(!credit && candidate?.uid===s.uid && visit?.status==='Completed' && !candidate.voidedAt && !candidate.consumedBy && (!candidate.reservedBy || candidate.reservedUntil<=this.now())){creditId=appointmentId;credit=candidate;}
        }
        try{policy=packagePaymentQuote(agreedTotal,s.selectedGowns.length,credit?.amountCents ?? 0);}catch{check(false,'PACKAGE_PRICE_REVIEW_REQUIRED');}
        check(input.depositCents===policy.depositCents,'DEPOSIT_QUOTE_CHANGED');
      }
      if(!waived)check(fittingFitsRental(booking,s.rentalPlan,this.now()),'FITTING_DATE_CONFLICT');
      const old=s.rentalId ? await tx.get(`rentals/${s.rentalId}`) : null;
      check(!old || ['Cancelled','Expired'].includes(old.state) || (old.state==='Held' && old.expiresAt<=this.now()),'RENTAL_ALREADY_EXISTS');
      const priorInvoice=s.invoiceId ? await tx.get(`sandboxInvoices/${s.invoiceId}`) : null;
      check(!priorInvoice || (priorInvoice.rentalId && ['Quoted','Unpaid','Pending'].includes(priorInvoice.state)),'PACKAGE_PAYMENT_REVIEW_REQUIRED');
      for (const g of s.selectedGowns) {
        const d=await tx.get(`dresses/${g.dressId}`);
        check(d?.published && d.availability==='Available' && d.sizes.split(', ').includes(g.size),'DRESS_UNAVAILABLE');
      }
      for(const a of s.selectedAccessories) check(accessoryCatalogue.items.some(v=>v.id===a.id),'ACCESSORY_CATALOGUE_CHANGED');
      const now=this.now(),dates=packageDates(s,s.rentalPlan,now);
      const resources=await this.checkResources(tx,s,dates,now,{strict:true});
      const commitPromotion=await preparePromotion(tx,s,rentalId,now+HOLD_MS,now);
      const fittingQuote=s.fittingQuote?.servicePlan?.some(row=>row.schedule)
        ? fittingPresentation(s).fittingQuote : s.fittingQuote;
      const rental={id:rentalId,uid:s.uid,appointmentId:input.appointmentId,invoiceId,packageSelectionId:selectionId,fingerprint,
        ...(waived?{fittingWaiver:{state:'Approved',uid:s.uid,acceptedAt:s.fittingChoice.acceptedAt,approvedAt:s.fittingDecision.recordedAt,approvedBy:s.fittingDecision.by}}:{}),
        gowns:s.selectedGowns,accessories:s.selectedAccessories,...s.rentalPlan,...dates,depositCents:input.depositCents,totalCents:agreedTotal,
        ...(s.fittingWorkflowVersion===2?{fittingQuote,packageBaseCents:s.totalCents,fittingAdjustmentsRequired:s.fittingDecision.adjustment!=='None'}:{}),
        ...(s.promotion?{promotion:s.promotion}:{}),
        balanceCents:agreedTotal-input.depositCents,...policy,fittingCreditId:creditId,state:'Held',paymentState:'AwaitingDeposit',createdBy:uid,createdAt:now,expiresAt:now+HOLD_MS};
      commitPromotion();
      if(credit)tx.set(`fittingCredits/${creditId}`,{...credit,reservedBy:rentalId,reservedUntil:rental.expiresAt});
      for(const {path,variant} of resources) {
        const allocations=Object.fromEntries(Object.entries(variant.allocations??{}).filter(([,a])=>consumesStock(a,now) && a.endDay>Math.floor((now+8*3600000)/86400000)));
        check(Object.keys(allocations).length<1000,'INVENTORY_REVIEW_REQUIRED');
        allocations[rentalId]={...dates,quantity:1,state:'Held',expiresAt:rental.expiresAt};
        tx.set(path,{...variant,allocations});
      }
      tx.set(`rentals/${rentalId}`,rental);
      tx.set(`sandboxInvoices/${invoiceId}`,{id:invoiceId,uid:s.uid,customerName:s.customerName,appointmentId:input.appointmentId,
        rentalId,packageSelectionId:selectionId,paymentPhase:'Deposit',purpose:'BookingDeposit',title:`Booking deposit: ${s.name}`,
        amountCents:input.depositCents,state:'Quoted',environment:'sandbox',holdExpiresAt:rental.expiresAt,createdAt:now,createdBy:uid});
      tx.set(`packageSelections/${selectionId}`,{...s,rentalId,invoiceId,balanceInvoiceId:null,
        ...(s.fittingWorkflowVersion===2?{fittingAgreedTotalCents:agreedTotal,fittingAgreedContext:s.fittingQuote.context}: {})});
      return rental;
    });
  }
}
