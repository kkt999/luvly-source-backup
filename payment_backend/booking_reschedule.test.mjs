import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {BookingService} from './booking_service.mjs';
import {withBusinessNotifications} from './business_notifications.mjs';
import {createHandler} from './http_app.mjs';
import {appointmentEvent} from './calendar_service.mjs';
import {WorkforceService,makeupTrial} from './workforce.mjs';
const now=Date.parse('2026-11-02T00:00:00Z'),start=Date.parse('2026-11-03T02:00:00Z'),hour=3600000;
const fails=code=>e=>e.code===code;
class Store {
  constructor(){this.rows=new Map(Object.entries({'brides/customer':{name:'Customer',phone:'0123456789',email:'customer@example.com'},'brides/other':{name:'Other',phone:'0123456789'},'staff/a':{active:true,role:'staff'},'staff/b':{active:true,role:'staff'},'staff/off':{active:false,role:'staff'},'schedulingSettings/policy':{requireServiceAssignments:true},'staffScheduling/a':{jobRole:'FittingSpecialist',serviceTypes:['Dress Trial','Bridal Consultation']},'staffScheduling/b':{jobRole:'FittingSpecialist',serviceTypes:['Dress Trial','Bridal Consultation']}}));this.queue=Promise.resolve();this.fail=false;}
  async get(path){return structuredClone(this.rows.get(path));}
  async activeStaffIds(){return ['a','b'];}
  atomic(fn){const op=this.queue.then(async()=>{const writes=new Map();let writing=false;
    const result=await fn({get:async p=>{assert(!writing,'Read after transaction write');return this.get(p);},set:(p,r)=>{writing=true;writes.set(p,r);},delete:p=>{writing=true;writes.set(p,null);}});
    if(this.fail)throw Error('Commit failed');for(const[p,r]of writes)r===null?this.rows.delete(p):this.rows.set(p,structuredClone(r));return result;});this.queue=op.catch(()=>{});return op;}
}
async function fixture({paid=true,notifications=false}={}){
  const base=new Store(),store=notifications?withBusinessNotifications(base,{now:()=>now}):base;
  const s=new BookingService({store,now:()=>now,feePolicy:paid,workforce:{}});
  const created=await s.create('customer',{requestId:'initial',type:'Dress Trial',startAt:start,notes:'Keep customer notes',feePolicyVersion:1});
  const id=created.appointmentId;
  if(paid){const b=base.rows.get(`appointments/${id}`),fee=base.rows.get(`sandboxInvoices/${b.fittingInvoiceId}`);base.rows.set(`appointments/${id}`,{...b,status:'Confirmed',revision:2});base.rows.set(`sandboxInvoices/${b.fittingInvoiceId}`,{...fee,state:'SandboxPaid',paidAt:now-1000});base.rows.set(`fittingCredits/${id}`,{uid:'customer',invoiceId:b.fittingInvoiceId,amountCents:5000,consumedBy:null,reservedBy:null});}
  return {base,store,s,id,move:(time=start+hour,requestId='change',revision=paid?2:1)=>s.reschedule('customer',id,{startAt:time,requestId,revision})};
}
test('makeup trial uses a qualified available artist, confirms without a fitting fee, and can move or cancel',async()=>{
  const base=new Store(),store=withBusinessNotifications(base,{now:()=>now});
  const workforce=new WorkforceService({store,now:()=>now});
  const s=new BookingService({store,now:()=>now,feePolicy:true,workforce});
  const day='2026-11-03',path=`appointmentAvailability/${day}`;
  const input={requestId:'makeup',type:makeupTrial,startAt:start,notes:'Soft rose look',feePolicyVersion:1};
  base.rows.set('schedulingSettings/policy',{requireServiceAssignments:false});
  base.rows.delete('staffScheduling/a'); // A legacy staff account is ineligible even in relaxed mode.
  assert.deepEqual((await s.day('customer',day,makeupTrial)).hours,[]);
  await assert.rejects(s.create('customer',input),fails('NO_STAFF_AVAILABLE'));

  base.rows.set('staffScheduling/b',{jobRole:'MakeupArtist',serviceTypes:['Bridal Makeup']});
  base.rows.set(path,{day,entries:{b:{available:false,startHour:11,endHour:12}},bookings:{},
    taskBlocks:{task:{staffId:'b',startHour:12,endHour:13}},revision:1});
  assert.deepEqual((await s.day('customer',day,makeupTrial)).hours,[10,14,15,16]);
  await assert.rejects(s.create('customer',{...input,dressId:'gown'}),fails('INVALID_BOOKING'));
  const result=await s.create('customer',input),id=result.appointmentId,bookingPath=`appointments/${id}`;
  assert.equal(result.status,'Confirmed');
  assert.equal(result.invoiceId,null);
  assert.equal((await base.get(bookingPath)).assignedStaffId,'b');
  assert.equal((await base.get(`appointmentMail/${id}-1`)).type,makeupTrial);
  assert.equal(appointmentEvent('customer',id,await base.get(bookingPath)).summary,'Luvly · Makeup Trial');
  assert([...base.rows].some(([p,r])=>p.startsWith('inboxes/b/items/')&&r.kind==='AppointmentConfirmed'));
  assert.deepEqual(await s.create('customer',input),result);
  await assert.rejects(s.create('other',{...input,requestId:'same-slot'}),fails('SLOT_UNAVAILABLE'));

  assert.equal((await s.rescheduleContext('customer',id)).type,makeupTrial);
  await assert.rejects(s.reschedule('customer',id,{requestId:'busy',startAt:start+hour,revision:1}),fails('NO_STAFF_AVAILABLE'));
  const nextStart=start+4*hour;
  await s.reschedule('customer',id,{requestId:'move',startAt:nextStart,revision:1});
  assert.equal((await base.get(bookingPath)).assignedStaffId,'b');
  assert.equal(await base.get(`appointmentSlots/${start}`),undefined);
  await s.transition('customer',id,{status:'Cancelled',revision:2,response:''});
  assert.equal(await base.get(`appointmentSlots/${nextStart}`),undefined);
  assert(![...base.rows.keys()].some(p=>p.startsWith('sandboxInvoices/')||p.startsWith('fittingCredits/')));
});

