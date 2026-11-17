import test from 'node:test';
import assert from 'node:assert/strict';
import {FittingWorkflow} from './fitting_workflow.mjs';
import {BookingService} from './booking_service.mjs';
import {PackageService} from './package_service.mjs';
import {PackageRentals} from './package_rentals.mjs';
import {RentalService,variantId,HOLD_MS} from './rental_service.mjs';
import {PaymentService} from './payment_service.mjs';
import {customerPlanning} from './customer_planning.mjs';
import {appointmentEvent} from './calendar_service.mjs';
import {createHandler} from './http_app.mjs';
import {createServer} from 'node:http';

class Store{
  data=new Map();queue=Promise.resolve();
  async get(p){return structuredClone(this.data.get(p));}
  async list(c,uid){return [...this.data].filter(([p,d])=>p.startsWith(c+'/')&&(uid===undefined||d.uid===uid)).map(([p,d])=>({...structuredClone(d),id:d.id??p.split('/')[1]}));}
  async activeStaffIds(){return ['staff'];}
  async completedDressTrials(uid){return (await this.list('appointments',uid)).filter(b=>b.type==='Dress Trial'&&b.status==='Completed');}
  atomic(fn){const run=this.queue.then(async()=>{let writing=false;const writes=new Map();const value=await fn({
    get:p=>{assert.equal(writing,false,'read before writes');return this.get(p);},
    staffRoster:()=>this.list('staff'),
    makeupTrialAppointments:uid=>this.list('appointments',uid),
    set:(p,v)=>{writing=true;writes.set(p,structuredClone(v));},delete:p=>{writing=true;writes.set(p,null);}});
    for(const[p,v]of writes)if(v===null)this.data.delete(p);else this.data.set(p,v);return value;});this.queue=run.catch(()=>{});return run;}
}
const sid='a'.repeat(32),fail=c=>e=>e.code===c;
function fixture(){
  const store=new Store();let now=Date.parse('2026-10-17T02:23:00Z');const clock=()=>now;
  for(const[p,v]of Object.entries({'staffScheduling/staff':{jobRole:'FrontDesk',serviceTypes:['Dress Trial','Bridal Consultation']},'staff/staff':{role:'staff',active:true},'staff/inactive':{role:'staff',active:false},
    'brides/bride':{name:'Test bride',phone:'0123456789',email:'test@example.com'},'brides/other':{name:'Other'},
    'dresses/gown':{published:true,availability:'Available',sizes:'M'},
    [`rentalVariants/${variantId('gown','M')}`]:{quantity:1,allocations:{},revision:1},
    [`packageSelections/${sid}`]:{id:sid,uid:'bride',customerName:'Test bride',name:'Bridal',totalCents:89900,services:[],selectedGowns:[{dressId:'gown',size:'M',name:'Gown'}],selectedAccessories:[],appointmentIds:[],invoiceId:null,
      rentalPlanRevision:1,rentalPlan:{pickupDate:'2026-10-20',eventDate:'2026-10-21',returnDate:'2026-10-22'}}}))store.data.set(p,v);
  const bookings=new BookingService({store,now:clock,feePolicy:true}),rentals=new RentalService({store,now:clock});
  const payments=new PaymentService({store,bookings,rentals,now:clock,gateway:{createBill:async p=>({...p,billCode:'testbill',checkoutUrl:'https://dev.toyyibpay.com/testbill',environment:'sandbox'})}});
  const packages=new PackageService({store,bookings,paymentService:payments,now:clock});
  const fitting=new FittingWorkflow({store,now:clock}),workflow=new PackageRentals({store,rentals,now:clock,paymentPolicy:true});
  const input={requestId:'visit',type:'Dress Trial',startAt:Date.parse('2026-10-19T02:00:00Z'),notes:'',feePolicyVersion:1};
  const record={requestId:'result',revision:0,mode:'Attended',outcome:'Satisfied',confirmed:true,note:'Customer attended and confirmed this gown and size.'};
  async function paid(id){await payments.checkout('bride',id);const i=await store.get(`sandboxInvoices/${id}`);return payments.applyResult(id,i.billCode,{state:'SandboxPaid',billCode:i.billCode,reference:i.reference,amountCents:i.amountCents,invoiceNo:'sandbox-receipt',environment:'sandbox'});}
  async function skip(){await fitting.choice('bride',sid,{mode:'SkipFitting',accepted:true,revision:0});return fitting.record('staff',sid,{...record,mode:'Waived',revision:1});}
  async function snapshot(){const data={};for(const c of ['appointments','packageSelections','rentals','sandboxInvoices'])data[c]=await store.list(c);return customerPlanning(data,'bride',now);}
  return {store,clock,bookings,rentals,payments,packages,fitting,workflow,input,record,paid,skip,snapshot,setTime:v=>now=v};
}

function replacementFixture(){
  const f=fixture();
  f.store.data.set('servicePackages/bridal',{id:'bridal',active:true,revision:1,includedGownCount:1,eligibleDressIds:['gown','replacement']});
  f.store.data.set('dresses/gown',{name:'Original gown',colour:'Ivory',category:'Ball Gown',published:true,availability:'Available',sizes:'M',revision:1});
  f.store.data.set('dresses/replacement',{name:'Replacement gown',colour:'White',category:'A-Line',published:true,availability:'Available',sizes:'S, M',revision:2,imageUrl:'https://example.com/gown.jpg'});
  f.store.data.set(`rentalVariants/${variantId('replacement','S')}`,{quantity:1,allocations:{},revision:1});
  f.store.data.set(`rentalVariants/${variantId('replacement','M')}`,{quantity:0,allocations:{},revision:1});
  const s=f.store.data.get(`packageSelections/${sid}`);
  Object.assign(s,{packageId:'bridal',packageRevision:1,includedGownCount:1,selectionRevision:0});
  f.change={gowns:[{dressId:'replacement',size:'S',revision:2}],packageRevision:1,selectionRevision:0,planRevision:1};
  return f;
}

test('replacement picker exposes only eligible public stock statuses and never reserves stock',async()=>{
  const f=replacementFixture(),before=structuredClone([...f.store.data]);
  for(const actor of ['bride','inactive','other'])await assert.rejects(f.fitting.gownOptions(actor,sid,{}),fail('STAFF_REQUIRED'));
  await assert.rejects(f.fitting.gownOptions('staff',sid,{uid:'bride'}),fail('INVALID_GOWN_SELECTION'));
  const options=await f.fitting.gownOptions('staff',sid,{});
  assert.equal(options.reserved,false);assert.equal(options.includedGownCount,1);
  assert.deepEqual(options.gowns.find(g=>g.dressId==='replacement').sizes,[{size:'S',status:'Available'},{size:'M',status:'Unavailable'}]);
  assert.equal(JSON.stringify(options).includes('allocations'),false);
  assert.deepEqual([...f.store.data],before);
});

