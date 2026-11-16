import {HttpError} from './payment_service.mjs';
const check=(ok,code,status=409)=>{if(!ok)throw new HttpError(status,code);};
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
export const closedPayment=(invoice,booking,rental)=>invoice.purpose==='FittingFee'
  ?booking?.uid===invoice.uid&&booking.fittingInvoiceId===invoice.id&&['Cancelled','NoShow','Expired'].includes(booking.status)
  :rental?.uid===invoice.uid&&['Cancelled','Expired'].includes(rental.state)&&
    [rental.invoiceId,rental.balanceInvoiceId,rental.securityInvoiceId,...(rental.extensionInvoiceIds??[])].includes(invoice.id);
export const reviewablePayment=(i,b,r,now)=>i?.environment==='sandbox'&&i.state==='SandboxPaid'&&typeof i.invoiceNo==='string'&&!!i.invoiceNo.trim()&&
  Number.isSafeInteger(i.paidAt)&&i.paidAt>0&&i.paidAt<=now&&Number.isSafeInteger(i.amountCents)&&i.amountCents>0&&!i.reviewResolution&&closedPayment(i,b,r);

// Reconciles an actual manual refund/retention decision, never initiates a
// transfer, declares unverified payment successful or reinstates stock/credit.
export async function resolvePaymentReview(service,uid,invoiceId,input){
  check(id(invoiceId)&&input&&Object.keys(input).every(k=>['requestId','refundCents','reason','reference','confirmed'].includes(k))&&
    id(input.requestId)&&Number.isSafeInteger(input.refundCents)&&input.refundCents>=0&&input.confirmed===true&&
    typeof input.reason==='string'&&input.reason.trim().length>=10&&input.reason.length<=700&&
    typeof input.reference==='string'&&input.reference.length<=100&&
    (input.refundCents===0?input.reference==='':input.reference.trim().length>=5),'INVALID_PAYMENT_RESOLUTION',400);
  return service.store.atomic(async tx=>{
    const actor=await tx.get(`staff/${uid}`),i=await tx.get(`sandboxInvoices/${invoiceId}`);
    check(actor?.active===true&&actor.role==='manager','MANAGER_REQUIRED',403);
    check(!!i,'INVOICE_NOT_FOUND',404);
    const fingerprint=JSON.stringify([input.refundCents,input.reason.trim(),input.reference.trim()]);
    if(i.reviewResolution?.requestId===input.requestId){check(i.reviewResolution.by===uid&&i.reviewResolution.fingerprint===fingerprint,'REQUEST_CONFLICT');return i;}
    const b=i.appointmentId?await tx.get(`appointments/${i.appointmentId}`):null,r=i.rentalId?await tx.get(`rentals/${i.rentalId}`):null;
    check(reviewablePayment(i,b,r,service.now()),'PAYMENT_RESOLUTION_NOT_AVAILABLE');
    check(input.refundCents<=i.amountCents,'INVALID_PAYMENT_RESOLUTION',400);
    const credit=i.purpose==='FittingFee'?await tx.get(`fittingCredits/${i.appointmentId}`):null;
    check(!credit?.consumedBy&&(!credit?.reservedBy||credit.reservedUntil<=service.now()),'FITTING_CREDIT_IN_USE');
    const other=[];
    if(r)for(const key of new Set([r.invoiceId,r.balanceInvoiceId,r.securityInvoiceId,...(r.extensionInvoiceIds??[])].filter(v=>v&&v!==invoiceId)))other.push(await tx.get(`sandboxInvoices/${key}`));
    const resolution={requestId:input.requestId,fingerprint,state:input.refundCents===0?'Retained':input.refundCents===i.amountCents?'RefundRecorded':'PartialRefundRecorded',
      refundCents:input.refundCents,retainedCents:i.amountCents-input.refundCents,reason:input.reason.trim(),reference:input.reference.trim(),
      by:uid,recordedAt:service.now(),previousReviewReason:i.reviewReason??null,environment:'sandbox-record-only'};
    const next={...i,reviewResolution:resolution,reviewReason:null,paymentBlocked:true};
    tx.set(`sandboxInvoices/${invoiceId}`,next);
    tx.set(`paymentResolutionAudit/${invoiceId}`,{...resolution,invoiceId,uid:i.uid,amountCents:i.amountCents});
    if(credit)tx.set(`fittingCredits/${i.appointmentId}`,{...credit,voidedAt:service.now(),reservedBy:null,reservedUntil:0});
    if(i.purpose==='FittingFee')tx.set(`appointments/${i.appointmentId}`,{...b,refundReviewRequired:false,paymentReviewResolvedAt:service.now()});
    if(r){
      const pending=other.some(v=>!v||v.state==='ReviewRequired'||v.state==='SandboxPaid'&&!v.reviewResolution);
      tx.set(`rentals/${i.rentalId}`,{...r,refundReviewRequired:pending,...(!pending?{reviewReason:null}:{}),paymentReviewUpdatedAt:service.now()});
    }
    return next;
  });
}
