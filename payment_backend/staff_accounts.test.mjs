import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {StaffAccountsService,FirebaseStaffAuth,StaffSetupMailer} from './staff_accounts.mjs';
import {FirestoreStore} from './firestore_store.mjs';
import {createHandler} from './http_app.mjs';

class Query {
  constructor(collection,filters=[],fields=null,cap=Infinity){Object.assign(this,{collection,filters,fields,cap});}
  where(...f){return new Query(this.collection,[...this.filters,f],this.fields,this.cap);}
  select(...fields){return new Query(this.collection,this.filters,fields,this.cap);}
  limit(cap){return new Query(this.collection,this.filters,this.fields,cap);}
}
const now=Date.UTC(2026,9,22,4);
const profile={jobRole:'FittingSpecialist',serviceTypes:['Dress Trial'],revision:1};
const draft={requestId:'create1',name:'New Employee',email:'new@example.com',phone:'0123456789',role:'staff',jobRole:'FrontDesk',serviceTypes:[]};
function fixture(){
  const data=new Map(Object.entries({
    'staff/manager':{active:true,role:'manager',name:'Manager'},
    'staff/otherManager':{active:true,role:'manager',name:'Other Manager'},
    'staff/target':{active:true,role:'staff',name:'Employee',email:'target@example.com',phone:'0123456789',accountRevision:1,privateField:'not returned'},
    'staff/revoked':{active:false,role:'manager'},
    'staffScheduling/target':profile,
  }));
  const reads=[];let queue=Promise.resolve();
  const doc=(path,value)=>({id:path.split('/')[1],exists:value!==undefined,data:()=>structuredClone(value)});
  const db={doc:path=>({path}),collection:name=>new Query(name),runTransaction:fn=>{
    const run=queue.then(async()=>{let writes=false;const stage=new Map(data);
      const result=await fn({get:async q=>{assert(!writes,'Firestore reads must precede writes');reads.push(q);
        if(q.path)return doc(q.path,stage.get(q.path));
        const rows=[...stage].filter(([path,v])=>path.startsWith(q.collection+'/')&&q.filters.every(([k,op,w])=>op==='=='&&v[k]===w)).slice(0,q.cap);
        return {size:rows.length,empty:!rows.length,docs:rows.map(([p,v])=>doc(p,q.fields?Object.fromEntries(q.fields.filter(k=>Object.hasOwn(v,k)).map(k=>[k,v[k]])):v))};},
        set:(p,v)=>{writes=true;stage.set(p.path,structuredClone(v));},delete:p=>{writes=true;stage.delete(p.path);}});
      data.clear();for(const [p,v]of stage)data.set(p,v);return result;});queue=run.catch(()=>{});return run;}};
  const store=new FirestoreStore(db),authRows=new Map([['target',{email:'target@example.com',disabled:false}],['manager',{email:'manager@example.com',disabled:false}]]),calls=[],emails=[];
  const auth={
    getUser:async id=>{calls.push(['getUser',id]);const r=authRows.get(id);if(!r)throw Object.assign(Error(),{code:'auth/user-not-found'});return {...r,uid:id};},
    createManagedUser:async r=>{calls.push(['create',r.uid]);if([...authRows].some(([id,u])=>id!==r.uid&&u.email===r.email))throw Object.assign(Error(),{code:'auth/email-already-exists'});authRows.set(r.uid,{email:r.email,disabled:false});},
    setDisabled:async(id,disabled)=>{calls.push(['disabled',id,disabled]);if(!authRows.has(id))throw Error();authRows.set(id,{...authRows.get(id),disabled});},
    revoke:async id=>{calls.push(['revoke',id]);},setupLink:async email=>{calls.push(['setup',email]);return 'https://project.firebaseapp.com/__/auth/action?private=example';},
  };
  let time=now;const mailer={send:async value=>emails.push(value)},service=new StaffAccountsService({store,auth,mailer,now:()=>time});
  return {data,reads,store,auth,authRows,calls,emails,mailer,service,tick:()=>time+=61000};
}
const rejects=(promise,code)=>assert.rejects(promise,e=>e.code===code);
const updateBody={name:'Updated Employee',phone:'0123456789',role:'staff',...profile,revision:1,profileRevision:1};
const change=(active=true,revision=1,requestId='change1')=>({active,revision,requestId,note:'Reviewed by manager'});