test('staff replacement atomically records exact new gown, actual attendance and old selection; no deposit or hold until customer consent',async()=>{
  const f=replacementFixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  const before=await f.store.get(`packageSelections/${sid}`);
  const input={...f.record,outcome:'Selected',adjustment:'None',appointmentId:b.appointmentId,gownChange:f.change};
  const result=await f.fitting.record('staff',sid,input);
  const s=await f.store.get(`packageSelections/${sid}`);
  assert.equal(s.selectedGowns[0].dressId,'replacement');assert.equal(s.selectedGowns[0].size,'S');assert.equal(s.selectedGowns[0].name,'Replacement gown');
  assert.equal(s.fittingDecision.state,'QuoteNeeded');assert.equal(s.selectionRevision,1);
  assert.deepEqual(s.fittingDecision.gownChange.from,before.selectedGowns);assert.deepEqual(s.fittingDecision.gownChange.to,s.selectedGowns);
  assert.deepEqual(s.fittingDecision.selectedGowns,s.selectedGowns);
  assert.deepEqual(s.selectionHistory[0].selectedGowns,before.selectedGowns);
  assert.deepEqual(s.rentalPlan,before.rentalPlan);assert.equal(s.totalCents,before.totalCents);
  assert.deepEqual(s.appointmentIds,before.appointmentIds);
  assert.equal((await f.store.get(`appointments/${b.appointmentId}`)).status,'Completed');
  assert.equal((await f.store.list('sandboxInvoices')).length,1);assert.equal((await f.store.list('rentals')).length,0);
  assert.deepEqual((await f.store.get(`rentalVariants/${variantId('replacement','S')}`)).allocations,{});
  assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,null);
  assert.deepEqual((await f.fitting.record('staff',sid,input)).fittingDecision,result.fittingDecision);
  assert.equal((await f.store.get(`packageSelections/${sid}`)).selectionHistory.length,1);
  await assert.rejects(f.fitting.record('staff',sid,{...input,gownChange:{...f.change,gowns:[{dressId:'replacement',size:'M',revision:2}]}}),fail('REQUEST_CONFLICT'));
  await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'r',planRevision:1,fittingRevision:1,depositCents:39950}),fail('FITTING_QUOTE_ACCEPTANCE_REQUIRED'));
  await proposal(f);await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
  const current=await f.store.get(`packageSelections/${sid}`);
  const rental=await f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'r',planRevision:1,fittingRevision:current.fittingDecisionRevision,depositCents:39950});
  assert.equal(rental.fittingCreditCents,5000);assert.equal(rental.totalCents,89900);
});

test('replacement rejects unavailable, unconfigured, cleaning-blocked and stale stock without completing attendance',async()=>{
  for(const mutation of ['zero','missing','cleaning','revision','unpublished','ineligible','wrong-size']){
    const f=replacementFixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
    const variant=`rentalVariants/${variantId('replacement','S')}`;
    let code='RENTAL_STOCK_UNAVAILABLE';
    if(mutation==='zero')f.store.data.get(variant).quantity=0;
    if(mutation==='missing'){f.store.data.delete(variant);code='INVENTORY_NOT_CONFIGURED';}
    if(mutation==='cleaning'){
      const startDay=Date.parse('2026-10-19T00:00:00Z')/86400000;
      f.store.data.get(variant).allocations.other={state:'Locked',quantity:1,startDay:startDay-2,endDay:startDay+3};
    }
    if(mutation==='revision'){f.store.data.get('dresses/replacement').revision=3;code='PACKAGE_GOWN_CHANGED';}
    if(mutation==='unpublished'){f.store.data.get('dresses/replacement').published=false;code='PACKAGE_GOWN_CHANGED';}
    if(mutation==='ineligible'){f.store.data.get('servicePackages/bridal').eligibleDressIds=['gown'];code='PACKAGE_GOWN_NOT_ELIGIBLE';}
    if(mutation==='wrong-size'){f.change.gowns[0].size='XL';code='PACKAGE_GOWN_CHANGED';}
    const before=structuredClone([...f.store.data]);
    await assert.rejects(f.fitting.record('staff',sid,{...f.record,outcome:'Selected',adjustment:'None',appointmentId:b.appointmentId,gownChange:f.change}),fail(code));
    assert.deepEqual([...f.store.data],before);
  }
});

test('replacement exact revision, entitlement, outcome and order locks cannot be bypassed',async()=>{
  for(const mutation of ['selection','dates','package','count','same','forged','decline','waived','locked','actor']){
    const f=replacementFixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
    let input={...f.record,outcome:'Selected',adjustment:'None',appointmentId:b.appointmentId,gownChange:f.change},actor='staff',code;
    if(mutation==='selection'){f.change.selectionRevision=1;code='FITTING_SELECTION_CHANGED';}
    if(mutation==='dates'){f.change.planRevision=2;code='RENTAL_PLAN_CHANGED';}
    if(mutation==='package'){f.store.data.get('servicePackages/bridal').revision=2;code='PACKAGE_CHANGED';}
    if(mutation==='count'){f.store.data.get('servicePackages/bridal').includedGownCount=2;code='PACKAGE_GOWN_COUNT';}
    if(mutation==='same'){f.change.gowns=[{dressId:'gown',size:'M',revision:1}];code='FITTING_GOWNS_UNCHANGED';}
    if(mutation==='forged'){f.change.gowns[0].name='Forged name';code='INVALID_GOWN_SELECTION';}
    if(mutation==='decline'){input.outcome='Reselect';code='INVALID_GOWN_SELECTION';}
    if(mutation==='waived'){input.mode='Waived';code='INVALID_GOWN_SELECTION';}
    if(mutation==='locked'){f.store.data.get(`packageSelections/${sid}`).invoiceId='locked';code='FITTING_ORDER_LOCKED';}
    if(mutation==='actor'){actor='bride';code='STAFF_REQUIRED';}
    const before=structuredClone([...f.store.data]);await assert.rejects(f.fitting.record(actor,sid,input),fail(code));assert.deepEqual([...f.store.data],before);
  }
});

test('replacement assessments reference the new gown, not copied old fit instructions',async()=>{
  const f=replacementFixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  const assessment={schemaVersion:1,bodyCm:{waist:70},followUp:'NotDecided',targetDate:null,gowns:[{dressId:'gown',size:'M',fit:{bust:'Good',waist:'Good',hips:'Good',length:'Good'},adjustmentNotes:''}]};
  const input={...f.record,outcome:'Selected',adjustment:'None',appointmentId:b.appointmentId,gownChange:f.change,assessment};
  await assert.rejects(f.fitting.record('staff',sid,input),fail('INVALID_FITTING_ASSESSMENT'));
  assessment.gowns[0].dressId='replacement';assessment.gowns[0].size='S';
  await f.fitting.record('staff',sid,input);
  assert.equal((await f.store.get(`packageSelections/${sid}`)).fittingDecision.assessment.gowns[0].dressId,'replacement');
});

