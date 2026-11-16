import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {BookingService} from './booking_service.mjs';
import {createHandler} from './http_app.mjs';
const now=Date.parse('2026-10-14T00:00:00Z'),start=Date.parse('2026-10-15T02:00:00Z');
class Store {
 constructor(){this.rows=new Map(Object.entries({'staff/john':{role:'staff',active:true},'staff/off':{role:'staff',active:false},'brides/bride':{name:'Demo',phone:'0123456789',email:'demo@example.com'},'brides/other':{name:'Other',phone:'0123456789',email:'other@example.com'}}));this.queue=Promise.resolve();}
 async get(p){return structuredClone(this.rows.get(p));}
 async activeStaffIds(){return [...this.rows].filter(([p,d])=>p.startsWith('staff/')&&d.active&&['staff','manager'].includes(d.role)).map(([p])=>p.split('/')[1]).sort();}
 atomic(fn){const run=this.queue.then(async()=>{const writes=new Map();let writing=false;
   const result=await fn({get:p=>{assert.equal(writing,false,'all reads must precede writes');return this.get(p);},set:(p,d)=>{writing=true;writes.set(p,d);},delete:p=>{writing=true;writes.set(p,null);}});
   for(const[p,d]of writes){if(d===null)this.rows.delete(p);else this.rows.set(p,structuredClone(d));}return result;
 });this.queue=run.catch(()=>{});return run;}
}
const fails=code=>e=>e.code===code;
const input=(requestId='req')=>({requestId,type:'Dress Trial',startAt:start,notes:''});
async function fixture(){const store=new Store(),s=new BookingService({store,now:()=>now});
 await s.availability('john',{day:'2026-10-15',startHour:10,endHour:17,available:true,revision:0});return {store,s};}
