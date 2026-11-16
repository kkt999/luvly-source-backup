import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {customerPlanning,CustomerPlanningService} from './customer_planning.mjs';
import {PaymentService} from './payment_service.mjs';
import {createHandler} from './http_app.mjs';
const now=Date.parse('2026-10-16T02:00:00Z');
function fixture(){return {
  packageSelections:[{id:'selection',uid:'bride',name:'Bridal Essentials',totalCents:89900,createdAt:now-86400000,appointmentIds:['visit'],selectedGowns:[{name:'Ivory gown',size:'M'}],selectedAccessories:[],
    rentalPlan:{pickupDate:'2026-10-20',eventDate:'2026-10-21',returnDate:'2026-10-22'},invoiceId:null,rentalId:null}],
  appointments:[{id:'visit',uid:'bride',type:'Dress Trial',status:'Completed',startAt:new Date(now-86400000)}],
  rentals:[],sandboxInvoices:[],
};}
function rental(data,state='Held'){
  const s=data.packageSelections[0];s.rentalId='rental';s.invoiceId='deposit';
  const r={id:'rental',uid:'bride',packageSelectionId:s.id,appointmentId:'visit',state,expiresAt:now+900000,invoiceId:'deposit',balanceInvoiceId:state==='Locked'?'balance':null,
    securityInvoiceId:state==='Locked'?'security':null,depositCents:44950,balanceCents:44950,securityCents:30000,...s.rentalPlan};data.rentals.push(r);
  for(const [id,phase,purpose,amountCents] of [['deposit','Deposit','BookingDeposit',44950],...(state==='Locked'?[['balance','Balance','PackageBalance',44950],['security','Security','SecurityDeposit',30000]]:[])]){
    data.sandboxInvoices.push({id,uid:'bride',packageSelectionId:s.id,rentalId:r.id,paymentPhase:phase,purpose,amountCents,environment:'sandbox',state:'Quoted',...(id==='deposit'?{holdExpiresAt:r.expiresAt}:{} )});
  }
  if(state==='Locked')pay(data,'deposit');return r;
}
function pay(data,id){Object.assign(data.sandboxInvoices.find(i=>i.id===id),{state:'SandboxPaid',invoiceNo:`SB-${id}`,paidAt:now-1000});}
const calculate=data=>customerPlanning(data,'bride',now);
const plan=data=>calculate(data).plans[0];