test('a verified self-service email reservation cannot be adopted by account creation',async()=>{
  const f=fixture(),path=`staffAccountEmails/${createHash('sha256').update(draft.email).digest('hex')}`;
  f.data.set(path,{uid:'target'});await rejects(f.service.create('manager',draft),'STAFF_EMAIL_IN_USE');
  assert.deepEqual(f.data.get(path),{uid:'target'});assert.equal(f.calls.length,0);
});

test('manager-only list is whitelisted; customer, staff and inactive manager cannot use any account action',async()=>{
  const f=fixture(),s=f.service;
  for(const actor of ['customer','target','revoked']){
    for(const action of [()=>s.list(actor),()=>s.details(actor,'target'),()=>s.create(actor,draft),()=>s.update(actor,'target',updateBody),()=>s.status(actor,'target',change(false)),()=>s.sync(actor,'target'),()=>s.invite(actor,'target',{requestId:'mail',revision:1}),()=>s.endSessions(actor,'target')])await rejects(action(),'MANAGER_REQUIRED');
  }
  assert.equal(f.calls.length,0);assert.equal(f.emails.length,0);
  const rows=(await s.list('manager')).records;assert.equal(rows.length,4);assert(!JSON.stringify(rows).includes('privateField'));
  assert(!f.reads.some(q=>q.collection==='brides'));
});

test('create persists real identity binding, explicit responsibilities and inactive access; repeated request is idempotent',async()=>{
  const f=fixture(),r=await f.service.create('manager',draft);
  assert.equal(r.created,true);assert.equal(f.authRows.get(r.id).email,draft.email);
  const row=f.data.get(`staff/${r.id}`);assert.equal(row.active,false);assert.equal(row.pendingActivation,true);assert.equal(row.accountRevision,1);
  assert.equal(f.data.get(`staffScheduling/${r.id}`).jobRole,'FrontDesk');assert.deepEqual(f.data.get(`staffScheduling/${r.id}`).serviceTypes,[]);
  assert.deepEqual(await f.service.create('manager',draft),r);assert.equal(f.calls.filter(c=>c[0]==='create').length,1);
  assert.equal(f.emails.length,0);assert(!JSON.stringify([...f.data]).includes('password'));assert(!JSON.stringify(r).includes('link'));
  await rejects(f.service.create('manager',{...draft,name:'Changed'}),'REQUEST_CONFLICT');
  await rejects(f.service.create('manager',{...draft,requestId:'another'}),'STAFF_EMAIL_IN_USE');
});

test('existing customer Auth email is never adopted or changed; forged fields are rejected',async()=>{
  const f=fixture();f.authRows.set('customer',{email:draft.email,disabled:false});f.data.set('brides/customer',{name:'Customer'});
  await rejects(f.service.create('manager',draft),'STAFF_EMAIL_IN_USE');
  assert.equal([...f.data.keys()].filter(k=>k.startsWith('staff/staff_')).length,0);
  assert.deepEqual(f.authRows.get('customer'),{email:draft.email,disabled:false});
  assert(![...f.data.keys()].some(path=>path.startsWith('staffAccountEmails/')));
  for(const extra of [{active:true},{uid:'customer'},{password:'private'},{unknown:true}])await rejects(f.service.create('manager',{...draft,...extra}),'INVALID_STAFF_ACCOUNT');
});