test('normal hours open by default; staff configure their own exceptions only',async()=>{
 const store=new Store(),s=new BookingService({store,now:()=>now});
 assert.deepEqual((await s.day('bride','2026-10-15')).hours,[10,11,12,14,15,16]);
 store.rows.get('staff/john').active=false;
 assert.deepEqual((await s.day('bride','2026-10-15')).hours,[]);
 await assert.rejects(s.create('bride',input()),fails('NO_STAFF_AVAILABLE'));
 store.rows.get('staff/john').active=true;
 for(const uid of ['bride','off'])await assert.rejects(s.availability(uid,{day:'2026-10-15',startHour:10,endHour:17,available:true,revision:0}),fails('STAFF_REQUIRED'));
 await assert.rejects(s.availability('john',{day:'2026-10-15',startHour:10,endHour:17,available:true,revision:0,staffId:'someone'}),fails('INVALID_AVAILABILITY'));
 await s.availability('john',{day:'2026-10-15',startHour:10,endHour:17,available:true,revision:0});
 const publicDay=await s.day('bride','2026-10-15');assert.deepEqual(publicDay.hours,[10,11,12,14,15,16]);assert.equal(publicDay.own,undefined);assert.doesNotMatch(JSON.stringify(publicDay),/john/);
});
test('partial absence blocks only affected hours; another active employee can cover',async()=>{
 const {s,store}=await fixture();
 await s.availability('john',{day:'2026-10-15',startHour:14,endHour:16,available:false,revision:1});
 assert.deepEqual((await s.day('bride','2026-10-15')).hours,[10,11,12,16]);
 await s.create('bride',input()); // unaffected 10:00
 await assert.rejects(s.create('other',{...input(),startAt:start+4*3600000}),fails('NO_STAFF_AVAILABLE'));
 store.rows.set('staff/jane',{active:true,role:'staff'});
 const covered=await s.create('other',{...input(),startAt:start+4*3600000});
 assert.equal((await store.get(`appointments/${covered.appointmentId}`)).assignedStaffId,'jane');
});
test('same time races have one winner; retries are idempotent; staff assignment and email are atomic',async()=>{
 const {s,store}=await fixture();const results=await Promise.allSettled([s.create('bride',input()),s.create('other',input())]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results[1].reason.code,'SLOT_UNAVAILABLE');
 const b=results[0].value;assert.deepEqual(await s.create('bride',input()),b);
 const row=await store.get(`appointments/${b.appointmentId}`);assert.equal(row.status,'Confirmed');assert.equal(row.assignedStaffId,'john');
 assert.equal((await store.get(`appointmentMail/${b.appointmentId}-1`)).state,'Queued');
 assert.equal((await s.day('bride','2026-10-15')).hours.includes(10),false);
 await assert.rejects(s.create('bride',{...input(),notes:'different'}),fails('REQUEST_CONFLICT'));
});
test('cancellation checks owner, releases exact reservation, and permits rebooking',async()=>{
 const {s,store}=await fixture();const b=await s.create('bride',input());
 const change={status:'Cancelled',revision:1,response:''};
 await assert.rejects(s.transition('other',b.appointmentId,change),fails('BOOKING_ACCESS_DENIED'));
 await assert.rejects(s.transition('off',b.appointmentId,change),fails('BOOKING_ACCESS_DENIED'));
 await s.transition('bride',b.appointmentId,change);assert.equal(await store.get(`appointmentSlots/${start}`),undefined);
 assert.equal((await s.day('bride','2026-10-15')).hours.includes(10),true);
 await s.create('other',input());
 await s.transition('bride',b.appointmentId,change);assert.ok(await store.get(`appointmentSlots/${start}`));
});
test('staff cannot close an assigned visit, revoke active staff or complete a future booking',async()=>{
 const {s,store}=await fixture();const b=await s.create('bride',input());const r=(await s.day('john','2026-10-15')).revision;
 await assert.rejects(s.availability('john',{day:'2026-10-15',startHour:11,endHour:17,available:true,revision:r}),fails('AVAILABILITY_HAS_BOOKINGS'));
 await assert.rejects(s.availability('john',{day:'2026-10-15',startHour:10,endHour:17,available:false,revision:r}),fails('AVAILABILITY_HAS_BOOKINGS'));
 await assert.rejects(s.availability('john',{day:'2026-10-15',startHour:10,endHour:17,available:true,revision:0}),fails('AVAILABILITY_CHANGED'));
 await assert.rejects(s.transition('john',b.appointmentId,{status:'Completed',revision:1,response:''}),fails('INVALID_BOOKING_TRANSITION'));
 store.rows.get('staff/john').active=false;assert.deepEqual((await s.day('bride','2026-10-15')).hours,[]);
});
test('only managers, front desk or the current assigned specialist can update a visit', async () => {
 const {s,store}=await fixture();
 const visit=await s.create('bride',input());
 const change={status:'Cancelled',revision:1,response:''};
 store.rows.set('staff/artist',{role:'staff',active:true});
 store.rows.set('staffScheduling/artist',{jobRole:'MakeupArtist',serviceTypes:['Bridal Makeup']});
 store.rows.set('staff/reception',{role:'staff',active:true});
 store.rows.set('staffScheduling/reception',{jobRole:'FrontDesk',serviceTypes:[]});
 store.rows.set('staff/boss',{role:'manager',active:true});
 await assert.rejects(s.transition('artist',visit.appointmentId,change),fails('BOOKING_ACCESS_DENIED'));
 const row=store.rows.get(`appointments/${visit.appointmentId}`);
 assert.equal(row.status,'Confirmed');
 row.assignedStaffId='artist';
 await assert.rejects(s.transition('john',visit.appointmentId,change),fails('BOOKING_ACCESS_DENIED'));
 await assert.rejects(s.transition('boss',visit.appointmentId,{...change,revision:0}),fails('BOOKING_CHANGED'));
 await assert.rejects(s.transition('artist',visit.appointmentId,{...change,revision:0}),fails('BOOKING_CHANGED'));
 assert.equal((await s.transition('reception',visit.appointmentId,change)).status,'Cancelled');
});
test('an absence outside an assigned visit is allowed; an overlapping absence is rejected',async()=>{
 const {s}=await fixture();await s.create('bride',input());
 const revision=(await s.day('john','2026-10-15')).revision;
 await s.availability('john',{day:'2026-10-15',startHour:14,endHour:16,available:false,revision});
 const nextRevision=(await s.day('john','2026-10-15')).revision;
 await assert.rejects(s.availability('john',{day:'2026-10-15',startHour:9,endHour:11,available:false,revision:nextRevision}),fails('AVAILABILITY_HAS_BOOKINGS'));
});
test('date/time validation and role forgery cannot create appointments',async()=>{
 const {s}=await fixture();for(const changes of [{startAt:now},{startAt:start+1},{startAt:start+3*3600000},{uid:'other'},{status:'Confirmed'},{dressId:0}])await assert.rejects(s.create('bride',{...input(),...changes}),fails('INVALID_BOOKING'));
 for(const day of ['2026-10-13','2026-99-15','2026-02-30','bad'])await assert.rejects(s.day('bride',day),fails('INVALID_AVAILABILITY_DATE'));
 await assert.rejects(s.create('john',input()),fails('BRIDE_REQUIRED'));
});
test('old pending package fitting is automatically checked, but invalid wedding order never confirmed',async()=>{
 const {s,store}=await fixture();store.rows.set('appointments/legacy',{uid:'bride',type:'Dress Trial',startAt:new Date(start),slotKey:String(start),status:'Requested',revision:1});
 store.rows.set('packageAppointments/legacy',{selectionId:'selection'});
 store.rows.set('packageSelections/selection',{uid:'bride',selectedGowns:[{dressId:'gown',size:'M'}],rentalPlan:{pickupDate:'2026-10-15',eventDate:'2026-10-16'}});
 store.rows.set('dresses/gown',{published:true,availability:'Available',sizes:'M'});
 await assert.rejects(s.recheck('legacy'),fails('FITTING_DATE_CONFLICT'));assert.equal((await store.get('appointments/legacy')).status,'Requested');
 store.rows.get('packageSelections/selection').rentalPlan.pickupDate='2026-10-16';
 await s.recheck('legacy');assert.equal((await store.get('appointments/legacy')).status,'Confirmed');
 await s.recheck('legacy');assert.equal((await store.get('appointments/legacy')).revision,2);
});
test('booking HTTP requires identity, rejects manual confirm and hides availability staff details',async()=>{
 const {s}=await fixture();const server=createServer(createHandler({bookings:s,verifyToken:async token=>({uid:token})}));
 await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
 const call=(path,uid,body)=>fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${uid}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
 try{assert.equal((await call('/v1/appointments',null,input())).status,401);
 const response=await call('/v1/appointments','bride',input());assert.equal(response.status,201);const b=await response.json();
 assert.equal((await call(`/v1/appointments/${b.appointmentId}/transition`,'john',{status:'Confirmed',revision:1,response:''})).status,400);
 assert.equal((await call('/v1/appointment-availability','bride',{day:'2026-10-15',startHour:10,endHour:17,available:true,revision:2})).status,403);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
});
