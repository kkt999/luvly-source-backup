import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {StaffWorkspaceService} from './staff_workspace.mjs';
import {BookingService} from './booking_service.mjs';
import {WorkforceService} from './workforce.mjs';
import {createHandler} from './http_app.mjs';

const firstNow=Date.parse('2026-10-23T00:00:00Z'),day='2026-10-24',startAt=Date.parse(day+'T02:00:00Z');
const fails=code=>e=>e.code===code;
function fixture(){
  let clock=firstNow,queue=Promise.resolve();
  const data=new Map(Object.entries({
    'staff/boss':{name:'Manager',email:'boss@example.com',phone:'0123456789',active:true,role:'manager',accountRevision:1},
    'staff/john':{name:'John',email:'john@example.com',phone:'0123456789',active:true,role:'staff',accountRevision:1},
    'staff/mary':{name:'Mary',active:true,role:'staff'},'staff/nina':{name:'Nina',active:true,role:'staff'},
    'staff/inactive':{name:'Inactive',active:false,role:'staff'},
    'staffScheduling/john':{jobRole:'FrontDesk',serviceTypes:[],revision:1},
    'staffScheduling/mary':{jobRole:'FittingSpecialist',serviceTypes:['Dress Trial'],revision:1},
    'staffScheduling/nina':{jobRole:'MakeupArtist',serviceTypes:['Bridal Makeup'],revision:1},
    'staffScheduling/boss':{jobRole:'Consultant',serviceTypes:['Bridal Consultation'],revision:1},
    'brides/bride':{name:'Amy',phone:'0123456789'},'brides/other':{name:'Other'}
  }));
  const scan=(collection,predicate=()=>true)=>[...data].filter(([p,r])=>p.startsWith(collection+'/')&&p.split('/').length===2&&predicate(r)).map(([p,r])=>({...structuredClone(r),id:p.split('/')[1]}));
  const store={get:async p=>structuredClone(data.get(p)),activeStaffIds:async()=>scan('staff',r=>r.active).map(r=>r.id),
    inboxPage:async(uid)=>{const records=[...data].filter(([p])=>p.startsWith(`inboxes/${uid}/items/`)).map(([p,r])=>({...structuredClone(r),id:p.split('/').at(-1)}));return {records,unread:records.filter(r=>r.readAt===null).length,nextCursor:null};},
    atomic:fn=>{
      const run=queue.then(async()=>{let written=false;const writes=new Map(),read=f=>{assert(!written,'Firestore transaction read after write');return f();};
        const result=await fn({get:p=>read(()=>store.get(p)),workspaceTasks:uid=>read(()=>scan('tasks',r=>uid===undefined||r.assignedStaffId===uid)),staffRoster:()=>read(()=>scan('staff')),staffAppointments:uid=>read(()=>scan('appointments',r=>r.assignedStaffId===uid)),schedulingDays:()=>read(()=>scan('appointmentAvailability')),timeOffRequests:uid=>read(()=>scan('staffTimeOff',r=>uid===undefined||r.uid===uid)),set:(p,r)=>{written=true;writes.set(p,r);},delete:p=>{written=true;writes.set(p,null);}});
        for(const[p,r]of writes){if(r===null)data.delete(p);else data.set(p,structuredClone(r));}return result;
      });queue=run.catch(()=>{});return run;
    }};
  let email='john@example.com',verified=false;
  const workspace=new StaffWorkspaceService({store,auth:{getUser:async uid=>({email:uid==='john'?email:`${uid}@example.com`,emailVerified:verified,disabled:false})},now:()=>clock});
  const workforce=new WorkforceService({store,now:()=>clock}),bookings=new BookingService({store,workforce,now:()=>clock});
  return {data,workspace,workforce,bookings,store,setNow:n=>clock=n,setEmail:(e,v)=>{email=e;verified=v;}};
}
const task=(extra={})=>({requestId:'request1',revision:0,title:'Prepare fitting room',description:'Check accessories and prepare the room.',type:'Fitting preparation',staffUid:'mary',day,startHour:10,endHour:11,...extra});

