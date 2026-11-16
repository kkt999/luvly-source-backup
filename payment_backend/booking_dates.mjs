// All cross-module comparisons use Malaysia calendar dates, not host timezone.
export function malaysiaDay(value) {
  const ms=value?.toMillis?.() ?? +value;
  return Number.isFinite(ms) ? new Date(ms+8*3600000).toISOString().slice(0,10) : null;
}
export function fittingBeforeRental(start,plan) {
  const day=malaysiaDay(start);
  return !!day && typeof plan?.pickupDate==='string' && typeof plan?.eventDate==='string' && day<plan.pickupDate && day<plan.eventDate;
}
export const effectiveVisitTime=booking=>booking?.actualAttendedAt??booking?.startAt;
// Only recorded attendance can justify collection on the fitting day. A
// scheduled/confirmed visit (or a legacy Completed flag alone) cannot do so.
export function fittingFitsRental(booking,plan,now) {
  const actual=booking?.actualAttendedAt;
  if(booking?.status==='Completed'&&actual!=null){
    const attendedAt=actual?.toMillis?.()??+actual;
    const day=malaysiaDay(actual);
    return Number.isFinite(attendedAt)&&Number.isFinite(now)&&attendedAt<=now&&!!day&&
      typeof plan?.pickupDate==='string'&&typeof plan?.eventDate==='string'&&
      day<=plan.pickupDate&&day<plan.eventDate;
  }
  if(booking?.feeIncluded===true){
    const day=malaysiaDay(effectiveVisitTime(booking));
    return !!day&&typeof plan?.pickupDate==='string'&&typeof plan?.eventDate==='string'&&day<=plan.pickupDate&&day<plan.eventDate;
  }
  return fittingBeforeRental(effectiveVisitTime(booking),plan);
}
export function hasFittingWaiver(rental){
  const w=rental?.fittingWaiver;
  return !!rental?.packageSelectionId && !rental.appointmentId && w?.state==='Approved' &&
    w.uid===rental.uid && Number.isFinite(w.acceptedAt) && Number.isFinite(w.approvedAt) && w.acceptedAt<=w.approvedAt && typeof w.approvedBy==='string' && w.approvedBy.length>0;
}