test('replacement options HTTP route requires authentication and rejects forged body or query identity',async t=>{
  const f=replacementFixture(),before=structuredClone([...f.store.data]);
  const server=createServer(createHandler({service:f.payments,fittingWorkflow:f.fitting,verifyToken:async token=>({uid:token})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
  const url=`http://127.0.0.1:${server.address().port}/v1/package-selections/${sid}/fitting-gown-options`;
  const send=(suffix,body,token)=>fetch(url+suffix,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
  assert.equal((await send('',{})).status,401);assert.equal((await send('',{},'bride')).status,403);
  assert.equal((await send('',{uid:'bride'},'staff')).status,400);assert.equal((await send('?uid=bride',{},'staff')).status,400);
  assert.equal((await send('',{},'staff')).status,200);assert.deepEqual([...f.store.data],before);
});
test('makeup options HTTP route requires operations access and rejects query overrides',async t=>{
  const f=fixture();
  const server=createServer(createHandler({service:f.payments,fittingWorkflow:f.fitting,verifyToken:async token=>({uid:token})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
  const url=`http://127.0.0.1:${server.address().port}/v1/package-selections/${sid}/fitting-makeup-options`;
  const get=(suffix,token)=>fetch(url+suffix,{headers:token?{authorization:`Bearer ${token}`}:{}});
  assert.equal((await get('')).status,401);
  assert.equal((await get('','bride')).status,403);
  assert.equal((await get('?uid=bride','staff')).status,400);
  assert.deepEqual(await (await get('','staff')).json(),{artists:[],trials:[]});
});
test('customer consent and staff approval are separate; no customer or inactive staff can approve',async()=>{
  const f=fixture();await assert.rejects(f.fitting.choice('other',sid,{mode:'SkipFitting',accepted:true,revision:0}),fail('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.fitting.choice('bride',sid,{mode:'SkipFitting',accepted:false,revision:0}),fail('FITTING_CONSENT_REQUIRED'));
  for(const uid of ['bride','inactive'])await assert.rejects(f.fitting.record(uid,sid,{...f.record,mode:'Waived'}),fail('STAFF_REQUIRED'));
  await assert.rejects(f.fitting.record('staff',sid,{...f.record,mode:'Waived'}),fail('FITTING_CONSENT_REQUIRED'));
  await f.skip();assert.equal((await f.store.get(`packageSelections/${sid}`)).fittingDecision.state,'Approved');
});
test('early real attendance preserves planned date, records today, frees original slot, sends correct completion and Calendar time',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  const before=await f.store.get(`appointments/${b.appointmentId}`);
  await assert.rejects(f.bookings.transition('staff',b.appointmentId,{status:'Completed',revision:before.revision,response:''}),fail('INVALID_BOOKING_TRANSITION'));
  const input={...f.record,appointmentId:b.appointmentId};await f.fitting.record('staff',sid,input);
  const visit=await f.store.get(`appointments/${b.appointmentId}`);assert.equal(+visit.startAt,f.input.startAt);assert.equal(+visit.actualAttendedAt,f.clock());assert.equal(visit.status,'Completed');
  assert.equal(await f.store.get(`appointmentSlots/${visit.slotKey}`),undefined);
  const day=await f.store.get('appointmentAvailability/2026-10-19');assert.equal(Object.values(day.bookings).some(v=>v.appointmentId===b.appointmentId),false);
  assert.equal(appointmentEvent('bride',b.appointmentId,visit).start.dateTime,new Date(f.clock()).toISOString());
  const mail=(await f.store.list('appointmentMail')).find(m=>m.event==='Completed');assert.equal(mail.startAt,f.clock());
  const again=await f.fitting.record('staff',sid,input);assert.equal(again.fittingDecision.actualAt,f.clock());assert.equal((await f.store.list('appointmentMail')).length,2);
  await assert.rejects(f.fitting.record('staff',sid,{...input,note:'A conflicting retry must not change the record.'}),fail('REQUEST_CONFLICT'));
  const plan=(await f.snapshot()).plans[0];assert.equal(plan.needsReview,false);assert.equal(plan.steps[2].state,'Completed');
  const r=await f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'rental',planRevision:1,fittingRevision:1,depositCents:39950});assert.equal(r.fittingCreditCents,5000);
});
test('staff can record actual pickup-day fitting before wedding and confirm rental, without auto collection',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  f.setTime(Date.parse('2026-10-20T02:00:00Z'));
  await f.fitting.record('staff',sid,{...f.record,appointmentId:b.appointmentId});
  const s=await f.store.get(`packageSelections/${sid}`);assert.equal(s.fittingDecision.state,'Approved');
  const plan=(await f.snapshot()).plans[0];assert.equal(plan.needsReview,false);assert.equal(plan.nextAction.type,'packages');
  const r=await f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'rental',planRevision:1,fittingRevision:1,depositCents:39950});
  assert.equal(r.pickupDate,'2026-10-20');assert.equal(r.state,'Held');assert.equal(r.collectedAt,undefined);
});

test('unpaid fitting cannot be marked attended; changes-needed outcome blocks rental confirmation',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);
  await assert.rejects(f.fitting.record('staff',sid,{...f.record,appointmentId:b.appointmentId}),fail('CONFIRMED_APPOINTMENT_REQUIRED'));
  await f.paid(b.invoiceId);await f.fitting.record('staff',sid,{...f.record,appointmentId:b.appointmentId,outcome:'NeedsChanges'});
  await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'rental',planRevision:1,fittingRevision:1,depositCents:39950}),fail('FITTING_RESULT_REQUIRED'));
  assert.equal((await f.snapshot()).plans[0].steps[2].state,'ChangesRequired');
});
test('no-fitting request requires normal cancellation first; cannot book another fitting while opted out',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  await assert.rejects(f.fitting.choice('bride',sid,{mode:'SkipFitting',accepted:true,revision:0}),fail('CANCEL_FITTING_FIRST'));
  const visit=await f.store.get(`appointments/${b.appointmentId}`);await f.bookings.transition('bride',b.appointmentId,{status:'Cancelled',revision:visit.revision,response:''});
  await f.skip();await assert.rejects(f.packages.book('bride',sid,{...f.input,requestId:'another'}),fail('FITTING_CHOICE_CONFLICT'));
  assert.match((await f.store.get(`sandboxInvoices/${b.invoiceId}`)).reviewReason,/refund review/);
});
test('no-fitting full verified payment flow never invents a visit, fitting fee or credit; pickup gates remain intact',async()=>{
  const f=fixture();await f.skip();
  let p=(await f.snapshot()).plans[0];assert.equal(p.steps[2].state,'Waived');assert.equal(p.nextAction.title,'Ready for rental confirmation');
  const input={appointmentId:'',requestId:'rental',planRevision:1,fittingRevision:2,depositCents:44950};
  await assert.rejects(f.workflow.confirm('staff',sid,{...input,fittingRevision:1}),fail('FITTING_CHANGED'));
  let r=await f.workflow.confirm('staff',sid,input);assert.equal(r.fittingCreditCents,0);assert.equal(r.appointmentId,'');assert.equal((await f.store.list('appointments')).length,0);
  await assert.rejects(f.fitting.choice('bride',sid,{mode:'TryOn',accepted:false,revision:1}),fail('RENTAL_ALREADY_EXISTS'));
  await f.paid(r.invoiceId);r=await f.store.get(`rentals/${r.id}`);assert.equal(r.state,'Locked');
  assert.equal((await f.store.list('fittingCredits')).length,0);assert.equal(r.balanceCents,44950);assert.equal(r.securityCents,30000);
  await f.paid(r.balanceInvoiceId);await f.paid(r.securityInvoiceId);
  await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'collect'}),fail('PICKUP_DATE_REQUIRED'));
  f.setTime(Date.parse('2026-10-20T02:00:00Z'));await f.rentals.fulfil('staff',r.id,{action:'collect'});
  assert.equal((await f.snapshot()).plans[0].steps[6].state,'Collected');
});
test('changing preference invalidates old approval; attendance on the wedding date cannot bypass rental date order',async()=>{
  const f=fixture();await f.skip();await f.fitting.choice('bride',sid,{mode:'TryOn',accepted:false,revision:1});
  await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:'',requestId:'r',planRevision:1,fittingRevision:2,depositCents:44950}),fail('FITTING_RESULT_REQUIRED'));
  const b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);f.setTime(Date.parse('2026-10-21T01:00:00Z'));
  await assert.rejects(f.fitting.record('staff',sid,{...f.record,revision:3,appointmentId:b.appointmentId}),fail('FITTING_DATE_CONFLICT'));
});
test('no-fitting inventory hold still expires after 15 minutes; late payment never locks stock',async()=>{
  const f=fixture();await f.skip();const r=await f.workflow.confirm('staff',sid,{appointmentId:'',requestId:'r',planRevision:1,fittingRevision:2,depositCents:44950});
  await f.payments.checkout('bride',r.invoiceId);f.setTime(f.clock()+HOLD_MS);await f.rentals.expire(r.id);
  const invoice=await f.store.get(`sandboxInvoices/${r.invoiceId}`);
  await f.payments.applyResult(r.invoiceId,invoice.billCode,{state:'SandboxPaid',billCode:invoice.billCode,reference:invoice.reference,amountCents:invoice.amountCents,invoiceNo:'late-receipt',environment:'sandbox'});
  assert.notEqual((await f.store.get(`rentals/${r.id}`)).state,'Locked');
});
test('fitting routes authenticate, reject forged owner fields and never accept query identity',async t=>{
  const f=fixture(),server=createServer(createHandler({service:f.payments,fittingWorkflow:f.fitting,verifyToken:async token=>{if(!['bride','staff'].includes(token))throw Error();return{uid:token};}}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
  const url=`http://127.0.0.1:${server.address().port}/v1/package-selections/${sid}/fitting-choice`;
  assert.equal((await fetch(url,{method:'POST',body:'{}'})).status,401);
  assert.equal((await fetch(url,{method:'POST',headers:{authorization:'Bearer bride','content-type':'application/json'},body:JSON.stringify({mode:'SkipFitting',accepted:true,revision:0,uid:'other'})})).status,400);
});

test('new fitting proposal and reselection routes retain auth, exact bodies and no query identity',async t=>{
  const f=fixture(),before=structuredClone([...f.store.data]);
  const server=createServer(createHandler({service:f.payments,packages:f.packages,fittingWorkflow:f.fitting,verifyToken:async token=>{if(token!=='bride')throw Error();return {uid:token};}}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());
  const base=`http://127.0.0.1:${server.address().port}/v1/package-selections/${sid}/`;
  for(const route of ['fitting-quote','fitting-response','fitting-intent','revise','final-fitting']){
    const send=(suffix,body,auth=true)=>fetch(base+route+suffix,{method:'POST',headers:{'content-type':'application/json',...(auth?{authorization:'Bearer bride'}:{})},body:JSON.stringify(body)});
    assert.equal((await send('',{},false)).status,401);
    assert.equal((await send('',{uid:'other'})).status,400);
    assert.equal((await send('?uid=other',{})).status,400);
  }
  assert.deepEqual([...f.store.data],before);
});

async function modernVisit(f,outcome='Selected',adjustment='None'){
  const b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  await f.fitting.record('staff',sid,{...f.record,appointmentId:b.appointmentId,outcome,adjustment});return b;
}
async function proposal(f,{extra=0,uid='staff'}={}){
  const s=await f.store.get(`packageSelections/${sid}`);
  return f.fitting.quote(uid,sid,{requestId:'quote',revision:s.fittingQuoteRevision??0,decisionRevision:s.fittingDecisionRevision,
    note:'Customer-facing agreement: selected gown and agreed fit adjustments before pickup.',
    lines:s.fittingDecision.adjustment==='None'?[]:[{description:'Waist adjustment before the final fitting',amountCents:extra}]});
}
test('a completed standalone trial can fund exactly one package without a second fitting fee',async()=>{
  const f=fixture(),path=`packageSelections/${sid}`;
  const visit=await f.bookings.create('bride',f.input);
  await f.paid(visit.invoiceId);
  const link={appointmentId:visit.appointmentId,planRevision:1,selectionRevision:0};
  assert.deepEqual(await f.packages.completedFittings('bride',sid),{visits:[]});
  await assert.rejects(f.packages.linkCompletedFitting('bride',sid,link),fail('COMPLETED_FITTING_UNAVAILABLE'));
  f.setTime(f.input.startAt+3600000);
  await f.bookings.transition('staff',visit.appointmentId,{status:'Completed',revision:2,response:'Attended'});
  assert.deepEqual(await f.packages.completedFittings('bride',sid),{
    visits:[{id:visit.appointmentId,attendedAt:f.clock(),creditCents:5000}],
  });
  await assert.rejects(f.packages.linkCompletedFitting('other',sid,link),fail('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.packages.linkCompletedFitting('bride',sid,{...link,planRevision:0}),fail('RENTAL_PLAN_CHANGED'));
  await f.fitting.choice('bride',sid,{mode:'SkipFitting',accepted:true,revision:0});
  const second='b'.repeat(32);
  f.store.data.set(`packageSelections/${second}`,{...await f.store.get(path),id:second});
  const results=await Promise.allSettled([
    f.packages.linkCompletedFitting('bride',sid,link),
    f.packages.linkCompletedFitting('bride',second,link),
  ]);
  assert.equal(results[0].status,'fulfilled');
  assert.equal(results[1].reason.code,'COMPLETED_FITTING_UNAVAILABLE');
  assert.deepEqual(await f.packages.linkCompletedFitting('bride',sid,link),{linked:true});
  assert.deepEqual(await f.packages.completedFittings('bride',second),{visits:[]});
  const attached=await f.store.get(path);
  assert.deepEqual(attached.appointmentIds,[visit.appointmentId]);
  assert.equal(attached.fittingChoice.mode,'TryOn');
  assert.equal(attached.fittingChoiceRevision,2);
  await assert.rejects(f.packages.book('bride',sid,{...f.input,requestId:'duplicate',startAt:f.input.startAt+86400000}),fail('COMPLETED_FITTING_ALREADY_LINKED'));
  await assert.rejects(f.fitting.choice('bride',sid,{mode:'SkipFitting',accepted:true,revision:0}),fail('COMPLETED_FITTING_ALREADY_LINKED'));
  assert.equal((await f.store.list('sandboxInvoices')).length,1);
  assert.equal((await f.store.list('appointments')).length,1);
  assert.equal((await f.store.list('rentals')).length,0);
  await f.fitting.record('staff',sid,{...f.record,revision:1,appointmentId:visit.appointmentId,outcome:'Selected',adjustment:'None'});
  await proposal(f);
  await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
  const ready=await f.store.get(path);
  const rental=await f.workflow.confirm('staff',sid,{appointmentId:visit.appointmentId,requestId:'reuse-rental',
    planRevision:1,fittingRevision:ready.fittingDecisionRevision,depositCents:39950});
  assert.equal(rental.fittingCreditCents,5000);
  assert.equal(rental.depositCents,39950);
  assert.equal((await f.store.list('sandboxInvoices')).length,2);
  await f.paid(rental.invoiceId);
  assert.equal((await f.store.get(`fittingCredits/${visit.appointmentId}`)).consumedBy,rental.id);
});
test('link rechecks dates and payment eligibility and leaves the selection untouched on failure',async()=>{
  const f=fixture(),path=`packageSelections/${sid}`;
  const visit=await f.bookings.create('bride',f.input);
  await f.paid(visit.invoiceId);
  f.setTime(f.input.startAt+3600000);
  await f.bookings.transition('staff',visit.appointmentId,{status:'Completed',revision:2,response:'Attended'});
  const link={appointmentId:visit.appointmentId,planRevision:1,selectionRevision:0};
  const credit=f.store.data.get(`fittingCredits/${visit.appointmentId}`);
  const invoice=f.store.data.get(`sandboxInvoices/${visit.invoiceId}`);
  const appointment=f.store.data.get(`appointments/${visit.appointmentId}`);
  for(const [record,key,value] of [
    [credit,'consumedBy','other-rental'],[credit,'voidedAt',f.clock()],
    [invoice,'reviewReason','Refund review'],[appointment,'actualAttendedAt',null],
    [appointment,'actualAttendedAt',new Date(f.clock()+1)],
  ]){
    const original=record[key];
    record[key]=value;
    assert.deepEqual(await f.packages.completedFittings('bride',sid),{visits:[]});
    await assert.rejects(f.packages.linkCompletedFitting('bride',sid,link),fail('COMPLETED_FITTING_UNAVAILABLE'));
    assert.deepEqual((await f.store.get(path)).appointmentIds,[]);
    record[key]=original;
  }
  const selection=f.store.data.get(path);
  selection.rentalPlan={pickupDate:'2026-10-19',eventDate:'2026-10-19',returnDate:'2026-10-20'};
  assert.deepEqual(await f.packages.completedFittings('bride',sid),{visits:[]});
  await assert.rejects(f.packages.linkCompletedFitting('bride',sid,link),fail('COMPLETED_FITTING_UNAVAILABLE'));
  assert.equal(await f.store.get(`packageAppointments/${visit.appointmentId}`),undefined);
});
test('staff must arrange selected services and dated accessories before the customer accepts a new proposal',async()=>{
  const f=fixture();
  await modernVisit(f);
  const path=`packageSelections/${sid}`,s=f.store.data.get(path);
  Object.assign(s,{selectionFlowVersion:1,services:[
    {id:'service-123',serviceType:'makeup-trial',name:'Wedding makeup'},{id:'portrait-session',name:'Bridal portraits'},
    {id:'service-456',serviceType:'veil-accessories',name:'Finishing touches'},
  ]});
  const quote={requestId:'new-quote',revision:0,decisionRevision:s.fittingDecisionRevision,
    note:'Customer-facing summary with agreed services.',lines:[]};
  const timing=[
    {serviceId:'service-123',timing:'19 Oct, 2 PM MYT with the bridal artist'},
    {serviceId:'portrait-session',timing:'21 Oct, 11 AM MYT with the studio team'},
  ];
  await assert.rejects(f.fitting.quote('staff',sid,quote),fail('PACKAGE_SERVICE_TIMING_REQUIRED'));
  await assert.rejects(f.fitting.quote('staff',sid,{...quote,serviceConfirmations:[timing[0],timing[0]]}),fail('PACKAGE_SERVICE_TIMING_REQUIRED'));
  const input={...quote,serviceConfirmations:timing};
  await assert.rejects(f.fitting.quote('staff',sid,input),fail('PACKAGE_ACCESSORY_SELECTION_REQUIRED'));
  assert.equal((await f.store.get(path)).fittingQuote,null);
  s.selectedAccessories=[{id:'veil-short',serviceId:'service-456'}];
  const {fittingQuote}=await f.fitting.quote('staff',sid,input);
  assert.deepEqual(fittingQuote.servicePlan.map(row=>row.serviceId),timing.map(row=>row.serviceId));
  assert.deepEqual((await f.fitting.quote('staff',sid,input)).fittingQuote,fittingQuote);
  const response={revision:1,response:'Accept'};
  await assert.rejects(f.fitting.respond('bride',sid,response),fail('PACKAGE_SERVICE_PLAN_UPDATE_REQUIRED'));
  const accepted=await f.fitting.respond('bride',sid,{...response,servicePlanVersion:1});
  assert.deepEqual(accepted.fittingQuote.servicePlan,fittingQuote.servicePlan);
  assert.equal(accepted.fittingQuote.state,'Accepted');
});
test('makeup arrangements use the event day and the customer’s confirmed trial details',async()=>{
  const f=fixture(),fittingVisit=await modernVisit(f);
  const path=`packageSelections/${sid}`,s=f.store.data.get(path);
  s.services=[
    {id:'beauty',serviceType:'makeup-hair',name:'Makeup',kind:'Optional'},
    {id:'trial-service',serviceType:'makeup-trial',name:'Trial',kind:'Add-on'},
  ];
  f.store.data.set('staff/artist',{active:true,role:'staff',name:'Test Artist'});
  f.store.data.set('staffScheduling/artist',{jobRole:'MakeupArtist',serviceTypes:['Bridal Makeup']});
  const visit={uid:'bride',status:'Confirmed',type:'Makeup Trial',assignedStaffId:'artist',revision:3,
    startAt:new Date('2026-10-18T06:00:00Z')};
  f.store.data.set('appointments/trial',visit);
  f.store.data.set('appointments/other-trial',{...visit,uid:'other'});
  f.store.data.set('appointments/same-day',{...visit,startAt:new Date('2026-10-21T02:00:00Z')});
  f.store.data.set('appointments/cancelled',{...visit,status:'Cancelled'});
  const options=await f.fitting.makeupOptions('staff',sid);
  assert.deepEqual(options.artists,[{id:'artist',name:'Test Artist'}]);
  assert.deepEqual(options.trials,[{id:'trial',day:'2026-10-18',minuteOfDay:840,artistId:'artist',artistName:'Test Artist',revision:3}]);
  await assert.rejects(f.fitting.makeupOptions('artist',sid),fail('OPERATIONS_ACCESS_REQUIRED'));
  const hair={serviceId:'beauty',artistId:'artist',minuteOfDay:450};
  const linked={serviceId:'trial-service',appointmentId:'trial',appointmentRevision:3};
  const quote={requestId:'makeup-quote',revision:0,decisionRevision:s.fittingDecisionRevision,
    note:'The makeup and hair arrangements have been agreed.',lines:[]};
  const send=(...serviceConfirmations)=>f.fitting.quote('staff',sid,{...quote,serviceConfirmations});
  await assert.rejects(send(hair,{...linked,appointmentId:'other-trial'}),fail('PACKAGE_MAKEUP_TRIAL_CHANGED'));
  await assert.rejects(send(hair,{...linked,appointmentRevision:2}),fail('PACKAGE_MAKEUP_TRIAL_CHANGED'));
  await assert.rejects(send({...hair,artistId:'staff'},linked),fail('PACKAGE_MAKEUP_ARTIST_UNAVAILABLE'));
  await assert.rejects(send({...hair,day:'2026-10-20'},linked),fail('PACKAGE_SERVICE_TIMING_REQUIRED'));
  await assert.rejects(send(hair,{serviceId:'trial-service',artistId:'artist',day:'2026-10-21',minuteOfDay:630}),fail('PACKAGE_SERVICE_TIMING_REQUIRED'));
  const {fittingQuote}=await send(hair,linked);
  assert.equal(fittingQuote.servicePlan[0].timing,'2026-10-21 · 07:30 MYT · Test Artist');
  assert.equal(fittingQuote.servicePlan[1].timing,'2026-10-18 · 14:00 MYT · Test Artist');
  assert.equal(fittingQuote.servicePlan[1].schedule.appointmentId,'trial');
  const accept={response:'Accept',revision:1,servicePlanVersion:1};
  f.store.data.set('appointments/trial',{...visit,status:'Cancelled'});
  await assert.rejects(f.fitting.respond('bride',sid,accept),fail('PACKAGE_MAKEUP_TRIAL_CHANGED'));
  f.store.data.set('appointments/trial',visit);
  const accepted=await f.fitting.respond('bride',sid,accept);
  assert.ok(accepted.fittingQuote.servicePlan.every(row=>!row.schedule));
  const rental={appointmentId:fittingVisit.appointmentId,requestId:'hold',planRevision:1,depositCents:39950,
    fittingRevision:(await f.store.get(path)).fittingDecisionRevision};
  f.store.data.set('appointments/trial',{...visit,startAt:new Date('2026-10-18T07:00:00Z')});
  await assert.rejects(f.workflow.confirm('staff',sid,rental),fail('PACKAGE_MAKEUP_TRIAL_CHANGED'));
  f.store.data.set('appointments/trial',{...visit,status:'Completed'});
  assert.equal((await f.workflow.confirm('staff',sid,rental)).state,'Held');
});
test('all four real customer decisions complete attendance without making a deposit or consuming fitting credit',async()=>{
  for(const outcome of ['Selected','Reselect','Considering','NotProceeding']){
    const f=fixture(),b=await modernVisit(f,outcome);
    assert.equal((await f.store.get(`appointments/${b.appointmentId}`)).status,'Completed');
    assert.equal((await f.store.list('sandboxInvoices')).length,1);
    assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,null);
    assert.equal((await f.store.list('rentals')).length,0);
    await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'r',planRevision:1,fittingRevision:1,depositCents:39950}),fail('FITTING_QUOTE_ACCEPTANCE_REQUIRED'));
    if(outcome!=='Selected')assert.equal((await f.snapshot()).plans[0].nextAction.type,'packages');
  }
});
test('included adjustments can be quoted by staff, but only the owner can accept the exact proposal',async()=>{
  const f=fixture(),b=await modernVisit(f,'Selected','Basic');await proposal(f);
  for(const uid of ['staff','other'])await assert.rejects(f.fitting.respond(uid,sid,{revision:1,response:'Accept'}),fail('SELECTION_ACCESS_DENIED'));
  const accepted=await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
  for(const internal of ['context','fingerprint','by','respondedBy'])assert.equal(Object.hasOwn(accepted.fittingQuote,internal),false);
  const s=await f.store.get(`packageSelections/${sid}`);
  const r=await f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'new-rental',planRevision:1,fittingRevision:s.fittingDecisionRevision,depositCents:39950});
  assert.equal(r.fittingCreditCents,5000);assert.equal(r.totalCents,89900);assert.equal(r.balanceCents,44950);
  assert.equal(r.fittingQuote.lines.length,1);
});
test('paid adjustments need manager authority and are included exactly once in the agreed 50 percent deposit',async()=>{
  const f=fixture(),b=await modernVisit(f,'Selected','Assessment');f.store.data.set('staff/manager',{role:'manager',active:true,name:'Manager'});
  await assert.rejects(proposal(f,{extra:10000}),fail('MANAGER_QUOTE_REQUIRED'));
  await proposal(f,{extra:10000,uid:'manager'});
  assert.equal((await f.store.get(`packageSelections/${sid}`)).totalCents,89900);
  assert.equal((await f.store.list('sandboxInvoices')).length,1);
  await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
  const s=await f.store.get(`packageSelections/${sid}`);
  const input={appointmentId:b.appointmentId,requestId:'extra-rental',planRevision:1,fittingRevision:s.fittingDecisionRevision,depositCents:44950};
  const r=await f.workflow.confirm('staff',sid,input);
  assert.equal(r.totalCents,99900);assert.equal(r.depositTargetCents,49950);assert.equal(r.balanceCents,49950);assert.equal(r.securityCents,30000);
  assert.equal((await f.workflow.confirm('staff',sid,input)).id,r.id);
  await assert.rejects(f.fitting.intent('bride',sid,{revision:s.fittingDecisionRevision,action:'Decline'}),fail('FITTING_ORDER_LOCKED'));
  await assert.rejects(proposal(f,{extra:10000,uid:'manager'}),fail('FITTING_ORDER_LOCKED'));
});

