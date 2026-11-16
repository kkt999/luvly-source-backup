import test from 'node:test';import assert from 'node:assert/strict';
import{PackageRentals}from'./package_rentals.mjs';import{RentalService,rentalDates,rentalResources,variantId,peakUsage,HOLD_MS}from'./rental_service.mjs';
import{PaymentService}from'./payment_service.mjs';import{customerPlanning}from'./customer_planning.mjs';import{calculateAnalytics,analyticsRange}from'./analytics.mjs';
const rid='a'.repeat(32),sid='b'.repeat(32),fail=code=>e=>e.code===code;
class Store{
 data=new Map();queue=Promise.resolve();async get(p){return structuredClone(this.data.get(p));}
 atomic(fn){const run=this.queue.then(async()=>{const writes=new Map();const value=await fn({get:p=>{assert.equal(writes.size,0,'All reads precede writes');return this.get(p);},set:(p,v)=>writes.set(p,structuredClone(v))});for(const[p,v]of writes)this.data.set(p,v);return value;});this.queue=run.catch(()=>{});return run;}
}
function fixture(){
 const store=new Store();let now=Date.parse('2026-10-17T06:00:00Z');const plan={pickupDate:'2026-10-28',eventDate:'2026-10-29',returnDate:'2026-10-30'},dates=rentalDates(plan,now);
 const r={id:rid,uid:'bride',packageSelectionId:sid,appointmentId:'visit',policyVersion:1,state:'Locked',paymentState:'Paid',securityState:'Paid',invoiceId:'deposit',balanceInvoiceId:'balance',securityInvoiceId:'security',depositCents:39950,balanceCents:44950,securityCents:30000,totalCents:89900,
 gowns:[{dressId:'gown',size:'M',name:'Ivory gown'}],accessories:[{id:'comb',name:'Hair comb'}],...plan,...dates};
 for(const[p,v]of Object.entries({'staffScheduling/staff':{jobRole:'FrontDesk',serviceTypes:['Dress Trial','Bridal Consultation']},'staff/staff':{active:true,role:'staff'},'brides/bride':{name:'Test bride',email:'test@example.com',phone:'0123456789'},'brides/other':{name:'Other'},
 [`rentals/${rid}`]:r,[`packageSelections/${sid}`]:{id:sid,uid:'bride',packageId:'package',name:'Bridal',rentalId:rid,appointmentIds:['visit'],services:[],rentalPlan:plan,rentalPlanRevision:1,totalCents:89900,selectedGowns:r.gowns},
 'servicePackages/package':{active:true,revision:3,services:[{kind:'Add-on',name:'One additional rental day',priceCents:10000}]},
 'appointments/visit':{uid:'bride',status:'Completed',type:'Dress Trial',startAt:new Date(now-86400000)},
 'sandboxInvoices/deposit':{id:'deposit',uid:'bride',rentalId:rid,packageSelectionId:sid,purpose:'BookingDeposit',paymentPhase:'Deposit',state:'SandboxPaid',amountCents:39950,environment:'sandbox',invoiceNo:'SB-deposit',paidAt:now},
 'sandboxInvoices/balance':{id:'balance',uid:'bride',rentalId:rid,packageSelectionId:sid,purpose:'PackageBalance',paymentPhase:'Balance',state:'SandboxPaid',amountCents:44950,environment:'sandbox',invoiceNo:'SB-balance',paidAt:now},
 'sandboxInvoices/security':{id:'security',uid:'bride',rentalId:rid,packageSelectionId:sid,purpose:'SecurityDeposit',paymentPhase:'Security',state:'SandboxPaid',amountCents:30000,environment:'sandbox',invoiceNo:'SB-security',paidAt:now},
 [`rentalVariants/${variantId('gown','M')}`]:{quantity:1,allocations:{[rid]:{...dates,quantity:1,state:'Locked'}}},'accessoryStock/comb':{quantity:1,allocations:{[rid]:{...dates,quantity:1,state:'Locked'}}}}))store.data.set(p,v);
 const rentals=new RentalService({store,now:()=>now}),workflow=new PackageRentals({store,rentals,now:()=>now}),payments=new PaymentService({store,rentals,now:()=>now,gateway:{createBill:async p=>({...p,billCode:p.reference.slice(-12),checkoutUrl:'https://dev.toyyibpay.com/testbill',environment:'sandbox'})}});
 const input={requestId:'extension-1',revision:0,pickupDate:'2026-10-27',returnDate:'2026-10-30',reason:'Customer requested an extra rental day and agrees to the quoted fee.',previewOnly:false,customerAgreed:true,quoteRateCents:10000,quotePackageRevision:3};
 async function create(overrides={}){return workflow.changeDates('staff',rid,{...input,...overrides});}
 async function intent(invoiceId){await payments.acceptExtension('bride',invoiceId,{accepted:true});await payments.checkout('bride',invoiceId);}
 async function pay(invoiceId){const i=await store.get(`sandboxInvoices/${invoiceId}`);return payments.applyResult(invoiceId,i.billCode,{state:'SandboxPaid',billCode:i.billCode,reference:i.reference,amountCents:i.amountCents,invoiceNo:'SB-extension',environment:'sandbox'});}
 function snapshot(){const data={};for(const c of ['rentals','packageSelections','appointments','sandboxInvoices'])data[c]=[...store.data].filter(([p])=>p.startsWith(c+'/')).map(([p,v])=>({...v,id:v.id??p.split('/')[1]}));return data;}
 return{store,rentals,workflow,payments,input,create,intent,pay,snapshot,now:()=>now,advance:v=>now+=v};
}
test('same-day completed fitting supports paid early pickup only after verified extension payment',async()=>{
 const f=fixture(),visit=f.store.data.get('appointments/visit');
 Object.assign(visit,{startAt:new Date('2026-10-21T04:00:00Z'),actualAttendedAt:new Date(f.now()-60000)});
 const pending=(await f.create({pickupDate:'2026-10-17'})).pendingExtension;
 assert.equal(pending.extraDays,11);assert.equal(pending.amountCents,110000);
 assert.equal((await f.store.get(`rentals/${rid}`)).pickupDate,'2026-10-28');
 await f.intent(pending.invoiceId);await f.pay(pending.invoiceId);
 const r=await f.store.get(`rentals/${rid}`);assert.equal(r.pickupDate,'2026-10-17');assert.equal(r.collectedAt,undefined);
 const p=customerPlanning(f.snapshot(),'bride',f.now()).plans[0];assert.equal(p.needsReview,false);assert.equal(p.pickupDate,'2026-10-17');
});

