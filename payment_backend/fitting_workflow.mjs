import {HttpError} from './payment_service.mjs';
import {hasAppointmentStaffAccess,hasBoutiqueOperationsAccess} from './appointment_access.mjs';
import {BookingService} from './booking_service.mjs';
import {effectiveVisitTime,fittingFitsRental,malaysiaDay} from './booking_dates.mjs';
import {quoteFitting,respondFitting} from './fitting_proposals.mjs';
import {validateFittingAssessment} from './fitting_assessment.mjs';
import {recordFinalFitting} from './final_fitting.mjs';
import {fittingGownOptions,validateGownChange,prepareFittingGownChange} from './fitting_gown_change.mjs';
import {requiresServiceTiming,requiresAccessorySelection} from './package_service_types.mjs';
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
const check=(v,code,status=409)=>{if(!v)throw new HttpError(status,code);};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>keys.includes(k));
const ms=v=>v?.toMillis?.()??+v;
const active=s=>s?.active===true&&['staff','manager'].includes(s.role);
export class FittingWorkflow{
  constructor({store,now=Date.now}){Object.assign(this,{store,now});this.bookings=new BookingService({store,now,feePolicy:true});}
  quote(uid,selectionId,input){return quoteFitting(this,uid,selectionId,input);}
  respond(uid,selectionId,input){return respondFitting(this,uid,selectionId,input);}
  final(uid,selectionId,input){return recordFinalFitting(this,uid,selectionId,input);}
  gownOptions(uid,selectionId,input){return fittingGownOptions(this,uid,selectionId,input);}
  async intent(uid,selectionId,input){
    check(id(selectionId)&&exact(input,['revision','action'])&&Number.isSafeInteger(input.revision)&&['Review','Consider','Decline'].includes(input.action),'INVALID_FITTING_RESPONSE',400);
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
      check(!staff&&bride&&s?.uid===uid,'SELECTION_ACCESS_DENIED',403);check(!s.invoiceId&&!s.rentalId,'FITTING_ORDER_LOCKED');
      check(s.fittingDecision&&(s.fittingDecisionRevision??0)===input.revision,'FITTING_CHANGED');
      tx.set(`packageSelections/${selectionId}`,{...s,fittingWorkflowVersion:2,fittingQuote:null,fittingQuoteHistory:[...(s.fittingQuoteHistory??[]),...(s.fittingQuote?[s.fittingQuote]:[])].slice(-20),
        fittingDecision:{...s.fittingDecision,state:{Review:'AwaitingReview',Consider:'Considering',Decline:'Declined'}[input.action],customerAction:input.action,customerActionAt:this.now()},fittingDecisionRevision:input.revision+1});
      return {saved:true};
    });
  }
  async choice(uid,selectionId,input){
    check(id(selectionId)&&exact(input,['mode','accepted','revision'])&&['TryOn','SkipFitting'].includes(input.mode)&&
      typeof input.accepted==='boolean'&&Number.isInteger(input.revision),'INVALID_FITTING_CHOICE',400);
    check(input.mode!=='SkipFitting'||input.accepted,'FITTING_CONSENT_REQUIRED',400);
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
      check(!staff&&bride&&s?.uid===uid,'SELECTION_ACCESS_DENIED',403);
      const rental=s.rentalId?await tx.get(`rentals/${s.rentalId}`):null;
      check(!rental||['Expired','Cancelled'].includes(rental.state),'RENTAL_ALREADY_EXISTS');
      check(input.mode!=='SkipFitting'||!s.reusedFittingAppointmentId,'COMPLETED_FITTING_ALREADY_LINKED');
      const visits=[];for(const appointmentId of s.appointmentIds??[])visits.push(await tx.get(`appointments/${appointmentId}`));
      if(input.mode==='SkipFitting')check(!visits.some(a=>['Confirmed','Requested'].includes(a?.status)||a?.status==='AwaitingPayment'&&a.paymentExpiresAt>this.now()),'CANCEL_FITTING_FIRST');
      if(s.fittingChoice?.mode===input.mode)return {fittingChoice:s.fittingChoice,fittingChoiceRevision:s.fittingChoiceRevision};
      check((s.fittingChoiceRevision??0)===input.revision,'FITTING_CHANGED');
      const next={mode:input.mode,accepted:input.mode==='SkipFitting',acceptedAt:this.now(),by:uid};
      tx.set(`packageSelections/${selectionId}`,{...s,fittingWorkflowVersion:s.fittingWorkflowVersion===2?2:1,fittingQuote:null,fittingChoice:next,fittingChoiceRevision:input.revision+1,
        fittingDecisionHistory:[...(s.fittingDecisionHistory??[]),...(s.fittingDecision?[s.fittingDecision]:[])].slice(-20),
        fittingDecision:null,fittingDecisionRevision:(s.fittingDecisionRevision??0)+1});
      return {fittingChoice:next,fittingChoiceRevision:input.revision+1};
    });
  }
  async record(uid,selectionId,input){
    const modern=['Selected','Reselect','Considering','NotProceeding'].includes(input?.outcome);
    check(id(selectionId)&&exact(input,['requestId','revision','mode','outcome','appointmentId','confirmed','note','adjustment','assessment','gownChange'])&&id(input.requestId)&&
      Number.isInteger(input.revision)&&['Attended','Waived'].includes(input.mode)&&['Satisfied','NeedsChanges','Selected','Reselect','Considering','NotProceeding'].includes(input.outcome)&&
      input.confirmed===true&&typeof input.note==='string'&&input.note.trim().length>=10&&input.note.length<=700&&
      (input.mode==='Waived'||id(input.appointmentId)),'INVALID_FITTING_RESULT',400);
    check(!modern||['None','Basic','Assessment'].includes(input.adjustment),'INVALID_FITTING_RESULT',400);
    check(input.mode!=='Waived'||['Satisfied','Selected','NotProceeding'].includes(input.outcome),'INVALID_FITTING_RESULT',400);
    if(input.gownChange!==undefined){
      check(input.mode==='Attended'&&input.outcome==='Selected','INVALID_GOWN_SELECTION',400);
      validateGownChange(input.gownChange);
    }
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
      check(active(staff),'STAFF_REQUIRED',403);check(!!s,'SELECTION_ACCESS_DENIED',404);
      const booking = input.mode === 'Attended'
        ? await tx.get(`appointments/${input.appointmentId}`)
        : null;
      if (input.mode === 'Waived') {
        check(await hasBoutiqueOperationsAccess(tx, uid, staff), 'OPERATIONS_ACCESS_REQUIRED', 403);
      }
      const link = booking ? await tx.get(`packageAppointments/${input.appointmentId}`) : null;
      if (booking) {
        check(await hasAppointmentStaffAccess(tx, uid, staff, booking), 'BOOKING_ACCESS_DENIED',403);
      }
      if (input.mode === 'Attended') {
        check(booking?.uid===s.uid&&link?.selectionId===selectionId&&booking.type==='Dress Trial'&&
          ['Confirmed','Completed'].includes(booking.status),'CONFIRMED_APPOINTMENT_REQUIRED');
      }
      check(input.assessment===undefined||modern,'INVALID_FITTING_ASSESSMENT',400);
      const retry=s.fittingDecision?.requestId===input.requestId;
      if(input.gownChange&&!retry)check(!s.invoiceId&&!s.rentalId,'FITTING_ORDER_LOCKED');
      const changed=input.gownChange&&!retry?await prepareFittingGownChange(tx,s,input.gownChange,uid,this.now()):s;
      const assessment=validateFittingAssessment(input.assessment,changed,{...input,now:retry?s.fittingDecision.recordedAt:this.now()});
      const fingerprint=JSON.stringify([input.mode,input.outcome,input.appointmentId??'',input.note.trim(),...(modern?[input.adjustment]:[]),...(assessment?[assessment]:[]),...(input.gownChange?[input.gownChange]:[])]);
      if(s.fittingDecision?.requestId===input.requestId){
        check(s.fittingDecision.fingerprint===fingerprint,'REQUEST_CONFLICT');return {fittingDecision:s.fittingDecision};}
      check((s.fittingDecisionRevision??0)===input.revision,'FITTING_CHANGED');
      const typedServiceNeedsProposal = s.services?.some(service => service.serviceType !== undefined &&
        (requiresServiceTiming(service) || requiresAccessorySelection(service)));
      check(modern || (s.fittingWorkflowVersion !== 2 && !typedServiceNeedsProposal), 'FITTING_CLIENT_UPDATE_REQUIRED');
      if(modern)check(!s.invoiceId&&!s.rentalId,'FITTING_ORDER_LOCKED');
      const rental=s.rentalId?await tx.get(`rentals/${s.rentalId}`):null;
      check(!rental||['Cancelled','Expired'].includes(rental.state),'RENTAL_ALREADY_EXISTS');
      const now=this.now();
      let slot,availability,bride,path,hour;
      if(input.mode==='Waived'){
        check(s.fittingChoice?.mode==='SkipFitting'&&s.fittingChoice.accepted===true,'FITTING_CONSENT_REQUIRED');
        for(const appointmentId of s.appointmentIds??[]){const a=await tx.get(`appointments/${appointmentId}`);check(!['Confirmed','Requested'].includes(a?.status)&&!(a?.status==='AwaitingPayment'&&a.paymentExpiresAt>now),'CANCEL_FITTING_FIRST');}
      }else{
        check(s.fittingChoice?.mode!=='SkipFitting','FITTING_CHOICE_CONFLICT');
        check(booking.status!=='Completed'||ms(effectiveVisitTime(booking))<=now,'FITTING_DATE_CONFLICT');
        const fee=booking.fittingInvoiceId?await tx.get(`sandboxInvoices/${booking.fittingInvoiceId}`):null;
        check(!booking.fittingInvoiceId||fee?.state==='SandboxPaid'&&fee.environment==='sandbox'&&!fee.reviewReason&&fee.uid===s.uid&&fee.appointmentId===input.appointmentId&&fee.purpose==='FittingFee'&&fee.amountCents===5000&&typeof fee.invoiceNo==='string'&&!!fee.invoiceNo.trim(),'FITTING_FEE_REVIEW');
        const start=ms(booking.startAt);check(Number.isFinite(start),'INVALID_FITTING_RESULT');
        slot=await tx.get(`appointmentSlots/${booking.slotKey}`);
        path=`appointmentAvailability/${malaysiaDay(start)}`;availability=await tx.get(path);hour=new Date(start+8*3600000).getUTCHours();
        bride=await tx.get(`brides/${s.uid}`);
      }
      const visitForDates=booking?.status==='Completed'?booking:{status:'Completed',actualAttendedAt:now};
      check(modern&&input.outcome!=='Selected'||s.rentalPlan&&(input.mode==='Attended'?fittingFitsRental(visitForDates,s.rentalPlan,now):
        malaysiaDay(now)<=s.rentalPlan.pickupDate&&malaysiaDay(now)<=s.rentalPlan.eventDate),'FITTING_DATE_CONFLICT');
      const decision={requestId:input.requestId,fingerprint,mode:input.mode,outcome:input.outcome,...(modern?{adjustment:input.adjustment,selectedGowns:changed.selectedGowns??[]}:{}),
        ...(input.gownChange?{gownChange:{from:s.selectedGowns??[],to:changed.selectedGowns}}:{}),...(assessment?{assessment}:{}),state:modern?{Selected:'QuoteNeeded',Reselect:'Reselect',Considering:'Considering',NotProceeding:'Declined'}[input.outcome]:input.outcome==='Satisfied'?'Approved':'NeedsChanges',
        actualAt:booking?.status==='Completed'?ms(effectiveVisitTime(booking)):now,recordedAt:now,by:uid,note:input.note.trim(),appointmentId:input.mode==='Attended'?input.appointmentId:null};
      if(booking&&booking.status!=='Completed'){
        const next={...booking,status:'Completed',actualAttendedAt:new Date(now),completedAt:new Date(now),attendanceNote:input.note.trim(),
          revision:booking.revision+1,updatedBy:uid,updatedAt:new Date(now)};
        if(slot?.appointmentId===input.appointmentId)tx.delete(`appointmentSlots/${booking.slotKey}`);
        if(availability?.bookings?.[hour]?.appointmentId===input.appointmentId){const bookings={...availability.bookings};delete bookings[hour];tx.set(path,{...availability,bookings,revision:availability.revision+1});}
        tx.set(`appointments/${input.appointmentId}`,next);
        this.bookings.email(tx,input.appointmentId,{...next,startAt:new Date(now)},bride,'Completed');
      }
      tx.set(`packageSelections/${selectionId}`,{...changed,fittingWorkflowVersion:modern?2:1,...(modern?{fittingQuote:null,fittingQuoteHistory:[...(s.fittingQuoteHistory??[]),...(s.fittingQuote?[s.fittingQuote]:[])].slice(-20)}:{}),fittingDecisionHistory:[...(s.fittingDecisionHistory??[]),...(s.fittingDecision?[s.fittingDecision]:[])].slice(-20),fittingDecision:decision,fittingDecisionRevision:input.revision+1});
      return {fittingDecision:decision,fittingDecisionRevision:input.revision+1};
    });
  }
}
