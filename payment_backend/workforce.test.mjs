import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {WorkforceService} from './workforce.mjs';
import {BookingService} from './booking_service.mjs';
import {createHandler} from './http_app.mjs';

const now=Date.parse('2026-10-21T00:00:00Z'),day='2026-10-22',start=Date.parse(day+'T06:00:00Z');
const fails=code=>e=>e.code===code;
function fixture(){const data=new Map(Object.entries({
  'staff/john':{active:true,role:'staff',name:'John'},'staff/mary':{active:true,role:'staff',name:'Mary'},'staff/nina':{active:true,role:'staff',name:'Nina'},'staff/boss':{active:true,role:'manager',name:'Manager'},
  'staffScheduling/john':{jobRole:'FrontDesk',serviceTypes:[],revision:1},'staffScheduling/mary':{jobRole:'FittingSpecialist',serviceTypes:['Dress Trial'],revision:1},
  'staffScheduling/nina':{jobRole:'MakeupArtist',serviceTypes:['Bridal Makeup'],revision:1},'staffScheduling/boss':{jobRole:'Consultant',serviceTypes:['Bridal Consultation'],revision:1},
  'brides/bride':{name:'Amy',phone:'0123456789'},
}));let queue=Promise.resolve();
  const scan=(collection,predicate=()=>true)=>[...data].filter(([p,d])=>p.startsWith(collection+'/')&&predicate(d)).map(([p,d])=>({...structuredClone(d),id:p.split('/')[1]}));
  const store={get:async p=>structuredClone(data.get(p)),activeStaffIds:async()=>scan('staff',d=>d.active).map(d=>d.id),
    atomic:fn=>{const run=queue.then(async()=>{const writes=new Map();let writing=false;const read=f=>{assert(!writing,'read after write');return f();};const result=await fn({get:p=>read(()=>store.get(p)),
      staffRoster:()=>read(()=>scan('staff')),timeOffRequests:uid=>read(()=>scan('staffTimeOff',d=>uid===undefined||d.uid===uid)),
      staffAppointments:uid=>read(()=>scan('appointments',d=>d.assignedStaffId===uid)),schedulingDays:()=>read(()=>scan('appointmentAvailability')),
      set:(p,v)=>{writing=true;writes.set(p,v);},delete:p=>{writing=true;writes.set(p,null);}});
      for(const[p,v]of writes){if(v===null)data.delete(p);else data.set(p,structuredClone(v));}return result;});queue=run.catch(()=>{});return run;}};
  const workforce=new WorkforceService({store,now:()=>now}),bookings=new BookingService({store,now:()=>now,workforce});return {data,store,workforce,bookings};}