test('legacy failed duplicate claim can be recovered without taking over a provisioned identity', async () => {
  const f = fixture();
  const id = 'staff_previous_attempt', opId = 'previous_operation';
  const claim = `staffAccountEmails/${createHash('sha256').update(draft.email).digest('hex')}`;
  const operation = `staffAccountOperations/${opId}`;
  f.data.set(claim, {uid:id, operationId:opId});
  f.data.set(operation, {id, by:'manager', state:'RetryRequired', leaseUntil:0, leaseToken:'lease'});
  f.authRows.set(id, {email:draft.email, disabled:false});
  await rejects(f.service.create('otherManager', draft), 'STAFF_EMAIL_IN_USE');
  assert.equal(f.data.get(claim).uid, id);
  f.authRows.delete(id);
  const result = await f.service.create('otherManager', draft);
  assert.notEqual(result.id, id);
  assert.equal(f.data.get(claim).uid, result.id);
  assert.equal(f.data.has(operation), false);
});

test('staff contact validation rejects invalid data without reserving an address or writing a profile', async () => {
  const f = fixture();
  for (const input of [{name:'**--'}, {phone:'abcdefghi'}, {phone:'-----1234'}, {phone:'1234567890123456'}]) {
    await rejects(f.service.create('manager', {...draft, ...input}), 'INVALID_STAFF_ACCOUNT');
    await rejects(f.service.update('manager', 'target', {...updateBody, ...input}), 'INVALID_STAFF_ACCOUNT');
  }
  assert.equal(f.calls.length, 0);
  const result = await f.service.create('manager', {...draft, name:'陈美玲', phone:'+60 (12) 345-6789'});
  assert.equal(f.data.get(`staff/${result.id}`).name, '陈美玲');
});

test('custom work titles round-trip with staff access and require a valid title', async () => {
  const f = fixture();
  const input = {...draft, jobRole: 'Other', jobTitle: '  Seamstress  '};
  await rejects(f.service.create('manager', {...input, jobTitle: '---'}), 'INVALID_STAFF_ACCOUNT');
  const {id} = await f.service.create('manager', input);
  const {record} = await f.service.details('manager', id);
  assert.equal(record.phone, '+60123456789');
  assert.equal(record.jobTitle, 'Seamstress');
  assert.equal(record.role, 'staff');
  assert.equal(record.active, false);
  await f.service.update('manager', id, {...updateBody, jobRole: 'Other', jobTitle: 'Wardrobe assistant'});
  assert.equal((await f.service.details('manager', id)).record.jobTitle, 'Wardrobe assistant');
});
test('a new staff account can be activated after its setup email is accepted', async () => {
  const f = fixture();
  const {id} = await f.service.create('manager', draft);
  await rejects(f.service.status('manager', id, change()), 'STAFF_SETUP_EMAIL_REQUIRED');
  assert.equal(f.data.get(`staff/${id}`).active, false);
  f.mailer.send = async () => {throw Error('Delivery uncertain');};
  const uncertain = await f.service.invite('manager', id, {requestId:'uncertain', revision:1});
  assert.equal(uncertain.reviewRequired, true);
  await rejects(f.service.status('manager', id, change(true, 2)), 'STAFF_SETUP_EMAIL_REQUIRED');
  f.tick();
  f.mailer.send = async message => {f.emails.push(message);};
  assert.deepEqual(await f.service.invite('manager', id, {requestId:'sent', revision:2}), {sent:true});
  assert.equal(f.emails.length, 1);
  assert.equal((await f.service.status('manager', id, change(true, 3))).saved, true);
  assert.equal(f.data.get(`staff/${id}`).active, true);
});