test('same-day move is atomic, retains reservation identity, verified fee/credit and unrelated bookings',async()=>{
  const f=await fixture(),before=await f.base.get(`appointments/${f.id}`),fee=await f.base.get(`sandboxInvoices/${before.fittingInvoiceId}`),credit=await f.base.get(`fittingCredits/${f.id}`);
  f.base.rows.get('appointmentAvailability/2026-11-03').bookings[16]={appointmentId:'unrelated',staffId:'b',uid:'other'};
  const context=await f.s.rescheduleContext('customer',f.id);assert(context.eligible);assert(context.feePreserved);
  await f.move();const after=await f.base.get(`appointments/${f.id}`),day=await f.base.get('appointmentAvailability/2026-11-03');
  assert.equal(after.status,'Confirmed');assert.equal(after.revision,3);assert.equal(+after.startAt,start+hour);assert.equal(after.assignedStaffId,'a');assert.equal(after.notes,before.notes);
  assert.equal(await f.base.get(`appointmentSlots/${start}`),undefined);assert.equal(day.bookings[10],undefined);assert.equal(day.bookings[11].appointmentId,f.id);assert.equal(day.bookings[16].appointmentId,'unrelated');
  assert.equal((await f.base.get(`appointmentSlots/${start+hour}`)).appointmentId,f.id);
  assert.deepEqual(await f.base.get(`sandboxInvoices/${before.fittingInvoiceId}`),fee);assert.deepEqual(await f.base.get(`fittingCredits/${f.id}`),credit);
  assert.equal(after.rescheduleHistory[0].fromStartAt,start);assert.equal((await f.base.get(`appointmentMail/${f.id}-3`)).event,'Rescheduled');
  assert.equal((await f.s.day('customer','2026-11-03','Dress Trial')).hours.includes(10),true);
});
test('cross-day move frees the old date and preserves exceptions on both dates',async()=>{
  const f=await fixture();f.base.rows.get('appointmentAvailability/2026-11-03').entries={b:{available:false,startHour:14,endHour:16}};
  f.base.rows.set('appointmentAvailability/2026-11-04',{entries:{b:{available:true,startHour:10,endHour:12}},bookings:{16:{appointmentId:'other'}},revision:8});
  await f.move(start+86400000);const old=await f.base.get('appointmentAvailability/2026-11-03'),next=await f.base.get('appointmentAvailability/2026-11-04');
  assert.equal(old.bookings[10],undefined);assert(old.entries.b);assert.equal(next.bookings[10].appointmentId,f.id);assert.equal(next.bookings[16].appointmentId,'other');assert.equal(next.revision,9);assert(next.entries.b);
});
test('occupied or staff/task-conflicting target leaves the complete original visit intact',async()=>{
  const f=await fixture();f.base.rows.set(`appointmentSlots/${start+hour}`,{appointmentId:'busy'});
  let before=structuredClone(f.base.rows);await assert.rejects(f.move(),fails('SLOT_UNAVAILABLE'));assert.deepEqual(f.base.rows,before);
  f.base.rows.delete(`appointmentSlots/${start+hour}`);
  f.base.rows.get('appointmentAvailability/2026-11-03').entries={a:{available:false,startHour:11,endHour:12},b:{available:false,startHour:11,endHour:12}};
  before=structuredClone(f.base.rows);await assert.rejects(f.move(),fails('NO_STAFF_AVAILABLE'));assert.deepEqual(f.base.rows,before);
});
test('keep the assigned employee when possible; otherwise require a qualified, available replacement',async()=>{
  const f=await fixture();f.base.rows.get(`appointments/${f.id}`).assignedStaffId='b';
  await f.move();assert.equal((await f.base.get(`appointments/${f.id}`)).assignedStaffId,'b');
  f.base.rows.get('appointmentAvailability/2026-11-03').entries={b:{available:false,startHour:12,endHour:13}};
  f.base.rows.get('staffScheduling/a').serviceTypes=['Bridal Consultation'];
  await assert.rejects(f.move(start+2*hour,'again',3),fails('NO_STAFF_AVAILABLE'));
  f.base.rows.get('staffScheduling/a').serviceTypes=['Dress Trial'];
  await f.move(start+2*hour,'again',3);assert.equal((await f.base.get(`appointments/${f.id}`)).assignedStaffId,'a');
});
test('scheduled work blocks prevent double assignment and an expired payment hold can be reused safely',async()=>{
 const f=await fixture(),day=f.base.rows.get('appointmentAvailability/2026-11-03');
 day.taskBlocks={task:{staffId:'a',startHour:11,endHour:12}};
 await f.move();assert.equal((await f.base.get(`appointments/${f.id}`)).assignedStaffId,'b');assert(day.taskBlocks.task);
 f.base.rows.set(`appointmentSlots/${start+2*hour}`,{appointmentId:'expired'});
 f.base.rows.set('appointments/expired',{uid:'other',status:'AwaitingPayment',paymentExpiresAt:now-1,revision:1});
 f.base.rows.get('appointmentAvailability/2026-11-03').bookings[12]={appointmentId:'expired',staffId:'a',uid:'other'};
 await f.move(start+2*hour,'second',3);
 assert.equal((await f.base.get('appointments/expired')).status,'Expired');assert.equal((await f.base.get(`appointmentSlots/${start+2*hour}`)).appointmentId,f.id);
});
test('only owner customers may move; closed, started, unpaid, corrupted or payment-review visits fail closed',async()=>{
  const f=await fixture();
  for(const uid of ['other','a','off','missing'])await assert.rejects(f.s.reschedule(uid,f.id,{revision:2,startAt:start+hour,requestId:'x'}),fails('BOOKING_ACCESS_DENIED'));
  const original=await f.base.get(`appointments/${f.id}`);
  for(const status of ['Cancelled','Completed','NoShow','Expired','Declined','Requested']){
    f.base.rows.set(`appointments/${f.id}`,{...original,status});await assert.rejects(f.move(),fails('RESCHEDULE_NOT_AVAILABLE'));
  }
  f.base.rows.set(`appointments/${f.id}`,{...original,status:'AwaitingPayment'});await assert.rejects(f.move(),fails('RESCHEDULE_PAYMENT_REQUIRED'));
  f.base.rows.set(`appointments/${f.id}`,{...original,startAt:new Date(now)});await assert.rejects(f.move(),fails('RESCHEDULE_NOT_AVAILABLE'));
  f.base.rows.set(`appointments/${f.id}`,original);f.base.rows.delete(`appointmentSlots/${start}`);await assert.rejects(f.move(),fails('BOOKING_RESERVATION_CHANGED'));
  f.base.rows.set(`appointmentSlots/${start}`,{appointmentId:f.id});f.base.rows.get(`sandboxInvoices/${original.fittingInvoiceId}`).reviewReason='Review';await assert.rejects(f.move(),fails('RESCHEDULE_PAYMENT_REVIEW'));
});
test('package fitting remains before pickup/event; package/rental amounts and references do not change',async()=>{
  const f=await fixture(),selection={uid:'customer',appointmentIds:[f.id],selectedGowns:[{dressId:'gown'}],totalCents:89900,rentalPlan:{pickupDate:'2026-11-05',eventDate:'2026-11-06'}};
  f.base.rows.set(`packageAppointments/${f.id}`,{uid:'customer',selectionId:'selection'});f.base.rows.set('packageSelections/selection',selection);
  const c=await f.s.rescheduleContext('customer',f.id);assert.equal(c.latestDay,'2026-11-04');
  await assert.rejects(f.move(start+2*86400000),fails('FITTING_DATE_CONFLICT'));await f.move(start+86400000);
  assert.deepEqual(await f.base.get('packageSelections/selection'),selection);assert.equal((await f.base.get(`packageAppointments/${f.id}`)).selectionId,'selection');
});
test('included follow-up allows pickup day but never event day and refuses collected/cancelled rental',async()=>{
  const f=await fixture({paid:false});f.base.rows.get(`appointments/${f.id}`).feeIncluded=true;
  f.base.rows.set(`packageAppointments/${f.id}`,{uid:'customer',selectionId:'selection'});
  f.base.rows.set('packageSelections/selection',{uid:'customer',appointmentIds:[f.id],selectedGowns:[{}],rentalId:'rental'});
  f.base.rows.set('rentals/rental',{uid:'customer',state:'Locked',paymentState:'Paid',pickupDate:'2026-11-05',eventDate:'2026-11-06'});
  assert.equal((await f.s.rescheduleContext('customer',f.id)).latestDay,'2026-11-05');
  await f.move(start+2*86400000);assert.equal((await f.base.get(`appointments/${f.id}`)).feeIncluded,true);
  await assert.rejects(f.move(start+3*86400000,'second',2),fails('FITTING_DATE_CONFLICT'));
  f.base.rows.get('rentals/rental').collectedAt=now;await assert.rejects(f.move(start+hour,'third',2),fails('APPOINTMENT_PACKAGE_REVIEW_REQUIRED'));
});
test('retry is idempotent, changed payload conflicts and stale revision cannot move a visit again',async()=>{
  const f=await fixture();const first=await f.move(),snapshot=structuredClone(f.base.rows);assert.deepEqual(await f.move(),first);assert.deepEqual(f.base.rows,snapshot);
  await assert.rejects(f.move(start+2*hour),fails('REQUEST_CONFLICT'));
  await assert.rejects(f.move(start+2*hour,'other-operation'),fails('BOOKING_CHANGED'));
  await f.move(start+2*hour,'next',3);const retry=await f.move();assert.equal(retry.startAt,start+2*hour);assert.equal(retry.revision,4);
});
test('concurrent changes to one visit have one winner and destination races do not destroy the loser',async()=>{
  const f=await fixture();let result=await Promise.allSettled([f.move(),f.move(start+2*hour,'racer')]);assert.equal(result.filter(x=>x.status==='fulfilled').length,1);assert.equal(result.find(x=>x.status==='rejected').reason.code,'BOOKING_CHANGED');
  const other=await f.s.create('other',{requestId:'other',type:'Bridal Consultation',startAt:start+2*hour,notes:'',feePolicyVersion:1});
  result=await Promise.allSettled([f.move(start+4*hour,'dest1',3),f.s.reschedule('other',other.appointmentId,{revision:1,requestId:'dest2',startAt:start+4*hour})]);
  assert.equal(result.filter(x=>x.status==='fulfilled').length,1);assert.equal(result.find(x=>x.status==='rejected').reason.code,'SLOT_UNAVAILABLE');
  assert.equal((await f.base.get(`appointmentSlots/${start+2*hour}`)).appointmentId,other.appointmentId);
});
test('rollback includes old/new slots, audit, email and in-app notifications; old and new staff are notified once',async()=>{
  const f=await fixture({notifications:true});f.base.rows.get('appointmentAvailability/2026-11-03').entries={a:{available:false,startHour:11,endHour:12}};
  const before=structuredClone(f.base.rows);f.base.fail=true;await assert.rejects(f.move());assert.deepEqual(f.base.rows,before);
  f.base.fail=false;await f.move();
  for(const uid of ['customer','a','b'])assert.equal([...f.base.rows].filter(([p,r])=>p.startsWith(`inboxes/${uid}/items/`)&&r.kind==='AppointmentChanged').length,1);
  await f.move();for(const uid of ['customer','a','b'])assert.equal([...f.base.rows].filter(([p,r])=>p.startsWith(`inboxes/${uid}/items/`)&&r.kind==='AppointmentChanged').length,1);
});
test('invalid times, forged types/owners and malformed package dates cannot bypass move constraints',async()=>{
  const f=await fixture();for(const extra of [{startAt:start},{startAt:start+1},{startAt:now},{startAt:start+3*hour},{uid:'other'},{type:'Bridal Consultation'},{revision:1.5},{requestId:'../bad'}])await assert.rejects(f.s.reschedule('customer',f.id,{revision:2,startAt:start+hour,requestId:'invalid',...extra}));
  f.base.rows.set(`packageAppointments/${f.id}`,{uid:'customer',selectionId:'selection'});f.base.rows.set('packageSelections/selection',{uid:'customer',appointmentIds:[f.id],selectedGowns:[{}],rentalPlan:{pickupDate:'invalid',eventDate:'2026-11-10'}});
  await assert.rejects(f.move(),fails('APPOINTMENT_PACKAGE_REVIEW_REQUIRED'));
});
test('HTTP requires auth and rejects foreign visits, query tokens and forged body identity',async t=>{
  const f=await fixture(),server=createServer(createHandler({bookings:f.s,verifyToken:async uid=>({uid})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>{server.closeAllConnections();server.close();});
  const url=`http://127.0.0.1:${server.address().port}/v1/appointments/${f.id}/reschedule`;
  assert.equal((await fetch(url)).status,401);assert.equal((await fetch(url,{headers:{Authorization:'Bearer other'}})).status,403);
  assert.equal((await fetch(url+'?uid=other',{headers:{Authorization:'Bearer customer'}})).status,400);
  const r=await fetch(url,{method:'POST',headers:{Authorization:'Bearer customer','Content-Type':'application/json'},body:JSON.stringify({revision:2,startAt:start+hour,requestId:'http'})});assert.equal(r.status,200);assert.equal((await r.json()).appointmentId,f.id);
});
