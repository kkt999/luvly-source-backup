import test from 'node:test';
import assert from 'node:assert/strict';
import { PackageRentals } from './package_rentals.mjs';
import { RentalService, variantId, HOLD_MS } from './rental_service.mjs';
import { PaymentService } from './payment_service.mjs';
import {createServer} from 'node:http';
import {createHandler} from './http_app.mjs';
class Store {
  data=new Map();queue=Promise.resolve();
  async get(p){return structuredClone(this.data.get(p));}
  atomic(fn){const run=this.queue.then(async()=>{const writes=new Map();const value=await fn({get:p=>{assert.equal(writes.size,0,'Firestore forbids read after write');return this.get(p);},set:(p,v)=>writes.set(p,structuredClone(v))});for(const [p,v]of writes)this.data.set(p,v);return value;});this.queue=run.catch(()=>{});return run;}
}
async function fixture(){
  const store=new Store();let now=Date.parse('2026-10-14T02:00:00Z');
  const s={id:'selection',uid:'bride',customerName:'Demo',name:'Bridal',totalCents:89900,selectedGowns:[{dressId:'gown',size:'M',name:'Gown'}],selectedAccessories:[{id:'ring-solitaire',name:'Ring'}],services:[],appointmentIds:['appointment'],rentalPlanRevision:0,invoiceId:null};
  for(const [p,v]of Object.entries({'staffScheduling/staff':{jobRole:'FrontDesk',serviceTypes:['Dress Trial','Bridal Consultation']},'staff/staff':{role:'staff',active:true},'staff/revoked':{role:'staff',active:false},'brides/bride':{name:'Demo',phone:'0123456789',email:'demo@example.com'},'brides/other':{name:'Other'},'dresses/gown':{published:true,availability:'Available',sizes:'M'},'packageSelections/selection':s,'appointments/appointment':{uid:'bride',status:'Confirmed',assignedStaffId:'staff'},'packageAppointments/appointment':{selectionId:'selection'},[`rentalVariants/${variantId('gown','M')}`]:{id:variantId('gown','M'),quantity:1,allocations:{},revision:1},'accessoryStock/ring-solitaire':{id:'ring-solitaire',quantity:1,allocations:{},revision:1}}))store.data.set(p,v);
  const rentals=new RentalService({store,now:()=>now});const workflow=new PackageRentals({store,rentals,now:()=>now});
  store.data.get('appointments/appointment').startAt=new Date('2026-10-15T02:00:00Z');
  const payments=new PaymentService({store,rentals,now:()=>now,gateway:{}});
  const plan={pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18',revision:0};
  const confirm={appointmentId:'appointment',requestId:'attempt',planRevision:1,depositCents:10000};
  async function paid(r,phase='Deposit'){
    const invoiceId=phase==='Balance'?store.data.get(`rentals/${r.id}`).balanceInvoiceId:r.invoiceId;
    const p=`sandboxInvoices/${invoiceId}`,i=store.data.get(p);
    store.data.set(p,{...i,billCode:'bill',reference:`LV_${invoiceId}`});
    return payments.applyResult(invoiceId,'bill',{state:'SandboxPaid',billCode:'bill',reference:`LV_${invoiceId}`,amountCents:i.amountCents,invoiceNo:'sandbox-receipt',environment:'sandbox'});
  }
  return {store,rentals,workflow,payments,plan,confirm,paid,advance:n=>now+=n};
}
const fails=c=>e=>e.code===c;
test('plan preflight reports conflicts and unknowns without mutating the saved plan or stock',async()=>{
  const f=await fixture(),before=structuredClone([...f.store.data]);
  assert.equal((await f.workflow.checkPlan('bride','selection',f.plan)).available,true);
  assert.deepEqual([...f.store.data],before);
  f.store.data.get(`rentalVariants/${variantId('gown','M')}`).quantity=0;
  f.store.data.delete('accessoryStock/ring-solitaire');
  const result=await f.workflow.checkPlan('bride','selection',f.plan);
  assert.equal(result.available,false);assert.deepEqual(result.items.map(r=>r.status),['Unavailable','Unconfirmed']);
  assert.equal(f.store.data.get('packageSelections/selection').rentalPlan,undefined);
  await assert.rejects(f.workflow.checkPlan('other','selection',f.plan),fails('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.workflow.checkPlan('staff','selection',f.plan),fails('SELECTION_ACCESS_DENIED'));
  f.store.data.get('packageSelections/selection').rentalId='locked';
  await assert.rejects(f.workflow.checkPlan('bride','selection',f.plan),fails('RENTAL_ALREADY_EXISTS'));
});
test('package plan validates dates/owner, checks stock and never reserves',async()=>{
  const f=await fixture();
  await assert.rejects(f.workflow.plan('other','selection',f.plan),fails('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.workflow.plan('bride','selection',{...f.plan,eventDate:'2026-10-19'}),fails('INVALID_RENTAL_DATE_ORDER'));
  await assert.rejects(f.workflow.plan('bride','selection',{...f.plan,returnDate:'2026-10-21'}),fails('PACKAGE_RENTAL_PERIOD'));
  const result=await f.workflow.plan('bride','selection',f.plan);
  assert.equal(result.reserved,false);assert.equal(result.availableAgain,'2026-10-22');
  assert.deepEqual(f.store.data.get('accessoryStock/ring-solitaire').allocations,{});
  await assert.rejects(f.workflow.plan('bride','selection',f.plan),fails('RENTAL_PLAN_CHANGED'));
});
test('changing rental dates cannot invalidate an existing fitting and confirmation repeats the check',async()=>{
  const f=await fixture();
  await assert.rejects(f.workflow.plan('bride','selection',{pickupDate:'2026-10-15',eventDate:'2026-10-16',returnDate:'2026-10-17',revision:0}),fails('FITTING_DATE_CONFLICT'));
  await f.workflow.plan('bride','selection',f.plan);
  f.store.data.get('appointments/appointment').startAt=new Date('2026-10-17T02:00:00Z');
  await assert.rejects(f.workflow.confirm('staff','selection',f.confirm),fails('FITTING_DATE_CONFLICT'));
});
test('deposit locks gowns and accessories, credits total and issues balance once',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);
  const r=await f.workflow.confirm('staff','selection',f.confirm);
  assert.equal(r.balanceCents,79900);assert.equal(r.expiresAt-r.createdAt,HOLD_MS);
  await assert.rejects(f.workflow.confirm('bride','selection',f.confirm),fails('STAFF_REQUIRED'));
  assert.equal((await f.workflow.confirm('staff','selection',f.confirm)).expiresAt,r.expiresAt);
  await f.paid(r);await f.paid(r);
  const locked=f.store.data.get(`rentals/${r.id}`);assert.equal(locked.state,'Locked');
  assert.equal(f.store.data.get('accessoryStock/ring-solitaire').allocations[r.id].state,'Locked');
  assert.equal(f.store.data.get(`sandboxInvoices/${locked.balanceInvoiceId}`).amountCents,79900);
  assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('sandboxInvoices/')).length,2);
  await f.paid(r,'Balance');assert.equal(f.store.data.get(`rentals/${r.id}`).paymentState,'Paid');
});
test('specialists cannot access rentals or execute counter operations with known IDs',async()=>{
  const f=await fixture();
  await f.workflow.plan('bride','selection',f.plan);
  const rental=await f.workflow.confirm('staff','selection',f.confirm);
  f.store.data.set('staff/specialist',{active:true,role:'staff'});
  f.store.data.set('staffScheduling/specialist',{jobRole:'FittingSpecialist'});
  f.store.data.get('appointments/appointment').assignedStaffId='specialist';
  f.store.list=async(collection,owner)=>[...f.store.data]
    .filter(([path,row])=>path.startsWith(collection+'/')&&(!owner||row.uid===owner))
    .map(([,row])=>structuredClone(row));
  const before=structuredClone([...f.store.data]);
  for(const request of [
    ()=>f.rentals.list('specialist'),
    ()=>f.rentals.get('specialist',rental.id),
    ()=>f.rentals.cancel('specialist',rental.id),
    ()=>f.rentals.fulfil('specialist',rental.id,{action:'collect'}),
    ()=>f.workflow.confirm('specialist','selection',f.confirm),
    ()=>f.workflow.cancelExtension('specialist',rental.id,{extensionId:'extension'}),
  ]) await assert.rejects(request(),fails('OPERATIONS_ACCESS_REQUIRED'));
  assert.deepEqual([...f.store.data],before);
  assert.equal((await f.rentals.get('staff',rental.id)).id,rental.id);
  assert.equal((await f.rentals.get('bride',rental.id)).id,rental.id);
});
test('expired holds release both inventories and late verified payment cannot relock',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);const r=await f.workflow.confirm('staff','selection',f.confirm);
  f.advance(HOLD_MS);await f.rentals.expire(r.id);
  assert.deepEqual(f.store.data.get('accessoryStock/ring-solitaire').allocations,{});
  const result=await f.paid(r);assert.ok(result.reviewReason);
  assert.equal(f.store.data.get(`rentals/${r.id}`).state,'PaymentReview');
  assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('sandboxInvoices/')).length,1);
});
test('accessory scarcity, unconfigured inventory, stale plan and legacy invoices block confirmation',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);
  await assert.rejects(f.workflow.confirm('staff','selection',{...f.confirm,planRevision:0}),fails('RENTAL_PLAN_CHANGED'));
  f.store.data.get('accessoryStock/ring-solitaire').quantity=0;
  await assert.rejects(f.workflow.confirm('staff','selection',f.confirm),fails('RENTAL_STOCK_UNAVAILABLE'));
  f.store.data.delete('accessoryStock/ring-solitaire');
  await assert.rejects(f.workflow.confirm('staff','selection',f.confirm),fails('INVENTORY_NOT_CONFIGURED'));
  const s=f.store.data.get('packageSelections/selection');s.invoiceId='legacy';f.store.data.set('sandboxInvoices/legacy',{state:'SandboxPaid'});
  await assert.rejects(f.workflow.confirm('staff','selection',f.confirm),fails('PACKAGE_PAYMENT_REVIEW_REQUIRED'));
});
test('shared gown stock blocks overlapping standalone rentals and cleaning days',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);await f.workflow.confirm('staff','selection',f.confirm);
  f.store.data.set('appointments/standalone',{uid:'bride',status:'Confirmed',assignedStaffId:'staff'});
  await assert.rejects(f.rentals.hold('staff',{...f.plan,revision:undefined,requestId:'s',appointmentId:'standalone',gowns:[{dressId:'gown',size:'M'}],depositCents:10000}),fails('INVALID_RENTAL'));
  const input={pickupDate:'2026-10-21',eventDate:'2026-10-21',returnDate:'2026-10-21',requestId:'s',appointmentId:'standalone',gowns:[{dressId:'gown',size:'M'}],depositCents:10000};
  await assert.rejects(f.rentals.hold('staff',input),fails('RENTAL_STOCK_UNAVAILABLE'));
  assert.equal((await f.rentals.hold('staff',{...input,pickupDate:'2026-10-22',eventDate:'2026-10-22',returnDate:'2026-10-22'})).state,'Held');
});
test('appointment cancellation frees allocations and paid cancellations require refund review',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);const r=await f.workflow.confirm('staff','selection',f.confirm);await f.paid(r);
  f.store.data.get('appointments/appointment').status='Cancelled';await f.rentals.audit(r.id);
  assert.equal(f.store.data.get(`rentals/${r.id}`).state,'Cancelled');
  assert.equal(f.store.data.get(`rentals/${r.id}`).refundReviewRequired,true);
  assert.deepEqual(f.store.data.get('accessoryStock/ring-solitaire').allocations,{});
  await assert.rejects(f.payments.checkout('bride',f.store.data.get(`rentals/${r.id}`).balanceInvoiceId),fails('CONFIRMED_APPOINTMENT_REQUIRED'));
});
test('concurrent packages cannot both reserve the final accessory; failed hold leaves no gown allocation',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);
  f.store.data.set('packageSelections/second',{...f.store.data.get('packageSelections/selection'),id:'second',appointmentIds:['secondAppointment'],selectedGowns:[{dressId:'secondGown',size:'M',name:'Second gown'}]});
  f.store.data.set('dresses/secondGown',{published:true,availability:'Available',sizes:'M'});
  f.store.data.set(`rentalVariants/${variantId('secondGown','M')}`,{id:variantId('secondGown','M'),quantity:1,allocations:{},revision:1});
  f.store.data.set('appointments/secondAppointment',{uid:'bride',status:'Confirmed',assignedStaffId:'staff'});
  f.store.data.get('appointments/secondAppointment').startAt=new Date('2026-10-15T02:00:00Z');
  f.store.data.set('packageAppointments/secondAppointment',{selectionId:'second'});
  const results=await Promise.allSettled([f.workflow.confirm('staff','selection',f.confirm),f.workflow.confirm('staff','second',{...f.confirm,requestId:'two',appointmentId:'secondAppointment'})]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('rentals/')).length,1);
  assert.deepEqual(f.store.data.get(`rentalVariants/${variantId('secondGown','M')}`).allocations,{});
});
test('stock quantity updates require staff and cannot drop below held units; unknown data stays unknown',async()=>{
  const f=await fixture();await f.workflow.plan('bride','selection',f.plan);await f.workflow.confirm('staff','selection',f.confirm);
  await assert.rejects(f.workflow.saveStock('bride',{id:'ring-solitaire',quantity:2,revision:1}),fails('STAFF_REQUIRED'));
  await assert.rejects(f.workflow.saveStock('staff',{id:'ring-solitaire',quantity:0,revision:1}),fails('QUANTITY_BELOW_RESERVED'));
  await assert.rejects(f.workflow.saveStock('staff',{id:'ring-solitaire',quantity:2,revision:0}),fails('VARIANT_CHANGED'));
  const result=await f.workflow.saveStock('staff',{id:'ring-solitaire',quantity:2,revision:1});assert.equal(result.revision,2);
  const list=await f.workflow.stock('staff');assert.equal(list.items.find(i=>i.id==='ring-halo').quantity,null);
});
test('new HTTP routes require identity, isolate plans and expose stock only to active staff',async()=>{
  const f=await fixture(),selectionId='a'.repeat(32);
  f.store.data.set(`packageSelections/${selectionId}`,{...f.store.data.get('packageSelections/selection'),id:selectionId});
  const server=createServer(createHandler({service:f.payments,rentals:f.rentals,packageRentals:f.workflow,verifyToken:async token=>({uid:token})}));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  async function request(path,uid,body){return fetch(base+path,{method:body?'POST':'GET',headers:{...(uid?{authorization:`Bearer ${uid}`} : {}),'content-type':'application/json'},body:body?JSON.stringify(body):undefined});}
  try {
    assert.equal((await request('/v1/accessory-stock')).status,401);
    assert.equal((await request('/v1/accessory-stock','bride')).status,403);
    assert.equal((await request('/v1/accessory-stock','staff')).status,200);
    assert.equal((await request(`/v1/package-selections/${selectionId}/plan`,'other',f.plan)).status,403);
    assert.equal((await request(`/v1/package-selections/${selectionId}/plan`,'bride',f.plan)).status,200);
    assert.equal((await request(`/v1/package-selections/${selectionId}/confirm-rental`,'bride',f.confirm)).status,403);
  } finally {await new Promise(resolve=>server.close(resolve));}
});
test('complete sandbox checkout path charges deposit then exact remaining balance',async()=>{
  const f=await fixture();const charged=[];
  f.payments.gateway={
    createBill:async input=>{charged.push(input.amountCents);return {reference:input.reference,amountCents:input.amountCents,billCode:`bill${charged.length}`,checkoutUrl:`https://dev.toyyibpay.com/bill${charged.length}`,environment:'sandbox'};},
    reconcile:async invoice=>({state:'SandboxPaid',billCode:invoice.billCode,reference:invoice.reference,amountCents:invoice.amountCents,invoiceNo:`receipt-${invoice.id}`,environment:'sandbox'}),
  };
  await f.workflow.plan('bride','selection',f.plan);const r=await f.workflow.confirm('staff','selection',f.confirm);
  await f.payments.checkout('bride',r.invoiceId);await f.payments.refresh('bride',r.invoiceId);
  const balance=f.store.data.get(`rentals/${r.id}`).balanceInvoiceId;
  await f.payments.checkout('bride',balance);await f.payments.refresh('bride',balance);
  assert.deepEqual(charged,[10000,79900]);
  assert.equal(charged.reduce((a,b)=>a+b,0),89900);
  assert.equal(f.store.data.get(`rentals/${r.id}`).paymentState,'Paid');
  await f.payments.refresh('bride',r.invoiceId);assert.equal(charged.length,2);
});