test('final fitting is a separate customer next step, not inferred from payment or initial attendance',()=>{
 const data=fixture(),r=rental(data,'Locked');pay(data,'balance');pay(data,'security');
 r.fittingQuote={adjustmentPlan:{followUp:'Required'}};
 assert.equal(plan(data).nextAction.title,'Arrange your final fitting');
 Object.assign(r,{pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18'});
 const pickup=()=>plan(data).steps.find(s=>s.key==='pickup').state;
 r.finalFitting={state:'Completed',alterationVersion:2};
 data.rentalServiceProgress=[{selectionId:'selection',rentalId:r.id,alteration:'Completed',alterationVersion:1}];
 assert.equal(plan(data).nextAction.title,'Arrange your final fitting');
 assert.equal(pickup(),'Scheduled');
 data.rentalServiceProgress[0].alterationVersion=2;
 assert.equal(pickup(),'ReadyForPickup');
 r.finalFitting.state='NeedsReview';
 assert.equal(plan(data).nextAction.title,'Arrange your final fitting');
 assert.equal(pickup(),'Scheduled');
});

test('paid pickup waits for alterations recorded against the current rental',()=>{
 const data=fixture(),r=rental(data,'Locked');pay(data,'balance');pay(data,'security');
 Object.assign(r,{fittingAdjustmentsRequired:true,pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18'});
 const pickup=()=>plan(data).steps.find(s=>s.key==='pickup').state;
 assert.equal(pickup(),'Scheduled');
 assert.match(plan(data).nextAction.title,/adjustments are in progress/);
 data.rentalServiceProgress=[{selectionId:'selection',rentalId:'old-rental',alteration:'Completed'}];
 assert.equal(pickup(),'Scheduled');
 data.rentalServiceProgress[0].rentalId=r.id;
 assert.equal(pickup(),'ReadyForPickup');
});

test('reconciled cancelled payment stays closed without implying an active rental or endless payment review',()=>{
 const data=fixture(),r=rental(data,'Locked');r.state='Cancelled';
 data.sandboxInvoices.find(i=>i.id==='deposit').reviewResolution={state:'Retained',refundCents:0};
 assert.equal(plan(data).deposit.state,'Closed');assert.equal(plan(data).needsReview,false);
 assert.equal(plan(data).rentalState,'Cancelled');assert.equal(plan(data).nextAction.title,'Review your rental availability');
});
test('empty own records have no invented event, appointment, package or percentage',()=>{
  const result=calculate({});assert.equal(result.plans.length,0);assert.equal(result.nextAppointment,null);assert.equal(result.nextAction.type,'packages');assert.ok(!JSON.stringify(result).includes('percent'));
});
test('saved selection and completed fitting do not imply stock or deposit confirmation',()=>{
  const p=plan(fixture());assert.equal(p.rentalState,'NotReserved');assert.equal(p.steps.find(s=>s.key==='fitting').state,'Completed');
  assert.equal(p.steps.find(s=>s.key==='deposit').state,'NotReserved');assert.equal(p.deposit.state,'NotIssued');assert.equal(p.nextAction.type,'packages');
  assert.equal(p.daysToEvent,5);
});
test('multiple plans keep separate dates and states; nearest active event wins over later/past completed plans',()=>{
  const data=fixture();data.packageSelections.push({...data.packageSelections[0],id:'later',rentalPlan:{pickupDate:'2026-11-20',eventDate:'2026-11-21',returnDate:'2026-11-22'}});
  assert.equal(calculate(data).plans[0].id,'selection');assert.equal(calculate(data).plans[1].daysToEvent,36);
});
test('invalid calendar dates and reversed date order are withheld and flagged, not repaired or guessed',()=>{
  for(const dates of [{pickupDate:'2026-02-30',eventDate:'2026-03-01',returnDate:'2026-03-02'},{pickupDate:'2026-10-22',eventDate:'2026-10-21',returnDate:'2026-10-20'}]){
    const data=fixture();data.packageSelections[0].rentalPlan=dates;const p=plan(data);assert.equal(p.eventDate,null);assert.equal(p.daysToEvent,null);assert.equal(p.needsReview,true);assert.equal(p.nextAction.type,'support');
  }
});
test('MYT calendar countdown distinguishes today, past and missing dates',()=>{
  const data=fixture();data.appointments=[];
  data.packageSelections[0].rentalPlan={pickupDate:'2026-10-15',eventDate:'2026-10-16',returnDate:'2026-10-17'};assert.equal(plan(data).daysToEvent,0);
  assert.equal(customerPlanning(data,'bride',Date.parse('2026-10-16T16:00:00Z')).plans[0].daysToEvent,-1);
  delete data.packageSelections[0].rentalPlan;assert.equal(plan(data).daysToEvent,null);assert.match(plan(data).nextAction.title,/dates/);
});
test('consultation is not mislabeled as a completed gown fitting and future completed visits do not count',()=>{
  const data=fixture();data.appointments[0].type='Bridal Consultation';assert.equal(plan(data).steps.find(s=>s.key==='fitting').state,'NotBooked');
  data.appointments[0].status='Confirmed';data.appointments[0].startAt=new Date(now+86400000);
  assert.equal(plan(data).steps.find(s=>s.key==='fitting').state,'ConsultationBooked');
  data.appointments[0].type='Dress Trial';data.appointments[0].status='Completed';assert.notEqual(plan(data).steps.find(s=>s.key==='fitting').state,'Completed');
});
test('a legacy fitting after pickup/event is flagged rather than recommended to attend',()=>{
  const data=fixture();data.appointments[0].status='Confirmed';data.appointments[0].startAt=new Date('2026-10-23T02:00:00Z');
  assert.equal(plan(data).needsReview,true);assert.equal(plan(data).nextAction.type,'support');
});
test('active deposit hold has a payment action; elapsed hold is not a reservation and cannot invite repayment',()=>{
  const data=fixture(),r=rental(data);assert.equal(plan(data).steps.find(s=>s.key==='deposit').state,'Held');assert.equal(plan(data).nextAction.targetId,'deposit');
  r.expiresAt=now;data.sandboxInvoices[0].holdExpiresAt=now;
  assert.equal(plan(data).rentalState,'Expired');assert.equal(plan(data).deposit.state,'Expired');assert.notEqual(plan(data).nextAction.type,'payments');
});
test('only verified deposit with a locked rental displays reserved; amount/purpose/ownership mismatch is review',()=>{
  const data=fixture();rental(data,'Locked');assert.equal(plan(data).steps.find(s=>s.key==='deposit').state,'Reserved');
  for(const patch of [{uid:'other'},{packageSelectionId:'other'},{rentalId:'other'},{purpose:'Other'},{amountCents:100},{invoiceNo:null},{state:'Quoted'},{paidAt:now+1}]){
    const changed=structuredClone(data);Object.assign(changed.sandboxInvoices[0],patch);assert.equal(plan(changed).needsReview,true,JSON.stringify(patch));assert.equal(plan(changed).nextAction.type,'support');
  }
});
test('late verified payment does not manufacture locked inventory or invite another payment',()=>{
  const data=fixture(),r=rental(data);r.expiresAt=now-1;pay(data,'deposit');
  assert.equal(plan(data).rentalState,'Expired');assert.equal(plan(data).needsReview,true);assert.equal(plan(data).nextAction.type,'support');
});
test('balance and security are separate, and both precede pickup without claiming handover',()=>{
  const data=fixture(),r=rental(data,'Locked');assert.equal(plan(data).nextAction.targetId,'balance');
  pay(data,'balance');assert.equal(plan(data).nextAction.targetId,'security');pay(data,'security');
  assert.equal(plan(data).steps.find(s=>s.key==='pickup').state,'Scheduled');
  Object.assign(r,{pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18'});
  assert.equal(plan(data).steps.find(s=>s.key==='pickup').state,'ReadyForPickup');assert.notEqual(plan(data).steps.find(s=>s.key==='pickup').state,'Collected');
});
test('return is not marked complete just because the date passed; actual collection and return records control it',()=>{
  const data=fixture(),r=rental(data,'Locked');data.appointments=[];pay(data,'balance');pay(data,'security');
  Object.assign(r,{pickupDate:'2026-10-13',eventDate:'2026-10-14',returnDate:'2026-10-15',collectedAt:now-86400000});
  assert.equal(plan(data).steps.find(s=>s.key==='return').state,'Overdue');assert.equal(plan(data).completed,false);assert.equal(plan(data).nextAction.type,'support');
  r.returnedAt=now;r.securityState='RefundDue';assert.equal(plan(data).completed,true);assert.equal(plan(data).steps.find(s=>s.key==='security').state,'RefundDue');
  r.securityState='RefundRecorded';assert.match(plan(data).nextAction.detail,/recorded by our team/);assert.doesNotMatch(plan(data).nextAction.detail,/bank transfer confirmed|money transferred/i);
});
test('global next appointment excludes cancelled, expired and past visits, without cross-plan fitting completion',()=>{
  const data=fixture();data.appointments.push({id:'cancelled',uid:'bride',type:'Dress Trial',status:'Cancelled',startAt:new Date(now+1000)},
    {id:'upcoming',uid:'bride',type:'Dress Trial',status:'Confirmed',startAt:new Date(now+3600000)});
  assert.equal(calculate(data).nextAppointment.id,'upcoming');assert.ok(!plan(data).appointmentIds.includes('upcoming'));
});
test('fitting fee held time is not shown as confirmed and expiration is read-only',()=>{
  const data=fixture();data.packageSelections=[];const a=data.appointments[0];Object.assign(a,{status:'AwaitingPayment',startAt:new Date(now+86400000),paymentExpiresAt:now+900000,fittingInvoiceId:'fee'});
  data.sandboxInvoices.push({id:'fee',uid:'bride',appointmentId:a.id,purpose:'FittingFee',environment:'sandbox',amountCents:5000,state:'Quoted',holdExpiresAt:now+900000});
  assert.equal(calculate(data).nextAppointment.status,'AwaitingPayment');assert.equal(calculate(data).nextAction.targetId,'fee');
  const before=JSON.stringify(data);assert.equal(customerPlanning(data,'bride',now+900001).nextAppointment,null);assert.equal(JSON.stringify(data),before);
});
test('awaiting fitting with missing or paid-but-not-confirmed invoice is never claimed booked',()=>{
  const data=fixture(),a=data.appointments[0];
  Object.assign(a,{status:'AwaitingPayment',startAt:new Date(now+86400000),paymentExpiresAt:now+900000,fittingInvoiceId:'fee'});
  assert.equal(plan(data).needsReview,true);assert.equal(plan(data).nextAction.type,'support');
  data.sandboxInvoices.push({id:'fee',uid:'bride',appointmentId:a.id,purpose:'FittingFee',environment:'sandbox',amountCents:5000,state:'SandboxPaid',invoiceNo:'SB-fee',paidAt:now-1000});
  assert.equal(plan(data).needsReview,false);assert.equal(plan(data).nextAction.type,'appointments');
  assert.match(plan(data).nextAction.title,/being checked/);assert.doesNotMatch(plan(data).nextAction.title,/booked/);
});
test('cross-customer records and internal invoice/contact data are never returned',()=>{
  const data=fixture();rental(data);Object.assign(data.sandboxInvoices[0],{checkoutUrl:'https://private-checkout',reference:'private-reference',createdBy:'private-staff'});
  data.packageSelections.push({...data.packageSelections[0],id:'foreign',uid:'other',name:'Private other customer'});
  data.appointments.push({id:'foreign',uid:'other',name:'Other name',phone:'private-phone',status:'Confirmed',startAt:new Date(now+1000)});
  const raw=JSON.stringify(calculate(data));for(const value of ['private-checkout','private-reference','private-staff','Private other customer','private-phone','Other name'])assert.ok(!raw.includes(value));
});
test('missing legacy paid metadata is review, never payable again or silently marked settled',()=>{
  const data=fixture();data.packageSelections[0].invoiceId='legacy';data.sandboxInvoices.push({id:'legacy',uid:'bride',packageSelectionId:'selection',environment:'sandbox',purpose:'PackagePayment',amountCents:89900,state:'SandboxPaid'});
  const p=plan(data);assert.equal(p.deposit.state,'NeedsReview');assert.equal(p.nextAction.type,'support');assert.equal(calculate(data).warnings.reviewPayments,1);
});
function serviceFixture(){const data=fixture(),roles={staff:{active:true,role:'staff'},manager:{active:true,role:'manager'},revoked:{active:false,role:'staff'}};let reads=0;
  const store={get:async p=>p.startsWith('staff/')?roles[p.slice(6)]:p==='brides/bride'?{uid:'bride'}:null,customerPlanningSnapshot:async()=>{reads++;return data;},atomic:()=>{throw Error('No writes allowed');}};
  const access=new PaymentService({store});return {data,store,roles,reads:()=>reads,service:new CustomerPlanningService({store,access:uid=>access.access(uid),now:()=>now})};
}
test('authenticated customer only, including inactive staff denial before snapshot read',async()=>{
  const f=serviceFixture();for(const uid of ['staff','manager','revoked','unknown'])await assert.rejects(f.service.get(uid));assert.equal(f.reads(),0);
  assert.equal((await f.service.get('bride')).uid,'bride');
});
test('record cap and account access change cannot return partial or stale private snapshots',async()=>{
  const f=serviceFixture();f.data.limited=true;await assert.rejects(f.service.get('bride'),e=>e.code==='PLANNING_LIMIT_REACHED');
  f.data.limited=false;f.store.customerPlanningSnapshot=async()=>{f.roles.bride={active:true,role:'staff'};return f.data;};await assert.rejects(f.service.get('bride'),e=>e.code==='BRIDE_REQUIRED');
});
test('HTTP identity comes only from verified token, not customer query input; route remains read-only',async t=>{
  const f=serviceFixture(),server=createServer(createHandler({service:{},customerPlanning:f.service,verifyToken:async uid=>({uid})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>{server.closeAllConnections();server.close();});const url=`http://127.0.0.1:${server.address().port}/v1/my-planning`;
  assert.equal((await fetch(url)).status,401);assert.equal((await fetch(url,{headers:{authorization:'Bearer manager'}})).status,403);
  assert.equal((await fetch(url+'?uid=other',{headers:{authorization:'Bearer bride'}})).status,400);
  const response=await fetch(url,{headers:{authorization:'Bearer bride'}});assert.equal(response.status,200);assert.equal((await response.json()).uid,'bride');
  assert.equal((await fetch(url,{method:'POST',headers:{authorization:'Bearer bride'}})).status,404);
});
