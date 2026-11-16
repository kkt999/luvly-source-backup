import {rentalResources,peakUsage} from './rental_service.mjs';
import {fittingFitsRental,hasFittingWaiver} from './booking_dates.mjs';
import {HttpError} from './payment_service.mjs';
const check=(ok,code)=>{if(!ok)throw new HttpError(409,code);};
export function extensionHolds(r,dates,extensionId,expiresAt){
  const ranges=[];
  if(dates.startDay<r.startDay)ranges.push([dates.startDay,Math.min(dates.endDay,r.startDay)]);
  if(dates.endDay>r.endDay)ranges.push([Math.max(dates.startDay,r.endDay),dates.endDay]);
  return ranges.filter(([start,end])=>start<end).map(([startDay,endDay],i)=>({key:`extension_${extensionId}_${i}`,startDay,endDay,quantity:1,state:'Held',expiresAt}));
}
export async function prepareExtensionClose(tx,r,e,state,now){
  const invoice=await tx.get(`sandboxInvoices/${e.invoiceId}`),rows=[];
  for(const resource of rentalResources(r)){rows.push({...resource,v:await tx.get(resource.path)});}
  return ()=>{
    for(const {path,v}of rows){if(!v)continue;const allocations={...v.allocations};for(const h of e.holds??[])delete allocations[h.key];tx.set(path,{...v,allocations});}
    tx.set(`rentalExtensions/${e.id}`,{...e,state,closedAt:now});
    if(invoice&&invoice.state!=='SandboxPaid')tx.set(`sandboxInvoices/${e.invoiceId}`,{...invoice,paymentBlocked:true});
    if(r.pendingExtension?.id===e.id)tx.set(`rentals/${r.id}`,{...r,pendingExtension:null,lastExtensionOutcome:state,updatedAt:now});
  };
}
export async function settleRentalExtension(tx,invoice,result,booking,r,now){
  const e=invoice.extensionId?await tx.get(`rentalExtensions/${invoice.extensionId}`):null;
  check(e?.invoiceId===invoice.id&&e.uid===invoice.uid&&e.rentalId===r?.id&&e.amountCents===result.amountCents&&invoice.packageSelectionId===r.packageSelectionId,'EXTENSION_PAYMENT_BINDING');
  if(e.state==='Applied')return null;
  const s=await tx.get(`packageSelections/${r.packageSelectionId}`),rows=[];
  let valid=e.state==='AwaitingPayment'&&e.expiresAt>now&&r.pendingExtension?.id===e.id&&r.state==='Locked'&&!r.collectedAt&&!r.returnedAt&&
    invoice.extensionAcceptedBy===r.uid&&Number.isFinite(invoice.extensionAcceptedAt)&&
    (r.dateRevision??0)===e.revision&&s?.uid===r.uid&&s.rentalId===r.id&&(!e.plan.pickupDate||e.plan.pickupDate>=new Date(now+8*3600000).toISOString().slice(0,10))&&
    (hasFittingWaiver(r)||booking?.uid===r.uid&&booking.status==='Completed'&&fittingFitsRental(booking,e.plan,now));
  for(const invoiceId of [r.invoiceId,r.balanceInvoiceId,r.securityInvoiceId].filter(Boolean)){const i=await tx.get(`sandboxInvoices/${invoiceId}`);if(!i||i.reviewReason||i.state==='ReviewRequired'||invoiceId===r.invoiceId&&i.state!=='SandboxPaid')valid=false;}
  for(const appointmentId of s?.appointmentIds??[]){const visit=await tx.get(`appointments/${appointmentId}`);
    if(visit?.uid===r.uid&&(['Completed','Confirmed','Requested'].includes(visit.status)||visit.status==='AwaitingPayment'&&visit.paymentExpiresAt>now)&&!fittingFitsRental(visit,e.plan,now))valid=false;}
  for(const resource of rentalResources(r)){
    const v=await tx.get(resource.path),allocations=v?.allocations??{},own=allocations[r.id];
    const exclude=new Set([r.id,...(e.holds??[]).map(h=>h.key)]);
    const others=Object.fromEntries(Object.entries(allocations).filter(([key])=>!exclude.has(key)));
    if(!own||own.state!=='Locked'||own.startDay!==r.startDay||own.endDay!==r.endDay||!Number.isInteger(v?.quantity)||v.quantity<1||
      peakUsage(others,e.dates.startDay,e.dates.endDay,now)+1>v.quantity||v.outstanding?.[r.id]||
      (e.holds??[]).some(h=>allocations[h.key]?.state!=='Held'||allocations[h.key]?.expiresAt!==e.expiresAt||allocations[h.key]?.startDay!==h.startDay||allocations[h.key]?.endDay!==h.endDay))valid=false;
    rows.push({...resource,v});
  }
  if(!valid){
    for(const {path,v}of rows){if(!v)continue;const allocations={...v.allocations};for(const h of e.holds??[])delete allocations[h.key];tx.set(path,{...v,allocations});}
    tx.set(`rentalExtensions/${e.id}`,{...e,state:'PaymentReview',closedAt:now});
    if(r.pendingExtension?.id===e.id)tx.set(`rentals/${r.id}`,{...r,pendingExtension:null,lastExtensionOutcome:'PaymentReview',updatedAt:now});
    return 'Extension paid after expiry, cancellation or changed rental/stock; original dates retained. Staff refund review required';
  }
  const change={...e.change,at:now,invoiceId:invoice.id,extensionId:e.id};
  for(const {path,v}of rows){const allocations={...v.allocations,[r.id]:{...v.allocations[r.id],...e.dates}};for(const h of e.holds??[])delete allocations[h.key];tx.set(path,{...v,allocations});}
  tx.set(`rentalExtensions/${e.id}`,{...e,state:'Applied',paidAt:now});
  tx.set(`rentals/${r.id}`,{...r,...e.plan,...e.dates,pendingExtension:null,dateRevision:e.revision+1,
    extensionDaysPaid:(r.extensionDaysPaid??0)+e.extraDays,extensionPaidCents:(r.extensionPaidCents??0)+e.amountCents,
    extensionInvoiceIds:[...(r.extensionInvoiceIds??[]),invoice.id],dateChangesCount:(r.dateChangesCount??0)+1,
    originalRentalPlan:r.originalRentalPlan??e.change.before,dateChangeHistory:[...(r.dateChangeHistory??[]),change].slice(-20),lastExtensionOutcome:'Applied',updatedAt:now});
  tx.set(`packageSelections/${r.packageSelectionId}`,{...s,rentalPlan:e.plan,rentalPlanRevision:(s.rentalPlanRevision??0)+1,lastRentalDateChange:change,rentalDateRevision:e.revision+1});
  tx.set(e.receiptPath,{...e.change,state:'Applied',rentalId:r.id,uid:r.uid,revision:e.revision+1});
  return null;
}