test('interrupted provision can resume same UID; revoked manager cannot grant access or send email',async()=>{
  const f=fixture(),original=f.auth.createManagedUser;
  f.auth.createManagedUser=async r=>{await original(r);throw Error('uncertain network result');};
  await rejects(f.service.create('manager',draft),'STAFF_AUTH_UNAVAILABLE');
  assert.equal([...f.authRows.keys()].filter(k=>k.startsWith('staff_')).length,1);
  f.auth.createManagedUser=original;const r=await f.service.create('manager',draft);assert.equal(f.data.get(`staff/${r.id}`).active,false);
  const recovery=fixture(),provision=recovery.auth.createManagedUser;
  recovery.auth.createManagedUser=async r=>{await provision(r);throw Error();};await rejects(recovery.service.create('manager',draft),'STAFF_AUTH_UNAVAILABLE');
  recovery.auth.createManagedUser=provision;
  const recovered=await recovery.service.create('manager',{...draft,requestId:'after_reload'});assert.equal(recovered.id,r.id);assert.equal(recovery.authRows.size,3);
  const g=fixture(),create=g.auth.createManagedUser;
  g.auth.createManagedUser=async r=>{await create(r);g.data.get('staff/manager').active=false;};
  await rejects(g.service.create('manager',draft),'MANAGER_REQUIRED');assert.equal([...g.data.keys()].filter(k=>k.startsWith('staff/staff_')).length,0);assert.equal(g.emails.length,0);
});

test('updates compare both account and scheduling revisions; email, identity and status cannot be forged',async()=>{
  const f=fixture();await f.service.update('manager','target',updateBody);
  assert.equal(f.data.get('staff/target').name,'Updated Employee');assert.equal(f.data.get('staff/target').email,'target@example.com');
  await rejects(f.service.update('manager','target',updateBody),'STAFF_ACCOUNT_CHANGED');
  for(const extra of [{active:false},{email:'attacker@example.com'},{id:'customer'}])await rejects(f.service.update('manager','target',{...updateBody,...extra}),'INVALID_STAFF_ACCOUNT');
  assert.equal(f.data.get('staffScheduling/target').revision,2);
});

test('manager cannot deactivate or demote self; removing a service with future bookings is blocked',async()=>{
  const f=fixture();await rejects(f.service.status('manager','manager',change(false,0)),'STAFF_SELF_PROTECTION');
  await rejects(f.service.update('manager','manager',{...updateBody,revision:0,profileRevision:0}),'STAFF_SELF_PROTECTION');
  f.data.set('appointments/future',{assignedStaffId:'target',status:'Confirmed',type:'Dress Trial',startAt:now+86400000});
  await rejects(f.service.update('manager','target',{...updateBody,serviceTypes:[]}),'STAFF_HAS_SERVICE_BOOKINGS');
  assert.equal(f.data.get('staffScheduling/target').revision,1);
});

test('deactivation blocks unfinished appointments, including past visits not properly closed, tasks and support tickets',async()=>{
  for(const [path,row] of [
    ['appointments/visit',{assignedStaffId:'target',status:'Confirmed',startAt:now-86400000}],
    ['tasks/task',{staffId:'target',status:'In progress'}],
    ['supportTickets/ticket',{assignedStaffId:'target',status:'Open'}],
  ]){const f=fixture();f.data.set(path,row);await rejects(f.service.status('manager','target',change(false)),'STAFF_HAS_WORK');assert.equal(f.data.get('staff/target').active,true);assert(!f.calls.some(c=>c[0]==='disabled'));}
});

test('expired payment holds and completed work do not prevent deactivation; history is retained',async()=>{
  const f=fixture();f.data.set('appointments/expired',{assignedStaffId:'target',status:'AwaitingPayment',paymentExpiresAt:now-1});
  f.data.set('tasks/done',{assignedStaffId:'target',staffId:'target',status:'Completed'});
  f.data.set('supportTickets/closed',{staffId:'target',status:'Resolved'});
  assert.deepEqual((await f.service.details('manager','target')).workload,{appointments:0,tasks:0,tickets:0});
  const body=change(false);assert.deepEqual(await f.service.status('manager','target',body),{saved:true,syncRequired:false});
  assert.equal(f.data.get('staff/target').active,false);assert.equal(f.authRows.get('target').disabled,true);
  assert(f.data.has('appointments/expired'));assert(f.data.has('tasks/done'));assert(f.data.get('staff/target').accountHistory.some(h=>h.action==='Deactivated access'));
  const calls=f.calls.length;await f.service.status('manager','target',body);assert.equal(f.calls.length,calls);
});