test('special alterations require manager feasibility review even when quoted at no extra charge',async()=>{
 const f=fixture();await modernVisit(f,'Selected','Assessment');
 await assert.rejects(proposal(f),fail('MANAGER_ASSESSMENT_REQUIRED'));
 f.store.data.set('staff/manager',{role:'manager',active:true});
 await proposal(f,{uid:'manager'});assert.equal((await f.store.get(`packageSelections/${sid}`)).fittingQuote.extraCents,0);
});
test('changed prices or dates invalidate a proposal instead of silently using old consent',async()=>{
  for(const mutation of [{promotionRevision:1},{rentalPlanRevision:2},{totalCents:99900},{selectionRevision:1}]){
    const f=fixture(),b=await modernVisit(f);await proposal(f);await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
    const s=await f.store.get(`packageSelections/${sid}`);f.store.data.set(`packageSelections/${sid}`,{...s,...mutation});
    await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'stale',planRevision:mutation.rentalPlanRevision??1,fittingRevision:s.fittingDecisionRevision,depositCents:39950}),fail('FITTING_QUOTE_ACCEPTANCE_REQUIRED'));
    assert.equal((await f.store.list('rentals')).length,0);
  }
});
test('considering can resume; declined requires another review and does not refund or remove fitting history',async()=>{
  const f=fixture(),b=await modernVisit(f);await proposal(f);
  await f.fitting.respond('bride',sid,{revision:1,response:'Considering'});
  await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
  const s=await f.store.get(`packageSelections/${sid}`);
  await f.fitting.intent('bride',sid,{revision:s.fittingDecisionRevision,action:'Decline'});
  assert.equal((await f.store.get(`appointments/${b.appointmentId}`)).status,'Completed');
  assert.equal((await f.store.get(`sandboxInvoices/${b.invoiceId}`)).state,'SandboxPaid');
  await assert.rejects(proposal(f),fail('FITTING_SELECTION_REQUIRED'));
  const declined=await f.store.get(`packageSelections/${sid}`);
  await f.fitting.intent('bride',sid,{revision:declined.fittingDecisionRevision,action:'Review'});
  assert.equal((await f.store.get(`packageSelections/${sid}`)).fittingDecision.state,'AwaitingReview');
});
test('quote writes are revisioned, idempotent and reject invalid lines or forged identities',async()=>{
  const f=fixture();await modernVisit(f,'Selected','Basic');await proposal(f);await proposalRetry();
  async function proposalRetry(){const old=await f.store.get(`packageSelections/${sid}`);const q=old.fittingQuote;
    const payload={requestId:q.requestId,revision:0,decisionRevision:1,note:q.note,lines:q.lines};
    assert.equal((await f.fitting.quote('staff',sid,payload)).fittingQuote.revision,1);
    await assert.rejects(f.fitting.quote('staff',sid,{...payload,note:'A different proposal with the same request ID.'}),fail('REQUEST_CONFLICT'));
    await assert.rejects(f.fitting.quote('bride',sid,payload),fail('STAFF_REQUIRED'));
    await assert.rejects(f.fitting.quote('inactive',sid,payload),fail('STAFF_REQUIRED'));
    await assert.rejects(f.fitting.quote('staff',sid,{...payload,requestId:'bad',lines:[{description:'Bad fee',amountCents:-1}]}),fail('INVALID_FITTING_QUOTE'));
  }
});
test('reselection preserves paid attendance and credit; requires an exact preview and re-review before any deposit',async()=>{
  const f=fixture(),b=await modernVisit(f,'Reselect');
  f.store.data.set('servicePackages/p',{id:'p',active:true,revision:1,name:'Bridal',description:'Original bridal package',basePriceCents:89900,includedGownCount:1,eligibleDressIds:['gown'],services:[{id:'core',name:'Gown rental',kind:'Required',priceCents:0}]});
  const s=await f.store.get(`packageSelections/${sid}`);f.store.data.set(`packageSelections/${sid}`,{...s,packageId:'p'});
  f.store.data.set('dresses/gown',{published:true,availability:'Available',revision:1,name:'Gown',category:'A-Line',colour:'Ivory',sizes:'M'});
  const input={requestId:'replace',revision:0,packageRevision:1,removedIds:[],addonIds:[],gowns:[{dressId:'gown',size:'M',revision:1}],accessories:[],previewOnly:true};
  const quote=await f.packages.revise('bride',sid,input);assert.equal(quote.totalCents,89900);
  await assert.rejects(f.packages.revise('other',sid,input),fail('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.packages.revise('bride',sid,{...input,previewOnly:false,expectedTotalCents:1}),fail('DEPOSIT_QUOTE_CHANGED'));
  await f.packages.revise('bride',sid,{...input,previewOnly:false,expectedTotalCents:quote.totalCents});
  const changed=await f.store.get(`packageSelections/${sid}`);
  assert.deepEqual(changed.appointmentIds,[b.appointmentId]);assert.equal(changed.fittingDecision.state,'AwaitingReview');
  assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,null);
  assert.equal((await f.store.list('sandboxInvoices')).length,1);assert.equal(changed.selectionHistory.length,1);
});
test('agreed adjustments must be completed for this exact rental before handover; agreed total remains stable after reservation',async()=>{
  const f=fixture(),b=await modernVisit(f,'Selected','Basic');await proposal(f);await f.fitting.respond('bride',sid,{revision:1,response:'Accept'});
  let s=await f.store.get(`packageSelections/${sid}`);
  let r=await f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'ready',planRevision:1,fittingRevision:s.fittingDecisionRevision,depositCents:39950});
  await f.paid(r.invoiceId);r=await f.store.get(`rentals/${r.id}`);await f.paid(r.balanceInvoiceId);await f.paid(r.securityInvoiceId);
  f.setTime(Date.parse('2026-10-20T02:00:00Z'));
  await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'collect'}),fail('FITTING_ADJUSTMENTS_PENDING'));
  f.store.data.set(`rentalServiceProgress/${sid}`,{rentalId:'wrong',alteration:'Completed'});
  await assert.rejects(f.rentals.fulfil('staff',r.id,{action:'collect'}),fail('FITTING_ADJUSTMENTS_PENDING'));
  f.store.data.set(`rentalServiceProgress/${sid}`,{rentalId:r.id,alteration:'Completed'});
  await f.rentals.fulfil('staff',r.id,{action:'collect'});
  assert.equal((await f.store.get(`rentals/${r.id}`)).fulfilment,'Collected');
  s=await f.store.get(`packageSelections/${sid}`);f.store.data.set(`packageSelections/${sid}`,{...s,rentalPlanRevision:5});
  const row=(await f.packages.selections('bride')).selections[0];
  assert.equal(row.agreedTotalCents,r.totalCents);assert.equal(row.fittingQuote.state,'Accepted');assert.equal(row.fittingQuote.by,undefined);
});