test('same-day extension is rejected if attendance is not complete at request or verified payment',async()=>{
 const f=fixture(),visit=f.store.data.get('appointments/visit');
 Object.assign(visit,{status:'Confirmed',startAt:new Date('2026-10-21T04:00:00Z')});
 await assert.rejects(f.create({pickupDate:'2026-10-17'}),fail('FITTING_DATE_CONFLICT'));
 Object.assign(visit,{status:'Completed',actualAttendedAt:new Date(f.now()-60000)});
 const p=(await f.create({pickupDate:'2026-10-17'})).pendingExtension;await f.intent(p.invoiceId);
 visit.status='Confirmed';const invoice=await f.pay(p.invoiceId);assert.ok(invoice.reviewReason);
 assert.equal((await f.store.get(`rentals/${rid}`)).pickupDate,'2026-10-28');
});

test('quote uses configured package/day rate; no writes or arbitrary fee; changed prices require a new quote',async()=>{
 const f=fixture(),before=structuredClone(f.store.data),preview=await f.workflow.changeDates('staff',rid,{...f.input,previewOnly:true});assert.equal(preview.additionalChargeCents,10000);assert.equal(preview.requiresPayment,true);assert.deepEqual(before,f.store.data);
 await assert.rejects(f.create({quoteRateCents:1}),fail('EXTENSION_QUOTE_CHANGED'));f.store.data.get('servicePackages/package').revision++;
 await assert.rejects(f.create(),fail('EXTENSION_QUOTE_CHANGED'));
});
test('issuing an invoice keeps original dates and receipts, holds only added intervals, retries never create two bills',async()=>{
 const f=fixture(),before=structuredClone(f.store.data),r=await f.create(),p=r.pendingExtension;
 assert.equal(r.pickupDate,'2026-10-28');assert.equal(p.amountCents,10000);assert.deepEqual(await f.create(),r);
 for(const path of rentalResources(r).map(v=>v.path)){const v=await f.store.get(path);assert.equal(peakUsage(v.allocations,r.startDay-1,r.endDay,f.now()),1);assert.equal(Object.keys(v.allocations).length,2);}
 for(const key of ['deposit','balance','security'])assert.deepEqual(await f.store.get(`sandboxInvoices/${key}`),before.get(`sandboxInvoices/${key}`));
 assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('rentalExtensions/')).length,1);
 await assert.rejects(f.create({requestId:'another'}),fail('EXTENSION_PENDING'));
});
test('payer must personally accept exact invoice terms; staff and other owners cannot accept or pay',async()=>{
 const f=fixture(),r=await f.create(),id=r.pendingExtension.invoiceId;
 await assert.rejects(f.payments.checkout('bride',id),fail('EXTENSION_CONSENT_REQUIRED'));
 await assert.rejects(f.payments.acceptExtension('other',id,{accepted:true}),fail('INVOICE_ACCESS_DENIED'));
 await assert.rejects(f.payments.acceptExtension('staff',id,{accepted:true}),fail('INVOICE_ACCESS_DENIED'));
 await assert.rejects(f.payments.acceptExtension('bride',id,{accepted:false}),fail('EXTENSION_CONSENT_REQUIRED'));
 await f.intent(id);assert.equal((await f.store.get(`rentals/${rid}`)).pickupDate,'2026-10-28');
});
test('only verified exact payment applies dates atomically; deposit, balance and security are never rewritten',async()=>{
 const f=fixture(),before=structuredClone(f.store.data),pending=(await f.create()).pendingExtension;await f.intent(pending.invoiceId);
 const i=await f.store.get(`sandboxInvoices/${pending.invoiceId}`);
 await assert.rejects(f.payments.applyResult(i.id,i.billCode,{state:'SandboxPaid',billCode:i.billCode,reference:i.reference,amountCents:999,invoiceNo:'wrong',environment:'sandbox'}),fail('PAYMENT_BINDING_MISMATCH'));
 await f.pay(i.id);await f.pay(i.id);const r=await f.store.get(`rentals/${rid}`);assert.equal(r.pickupDate,'2026-10-27');assert.equal(r.extensionDaysPaid,1);assert.equal(r.extensionPaidCents,10000);assert.equal(r.totalCents,89900);assert.equal(r.pendingExtension,null);assert.equal(r.dateRevision,1);
 for(const resource of rentalResources(r)){const v=await f.store.get(resource.path);assert.equal(Object.keys(v.allocations).length,1);assert.equal(v.allocations[rid].startDay,r.startDay);}
 for(const key of ['deposit','balance','security'])assert.deepEqual(await f.store.get(`sandboxInvoices/${key}`),before.get(`sandboxInvoices/${key}`));
 assert.equal(customerPlanning(f.snapshot(),'bride',f.now()).plans[0].pickupDate,'2026-10-27');
});
test('unpaid expiry releases extra stock only, blocks checkout and retains original reservation',async()=>{
 const f=fixture(),r=await f.create(),pending=r.pendingExtension;f.advance(HOLD_MS);assert.equal(await f.rentals.expireExtension(pending.id),true);
 const next=await f.store.get(`rentals/${rid}`);assert.equal(next.state,'Locked');assert.equal(next.pickupDate,'2026-10-28');assert.equal(next.pendingExtension,null);
 for(const resource of rentalResources(next)){const v=await f.store.get(resource.path);assert.equal(Object.keys(v.allocations).length,1);assert.equal(v.allocations[rid].state,'Locked');}
 await assert.rejects(f.payments.checkout('bride',pending.invoiceId),fail('EXTENSION_EXPIRED'));
});
test('late success after expiry or cancellation is a review receipt, never a date change',async()=>{
 for(const cancel of [true,false]){const f=fixture(),pending=(await f.create()).pendingExtension;await f.intent(pending.invoiceId);
  if(cancel)await f.workflow.cancelExtension('staff',rid,{extensionId:pending.id});else{f.advance(HOLD_MS);await f.rentals.expireExtension(pending.id);}
  const invoice=await f.pay(pending.invoiceId);assert.ok(invoice.reviewReason);const r=await f.store.get(`rentals/${rid}`);assert.equal(r.pickupDate,'2026-10-28');assert.equal(r.extensionPaidCents,undefined);
 }
});
test('stock lost after checkout never applies or double allocates, and no payment is automatically retried',async()=>{
 const f=fixture(),pending=(await f.create()).pendingExtension;await f.intent(pending.invoiceId);const v=f.store.data.get('accessoryStock/comb');
 for(const key of Object.keys(v.allocations))if(key!==rid)delete v.allocations[key];
 assert.ok((await f.pay(pending.invoiceId)).reviewReason);assert.equal((await f.store.get(`rentals/${rid}`)).pickupDate,'2026-10-28');
});
test('late old extension cannot erase a replacement pending hold or original reservation',async()=>{
 const f=fixture(),old=(await f.create()).pendingExtension;await f.intent(old.invoiceId);f.advance(HOLD_MS);await f.rentals.expireExtension(old.id);
 const next=(await f.create({requestId:'replacement'})).pendingExtension;assert.ok((await f.pay(old.invoiceId)).reviewReason);
 assert.equal((await f.store.get(`rentals/${rid}`)).pendingExtension.id,next.id);const e=await f.store.get(`rentalExtensions/${next.id}`);
 for(const h of e.holds)assert.equal((await f.store.get('accessoryStock/comb')).allocations[h.key].state,'Held');
});
test('shorter dates after a paid extension do not automatically refund or charge again',async()=>{
 const f=fixture(),pending=(await f.create()).pendingExtension;await f.intent(pending.invoiceId);await f.pay(pending.invoiceId);
 const next=await f.workflow.changeDates('staff',rid,{requestId:'shorter',revision:1,pickupDate:'2026-10-28',returnDate:'2026-10-30',reason:'Customer agreed to shorten back to the original rental dates.',previewOnly:false,customerAgreed:true});
 assert.equal(next.extensionPaidCents,10000);assert.equal(next.extensionDaysPaid,1);assert.equal(next.pickupDate,'2026-10-28');assert.equal((await f.store.get(`sandboxInvoices/${pending.invoiceId}`)).state,'SandboxPaid');
});
test('paid extension entitlement prevents charging the same days twice, future extra days use only incremental units',async()=>{
 const f=fixture(),pending=(await f.create()).pendingExtension;await f.intent(pending.invoiceId);await f.pay(pending.invoiceId);
 const free=await f.workflow.changeDates('staff',rid,{...f.input,revision:1,requestId:'free-shift',pickupDate:'2026-10-26',returnDate:'2026-10-29',previewOnly:true});assert.equal(free.additionalChargeCents,0);
 const more=await f.workflow.changeDates('staff',rid,{...f.input,revision:1,requestId:'another-day',pickupDate:'2026-10-26',previewOnly:true});assert.equal(more.extraDaysRequired,1);assert.equal(more.additionalChargeCents,10000);
});
test('pending extension prevents accidental original-date handover or cancellation; staff can cancel just the extension',async()=>{
 const f=fixture(),pending=(await f.create()).pendingExtension;
 await assert.rejects(f.rentals.fulfil('staff',rid,{action:'collect'}),fail('EXTENSION_PENDING'));await assert.rejects(f.rentals.cancel('staff',rid),fail('EXTENSION_PENDING'));
 await f.workflow.cancelExtension('staff',rid,{extensionId:pending.id});await f.workflow.cancelExtension('staff',rid,{extensionId:pending.id});assert.equal((await f.store.get(`rentals/${rid}`)).state,'Locked');
});
test('planning prioritizes pending extension with original dates; analytics counts verified fee only once, not security or late-review payments',async()=>{
 const f=fixture(),pending=(await f.create()).pendingExtension;const p=customerPlanning(f.snapshot(),'bride',f.now()).plans[0];assert.equal(p.pickupDate,'2026-10-28');assert.equal(p.nextAction.targetId,pending.invoiceId);
 await f.intent(pending.invoiceId);await f.pay(pending.invoiceId);const result=calculateAnalytics(f.snapshot(),analyticsRange({from:'2026-10-17',to:'2026-10-17'},f.now()),f.now());assert.equal(result.totals.serviceCents,39950+44950+10000);assert.equal(result.totals.securityCents,30000);
});