const input=(requestId='off')=>({requestId,day,startHour:14,endHour:16,reason:'Personal appointment'});
const review=(r,action='Approve')=>({action,revision:r.revision,note:''});
test('request is own-only, idempotent and pending never changes availability',async()=>{
  const f=fixture(),r=(await f.workforce.request('john',input())).request;
  assert.equal(r.state,'Pending');assert.equal(f.data.has('appointmentAvailability/'+day),false);
  assert.deepEqual((await f.workforce.request('john',input())).request,r);
  await assert.rejects(f.workforce.request('john',{...input(),reason:'Changed reason'}),fails('REQUEST_CONFLICT'));
  await assert.rejects(f.workforce.request('john',{...input(),uid:'mary'}),fails('INVALID_TIME_OFF'));
  await assert.rejects(f.workforce.request('bride',input()),fails('STAFF_REQUIRED'));
  assert.equal((await f.workforce.context('mary')).requests.length,0);
  assert.equal((await f.workforce.context('boss')).requests.length,1);
});
test('only manager approves; approved absence alone blocks hours; staff cannot bypass old endpoint',async()=>{
  const f=fixture(),r=(await f.workforce.request('mary',input())).request;
  await assert.rejects(f.workforce.review('john',r.id,review(r)),fails('MANAGER_REQUIRED'));
  await assert.rejects(f.bookings.availability('mary',{day,startHour:10,endHour:17,available:false,revision:0}),fails('TIME_OFF_REQUEST_REQUIRED'));
  const a=(await f.workforce.review('boss',r.id,review(r))).request;assert.equal(a.state,'Approved');
  assert.equal(f.data.get('appointmentAvailability/'+day).entries.mary.timeOffId,r.id);
  assert.deepEqual((await f.bookings.day('bride',day,'Dress Trial')).hours,[10,11,12,16]);
  const cancelled=(await f.workforce.review('boss',a.id,review(a,'CancelApproved'))).request;assert.equal(cancelled.state,'Cancelled');
  assert((await f.bookings.day('bride',day,'Dress Trial')).hours.includes(14));
});
test('existing appointment prevents overlapping absence, but another time is allowed',async()=>{
  const f=fixture(),b=await f.bookings.create('bride',{requestId:'book',type:'Dress Trial',startAt:start,notes:''});
  assert.equal(f.data.get('appointments/'+b.appointmentId).assignedStaffId,'mary');
  await assert.rejects(f.workforce.request('mary',input()),fails('AVAILABILITY_HAS_BOOKINGS'));
  assert.equal((await f.workforce.request('mary',{...input(),startHour:10,endHour:12})).request.state,'Pending');
});
test('consultation is assigned to its qualified employee, not reception or unrelated specialists',async()=>{
  const f=fixture(),b=await f.bookings.create('bride',{requestId:'consult',type:'Bridal Consultation',startAt:start,notes:''});
  assert.equal(f.data.get('appointments/'+b.appointmentId).assignedStaffId,'boss');
  f.data.get('staff/boss').active=false;
  assert.deepEqual((await f.bookings.day('bride',day,'Bridal Consultation')).hours,[]);
  assert((await f.bookings.day('bride',day,'Dress Trial')).hours.includes(10));
});
test('new booking between request and approval blocks approval without losing customer reservation',async()=>{
  const f=fixture(),r=(await f.workforce.request('mary',input())).request;
  const b=await f.bookings.create('bride',{requestId:'book',type:'Dress Trial',startAt:start,notes:''});
  await assert.rejects(f.workforce.review('boss',r.id,review(r)),fails('AVAILABILITY_HAS_BOOKINGS'));
  assert.equal(f.data.get('staffTimeOff/'+r.id).state,'Pending');assert.equal(f.data.get('appointments/'+b.appointmentId).status,'Confirmed');
});
test('qualified coverage and role minima cannot be replaced by unrelated employees',async()=>{
  const f=fixture();f.data.set('schedulingSettings/policy',{revision:1,minimumOnDuty:1,minimumByRole:{FrontDesk:1},minimumByService:{'Dress Trial':1}});
  await assert.rejects(f.workforce.request('mary',input()),fails('MINIMUM_SERVICE_COVERAGE'));
  await assert.rejects(f.workforce.request('john',input()),fails('MINIMUM_ROLE_COVERAGE'));
  f.data.set('staff/helper',{role:'staff',active:true});f.data.set('staffScheduling/helper',{jobRole:'FittingSpecialist',serviceTypes:['Dress Trial'],revision:1});
  assert.equal((await f.workforce.request('mary',input())).request.state,'Pending');
});
test('simultaneous approvals recheck minimum total staffing atomically',async()=>{
  const f=fixture();f.data.set('schedulingSettings/policy',{revision:1,minimumOnDuty:3});
  const a=(await f.workforce.request('john',input('one'))).request,b=(await f.workforce.request('mary',input('two'))).request;
  const results=await Promise.allSettled([f.workforce.review('boss',a.id,review(a)),f.workforce.review('boss',b.id,review(b))]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'MINIMUM_STAFF_COVERAGE');
});
test('withdraw/reject never block hours and cannot edit another employees request',async()=>{
  const f=fixture(),r=(await f.workforce.request('mary',input())).request;
  await assert.rejects(f.workforce.review('john',r.id,review(r,'Withdraw')),fails('TIME_OFF_ACCESS_DENIED'));
  await f.workforce.review('mary',r.id,review(r,'Withdraw'));assert.equal(f.data.has('appointmentAvailability/'+day),false);
  await assert.rejects(f.workforce.review('boss',r.id,review(r)),fails('SCHEDULING_CHANGED'));
});
test('responsibilities are separate from auth roles; manager config is revision checked',async()=>{
  const f=fixture(),body={uid:'john',jobRole:'FrontDesk',serviceTypes:[],revision:1};
  await assert.rejects(f.workforce.saveProfile('john',body),fails('MANAGER_REQUIRED'));
  await f.workforce.saveProfile('boss',body);assert.equal(f.data.get('staff/john').role,'staff');
  assert.equal((await f.workforce.context('john')).canViewAll,true);assert.equal((await f.workforce.context('mary')).canViewAll,false);
  await assert.rejects(f.workforce.saveProfile('boss',body),fails('SCHEDULING_CHANGED'));
  await assert.rejects(f.workforce.saveProfile('boss',{...body,revision:2,role:'manager'}),fails('INVALID_STAFF_SCHEDULING'));
});
test('custom job title is editable from scheduling and carries no reception access', async () => {
  const f = fixture();
  const body = {uid:'john', jobRole:'Other', jobTitle:'  Front desk coordinator  ', serviceTypes:[], revision:1};
  await f.workforce.saveProfile('boss', body);
  const context = await f.workforce.context('john');
  assert.equal(context.profile.jobTitle, 'Front desk coordinator');
  assert.equal(context.canViewAll, false);
  await assert.rejects(f.workforce.saveProfile('boss', {...body, jobTitle:' ', revision:2}), fails('INVALID_STAFF_SCHEDULING'));
});
test('removing a service cannot strand future bookings; strict assignment excludes unconfigured newcomers',async()=>{
  const f=fixture();await f.bookings.create('bride',{requestId:'book',type:'Dress Trial',startAt:start,notes:''});
  await assert.rejects(f.workforce.saveProfile('boss',{uid:'mary',jobRole:'FittingSpecialist',serviceTypes:[],revision:1}),fails('STAFF_HAS_SERVICE_BOOKINGS'));
  await f.workforce.savePolicy('boss',{revision:0,minimumOnDuty:1,minimumByRole:{},minimumByService:{},requireServiceAssignments:true});
  f.data.set('staff/new',{active:true,role:'staff'});f.data.get('staff/mary').active=false;
  assert.deepEqual((await f.bookings.day('bride',day,'Dress Trial')).hours,[]);
  await assert.rejects(f.workforce.savePolicy('boss',{revision:1,minimumOnDuty:1,minimumByRole:{},minimumByService:{},requireServiceAssignments:true}),fails('STAFF_PROFILES_REQUIRED'));
});
test('manager reassigns to qualified cover without changing appointment dates, payment or customer',async()=>{
  const f=fixture(),b=await f.bookings.create('bride',{requestId:'book',type:'Dress Trial',startAt:start,notes:''});
  await assert.rejects(f.workforce.reassign('john',b.appointmentId,{staffUid:'boss',revision:1}),fails('MANAGER_REQUIRED'));
  await assert.rejects(f.workforce.reassign('boss',b.appointmentId,{staffUid:'john',revision:1}),fails('STAFF_SERVICE_REQUIRED'));
  await f.workforce.saveProfile('boss',{uid:'boss',jobRole:'Consultant',serviceTypes:['Dress Trial','Bridal Consultation'],revision:1});
  const before=structuredClone(f.data.get('appointments/'+b.appointmentId));await f.workforce.reassign('boss',b.appointmentId,{staffUid:'boss',revision:1});
  const after=f.data.get('appointments/'+b.appointmentId);for(const k of ['uid','type','startAt','status','fittingInvoiceId'])assert.deepEqual(after[k],before[k]);
  assert.equal(after.assignedStaffId,'boss');assert.equal(f.data.get('appointmentAvailability/'+day).bookings[14].staffId,'boss');
  assert.equal((await f.workforce.request('mary',input())).request.state,'Pending');
});
test('legacy exceptions require manager restoration and are not overwritten by requests',async()=>{
  const f=fixture();f.data.set('appointmentAvailability/'+day,{day,entries:{john:{available:false,startHour:14,endHour:17}},bookings:{},revision:1});
  await assert.rejects(f.workforce.request('john',input()),fails('TIME_OFF_DAY_HAS_EXCEPTION'));
  assert.equal((await f.workforce.context('boss')).exceptions.length,1);
  await assert.rejects(f.workforce.restore('john',{day,staffUid:'john',revision:1}),fails('MANAGER_REQUIRED'));
  await f.workforce.restore('boss',{day,staffUid:'john',revision:1});assert.deepEqual(f.data.get('appointmentAvailability/'+day).entries,{});
});
test('HTTP endpoints authenticate and reject arbitrary role or target injection',async()=>{
  const f=fixture(),server=createServer(createHandler({...f,verifyToken:async uid=>({uid})}));await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const call=(path,uid,body)=>fetch(`http://127.0.0.1:${server.address().port}${path}`,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${uid}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
  try{assert.equal((await (await call('/health')).json()).staffSchedulingVersion,1);assert.equal((await call('/v1/staff-scheduling')).status,401);assert.equal((await call('/v1/staff-scheduling','bride')).status,403);
    assert.equal((await call('/v1/staff-scheduling/profile','john',{uid:'john',jobRole:'FrontDesk',serviceTypes:[],revision:1})).status,403);
    assert.equal((await call('/v1/staff-time-off','john',{...input(),staffUid:'mary'})).status,400);
    assert.equal((await call('/v1/staff-time-off','john',input())).status,200);
  }finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
});
