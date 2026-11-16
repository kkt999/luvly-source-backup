import test from 'node:test';
import assert from 'node:assert/strict';
import {BookingService} from './booking_service.mjs';
import {PaymentService} from './payment_service.mjs';
import {PackageService} from './package_service.mjs';
import {PackageRentals} from './package_rentals.mjs';
import {RentalService,variantId,HOLD_MS} from './rental_service.mjs';
import {packagePaymentQuote} from './bridal_payment_policy.mjs';
import {createServer} from 'node:http';
import {createHandler} from './http_app.mjs';
class Store{
 data=new Map();queue=Promise.resolve();
 async get(p){return structuredClone(this.data.get(p));}
 async list(c,uid){return [...this.data].filter(([p,d])=>p.startsWith(c+'/') && (uid===undefined || d.uid===uid)).map(([,d])=>structuredClone(d));}
 async activeStaffIds(){return ['staff','manager'];}
 atomic(fn){const run=this.queue.then(async()=>{const writes=new Map();let writing=false;
  const v=await fn({get:p=>{assert.equal(writing,false,'Firestore reads must precede ALL writes');return this.get(p);},set:(p,d)=>{writing=true;writes.set(p,structuredClone(d));},delete:p=>{writing=true;writes.set(p,null);}});
  for(const[p,d]of writes){if(d===null)this.data.delete(p);else this.data.set(p,d);}return v;
 });this.queue=run.catch(()=>{});return run;}
}
function fixture(){
 const store=new Store();let now=Date.parse('2026-10-14T00:00:00Z');const clock=()=>now;
 for(const[p,v]of Object.entries({'staffScheduling/staff':{jobRole:'FrontDesk',serviceTypes:['Dress Trial','Bridal Consultation']},'staff/staff':{role:'staff',active:true},'staff/manager':{role:'manager',active:true},
 'brides/bride':{name:'Demo',phone:'0123456789',email:'example@example.com'},'brides/other':{name:'Other',phone:'0123456789',email:'other@example.com'},
 'dresses/gown':{published:true,availability:'Available',sizes:'M'},
 [`rentalVariants/${variantId('gown','M')}`]:{id:variantId('gown','M'),quantity:1,allocations:{},revision:1}}))store.data.set(p,v);
 const bookings=new BookingService({store,now:clock,feePolicy:true}),rentals=new RentalService({store,now:clock});
 const payments=new PaymentService({store,bookings,rentals,now:clock,gateway:{createBill:async p=>({...p,billCode:'bill',checkoutUrl:'https://dev.toyyibpay.com/bill',environment:'sandbox'})}});
 const packages=new PackageService({store,bookings,paymentService:payments,now:clock}),workflow=new PackageRentals({store,rentals,now:clock,paymentPolicy:true});
 const input={requestId:'request',type:'Dress Trial',startAt:Date.parse('2026-10-15T02:00:00Z'),notes:'',feePolicyVersion:1};
 const selection={id:'selection',uid:'bride',customerName:'Demo',name:'Bridal',totalCents:89900,services:[],selectedGowns:[{dressId:'gown',size:'M',name:'Gown'}],selectedAccessories:[],appointmentIds:[],invoiceId:null,
  rentalPlanRevision:1,rentalPlan:{pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18'}};
 store.data.set('packageSelections/selection',selection);
 async function paid(id){let i=store.data.get(`sandboxInvoices/${id}`);if(!i.billCode){await payments.checkout('bride',id);i=store.data.get(`sandboxInvoices/${id}`);}
  return payments.applyResult(id,i.billCode,{state:'SandboxPaid',billCode:i.billCode,reference:i.reference,amountCents:i.amountCents,invoiceNo:'sandbox-receipt',environment:'sandbox'});
 }
 async function attended(){const b=await packages.book('bride','selection',input);await paid(b.invoiceId);now=input.startAt+3600000;
  const row=await store.get(`appointments/${b.appointmentId}`);await bookings.transition('staff',b.appointmentId,{status:'Completed',revision:row.revision,response:''});return b;}
 return {store,bookings,rentals,payments,packages,workflow,input,paid,attended,advance:n=>now+=n,setTime:n=>now=n};
}
const fails=c=>e=>e.code===c;

test('no-show requires active staff, ended scheduled hour and reason; never completes fitting or earns credit',async()=>{
 const f=fixture(),b=await f.packages.book('bride','selection',f.input);await f.paid(b.invoiceId);
 let row=await f.store.get(`appointments/${b.appointmentId}`);
 const input={status:'NoShow',revision:row.revision,response:'Customer did not attend the scheduled fitting.'};
 await assert.rejects(f.bookings.transition('bride',b.appointmentId,input),fails('INVALID_BOOKING_TRANSITION'));
 await assert.rejects(f.bookings.transition('staff',b.appointmentId,input),fails('INVALID_BOOKING_TRANSITION'));
 f.setTime(f.input.startAt+3600000);
 await assert.rejects(f.bookings.transition('staff',b.appointmentId,{...input,response:''}),fails('NO_SHOW_REASON_REQUIRED'));
 await f.bookings.transition('staff',b.appointmentId,input);
 row=await f.store.get(`appointments/${b.appointmentId}`);assert.equal(row.status,'NoShow');assert.equal(row.actualAttendedAt,undefined);assert.equal(row.refundReviewRequired,true);
 assert.equal(await f.store.get(`appointmentSlots/${row.slotKey}`),undefined);
 const s=(await f.packages.selections('staff')).selections[0];assert.equal(s.appointments[0].availableCreditCents,0);
 await assert.rejects(f.workflow.confirm('staff','selection',{appointmentId:b.appointmentId,requestId:'no-show-rent',planRevision:1,depositCents:39950}),fails('CONFIRMED_APPOINTMENT_REQUIRED'));
});

const resolution=(refundCents=5000)=>({requestId:'review',refundCents,reason:'Manager reviewed cancellation terms and discussed the outcome with the customer.',reference:refundCents?'REF-verified-001':'',confirmed:true});
async function cancelledFee(){const f=fixture(),b=await f.packages.book('bride','selection',f.input);await f.paid(b.invoiceId);const row=await f.store.get(`appointments/${b.appointmentId}`);
 await f.bookings.transition('bride',b.appointmentId,{status:'Cancelled',revision:row.revision,response:''});return {...f,b};}

test('manager reconciliation preserves original payment, closes review, voids unused credit and never invokes gateway',async()=>{
 const f=await cancelledFee();const before=await f.store.get(`sandboxInvoices/${f.b.invoiceId}`);
 assert.equal((await f.payments.details('manager',f.b.invoiceId)).canResolveReview,true);
 for(const actor of ['bride','other','staff'])await assert.rejects(f.payments.resolveReview(actor,f.b.invoiceId,resolution()),fails('MANAGER_REQUIRED'));
 const saved=await f.payments.resolveReview('manager',f.b.invoiceId,resolution());
 assert.equal(saved.state,'SandboxPaid');assert.equal(saved.amountCents,before.amountCents);assert.equal(saved.invoiceNo,before.invoiceNo);assert.equal(saved.reviewReason,undefined);
 assert.equal(saved.reviewResolution.state,'RefundRecorded');assert.equal(saved.reviewResolution.refundCents,5000);assert.equal(saved.reviewResolution.reason,undefined);
 assert.equal((await f.store.get(`appointments/${f.b.appointmentId}`)).refundReviewRequired,false);
 assert.ok((await f.store.get(`fittingCredits/${f.b.appointmentId}`)).voidedAt);assert.equal((await f.store.list('paymentResolutionAudit')).length,1);
 assert.deepEqual(await f.payments.resolveReview('manager',f.b.invoiceId,resolution()),saved);
 await assert.rejects(f.payments.resolveReview('manager',f.b.invoiceId,{...resolution(),reason:'A conflicting decision must not overwrite the original.'}),fails('REQUEST_CONFLICT'));
 await assert.rejects(f.payments.resolveReview('manager',f.b.invoiceId,{...resolution(),requestId:'duplicate'}),fails('PAYMENT_RESOLUTION_NOT_AVAILABLE'));
});

test('refund reconciliation rejects overpayment, missing evidence, unverified money and active bookings without writes',async()=>{
 const f=await cancelledFee(),before=structuredClone([...f.store.data]);
 for(const patch of [{refundCents:5001},{refundCents:-1},{refundCents:0.5},{reference:''},{confirmed:false},{reason:'x'},{uid:'other'}])
  await assert.rejects(f.payments.resolveReview('manager',f.b.invoiceId,{...resolution(),...patch}),fails('INVALID_PAYMENT_RESOLUTION'));
 assert.deepEqual([...f.store.data],before);
 f.store.data.get(`sandboxInvoices/${f.b.invoiceId}`).state='ReviewRequired';
 await assert.rejects(f.payments.resolveReview('manager',f.b.invoiceId,resolution()),fails('PAYMENT_RESOLUTION_NOT_AVAILABLE'));
 f.store.data.get(`sandboxInvoices/${f.b.invoiceId}`).state='SandboxPaid';f.store.data.get(`appointments/${f.b.appointmentId}`).status='Confirmed';
 await assert.rejects(f.payments.resolveReview('manager',f.b.invoiceId,resolution()),fails('PAYMENT_RESOLUTION_NOT_AVAILABLE'));
});

test('retained and partially refunded fitting outcomes are explicit, and consumed fitting credits cannot be refunded twice',async()=>{
 for(const amount of [0,2500]){
  const f=await cancelledFee();const result=await f.payments.resolveReview('manager',f.b.invoiceId,resolution(amount));
  assert.equal(result.reviewResolution.state,amount?'PartialRefundRecorded':'Retained');assert.equal(result.reviewResolution.retainedCents,5000-amount);
 }
 const f=await cancelledFee();f.store.data.get(`fittingCredits/${f.b.appointmentId}`).consumedBy='another-rental';
 await assert.rejects(f.payments.resolveReview('manager',f.b.invoiceId,resolution()),fails('FITTING_CREDIT_IN_USE'));
});

test('cancelled rental resolves each actual receipt before closing its review; no stock or invoice is revived',async()=>{
 const f=fixture(),b=await f.attended();
 let r=await f.workflow.confirm('staff','selection',{appointmentId:b.appointmentId,requestId:'r',planRevision:1,depositCents:39950});await f.paid(r.invoiceId);
 r=await f.store.get(`rentals/${r.id}`);await f.paid(r.securityInvoiceId);
 await f.rentals.cancel('staff',r.id);
 assert.ok((await f.store.get(`sandboxInvoices/${r.invoiceId}`)).reviewReason);
 assert.equal((await f.store.get(`sandboxInvoices/${r.balanceInvoiceId}`)).paymentBlocked,true);
 await f.payments.resolveReview('manager',r.invoiceId,resolution(0));assert.equal((await f.store.get(`rentals/${r.id}`)).refundReviewRequired,true);
 await f.payments.resolveReview('manager',r.securityInvoiceId,{...resolution(30000),requestId:'security'});
 assert.equal((await f.store.get(`rentals/${r.id}`)).refundReviewRequired,false);assert.equal((await f.store.get(`rentals/${r.id}`)).state,'Cancelled');
 assert.equal((await f.store.get(`rentalVariants/${variantId('gown','M')}`)).allocations[r.id],undefined);
 assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,r.id);
});

test('return issue records an unresolved case without returning, releasing stock or inventing charges',async()=>{
 const f=fixture(),b=await f.attended();let r=await f.workflow.confirm('staff','selection',{appointmentId:b.appointmentId,requestId:'r',planRevision:1,depositCents:39950});
 await f.paid(r.invoiceId);r=await f.store.get(`rentals/${r.id}`);await f.paid(r.balanceInvoiceId);await f.paid(r.securityInvoiceId);
 await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'report-return-issue',reason:'Veil is missing and must be reviewed.'}),fails('INVALID_RETURN_ISSUE'));
 f.setTime(Date.parse('2026-10-16T02:00:00Z'));await f.rentals.fulfil('staff',r.id,{action:'collect'});
 const count=(await f.store.list('sandboxInvoices')).length;
 const issue={action:'report-return-issue',reason:'Veil is missing and must be reviewed with the customer.'};
 await assert.rejects(f.rentals.fulfil('bride',r.id,issue),fails('STAFF_REQUIRED'));
 let result=await f.rentals.fulfil('staff',r.id,issue);assert.equal(result.returnIssue.state,'Open');assert.equal(result.returnedAt,undefined);
 assert.deepEqual(await f.rentals.fulfil('staff',r.id,issue),result);
 assert.equal((await f.store.get(`rentalVariants/${variantId('gown','M')}`)).outstanding[r.id],true);assert.equal((await f.store.list('sandboxInvoices')).length,count);
 result=await f.rentals.fulfil('staff',r.id,{action:'return',damageCents:0,lateCents:0,allReturned:true,reason:'All items now returned and checked.'});
 assert.equal(result.returnIssue.state,'ClosedAfterInspection');assert.equal(result.securityState,'RefundDue');
 assert.equal((await f.store.get(`rentalVariants/${variantId('gown','M')}`)).outstanding[r.id],undefined);
});