function measured(){return {schemaVersion:1,bodyCm:{bust:85,waist:68},gowns:[{dressId:'gown',size:'M',fit:{bust:'Good',waist:'Loose',hips:'NotAssessed',length:'NotAssessed'},adjustmentNotes:'Take in waist by 2 cm'}],followUp:'Required',targetDate:'2026-10-20'};}

test('an undecided follow-up requirement cannot be presented as a final customer proposal',async()=>{
 const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
 await f.fitting.record('staff',sid,{...f.record,outcome:'Selected',adjustment:'Basic',appointmentId:b.appointmentId,assessment:{...measured(),followUp:'NotDecided'}});
 await assert.rejects(proposal(f),fail('FITTING_FOLLOW_UP_DECISION_REQUIRED'));
 assert.equal((await f.store.get(`packageSelections/${sid}`)).fittingQuote,null);assert.equal((await f.store.list('rentals')).length,0);
});

async function finalFixture(){
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  await f.fitting.record('staff',sid,{...f.record,outcome:'Selected',adjustment:'Basic',appointmentId:b.appointmentId,assessment:measured()});
  await proposal(f);await f.fitting.respond('bride',sid,{revision:1,response:'Accept',adjustmentPlanVersion:1});
  const s=await f.store.get(`packageSelections/${sid}`);
  let r=await f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'rent',planRevision:1,fittingRevision:s.fittingDecisionRevision,depositCents:39950});
  await f.paid(r.invoiceId);r=await f.store.get(`rentals/${r.id}`);await f.paid(r.balanceInvoiceId);await f.paid(r.securityInvoiceId);
  f.setTime(f.clock()+60000);
  await f.packages.serviceProgress('staff',sid,{requestId:'prep',revision:0,alteration:'Completed',preparation:'Preparing',note:'Waist adjustment completed; final fit check needed.'});
  const follow=await f.packages.book('bride',sid,{...f.input,requestId:'follow',startAt:Date.parse('2026-10-20T02:00:00Z')});
  f.finalInput={requestId:'final',rentalId:r.id,appointmentId:follow.appointmentId,confirmed:true,note:'Customer attended, checked the altered waist and accepted the fit.'};
  return {...f,r,b,follow};
}

