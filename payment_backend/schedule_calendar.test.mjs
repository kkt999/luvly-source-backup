import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {BookingService} from './booking_service.mjs';
import {FirestoreStore} from './firestore_store.mjs';
import {createHandler} from './http_app.mjs';

const now=Date.parse('2026-10-18T16:30:00Z'); // 19 October MYT
function fixture() {
  const data=new Map(Object.entries({
    'staff/john':{active:true,role:'staff'},'staff/manager':{active:true,role:'manager'},'staff/off':{active:false,role:'staff'},
    'appointmentAvailability/2026-10-20':{entries:{john:{available:false,startHour:14,endHour:16},other:{available:false,startHour:10,endHour:17}}},
    'appointments/a':{assignedStaffId:'john',name:'Jane',type:'Dress Trial',startAt:new Date('2026-10-18T16:00:00Z'),status:'Confirmed',phone:'private',notes:'private'},
    'appointments/b':{assignedStaffId:'other',name:'Hidden',type:'Dress Trial',startAt:new Date('2026-10-20T02:00:00Z'),status:'Confirmed'},
    'appointments/c':{assignedStaffId:'john',name:'Outside month',type:'Dress Trial',startAt:new Date('2026-10-31T16:00:00Z'),status:'Confirmed'},
    'appointments/d':{assignedStaffId:'john',name:'Unpaid',type:'Dress Trial',startAt:new Date('2026-10-20T04:00:00Z'),status:'AwaitingPayment',paymentExpiresAt:now-1},
  }));
  const reads=[];
  const doc=(path)=>({id:path.split('/')[1],data:()=>data.get(path),get:async()=>doc(path)});
  class Query {
    constructor(name){this.name=name;this.fields=null;this.cap=Infinity;}
    where(field,op,value){assert.equal(field,'assignedStaffId');assert.equal(op,'==');this.uid=value;return this;}
    select(...fields){this.fields=fields;return this;}
    limit(cap){assert.equal(cap,2001);this.cap=cap;return this;}
  }
  const db={doc,collection:name=>new Query(name),runTransaction:async(fn,opts)=>{
    assert.deepEqual(opts,{readOnly:true});
    return fn({get:async target=>{
      reads.push(target);
      if(!(target instanceof Query))return target;
      assert.equal(target.name,'appointments');
      return {docs:[...data].filter(([p,d])=>p.startsWith('appointments/') && (target.uid===undefined||d.assignedStaffId===target.uid)).slice(0,target.cap).map(([p,d])=>({id:p.split('/')[1],data:()=>Object.fromEntries(target.fields.filter(k=>Object.hasOwn(d,k)).map(k=>[k,d[k]]))}))};
    },set:()=>assert.fail('Calendar reads must not write'),delete:()=>assert.fail('Calendar reads must not delete')});
  }};
  const store=new FirestoreStore(db),service=new BookingService({store,now:()=>now});
  return {data,store,service,reads};
}
test('month snapshot is complete, own-scoped and maps UTC midnight to MYT date',async()=>{
  const f=fixture(),result=await f.service.calendar('john','2026-10');
  assert.equal(result.days.length,31);assert.equal(result.today,'2026-10-19');assert.equal(result.editableUntil,'2027-04-16');
  assert.deepEqual(result.days.find(d=>d.day==='2026-10-19').appointments,[{id:'a',name:'Jane',type:'Dress Trial',startAt:Date.parse('2026-10-18T16:00:00Z'),status:'Confirmed'}]);
  assert.equal(result.days[0].own,null);
  assert.deepEqual(result.days.find(d=>d.day==='2026-10-20').own,{available:false,startHour:14,endHour:16});
  assert(!JSON.stringify(result).includes('Hidden'));assert(!JSON.stringify(result).includes('private'));assert(!JSON.stringify(result).includes('Outside month'));
  assert.equal(f.reads.filter(q=>q instanceof Object && q.name==='appointments')[0].uid,'john');
});
test('expired unpaid hold is labelled expired without mutating it',async()=>{
  const f=fixture(),result=await f.service.calendar('john','2026-10');
  assert.equal(result.days.find(d=>d.day==='2026-10-20').appointments[0].status,'Expired');
  assert.equal(f.data.get('appointments/d').status,'AwaitingPayment');
});
test('bride, inactive staff and invalid month cannot read the schedule',async()=>{
  const f=fixture();
  for(const uid of ['bride','off'])await assert.rejects(f.service.calendar(uid,'2026-10'),e=>e.status===403);
  for(const month of ['2026-09','2027-05','2026-13','2026-1','bad'])await assert.rejects(f.service.calendar('john',month),e=>e.code==='INVALID_SCHEDULE_MONTH');
  assert.equal(f.reads.length,0);
});
test('manager and explicit front desk see all appointments; specialists cannot request all',async()=>{
  const f=fixture();assert.equal((await f.service.calendar('manager','2026-10')).scope,'all');
  assert((await f.service.calendar('manager','2026-10')).days.some(d=>d.appointments.some(b=>b.name==='Hidden')));
  await assert.rejects(f.service.calendar('john','2026-10','all'),e=>e.code==='SCHEDULE_ACCESS_DENIED');
  f.data.set('staffScheduling/john',{jobRole:'FrontDesk',serviceTypes:[]});
  assert.equal((await f.service.calendar('john','2026-10')).scope,'all');
  assert(!(await f.service.calendar('john','2026-10','own')).days.some(d=>d.appointments.some(b=>b.name==='Hidden')));
});
test('read snapshot rechecks revocation, refuses truncation and filters overbroad stores',async()=>{
  const actor={active:true,role:'staff'},snapshot={actor,days:[],appointments:[{id:'x',assignedStaffId:'other',startAt:new Date('2026-10-20T02:00:00Z'),status:'Confirmed',name:'Hidden'}],limited:false};
  const service=new BookingService({now:()=>now,store:{get:async()=>actor,scheduleSnapshot:async()=>snapshot}});
  assert((await service.calendar('john','2026-10')).days.every(d=>d.appointments.length===0));
  snapshot.limited=true;await assert.rejects(service.calendar('john','2026-10'),e=>e.code==='SCHEDULE_LIMIT');
  snapshot.actor={active:false,role:'staff'};await assert.rejects(service.calendar('john','2026-10'),e=>e.code==='STAFF_REQUIRED');
});
test('more than 100 appointments are not silently dropped; oversized history is rejected',async()=>{
  const f=fixture();for(let i=0;i<120;i++)f.data.set(`appointments/x${i}`,{assignedStaffId:'john',name:`Customer ${i}`,type:'Dress Trial',startAt:new Date('2026-10-22T02:00:00Z'),status:'Cancelled'});
  assert.equal((await f.service.calendar('john','2026-10')).days.find(d=>d.day==='2026-10-22').appointments.length,120);
  for(let i=120;i<2001;i++)f.data.set(`appointments/x${i}`,{assignedStaffId:'john',startAt:new Date('2026-10-22T02:00:00Z'),status:'Cancelled'});
  await assert.rejects(f.service.calendar('john','2026-10'),e=>e.code==='SCHEDULE_LIMIT');
});
test('HTTP authenticates, rejects staffId/month overrides, and has no schedule mutation route',async()=>{
  const f=fixture(),server=createServer(createHandler({bookings:f.service,verifyToken:async uid=>({uid})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
  const request=(path,uid,method='GET')=>fetch(base+path,{method,headers:uid?{Authorization:`Bearer ${uid}`}:{}});
  try {
    assert.equal((await request('/v1/appointment-schedule?month=2026-10')).status,401);
    assert.equal((await request('/v1/appointment-schedule?month=2026-10','bride')).status,403);
    assert.equal((await request('/v1/appointment-schedule?month=2026-10&staffId=other','john')).status,400);
    assert.equal((await request('/v1/appointment-schedule?month=2026-10&month=2026-11','john')).status,400);
    assert.equal((await request('/v1/appointment-schedule?month=2026-10','john','POST')).status,404);
    assert.equal((await request('/v1/appointment-schedule?month=2026-10','john')).status,200);
  } finally {server.closeAllConnections();await new Promise(r=>server.close(r));}
});