test('resolution HTTP authenticates and refuses query identity or forged financial authority',async t=>{
 const f=await cancelledFee(),server=createServer(createHandler({service:f.payments,verifyToken:async token=>({uid:token})}));
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
 const base=`http://127.0.0.1:${server.address().port}/v1/invoices/${f.b.invoiceId}/resolve-review`;
 const send=(url,body,actor)=>fetch(url,{method:'POST',headers:{'content-type':'application/json',...(actor?{authorization:`Bearer ${actor}`}:{})},body:JSON.stringify(body)});
 assert.equal((await send(base,resolution())).status,401);
 assert.equal((await send(base,resolution(),'staff')).status,403);
 assert.equal((await send(base+'?uid=manager',resolution(),'manager')).status,400);
 assert.equal((await send(base,{...resolution(),by:'manager'},'manager')).status,400);
 assert.equal((await send(base,resolution(),'manager')).status,200);
});
test('RM899 example reconciles exactly; security is separate; odd cents never disappear',()=>{
 assert.deepEqual(packagePaymentQuote(89900,1,5000),{policyVersion:1,depositTargetCents:44950,fittingCreditCents:5000,depositCents:39950,balanceCents:44950,securityCents:30000});
 const p=packagePaymentQuote(89901,2,5000);assert.equal(5000+p.depositCents+p.balanceCents,89901);assert.equal(p.securityCents,60000);
 assert.throws(()=>packagePaymentQuote(5000,1,5000));
});
test('fee consent, immutable RM50, idempotency, no confirmation/email before verified payment',async()=>{
 const f=fixture();await assert.rejects(f.bookings.create('bride',{...f.input,feePolicyVersion:undefined}),fails('PAYMENT_TERMS_REQUIRED'));
 const b=await f.bookings.create('bride',f.input);assert.equal(b.status,'AwaitingPayment');assert.equal((await f.store.get(`sandboxInvoices/${b.invoiceId}`)).amountCents,5000);
 assert.deepEqual(await f.bookings.create('bride',f.input),b);assert.equal([...f.store.data.keys()].some(p=>p.startsWith('appointmentMail/')),false);
 await assert.rejects(f.payments.checkout('other',b.invoiceId),fails('INVOICE_ACCESS_DENIED'));
 await f.paid(b.invoiceId);await f.paid(b.invoiceId);
 assert.equal((await f.store.get(`appointments/${b.appointmentId}`)).status,'Confirmed');
 assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).amountCents,5000);
 assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('appointmentMail/')).length,1);
});
test('unpaid expiry frees the exact slot; late verified payment cannot reclaim another booking',async()=>{
 const f=fixture(),b=await f.bookings.create('bride',f.input);await f.payments.checkout('bride',b.invoiceId);f.advance(HOLD_MS);
 const other=await f.bookings.create('other',f.input);assert.equal(other.status,'AwaitingPayment');
 const late=await f.paid(b.invoiceId);assert.ok(late.reviewReason);
 await f.bookings.expirePayment(b.appointmentId);assert.equal((await f.store.get(`appointmentSlots/${f.input.startAt}`)).appointmentId,other.appointmentId);
 assert.equal(await f.store.get(`fittingCredits/${b.appointmentId}`),undefined);
});
test('cancel paid fitting queues review, removes slot and prevents credit from cancelled attendance',async()=>{
 const f=fixture(),b=await f.bookings.create('bride',f.input);await f.paid(b.invoiceId);
 await f.bookings.transition('bride',b.appointmentId,{status:'Cancelled',revision:2,response:''});
 assert.equal((await f.store.get(`appointments/${b.appointmentId}`)).refundReviewRequired,true);assert.ok((await f.store.get(`sandboxInvoices/${b.invoiceId}`)).reviewReason);
 assert.equal(await f.store.get(`appointmentSlots/${f.input.startAt}`),undefined);
});
test('completed fitting required; RM50 reserved once, verified deposit consumes it and creates exact balance/security',async()=>{
 const f=fixture(),b=await f.packages.book('bride','selection',f.input);await f.paid(b.invoiceId);
 const input={appointmentId:b.appointmentId,requestId:'rental',planRevision:1,depositCents:39950};
 await assert.rejects(f.workflow.confirm('staff','selection',input),fails('COMPLETED_FITTING_REQUIRED'));
 f.setTime(f.input.startAt+3600000);await f.bookings.transition('staff',b.appointmentId,{status:'Completed',revision:2,response:''});
 await assert.rejects(f.workflow.confirm('staff','selection',{...input,depositCents:10000}),fails('DEPOSIT_QUOTE_CHANGED'));
 const r=await f.workflow.confirm('staff','selection',input);assert.equal(r.fittingCreditCents,5000);assert.equal(r.balanceCents,44950);
 await f.paid(r.invoiceId);await f.paid(r.invoiceId);
 const locked=await f.store.get(`rentals/${r.id}`);assert.equal(locked.state,'Locked');assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,r.id);
 assert.equal((await f.store.get(`sandboxInvoices/${locked.balanceInvoiceId}`)).amountCents,44950);assert.equal((await f.store.get(`sandboxInvoices/${locked.securityInvoiceId}`)).amountCents,30000);
 const followup=await f.packages.book('bride','selection',{...f.input,requestId:'followup',startAt:f.input.startAt+4*3600000});assert.equal(followup.status,'Confirmed');assert.equal(followup.invoiceId,null);
});
test('expiry releases credit reservation; late old deposit cannot consume credit reserved by replacement',async()=>{
 const f=fixture(),b=await f.attended(),input={appointmentId:b.appointmentId,requestId:'r1',planRevision:1,depositCents:39950};
 const r=await f.workflow.confirm('staff','selection',input);await f.payments.checkout('bride',r.invoiceId);f.advance(HOLD_MS);await f.rentals.expire(r.id);
 const replacement=await f.workflow.confirm('staff','selection',{...input,requestId:'r2'});
 const late=await f.paid(r.invoiceId);assert.ok(late.reviewReason);assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).reservedBy,replacement.id);
 assert.equal((await f.store.get(`rentals/${replacement.id}`)).state,'Held');
});
test('handover blocks unpaid/date/role; return deductions bounded; manager refund is a record only',async()=>{
 const f=fixture(),b=await f.attended();let r=await f.workflow.confirm('staff','selection',{appointmentId:b.appointmentId,requestId:'r1',planRevision:1,depositCents:39950});await f.paid(r.invoiceId);
 r=await f.store.get(`rentals/${r.id}`);
 await assert.rejects(f.rentals.fulfil('bride',r.id,{action:'collect'}),fails('STAFF_REQUIRED'));
 await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'collect'}),fails('PICKUP_DATE_REQUIRED'));
 f.setTime(Date.parse('2026-10-16T02:00:00Z'));
 await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'collect'}),fails('PICKUP_PAYMENT_REQUIRED'));
 await f.paid(r.balanceInvoiceId);await f.paid(r.securityInvoiceId);await f.rentals.fulfil('staff',r.id,{action:'collect'});
 await assert.rejects(f.rentals.cancel('staff',r.id),fails('RETURN_INSPECTION_REQUIRED'));
 await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'return',allReturned:true,damageCents:30001,lateCents:0,reason:'damage'}),fails('INVALID_INSPECTION'));
 f.setTime(Date.parse('2026-10-20T02:00:00Z'));
 r=await f.rentals.fulfil('staff',r.id,{action:'return',allReturned:true,damageCents:3000,lateCents:2000,reason:'Agreed torn lace repair RM30; late return RM20'});
 assert.equal(r.refundDueCents,25000);assert.equal(r.securityState,'RefundDue');
 assert.equal((await f.rentals.fulfil('staff',r.id,{action:'return',allReturned:true,damageCents:3000,lateCents:2000,reason:'Agreed torn lace repair RM30; late return RM20'})).returnedAt,r.returnedAt);
 await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'return',allReturned:true,damageCents:0,lateCents:0,reason:''}),fails('INSPECTION_ALREADY_RECORDED'));
 const variant=await f.store.get(`rentalVariants/${variantId('gown','M')}`);assert.deepEqual(variant.outstanding,{});assert.equal(variant.allocations[r.id].endDay,Date.parse('2026-10-24')/86400000);
 await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'record-refund',reference:'sandbox-001'}),fails('MANAGER_REQUIRED'));
 r=await f.rentals.fulfil('manager',r.id,{action:'record-refund',reference:'sandbox-001'});assert.equal(r.securityState,'RefundRecorded');assert.equal(r.refundEnvironment,'sandbox-record-only');
 assert.equal((await f.rentals.fulfil('manager',r.id,{action:'record-refund',reference:'sandbox-001'})).refundReference,'sandbox-001');
});
test('cancelling an unpaid rental immediately releases unused fitting credit, but never consumed credit',async()=>{
 const f=fixture(),b=await f.attended(),input={appointmentId:b.appointmentId,requestId:'r1',planRevision:1,depositCents:39950};
 const r=await f.workflow.confirm('staff','selection',input);await f.rentals.cancel('staff',r.id);
 assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).reservedBy,null);
 const replacement=await f.workflow.confirm('staff','selection',{...input,requestId:'r2'});assert.equal(replacement.fittingCreditCents,5000);
 await f.paid(replacement.invoiceId);await f.rentals.cancel('staff',replacement.id);
 assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,replacement.id);
});
test('new fitting cannot receive a second arbitrary appointment-deposit invoice',async()=>{
 const f=fixture(),b=await f.bookings.create('bride',f.input);await f.paid(b.invoiceId);
 await assert.rejects(f.payments.createQuote('manager',{appointmentId:b.appointmentId,purpose:'AppointmentDeposit',amountCents:5000}),fails('FITTING_FEE_ALREADY_ISSUED'));
 const consultation=await f.bookings.create('other',{...f.input,requestId:'consult',type:'Bridal Consultation',startAt:f.input.startAt+3600000});
 assert.equal(consultation.status,'Confirmed');assert.equal(consultation.invoiceId,null);
});
test('HTTP new policy returns the exact fitting invoice and single-invoice reads enforce owner/auth',async t=>{
 const f=fixture(),server=createServer(createHandler({service:f.payments,bookings:f.bookings,packages:f.packages,rentals:f.rentals,packageRentals:f.workflow,
  verifyToken:async token=>{if(!['bride','other','staff'].includes(token))throw Error();return {uid:token};}}));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();}));
 const origin=`http://127.0.0.1:${server.address().port}`;
 const r=await fetch(origin+'/v1/appointments',{method:'POST',headers:{Authorization:'Bearer bride','Content-Type':'application/json'},body:JSON.stringify(f.input)});assert.equal(r.status,201);
 const b=await r.json();assert.equal(b.status,'AwaitingPayment');
 assert.equal((await fetch(origin+'/v1/invoices/'+b.invoiceId)).status,401);
 assert.equal((await fetch(origin+'/v1/invoices/'+b.invoiceId,{headers:{Authorization:'Bearer other'}})).status,403);
 const own=await fetch(origin+'/v1/invoices/'+b.invoiceId,{headers:{Authorization:'Bearer bride'}});assert.equal(own.status,200);assert.equal((await own.json()).amountCents,5000);
 const forged=await fetch(origin+'/v1/invoices/'+b.invoiceId+'/checkout',{method:'POST',headers:{Authorization:'Bearer bride','Content-Type':'application/json'},body:JSON.stringify({amountCents:1,paymentMethod:'FPX'})});assert.equal(forged.status,400);
});
