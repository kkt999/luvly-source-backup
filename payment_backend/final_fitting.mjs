import {HttpError} from './payment_service.mjs';
import {hasAppointmentStaffAccess} from './appointment_access.mjs';
import {effectiveVisitTime,malaysiaDay} from './booking_dates.mjs';
const check=(ok,code,status=409)=>{if(!ok)throw new HttpError(status,code);};
const ms=v=>v?.toMillis?.()??+v;
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
export const finalFittingRequired=r=>r?.fittingQuote?.adjustmentPlan?.followUp==='Required';
export function finalFittingComplete(r,progress) {
  return !finalFittingRequired(r)||r.finalFitting?.state==='Completed'&&
    progress?.rentalId===r.id&&progress.alteration==='Completed'&&
    r.finalFitting.alterationVersion===(progress.alterationVersion??progress.revision);
}

// Records a real post-booking visit, not a replacement initial fitting.
export async function recordFinalFitting(workflow,uid,selectionId,input){
  check(id(selectionId)&&input&&Object.keys(input).every(k=>['requestId','rentalId','appointmentId','confirmed','note'].includes(k))&&
    id(input.requestId)&&id(input.rentalId)&&id(input.appointmentId)&&input.confirmed===true&&
    typeof input.note==='string'&&input.note.trim().length>=10&&input.note.length<=700,'INVALID_FINAL_FITTING',400);
  return workflow.store.atomic(async tx=>{
    const actor=await tx.get(`staff/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
    check(actor?.active===true&&['staff','manager'].includes(actor.role),'STAFF_REQUIRED',403);
    check(s?.rentalId===input.rentalId,'RENTAL_PLAN_CHANGED');
    const r=await tx.get(`rentals/${input.rentalId}`),p=await tx.get(`rentalServiceProgress/${selectionId}`);
    check(r?.uid===s.uid&&r.packageSelectionId===selectionId,'RENTAL_PLAN_CHANGED');
    const b=await tx.get(`appointments/${input.appointmentId}`);
    if (b) check(await hasAppointmentStaffAccess(tx, uid, actor, b), 'BOOKING_ACCESS_DENIED',403);
    const link=await tx.get(`packageAppointments/${input.appointmentId}`);
    check(input.appointmentId!==r.appointmentId&&s.appointmentIds.includes(input.appointmentId)&&b?.uid===s.uid&&
      link?.selectionId===selectionId&&b.type==='Dress Trial'&&['Confirmed','Completed'].includes(b.status)&&
      b.feeIncluded===true&&!b.fittingInvoiceId&&ms(b.createdAt)>=r.createdAt,'FINAL_FITTING_VISIT_REQUIRED');
    const fingerprint=JSON.stringify([input.appointmentId,input.note.trim()]);
    if(r.finalFitting?.requestId===input.requestId){check(r.finalFitting.by===uid&&r.finalFitting.fingerprint===fingerprint,'REQUEST_CONFLICT');return {finalFitting:r.finalFitting};}
    check(r.state==='Locked'&&!r.collectedAt&&!r.returnedAt&&finalFittingRequired(r),'FINAL_FITTING_NOT_REQUIRED');
    check(p?.rentalId===r.id&&p.alteration==='Completed','FITTING_ADJUSTMENTS_PENDING');
    check(!finalFittingComplete(r,p),'FINAL_FITTING_ALREADY_RECORDED');
    const now=workflow.now();
    const attended=b.status==='Completed'?ms(effectiveVisitTime(b)):now;
    check(Number.isFinite(attended)&&attended>=r.createdAt&&attended>=(p.alterationChangedAt??p.updatedAt)&&attended<=now&&
      malaysiaDay(attended)<=r.pickupDate&&malaysiaDay(now)<=r.pickupDate,'FINAL_FITTING_DATE_CONFLICT');
    const day=malaysiaDay(ms(b.startAt)),hour=new Date(ms(b.startAt)+8*3600000).getUTCHours();
    const path=`appointmentAvailability/${day}`,availability=await tx.get(path),slot=await tx.get(`appointmentSlots/${b.slotKey}`),bride=await tx.get(`brides/${s.uid}`);
    const finalFitting={state:'Completed',requestId:input.requestId,fingerprint,appointmentId:input.appointmentId,
      alterationVersion:p.alterationVersion??p.revision,actualAt:attended,recordedAt:now,by:uid,note:input.note.trim()};
    if(b.status!=='Completed'){
      const next={...b,status:'Completed',actualAttendedAt:new Date(now),completedAt:new Date(now),revision:b.revision+1,
        attendanceNote:input.note.trim(),updatedBy:uid,updatedAt:new Date(now)};
      if(slot?.appointmentId===input.appointmentId)tx.delete(`appointmentSlots/${b.slotKey}`);
      if(availability?.bookings?.[hour]?.appointmentId===input.appointmentId){const bookings={...availability.bookings};delete bookings[hour];tx.set(path,{...availability,bookings,revision:availability.revision+1});}
      tx.set(`appointments/${input.appointmentId}`,next);
      workflow.bookings.email(tx,input.appointmentId,{...next,startAt:new Date(now)},bride,'Completed');
    }
    tx.set(`rentals/${r.id}`,{...r,finalFitting,finalFittingHistory:[...(r.finalFittingHistory??[]),...(r.finalFitting?[r.finalFitting]:[])].slice(-20)});
    tx.set(`finalFittingAudit/${r.id}_${input.requestId}`,{...finalFitting,rentalId:r.id,selectionId,uid:s.uid});
    return {finalFitting};
  });
}