test('own profile cannot change role, active flag, UID or arbitrary email',async()=>{
  const f=fixture();assert.equal((await f.workspace.profile('john')).email,'john@example.com');
  for(const patch of [{role:'manager'},{uid:'boss'},{email:'other@example.com'},{active:false}])await assert.rejects(f.workspace.saveProfile('john',{name:'John New',phone:'0123456789',revision:1,...patch}),fails('INVALID_SELF_PROFILE'));
  await assert.rejects(f.workspace.profile('bride'),fails('STAFF_REQUIRED'));await assert.rejects(f.workspace.profile('inactive'),fails('STAFF_REQUIRED'));
  await assert.rejects(f.workspace.saveProfile('john',{name:'John',phone:'-----------',revision:1}),fails('INVALID_SELF_PROFILE'));
  await f.workspace.saveProfile('john',{name:'John New',phone:'+60 123456789',revision:1});assert.equal(f.data.get('staff/john').role,'staff');assert.equal(f.data.get('staff/john').active,true);
  await assert.rejects(f.workspace.saveProfile('john',{name:'Stale',phone:'0123456789',revision:1}),fails('STAFF_ACCOUNT_CHANGED'));
});
test('verified auth email only; database changes never trust a supplied email',async()=>{
  const f=fixture();f.setEmail('new@example.com',false);await f.workspace.saveProfile('john',{name:'John',phone:'0123456789',revision:1});assert.equal(f.data.get('staff/john').email,'john@example.com');
  f.setEmail('new@example.com',true);await f.workspace.saveProfile('john',{name:'John',phone:'0123456789',revision:2});assert.equal(f.data.get('staff/john').email,'new@example.com');
});
test('profile and manager edit share a revision; concurrent saves do not overwrite',async()=>{
  const f=fixture(),input={name:'John',phone:'0123456789',revision:1};const r=await Promise.allSettled([f.workspace.saveProfile('john',input),f.workspace.saveProfile('john',input)]);assert.equal(r.filter(r=>r.status==='fulfilled').length,1);
});
test('manager assigns a qualified task; staff sees only own tasks and inbox',async()=>{
  const f=fixture();await assert.rejects(f.workspace.saveTask('john',null,task()),fails('MANAGER_REQUIRED'));const row=(await f.workspace.saveTask('boss',null,task())).record;
  assert.equal((await f.workspace.taskList('mary')).records.length,1);assert.equal((await f.workspace.taskList('john')).records.length,0);assert.equal((await f.workspace.taskList('boss')).records.length,1);
  assert.equal((await f.workspace.notifications('mary')).unread,1);assert.equal((await f.workspace.notifications('john')).unread,0);assert.equal(f.data.get(`appointmentAvailability/${day}`).taskBlocks[row.id].staffId,'mary');
});
test('create retries do not duplicate tasks or reset a read notification',async()=>{
  const f=fixture(),row=(await f.workspace.saveTask('boss',null,task())).record,n=(await f.workspace.notifications('mary')).records[0];await f.workspace.readNotification('mary',n.id);await f.workspace.saveTask('boss',null,task());assert.equal((await f.workspace.notifications('mary')).unread,0);assert.equal((await f.workspace.taskList('boss')).records.length,1);
  await assert.rejects(f.workspace.saveTask('boss',null,task({title:'Different task'})),fails('REQUEST_CONFLICT'));assert.equal(f.data.get(`tasks/${row.id}`).revision,1);
});
test('unqualified employee, lunch overlap, past and invalid calendar dates are rejected',async()=>{
  const f=fixture();await assert.rejects(f.workspace.saveTask('boss',null,task({staffUid:'john'})),fails('TASK_SKILL_REQUIRED'));
  for(const patch of [{startHour:12,endHour:15},{startHour:14,endHour:13},{day:'2026-02-30'},{day:'2026-10-22'},{day:'2027-12-01'}])await assert.rejects(f.workspace.saveTask('boss',null,task(patch)),fails('INVALID_TASK_TIME'));
});
test('task blocks new bookings and conflicting tasks, but keeps other hours bookable',async()=>{
  const f=fixture();await f.workspace.saveTask('boss',null,task());const available=await f.bookings.day('bride',day,'Dress Trial');assert(!available.hours.includes(10));assert(available.hours.includes(11));
  await assert.rejects(f.bookings.create('bride',{requestId:'booking',type:'Dress Trial',startAt,notes:''}),fails('NO_STAFF_AVAILABLE'));
  await assert.rejects(f.workspace.saveTask('boss',null,task({requestId:'second'})),fails('TASK_STAFF_UNAVAILABLE'));
});
test('existing visit and approved leave block task assignment',async()=>{
  const f=fixture();await f.bookings.create('bride',{requestId:'booking',type:'Dress Trial',startAt,notes:''});await assert.rejects(f.workspace.saveTask('boss',null,task()),fails('TASK_APPOINTMENT_CONFLICT'));
  const g=fixture();g.data.set(`appointmentAvailability/${day}`,{entries:{mary:{available:false,startHour:10,endHour:12}},bookings:{},revision:1});await assert.rejects(g.workspace.saveTask('boss',null,task()),fails('TASK_STAFF_UNAVAILABLE'));
});
test('simultaneous task and booking commit only one overlapping reservation',async()=>{
  const f=fixture();const result=await Promise.allSettled([f.workspace.saveTask('boss',null,task()),f.bookings.create('bride',{requestId:'booking',type:'Dress Trial',startAt,notes:''})]);assert.equal(result.filter(r=>r.status==='fulfilled').length,1);
});
test('task prevents leave request and approval; responsibility changes cannot invalidate tasks',async()=>{
  const f=fixture();await f.workspace.saveTask('boss',null,task());await assert.rejects(f.workforce.request('mary',{requestId:'off',day,startHour:10,endHour:11,reason:'Personal appointment'}),fails('AVAILABILITY_HAS_TASKS'));
  await assert.rejects(f.workforce.saveProfile('boss',{uid:'mary',jobRole:'FrontDesk',serviceTypes:[],revision:1}),fails('STAFF_HAS_WORK'));
  const g=fixture(),r=(await g.workforce.request('mary',{requestId:'off',day,startHour:10,endHour:11,reason:'Personal appointment'})).request;await g.workspace.saveTask('boss',null,task());await assert.rejects(g.workforce.review('boss',r.id,{action:'Approve',revision:1,note:''}),fails('AVAILABILITY_HAS_TASKS'));
});
test('edit moves blocks atomically; cancellation releases time; stale updates fail',async()=>{
  const f=fixture(),row=(await f.workspace.saveTask('boss',null,task())).record;
  const next=(await f.workspace.saveTask('boss',row.id,task({revision:1,day:'2026-10-25',requestId:'move'}))).record;
  assert.equal(Object.keys(f.data.get(`appointmentAvailability/${day}`).taskBlocks).length,0);assert(f.data.get('appointmentAvailability/2026-10-25').taskBlocks[row.id]);
  await assert.rejects(f.workspace.taskStatus('boss',row.id,{revision:1,status:'Cancelled',note:''}),fails('TASK_CHANGED'));
  await f.workspace.taskStatus('boss',row.id,{revision:next.revision,status:'Cancelled',note:'Not needed'});assert.equal(Object.keys(f.data.get('appointmentAvailability/2026-10-25').taskBlocks).length,0);
});
test('only assigned staff/manager updates progress, no completion before starting or early attendance',async()=>{
  const f=fixture(),r=(await f.workspace.saveTask('boss',null,task())).record;
  await assert.rejects(f.workspace.taskStatus('john',r.id,{revision:1,status:'In Progress',note:''}),fails('TASK_ACCESS_DENIED'));
  await assert.rejects(f.workspace.taskStatus('mary',r.id,{revision:1,status:'Completed',note:''}),fails('INVALID_TASK_TRANSITION'));
  await assert.rejects(f.workspace.taskStatus('mary',r.id,{revision:1,status:'In Progress',note:''}),fails('INVALID_TASK_TRANSITION'));
  f.setNow(startAt);await f.workspace.taskStatus('mary',r.id,{revision:1,status:'In Progress',note:'Started'});await f.workspace.taskStatus('mary',r.id,{revision:2,status:'Completed',note:'Ready'});assert.equal(f.data.get(`tasks/${r.id}`).status,'Completed');
});
test('reassignment removes old staff task access without disclosing private notification text',async()=>{
  const f=fixture(),r=(await f.workspace.saveTask('boss',null,task())).record;
  await f.workspace.saveTask('boss',r.id,task({revision:1,staffUid:'boss',requestId:'reassign'}));assert.equal((await f.workspace.taskList('mary')).records.length,0);
  assert((await f.workspace.notifications('mary')).records.some(n=>n.kind==='TaskRemoved'));assert(!(await f.workspace.notifications('mary')).records.some(n=>n.title.includes('Prepare')));
});
test('support create/reply/close saves real messages and notifications in the same transaction',async()=>{
  const f=fixture(),r=await f.workspace.support('bride',null,{action:'Create',requestId:'case1',subject:'Fitting question',category:'Appointments',body:'Private question'});
  assert.equal((await f.workspace.notifications('john')).unread,1);await assert.rejects(f.workspace.notifications('inactive'),fails('ACCOUNT_ACCESS_REQUIRED'));
  assert.equal(f.data.get(`supportTickets/${r.id}`).name,'Amy');assert(![...f.data.keys()].some(p=>p.startsWith('inboxes/inactive/')));
});
test('support replies notify the other party; idempotent retries keep read state',async()=>{
  const f=fixture(),input={action:'Create',requestId:'case1',subject:'Fitting question',category:'Appointments',body:'Private question'},r=await f.workspace.support('bride',null,input);
  await f.workspace.support('bride',null,input);assert.equal((await f.workspace.notifications('john')).records.length,1);
  const reply={action:'Reply',requestId:'reply1',body:'Please visit the boutique.'};await f.workspace.support('john',r.id,reply);
  const n=(await f.workspace.notifications('bride')).records[0];assert(!JSON.stringify(n).includes(reply.body));await f.workspace.readNotification('bride',n.id);await f.workspace.support('john',r.id,reply);assert.equal((await f.workspace.notifications('bride')).unread,0);
  await assert.rejects(f.workspace.support('other',r.id,{action:'Reply',requestId:'hack',body:'Not my ticket'}),fails('SUPPORT_ACCESS_DENIED'));
  await f.workspace.support('john',r.id,{action:'Close',requestId:'close',revision:2});assert.equal(f.data.get(`supportTickets/${r.id}`).status,'Closed');assert.equal((await f.workspace.notifications('bride')).unread,1);
  await assert.rejects(f.workspace.support('bride',r.id,{action:'Reply',requestId:'late',body:'Hello'}),fails('SUPPORT_CHANGED'));
});
test('notification read is owner-bound; deactivation and forged actors are denied',async()=>{
  const f=fixture();await f.workspace.saveTask('boss',null,task());const n=(await f.workspace.notifications('mary')).records[0];await assert.rejects(f.workspace.readNotification('john',n.id),fails('NOTIFICATION_NOT_FOUND'));f.data.get('staff/mary').active=false;await assert.rejects(f.workspace.notifications('mary'),fails('ACCOUNT_ACCESS_REQUIRED'));
});
test('new HTTP routes require auth and reject unexpected queries and bodies',async()=>{
  const f=fixture(),server=createServer(createHandler({workspace:f.workspace,verifyToken:async token=>({uid:token})}));await new Promise(r=>server.listen(0,'127.0.0.1',r));
  try{const base=`http://127.0.0.1:${server.address().port}`;assert.equal((await fetch(base+'/v1/staff-tasks')).status,401);assert.equal((await fetch(base+'/v1/my-staff-profile?uid=boss',{headers:{Authorization:'Bearer john'}})).status,400);assert.equal((await fetch(base+'/v1/staff-tasks',{headers:{Authorization:'Bearer bride'}})).status,403);assert.equal((await fetch(base+'/v1/notifications?uid=john',{headers:{Authorization:'Bearer bride'}})).status,400);assert.equal((await fetch(base+'/v1/my-staff-profile',{headers:{Authorization:'Bearer john'}})).status,200);}
  finally{await new Promise(r=>server.close(r));}
});