test('minimum role and service staffing are checked before deactivation or profile changes',async()=>{
  for(const policy of [{minimumByRole:{FittingSpecialist:1}},{minimumByService:{'Dress Trial':1}},{minimumOnDuty:3}]){
    const f=fixture();f.data.set('schedulingSettings/policy',{revision:0,minimumOnDuty:1,...policy});
    await assert.rejects(f.service.status('manager','target',change(false)),e=>/^MINIMUM_/.test(e.code));assert.equal(f.data.get('staff/target').active,true);
  }
  const f=fixture();f.data.set('schedulingSettings/policy',{revision:0,minimumOnDuty:1,minimumByService:{'Dress Trial':1}});
  await rejects(f.service.update('manager','target',{...updateBody,serviceTypes:[]}),'MINIMUM_SERVICE_COVERAGE');
});

test('Auth failure leaves access inactive with an explicit retry, never a false success; sync restores correct desired status',async()=>{
  const f=fixture(),original=f.auth.setDisabled;
  f.auth.setDisabled=async()=>{throw Error();};const result=await f.service.status('manager','target',change(false));
  assert.equal(result.saved,false);assert.equal(result.syncRequired,true);assert.equal(f.data.get('staff/target').active,false);assert(f.data.get('staff/target').accountPending);
  await rejects(f.service.update('manager','target',updateBody),'STAFF_ACCOUNT_SYNC_REQUIRED');
  f.auth.setDisabled=original;await f.service.sync('manager','target');assert.equal(f.authRows.get('target').disabled,true);assert.equal(f.data.get('staff/target').accountPending,null);
  await f.service.status('manager','target',change(true,3,'enable'));assert.equal(f.data.get('staff/target').active,true);assert.equal(f.authRows.get('target').disabled,false);
});

test('activation failure does not grant portal access; explicit responsibilities required',async()=>{
  const f=fixture();f.data.get('staff/target').active=false;f.data.delete('staffScheduling/target');
  await rejects(f.service.status('manager','target',change(true)),'STAFF_RESPONSIBILITIES_REQUIRED');
  f.data.set('staffScheduling/target',profile);f.auth.revoke=async()=>{throw Error();};
  assert.equal((await f.service.status('manager','target',change(true))).syncRequired,true);assert.equal(f.data.get('staff/target').active,false);
});