test('required final fitting gates handover and ready; real follow-up completes without another fee/credit',async()=>{
  const f=await finalFixture();assert.equal(f.follow.invoiceId,null);const invoices=(await f.store.list('sandboxInvoices')).length;
  assert.equal((await f.packages.selections('staff')).selections[0].appointments.find(b=>b.id===f.follow.appointmentId).feeIncluded,true);
  await assert.rejects(f.packages.serviceProgress('staff',sid,{requestId:'ready',revision:1,alteration:'Completed',preparation:'Ready',note:'Everything prepared for customer collection.'}),fail('FINAL_FITTING_PENDING'));
  f.setTime(Date.parse('2026-10-20T02:00:00Z'));
  await assert.rejects(f.rentals.fulfil('staff',f.r.id,{action:'collect'}),fail('FINAL_FITTING_PENDING'));
  const saved=await f.fitting.final('staff',sid,f.finalInput);
  assert.equal(saved.finalFitting.state,'Completed');
  assert.equal((await f.store.get(`appointments/${f.follow.appointmentId}`)).status,'Completed');
  assert.equal(+((await f.store.get(`appointments/${f.follow.appointmentId}`)).actualAttendedAt),f.clock());
  assert.equal((await f.store.list('sandboxInvoices')).length,invoices);assert.equal((await f.store.list('fittingCredits')).length,1);
  assert.deepEqual(await f.fitting.final('staff',sid,f.finalInput),saved);
  await assert.rejects(f.fitting.final('staff',sid,{...f.finalInput,note:'A conflicting duplicated request must not overwrite attendance.'}),fail('REQUEST_CONFLICT'));
  await f.packages.serviceProgress('staff',sid,{requestId:'ready',revision:1,alteration:'Completed',preparation:'Ready',note:'Everything prepared for customer collection.'});
  await f.rentals.fulfil('staff',f.r.id,{action:'collect'});
});

