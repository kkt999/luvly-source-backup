import test from 'node:test';
import assert from 'node:assert/strict';
import {PackageRentals} from './package_rentals.mjs';
import {RentalService,rentalDates,variantId} from './rental_service.mjs';
import {customerPlanning} from './customer_planning.mjs';
import {createHandler} from './http_app.mjs';
import {createServer} from 'node:http';
const rid='a'.repeat(32),sid='b'.repeat(32),fail=c=>e=>e.code===c;
class Store{
  data=new Map();queue=Promise.resolve();
  async get(p){return structuredClone(this.data.get(p));}
  atomic(fn){const run=this.queue.then(async()=>{const writes=new Map();let writing=false;
    const result=await fn({get:p=>{assert.equal(writing,false,'Firestore reads before all writes');return this.get(p);},set:(p,v)=>{writing=true;writes.set(p,structuredClone(v));}});
    for(const[p,v]of writes)this.data.set(p,v);return result;});this.queue=run.catch(()=>{});return run;}
}
function fixture(){
  const store=new Store();let now=Date.parse('2026-10-17T06:00:00Z');
  const original={pickupDate:'2026-10-28',eventDate:'2026-10-29',returnDate:'2026-10-30'},dates=rentalDates(original,now);
  const rental={id:rid,uid:'bride',packageSelectionId:sid,appointmentId:'visit',policyVersion:1,invoiceId:'deposit',balanceInvoiceId:'balance',securityInvoiceId:'security',
    state:'Locked',paymentState:'Paid',securityState:'Paid',totalCents:89900,depositCents:39950,balanceCents:44950,securityCents:30000,
    gowns:[{dressId:'gown',name:'Ivory gown',size:'M'}],accessories:[{id:'comb',name:'Hair comb'}],...original,...dates};
  for(const[p,v]of Object.entries({'staffScheduling/staff':{jobRole:'FrontDesk',serviceTypes:['Dress Trial','Bridal Consultation']},'staff/staff':{active:true,role:'staff'},'staff/manager':{active:true,role:'manager'},'staff/inactive':{active:false,role:'staff'},
    [`rentals/${rid}`]:rental,[`packageSelections/${sid}`]:{id:sid,uid:'bride',rentalId:rid,appointmentIds:['visit'],name:'Bridal',selectedGowns:rental.gowns,services:[],rentalPlan:original,rentalPlanRevision:1,totalCents:89900},
    'appointments/visit':{uid:'bride',id:'visit',status:'Completed',type:'Dress Trial',startAt:new Date(now-86400000)},
    'sandboxInvoices/deposit':{id:'deposit',uid:'bride',environment:'sandbox',rentalId:rid,packageSelectionId:sid,purpose:'BookingDeposit',paymentPhase:'Deposit',state:'SandboxPaid',amountCents:39950,invoiceNo:'SB-deposit',paidAt:now},
    'sandboxInvoices/balance':{id:'balance',uid:'bride',environment:'sandbox',rentalId:rid,packageSelectionId:sid,purpose:'PackageBalance',paymentPhase:'Balance',state:'SandboxPaid',amountCents:44950,invoiceNo:'SB-balance',paidAt:now},
    'sandboxInvoices/security':{id:'security',uid:'bride',environment:'sandbox',rentalId:rid,packageSelectionId:sid,purpose:'SecurityDeposit',paymentPhase:'Security',state:'SandboxPaid',amountCents:30000,invoiceNo:'SB-security',paidAt:now},
    [`rentalVariants/${variantId('gown','M')}`]:{quantity:1,allocations:{[rid]:{...dates,quantity:1,state:'Locked'}},outstanding:{}},
    'accessoryStock/comb':{quantity:1,allocations:{[rid]:{...dates,quantity:1,state:'Locked'}},outstanding:{}}
  }))store.data.set(p,v);
  const rentals=new RentalService({store,now:()=>now}),service=new PackageRentals({store,rentals,now:()=>now,paymentPolicy:true});
  const input={requestId:'change-1',revision:0,pickupDate:'2026-10-27',returnDate:'2026-10-29',reason:'Customer agreed to collect one day earlier and return after the event.',customerAgreed:true,previewOnly:false};
  return {store,rentals,service,input,original,dates,setTime:v=>now=v,now:()=>now};
}
test('preview writes nothing; confirmed amendment moves gown and accessory stock atomically and preserves invoices and original dates',async()=>{
  const f=fixture(),before=structuredClone(f.store.data);
  const preview=await f.service.changeDates('staff',rid,{...f.input,previewOnly:true,customerAgreed:false});
  assert.equal(preview.canConfirm,true);assert.equal(preview.additionalChargeCents,0);assert.deepEqual(f.store.data,before);
  const r=await f.service.changeDates('staff',rid,f.input);assert.equal(r.pickupDate,'2026-10-27');assert.deepEqual(r.originalRentalPlan,f.original);assert.equal(r.dateRevision,1);
  assert.equal((await f.store.get('accessoryStock/comb')).allocations[rid].startDay,r.startDay);
  assert.equal((await f.store.get(`rentalVariants/${variantId('gown','M')}`)).allocations[rid].endDay,r.endDay);
  const s=await f.store.get(`packageSelections/${sid}`);assert.equal(s.rentalPlan.pickupDate,r.pickupDate);assert.equal(s.rentalPlanRevision,2);
  for(const id of ['deposit','balance','security'])assert.deepEqual(await f.store.get(`sandboxInvoices/${id}`),before.get(`sandboxInvoices/${id}`));
  assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('rentalDateChanges/')).length,1);
  const data={};for(const c of ['packageSelections','rentals','appointments','sandboxInvoices'])data[c]=[...f.store.data].filter(([p])=>p.startsWith(c+'/')).map(([p,v])=>({...v,id:v.id??p.split('/')[1]}));
  const plan=customerPlanning(data,'bride',f.now()).plans[0];assert.equal(plan.pickupDate,'2026-10-27');assert.equal(plan.returnDate,'2026-10-29');
});
test('same request retries do not append history; changed payload or stale competing version cannot overwrite',async()=>{
  const f=fixture();const first=await f.service.changeDates('staff',rid,f.input);assert.deepEqual(await f.service.changeDates('staff',rid,f.input),first);
  await assert.rejects(f.service.changeDates('staff',rid,{...f.input,reason:'Another different reason on the same request.'}),fail('REQUEST_CONFLICT'));
  await assert.rejects(f.service.changeDates('staff',rid,{...f.input,requestId:'other'}),fail('RENTAL_DATES_CHANGED'));
  assert.equal((await f.store.get(`rentals/${rid}`)).dateChangesCount,1);
});
test('extra days are disclosed but not silently free, quoted or charged; purchased extra day is honored',async()=>{
  const f=fixture(),input={...f.input,returnDate:'2026-10-30'};
  const preview=await f.service.changeDates('staff',rid,{...input,previewOnly:true});assert.equal(preview.canConfirm,false);assert.equal(preview.extraDaysRequired,1);assert.equal(preview.additionalChargeCents,null);
  await assert.rejects(f.service.changeDates('staff',rid,input),fail('EXTENSION_PRICE_REQUIRED'));
  const s=f.store.data.get(`packageSelections/${sid}`);s.services=[{name:'Extra rental day',priceCents:8000}];
  assert.equal((await f.service.changeDates('staff',rid,input)).pickupDate,'2026-10-27');
});
test('gown or accessory overlap including cleaning blocks all writes; own allocation is not double counted',async()=>{
  for(const path of [`rentalVariants/${variantId('gown','M')}`,'accessoryStock/comb']){
    const f=fixture(),v=f.store.data.get(path);v.allocations.other={startDay:f.dates.startDay-5,endDay:f.dates.startDay,quantity:1,state:'Locked'};
    const before=structuredClone(f.store.data);await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('RENTAL_STOCK_UNAVAILABLE'));assert.deepEqual(f.store.data,before);
  }
});
test('new overlapping reservation after preview is checked again at commit',async()=>{
  const f=fixture();await f.service.changeDates('staff',rid,{...f.input,previewOnly:true});
  f.store.data.get('accessoryStock/comb').allocations.other={startDay:f.dates.startDay-2,endDay:f.dates.startDay,quantity:1,state:'Locked'};
  await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('RENTAL_STOCK_UNAVAILABLE'));
  assert.equal((await f.store.get(`rentals/${rid}`)).dateRevision,undefined);
});
test('customer consent, active staff, real dates, fitting order and no collection are mandatory',async()=>{
  const f=fixture();for(const uid of ['bride','inactive'])await assert.rejects(f.service.changeDates(uid,rid,f.input),fail('STAFF_REQUIRED'));
  await assert.rejects(f.service.changeDates('staff',rid,{...f.input,customerAgreed:false}),fail('DATE_CHANGE_CONSENT_REQUIRED'));
  await assert.rejects(f.service.changeDates('staff',rid,{...f.input,pickupDate:'2026-10-16'}),fail('INVALID_RENTAL_DATE_ORDER'));
  await assert.rejects(f.service.changeDates('staff',rid,{...f.input,returnDate:'2026-10-28'}),fail('INVALID_RENTAL_DATE_ORDER'));
  await assert.rejects(f.service.changeDates('staff',rid,{...f.input,pickupDate:'2026-10-28',returnDate:'2026-10-30'}),fail('RENTAL_DATES_UNCHANGED'));
  f.store.data.get('appointments/visit').actualAttendedAt=new Date('2026-10-27T02:00:00Z');
  await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('FITTING_DATE_CONFLICT'));
  f.store.data.get(`rentals/${rid}`).collectedAt=f.now();await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('DATE_CHANGE_BEFORE_PICKUP_ONLY'));
});
test('completed actual fitting permits same-day amendment, keeps handover separate and rejects incomplete fitting',async()=>{
  const f=fixture();f.setTime(Date.parse('2026-10-27T08:00:00Z'));
  const visit=f.store.data.get('appointments/visit');visit.startAt=new Date('2026-10-28T02:00:00Z');visit.actualAttendedAt=new Date('2026-10-27T02:00:00Z');
  const before=structuredClone(f.store.data);
  const preview=await f.service.changeDates('staff',rid,{...f.input,previewOnly:true});assert.equal(preview.canConfirm,true);assert.deepEqual(f.store.data,before);
  visit.status='Confirmed';await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('FITTING_DATE_CONFLICT'));
  visit.status='Completed';const r=await f.service.changeDates('staff',rid,f.input);assert.equal(r.pickupDate,'2026-10-27');assert.equal(r.collectedAt,undefined);
  const data={};for(const c of ['packageSelections','rentals','appointments','sandboxInvoices'])data[c]=[...f.store.data].filter(([p])=>p.startsWith(c+'/')).map(([p,v])=>({...v,id:v.id??p.split('/')[1]}));
  const p=customerPlanning(data,'bride',f.now()).plans[0];assert.equal(p.needsReview,false);assert.equal(p.steps.find(s=>s.key==='pickup').state,'ReadyForPickup');
  f.store.data.get('sandboxInvoices/balance').state='Quoted';await assert.rejects(f.rentals.fulfil('staff',rid,{action:'collect'}),fail('PICKUP_PAYMENT_REQUIRED'));
  f.store.data.get('sandboxInvoices/balance').state='SandboxPaid';assert.ok((await f.rentals.fulfil('staff',rid,{action:'collect'})).collectedAt);
});