test('concurrent deactivation and sync requests cannot consume required cover or reorder Auth mutations',async()=>{
  const f=fixture();f.data.set('staff/second',{active:true,role:'staff',name:'Second',accountRevision:1});f.data.set('staffScheduling/second',profile);f.authRows.set('second',{email:'second@example.com',disabled:false});
  f.data.set('schedulingSettings/policy',{revision:0,minimumOnDuty:1,minimumByService:{'Dress Trial':1}});
  const results=await Promise.allSettled([f.service.status('manager','target',change(false)),f.service.status('manager','second',change(false,1,'two'))]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal([...['target','second']].filter(id=>f.data.get(`staff/${id}`).active).length,1);
  const g=fixture(),set=g.auth.setDisabled;g.auth.setDisabled=async(...args)=>{await new Promise(resolve=>setTimeout(resolve,10));return set(...args);};
  const first=g.service.status('manager','target',change(false));
  await new Promise(resolve=>setTimeout(resolve,2));await Promise.all([first,g.service.sync('otherManager','target')]);
  assert.equal(g.calls.filter(c=>c[0]==='disabled').length,1);
});

test('portal manager cannot create or grant manager access or change another manager’s role',async()=>{
  const f=fixture(),before=structuredClone(f.data);
  await rejects(f.service.create('manager',{...draft,role:'manager'}),'STAFF_ROLE_PROTECTED');
  await rejects(f.service.update('manager','target',{...updateBody,role:'manager'}),'STAFF_ROLE_PROTECTED');
  await rejects(f.service.update('manager','otherManager',{...updateBody,revision:0,profileRevision:0}),'STAFF_ROLE_PROTECTED');
  assert.deepEqual(f.data,before);
  assert.equal(f.calls.length,0);
  await f.service.update('manager','otherManager',{...updateBody,role:'manager',revision:0,profileRevision:0});
  assert.equal(f.data.get('staff/otherManager').role,'manager');
  assert.equal(f.calls.length,0);
});
test('explicit session revocation clears a staff review but cannot revoke arbitrary customer identities',async()=>{
  const f=fixture();
  f.data.get('staff/target').sessionReviewRequired=true;
  await rejects(f.service.endSessions('manager','customer'),'STAFF_ACCOUNT_NOT_FOUND');
  await f.service.endSessions('manager','target');
  assert.deepEqual(f.calls,[['revoke','target']]);
  assert.equal(f.data.get('staff/target').sessionReviewRequired,false);
});

test('setup email is explicit, sent only to authoritative account owner and never returned or stored as a link',async()=>{
  const f=fixture(),result=await f.service.invite('manager','target',{requestId:'mail1',revision:1});
  assert.deepEqual(result,{sent:true});assert.equal(f.emails.length,1);assert.equal(f.emails[0].to,'target@example.com');assert.match(f.emails[0].link,/private=example/);
  assert(!JSON.stringify([...f.data]).includes('private=example'));assert(!JSON.stringify(result).includes('link'));
  await f.service.invite('manager','target',{requestId:'mail1',revision:1});assert.equal(f.emails.length,1);
  await rejects(f.service.invite('manager','target',{requestId:'mail2',revision:2}),'STAFF_INVITE_WAIT');
  f.tick();await f.service.invite('manager','target',{requestId:'mail2',revision:2});assert.equal(f.emails.length,2);
});

test('ambiguous mail delivery is review-only and never automatically resent; missing SMTP and identity mismatch fail safely',async()=>{
  const f=fixture();f.mailer.send=async()=>{throw Error();};
  assert.deepEqual(await f.service.invite('manager','target',{requestId:'mail',revision:1}),{sent:false,reviewRequired:true});
  await rejects(f.service.invite('manager','target',{requestId:'mail',revision:2}),'STAFF_INVITE_REVIEW');
  assert.equal(f.data.get('staff/target').invitationState,'ReviewRequired');
  const g=fixture();g.authRows.set('target',{email:'changed@example.com',disabled:false});await rejects(g.service.invite('manager','target',{requestId:'mail',revision:1}),'STAFF_ACCOUNT_CONFLICT');assert.equal(g.emails.length,0);
  g.service.mailer=null;await rejects(g.service.invite('manager','target',{requestId:'mail2',revision:2}),'STAFF_MAIL_UNAVAILABLE');
});

test('Firebase Admin adapter creates a unique identity with a random unexposed password and does not adopt another email',async()=>{
  let created,updated,revoked,reset;
  const adapter=new FirebaseStaffAuth({getUser:async()=>{throw Object.assign(Error(),{code:'auth/user-not-found'});},
    createUser:async r=>{created=r;return {uid:r.uid};},updateUser:async(...args)=>updated=args,revokeRefreshTokens:async id=>revoked=id,generatePasswordResetLink:async email=>{reset=email;return 'https://example.com/reset';}});
  assert.deepEqual(await adapter.createManagedUser({uid:'unique',email:'new@example.com',displayName:'Employee'}),{uid:'unique'});
  assert.equal(created.uid,'unique');assert.equal(created.disabled,false);assert(created.password.length>40);assert.equal(created.emailVerified,false);
  await adapter.setDisabled('unique',true);assert.deepEqual(updated,['unique',{disabled:true}]);await adapter.revoke('unique');assert.equal(revoked,'unique');await adapter.setupLink('new@example.com');assert.equal(reset,'new@example.com');
  adapter.auth.getUser=async()=>({email:'other@example.com'});await rejects(adapter.createManagedUser({uid:'unique',email:'new@example.com'}),'STAFF_ACCOUNT_CONFLICT');
});

test('SMTP adapter requires acceptance of the exact recipient and sends plaintext owner-only setup mail',async()=>{
  let message;const mailer=new StaffSetupMailer({from:'sender@example.com',transport:{sendMail:async m=>{message=m;return {accepted:[m.to]};}}});
  await mailer.send({to:'owner@example.com',name:'Employee',link:'https://example.com/reset'});assert.equal(message.to,'owner@example.com');assert.equal(message.bcc,undefined);assert.match(message.text,/manager must also activate/);
  mailer.transport.sendMail=async()=>({accepted:['someoneelse@example.com']});await assert.rejects(mailer.send({to:'owner@example.com',name:'Employee',link:'https://example.com/reset'}));
});

test('staff workload query deduplicates assignment fields and fails closed beyond safety cap',async()=>{
  const f=fixture();f.data.set('tasks/task',{assignedStaffId:'target',staffId:'target',status:'Open'});
  assert.equal((await f.service.details('manager','target')).workload.tasks,1);
  for(let i=0;i<501;i++)f.data.set(`appointments/large${i}`,{assignedStaffId:'target',status:'Confirmed'});
  await rejects(f.service.status('manager','target',change(false)),'SCHEDULE_LIMIT');assert.equal(f.data.get('staff/target').active,true);
});

test('account capacity is checked before provisioning; old status requests cannot misreport a newer access state',async()=>{
  const f=fixture();for(let i=0;i<96;i++)f.data.set(`staff/old${i}`,{active:false,role:'staff'});
  await rejects(f.service.create('manager',draft),'STAFF_ACCOUNT_LIMIT');assert.equal(f.calls.length,0);
  const g=fixture();await g.service.status('manager','target',change(false));await g.service.status('manager','target',change(true,3,'newer'));
  await rejects(g.service.status('manager','target',change(false)),'STAFF_ACCOUNT_CHANGED');assert.equal(g.data.get('staff/target').active,true);
});

test('HTTP endpoints use verified token identity, reject extra scope/body fields, and provide no delete route',async()=>{
  const f=fixture(),server=createServer(createHandler({service:{},staffAccounts:f.service,verifyToken:async uid=>({uid})}));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${server.address().port}`;
  const request=(path,uid='manager',body,method=body?'POST':'GET')=>fetch(base+path,{method,headers:{...(uid?{authorization:`Bearer ${uid}`}:{}) ,...(body?{'content-type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});
  try{
    assert.equal((await request('/v1/staff-accounts',null)).status,401);
    assert.equal((await request('/v1/staff-accounts','target')).status,403);
    assert.equal((await request('/v1/staff-accounts?uid=target')).status,400);
    assert.equal((await request('/v1/staff-accounts/target/sync','manager',{uid:'manager'})).status,400);
    assert.equal((await request('/v1/staff-accounts/target','manager',undefined,'DELETE')).status,404);
    assert.equal((await request('/v1/staff-accounts','manager',{...draft,active:true})).status,400);
    assert.equal((await request('/v1/staff-accounts','manager',{...draft,role:'manager'})).status,403);
    assert.equal((await request('/v1/staff-accounts/target','manager',{...updateBody,role:'manager'})).status,403);
    const response=await request('/v1/staff-accounts','manager',draft);assert.equal(response.status,201);assert((await response.json()).id.startsWith('staff_'));
    assert.equal((await request('/v1/staff-accounts/target')).status,200);
  }finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});