test('assigned fitting specialist can record the final visit without opening its rental',async()=>{
  const f=await finalFixture();
  f.store.data.set('staff/specialist',{active:true,role:'staff'});
  f.store.data.set('staffScheduling/specialist',{jobRole:'FittingSpecialist'});
  await assert.rejects(f.packages.assignedFitting('specialist',sid),fail('SELECTION_ACCESS_DENIED'));
  f.store.data.get(`appointments/${f.follow.appointmentId}`).assignedStaffId='specialist';
  const details=await f.packages.assignedFitting('specialist',sid);
  assert.deepEqual(details.appointments.map(a=>a.id),[f.follow.appointmentId]);
  assert.equal(details.serviceProgress.alteration,'Completed');
  assert(!JSON.stringify(details).includes('InvoiceId'));
  assert(!Object.hasOwn(details.rental,'depositCents'));
  f.setTime(Date.parse('2026-10-20T02:00:00Z'));
  const recorded=await f.fitting.final('specialist',sid,f.finalInput);
  assert.equal(recorded.finalFitting.state,'Completed');
  f.store.data.get(`appointments/${f.follow.appointmentId}`).assignedStaffId='staff';
  await assert.rejects(f.fitting.final('specialist',sid,f.finalInput),fail('BOOKING_ACCESS_DENIED'));
});
test('final fitting rejects forged identity, initial visit, unaccepted fit, unfinished alterations and wrong rental',async()=>{
  const f=await finalFixture(),before=structuredClone([...f.store.data]);
  for(const actor of ['bride','other','inactive'])await assert.rejects(f.fitting.final(actor,sid,f.finalInput),fail('STAFF_REQUIRED'));
  await assert.rejects(f.fitting.final('staff',sid,{...f.finalInput,confirmed:false}),fail('INVALID_FINAL_FITTING'));
  await assert.rejects(f.fitting.final('staff',sid,{...f.finalInput,rentalId:'wrong'}),fail('RENTAL_PLAN_CHANGED'));
  await assert.rejects(f.fitting.final('staff',sid,{...f.finalInput,appointmentId:f.b.appointmentId}),fail('FINAL_FITTING_VISIT_REQUIRED'));
  assert.deepEqual([...f.store.data],before);
  f.store.data.get(`rentalServiceProgress/${sid}`).alteration='InProgress';
  await assert.rejects(f.fitting.final('staff',sid,f.finalInput),fail('FITTING_ADJUSTMENTS_PENDING'));
});

