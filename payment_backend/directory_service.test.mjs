import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {DirectoryService} from './directory_service.mjs';
import {FirestoreStore} from './firestore_store.mjs';
import {createHandler} from './http_app.mjs';

class Query {
  constructor(collection,filters=[],fields=null,cap=Infinity){Object.assign(this,{collection,filters,fields,cap});}
  where(...filter){return new Query(this.collection,[...this.filters,filter],this.fields,this.cap);}
  select(...fields){return new Query(this.collection,this.filters,fields,this.cap);}
  limit(cap){return new Query(this.collection,this.filters,this.fields,cap);}
}
function fixture() {
  const data=new Map(Object.entries({
    'staff/manager':{active:true,role:'manager',name:'Manager',secret:'private'},
    'staff/staff':{active:true,role:'staff',name:'John'},'staff/revoked':{active:false,role:'staff'},
    'brides/a':{name:'Jane',email:'jane@example.com',phone:'0123456789',notes:'private profile note',measurements:{bust:88}},
    'brides/b':{name:'Amy',email:'amy@example.com',phone:'0198765432',calendarToken:'private'},
    'appointments/one':{uid:'a',assignedStaffId:'staff'},'appointments/two':{uid:'b',assignedStaffId:'other'},
    'packageSelections/one':{uid:'a',rentalPlan:{eventDate:'2030-10-24'},invoiceId:'private'},
    'packageSelections/two':{uid:'b',rentalPlan:{eventDate:'2030-11-15'}},
  }));
  const reads=[];
  const doc=(path,value)=>({id:path.split('/')[1],exists:value!==undefined,data:()=>structuredClone(value)});
  const database={doc:path=>({path}),collection:name=>new Query(name),runTransaction:async(fn,options)=>{
    assert.deepEqual(options,{readOnly:true});
    return fn({get:async target=>{
      reads.push(target);
      if(target.path)return doc(target.path,data.get(target.path));
      const rows=[...data].filter(([path,value])=>path.startsWith(target.collection+'/') && target.filters.every(([field,op,wanted])=>op==='in'?wanted.includes(value[field]):value[field]===wanted)).slice(0,target.cap);
      return {docs:rows.map(([path,value])=>doc(path,target.fields?Object.fromEntries(target.fields.filter(k=>Object.hasOwn(value,k)).map(k=>[k,value[k]])):value))};
    },set:()=>assert.fail('read-only directory must never write'),delete:()=>assert.fail('read-only directory must never delete')});
  }};
  const store=new FirestoreStore(database);
  const access=async uid=>{const actor=data.get(`staff/${uid}`);if(actor?.active!==true)throw Object.assign(Error(),{status:403,code:'ACCOUNT_ACCESS_REQUIRED'});return {uid,role:actor.role};};
  return {data,reads,store,service:new DirectoryService({store,access})};
}
test('staff customer directory is assignment-scoped and returns only basic fields',async()=>{
  const f=fixture(),result=await f.service.list('staff','customers');
  assert.deepEqual(result,{records:[{id:'a',name:'Jane',email:'jane@example.com',phone:'0123456789',eventDates:['2030-10-24']}],limited:false});
  assert(!JSON.stringify(result).includes('private'));
  assert(!f.reads.some(q=>q.collection==='brides'));
  assert(!f.reads.some(q=>q.path==='brides/b'));
  assert(f.reads.filter(q=>q.collection==='packageSelections').every(q=>q.filters.some(([key,op,ids])=>key==='uid'&&op==='in'&&ids.every(id=>id==='a'))));
});
test('staff without assignments see an empty list and never query all customers',async()=>{
  const f=fixture();f.data.set('staff/empty',{active:true,role:'staff'});
  assert.deepEqual((await f.service.list('empty','customers')).records,[]);
  assert(!f.reads.some(q=>q.collection==='brides'||q.collection==='packageSelections'));
});
test('front desk finds contacts from all visits, without reading unrelated profiles',async()=>{
  const f=fixture();
  f.data.set('staff/front',{active:true,role:'staff'});
  f.data.set('staffScheduling/front',{jobRole:'FrontDesk'});
  f.data.set('brides/unrelated',{name:'Unrelated'});
  assert.deepEqual((await f.service.list('front','customers')).records.map(r=>r.id),['b','a']);
  assert(!f.reads.some(q=>q.collection==='brides'||q.path==='brides/unrelated'));
});
test('manager customer and staff directories are whitelisted, sorted and read-only',async()=>{
  const f=fixture();
  assert.deepEqual((await f.service.list('manager','customers')).records.map(r=>r.id),['b','a']);
  const result=await f.service.list('manager','staff');
  assert.equal(result.records.length,3);
  assert(!JSON.stringify(result).includes('secret'));
  assert(result.records.every(r=>Object.keys(r).every(k=>['id','name','email','phone','role','active'].includes(k))));
});
test('staff and revoked sessions cannot query staff accounts; revocation is rechecked in snapshot',async()=>{
  const f=fixture();
  await assert.rejects(f.service.list('staff','staff'),e=>e.code==='DIRECTORY_ACCESS_REQUIRED');
  assert.equal(f.reads.length,0);
  await assert.rejects(f.service.list('revoked','customers'));
  const denied=new DirectoryService({store:f.store,access:async()=>({role:'manager'})});
  await assert.rejects(denied.list('revoked','customers'),e=>e.code==='DIRECTORY_ACCESS_REQUIRED');
  await assert.rejects(denied.list('staff','staff'),e=>e.code==='DIRECTORY_ACCESS_REQUIRED');
});
test('service defensively filters out unassigned customers even with an overbroad store response',async()=>{
  const service=new DirectoryService({access:async()=>({role:'staff'}),store:{directorySnapshot:async()=>({actor:{active:true,role:'staff'},profiles:[{id:'a',name:'Allowed'},{id:'b',name:'Hidden'}],appointments:[{uid:'a',assignedStaffId:'staff'},{uid:'b',assignedStaffId:'other'}],plans:[]})}});
  assert.deepEqual((await service.list('staff','customers')).records.map(r=>r.id),['a']);
});
test('directory refuses truncated results and forged list kinds',async()=>{
  const f=fixture();for(let i=0;i<501;i++)f.data.set(`brides/x${i}`,{name:`Customer ${i}`});
  await assert.rejects(f.service.list('manager','customers'),e=>e.code==='DIRECTORY_LIMIT');
  await assert.rejects(f.service.list('manager','permissions'),e=>e.code==='INVALID_DIRECTORY_QUERY');
});
test('customer beyond first 100 rows is returned, not silently omitted',async()=>{
  const f=fixture();for(let i=0;i<120;i++)f.data.set(`brides/x${i}`,{name:`Customer ${i}`});
  assert.equal((await f.service.list('manager','customers')).records.length,122);
});
test('HTTP requires authentication, rejects caller scope overrides and exposes no write endpoint',async()=>{
  const f=fixture();
  const server=createServer(createHandler({directory:f.service,service:{},verifyToken:async uid=>{if(!['manager','staff'].includes(uid))throw Error();return{uid};}}));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  const request=(path,uid,method='GET')=>fetch(base+path,{method,headers:uid?{Authorization:`Bearer ${uid}`}:{}});
  try{
    assert.equal((await request('/v1/directory/customers')).status,401);
    assert.equal((await request('/v1/directory/staff','staff')).status,403);
    assert.equal((await request('/v1/directory/customers?uid=b','staff')).status,400);
    const result=await (await request('/v1/directory/customers','staff')).json();assert.deepEqual(result.records.map(r=>r.id),['a']);
    assert.equal((await request('/v1/directory/customers','manager','POST')).status,404);
  }finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});