test('concurrent staff amendments have one winner and one consistent inventory period',async()=>{
  const f=fixture(),results=await Promise.allSettled([f.service.changeDates('staff',rid,f.input),f.service.changeDates('manager',rid,{...f.input,requestId:'second'})]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.filter(r=>r.status==='rejected').length,1);
  assert.equal((await f.store.get(`rentals/${rid}`)).dateChangesCount,1);
});
test('after a genuine date amendment, collection remains date and verified payment gated; no auto handover',async()=>{
  const f=fixture();const r=await f.service.changeDates('staff',rid,f.input);assert.equal(r.collectedAt,undefined);
  await assert.rejects(f.rentals.fulfil('staff',rid,{action:'collect'}),fail('PICKUP_DATE_REQUIRED'));
  f.setTime(Date.parse('2026-10-27T02:00:00Z'));f.store.data.get('sandboxInvoices/balance').state='Quoted';
  await assert.rejects(f.rentals.fulfil('staff',rid,{action:'collect'}),fail('PICKUP_PAYMENT_REQUIRED'));
  f.store.data.get('sandboxInvoices/balance').state='SandboxPaid';assert.ok((await f.rentals.fulfil('staff',rid,{action:'collect'})).collectedAt);
});
test('no-fitting approvals can amend dates without creating an appointment; missing allocation and review flags cannot bypass checks',async()=>{
  const f=fixture(),r=f.store.data.get(`rentals/${rid}`);r.appointmentId='';r.fittingWaiver={state:'Approved',uid:'bride',acceptedAt:f.now()-1000,approvedAt:f.now(),approvedBy:'staff'};
  f.store.data.get(`packageSelections/${sid}`).appointmentIds=[];f.store.data.delete('appointments/visit');
  await f.service.changeDates('staff',rid,{...f.input,previewOnly:true});
  f.store.data.get('accessoryStock/comb').allocations={};await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('INVENTORY_REVIEW_REQUIRED'));
  f.store.data.get('sandboxInvoices/deposit').reviewReason='Needs review';await assert.rejects(f.service.changeDates('staff',rid,f.input),fail('PACKAGE_PAYMENT_REVIEW_REQUIRED'));
});
test('HTTP date amendments require authentication and reject forged event date / financial fields',async t=>{
  const f=fixture(),server=createServer(createHandler({service:{},packageRentals:f.service,verifyToken:async token=>{if(token!=='staff')throw Error();return{uid:'staff'};}}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());const url=`http://127.0.0.1:${server.address().port}/v1/rentals/${rid}/change-dates`;
  assert.equal((await fetch(url,{method:'POST',body:'{}'})).status,401);
  const response=await fetch(url,{method:'POST',headers:{authorization:'Bearer staff','content-type':'application/json'},body:JSON.stringify({...f.input,eventDate:'2026-10-17',depositCents:0})});assert.equal(response.status,400);
});