test('new alteration work invalidates final fitting but preparation-note changes do not',async()=>{
  const f=await finalFixture();await f.fitting.final('staff',sid,f.finalInput);
  const body={revision:1,alteration:'Completed',preparation:'Preparing',note:'Steam gown and check included accessories.'};
  await f.packages.serviceProgress('staff',sid,{...body,requestId:'notes'});
  assert.equal((await f.store.get(`rentals/${f.r.id}`)).finalFitting.state,'Completed');
  f.setTime(f.clock()+60000);
  await f.packages.serviceProgress('staff',sid,{...body,requestId:'rework',revision:2,alteration:'InProgress'});
  assert.equal((await f.store.get(`rentals/${f.r.id}`)).finalFitting.state,'NeedsReview');
  await f.packages.serviceProgress('staff',sid,{...body,requestId:'done-again',revision:3});
  await assert.rejects(f.fitting.final('staff',sid,{...f.finalInput,requestId:'reuse-visit'}),fail('FINAL_FITTING_DATE_CONFLICT'));
});

test('changing package preserves exact attendance and one credit, removes old promotion, requires new consent and locks after invoice',async()=>{
  const f=fixture(),b=await modernVisit(f,'Reselect');
  Object.assign(f.store.data.get(`packageSelections/${sid}`),{packageId:'old',promotion:{id:'old-offer',discountCents:5000}});
  f.store.data.set('servicePackages/new',{id:'new',active:true,revision:1,name:'Signature',description:'A different bridal package',basePriceCents:129900,includedGownCount:1,eligibleDressIds:['gown'],services:[{id:'core',name:'Gown rental',kind:'Required',priceCents:0}]});
  f.store.data.set('dresses/gown',{published:true,availability:'Available',revision:1,name:'Gown',category:'A-Line',colour:'Ivory',sizes:'M'});
  const input={requestId:'switch',revision:0,packageId:'new',packageRevision:1,removedIds:[],addonIds:[],gowns:[{dressId:'gown',size:'M',revision:1}],accessories:[],previewOnly:true};
  const q=await f.packages.revise('bride',sid,input);assert.equal(q.totalCents,129900);
  const save={...input,previewOnly:false,expectedTotalCents:q.totalCents};await f.packages.revise('bride',sid,save);await f.packages.revise('bride',sid,save);
  const s=await f.store.get(`packageSelections/${sid}`);
  assert.equal(s.packageId,'new');assert.equal(s.promotion,null);assert.equal(s.selectionHistory[0].packageId,'old');
  assert.deepEqual(s.appointmentIds,[b.appointmentId]);assert.equal(s.fittingDecision.state,'AwaitingReview');assert.equal(s.fittingQuote,null);
  assert.equal((await f.store.get(`fittingCredits/${b.appointmentId}`)).consumedBy,null);assert.equal((await f.store.list('sandboxInvoices')).length,1);
  await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'invalid',planRevision:1,fittingRevision:s.fittingDecisionRevision,depositCents:59950}),fail('FITTING_QUOTE_ACCEPTANCE_REQUIRED'));
  f.store.data.get(`packageSelections/${sid}`).invoiceId='locked';
  await assert.rejects(f.packages.revise('bride',sid,{...input,revision:1}),fail('FITTING_ORDER_LOCKED'));
});
test('measured fitting persists only its service record; accepted proposal snapshots instructions, not body data',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  const input={...f.record,outcome:'Selected',adjustment:'Basic',appointmentId:b.appointmentId,assessment:measured()};
  const before=(await f.store.list('sandboxInvoices')).length;
  const result=await f.fitting.record('staff',sid,input);assert.deepEqual(result.fittingDecision.assessment,measured());
  await f.fitting.record('staff',sid,input);assert.equal((await f.store.list('appointmentMail')).length,2);
  await assert.rejects(f.fitting.record('staff',sid,{...input,assessment:{...measured(),bodyCm:{bust:86}}}),fail('REQUEST_CONFLICT'));
  assert.equal((await f.store.get('brides/bride')).bust,undefined);assert.equal((await f.store.list('sandboxInvoices')).length,before);
  const quote=await proposal(f);assert.equal(quote.fittingQuote.adjustmentPlan.gowns[0].instructions,'Take in waist by 2 cm');
  assert.equal(JSON.stringify(quote.fittingQuote).includes('bodyCm'),false);
  await assert.rejects(f.fitting.respond('bride',sid,{revision:1,response:'Accept'}),fail('FITTING_PLAN_UPDATE_REQUIRED'));
  await f.fitting.respond('bride',sid,{revision:1,response:'Accept',adjustmentPlanVersion:1});
  const s=await f.store.get(`packageSelections/${sid}`);s.fittingDecision.assessment.gowns[0].adjustmentNotes='Different alteration';f.store.data.set(`packageSelections/${sid}`,s);
  await assert.rejects(f.workflow.confirm('staff',sid,{appointmentId:b.appointmentId,requestId:'changed',planRevision:1,fittingRevision:s.fittingDecisionRevision,depositCents:39950}),fail('FITTING_QUOTE_ACCEPTANCE_REQUIRED'));
});
test('invalid or unauthorized metrics cannot complete attendance or create side effects',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  const input={...f.record,outcome:'Selected',adjustment:'Basic',appointmentId:b.appointmentId,assessment:measured()},before=structuredClone([...f.store.data]);
  for(const uid of ['bride','other','inactive'])await assert.rejects(f.fitting.record(uid,sid,input),fail('STAFF_REQUIRED'));
  await assert.rejects(f.fitting.record('staff',sid,{...input,assessment:{...measured(),bodyCm:{bust:-85}}}),fail('INVALID_FITTING_ASSESSMENT'));
  assert.deepEqual([...f.store.data],before);
});
test('completion target is rechecked before a new acceptance, but identical factual attendance retries remain idempotent',async()=>{
  const f=fixture(),b=await f.packages.book('bride',sid,f.input);await f.paid(b.invoiceId);
  const input={...f.record,outcome:'Selected',adjustment:'Basic',appointmentId:b.appointmentId,assessment:measured()};
  await f.fitting.record('staff',sid,input);await proposal(f);
  f.setTime(Date.parse('2026-10-21T02:00:00Z'));
  await f.fitting.record('staff',sid,input);assert.equal((await f.store.list('appointmentMail')).length,2);
  await assert.rejects(f.fitting.respond('bride',sid,{revision:1,response:'Accept',adjustmentPlanVersion:1}),fail('INVALID_FITTING_ASSESSMENT'));
  assert.equal((await f.store.list('rentals')).length,0);
});
