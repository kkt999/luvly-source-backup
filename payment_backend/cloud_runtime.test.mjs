import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {prepareCloudConfig,scheduledHandler,maintenance} from './cloud_runtime.mjs';
import {FirestoreCalendarCoordination} from './calendar_coordination.mjs';

function database(){
  const rows=new Map();let queue=Promise.resolve();
  const db={doc:path=>({path}),runTransaction:fn=>{const r=queue.then(async()=>{const writes=[];let writing=false;
    const value=await fn({get:async ref=>{assert(!writing);return {data:()=>structuredClone(rows.get(ref.path))};},set:(ref,row)=>{writing=true;writes.push([ref.path,row]);},delete:ref=>{writing=true;writes.push([ref.path,undefined]);}});
    for(const[p,row]of writes)if(row===undefined)rows.delete(p);else rows.set(p,structuredClone(row));return value;
  });queue=r.catch(()=>{});return r;}};
  return {db,rows};
}
test('cloud configuration excludes local administrator credentials and preserves the Calendar encryption key',()=>{
  assert.equal(prepareCloudConfig({}),null);
  assert.throws(()=>prepareCloudConfig({K_SERVICE:'api'}));
  const key=Buffer.alloc(32,8),env={K_SERVICE:'api',LUVLY_CONFIG_BUNDLE:JSON.stringify({projectId:'luvly-44c77',paymentSecret:'fixture-secret',categoryCode:'fixture',calendarKey:key.toString('base64'),files:{'mail-config.json':{enabled:false},'../outside.json':{}}})};
  const dir=prepareCloudConfig(env);assert.equal(env.TOYYIBPAY_ENV,'sandbox');assert.equal(env.LUVLY_CONFIG_BUNDLE,undefined);
  assert.deepEqual(readFileSync(join(dir,'calendar-token.key')),key);
  assert(!existsSync(join(dir,'service-account.json')));assert(existsSync(join(dir,'mail-config.json')));
});
test('scheduler route rejects app tokens / wrong identities and awaits work before acknowledging',async t=>{
  let calls=0;const audience='https://api.example',email='worker@example.iam.gserviceaccount.com';
  const payload={email,email_verified:true,aud:audience,iss:'https://accounts.google.com',exp:100};
  const server=createServer(scheduledHandler({handler:(_q,r)=>{r.writeHead(418);r.end();},audience,email,now:()=>1000,
    verify:async token=>token==='valid'?payload:{...payload,email:'other@example.com'},run:async()=>{await new Promise(r=>setTimeout(r,5));calls++;return {failed:[]};}}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>server.close());const base=`http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base+'/health')).status,418);
  assert.equal((await fetch(base+'/internal/maintenance')).status,404);
  for(const token of ['', 'app-token'])assert.equal((await fetch(base+'/internal/maintenance',{method:'POST',headers:{Authorization:'Bearer '+token}})).status,401);
  assert.equal(calls,0);assert.equal((await fetch(base+'/internal/maintenance',{method:'POST',headers:{Authorization:'Bearer valid'}})).status,200);assert.equal(calls,1);
  payload.exp=0;assert.equal((await fetch(base+'/internal/maintenance',{method:'POST',headers:{Authorization:'Bearer valid'}})).status,401);
});
test('maintenance lease prevents overlap; errors are retryable and never skip unrelated queues',async()=>{
  const {db}=database(),calls=[];let release;
  const options={db,now:()=>100,store:{expiredRentalIds:async()=>[],expiredExtensionIds:async()=>[],activeRentalIds:async()=>[],pendingFittingIds:async()=>['a'],pendingBookingIds:async()=>[]},
    rentals:{},bookings:{expirePayment:async()=>{calls.push('booking');await new Promise(r=>release=r);}},reviews:{cleanup:async()=>{calls.push('cleanup');throw Error('private error');}}};
  const first=maintenance(options);while(!release)await new Promise(r=>setTimeout(r,1));
  assert.deepEqual(await maintenance(options),{busy:true});release();
  assert.deepEqual(await first,{busy:false,failed:['reviewCleanup']});assert.deepEqual(calls,['booking','cleanup']);
  options.bookings.expirePayment=async()=>{};options.reviews.cleanup=async()=>{};assert.deepEqual(await maintenance(options),{busy:false,failed:[]});
});
test('OAuth states survive process replacement, are single-use and a new connect/disconnect invalidates old states',async()=>{
  const {db}=database(),a=new FirestoreCalendarCoordination({db}),b=new FirestoreCalendarCoordination({db});
  await a.put('first',{uid:'u',verifier:'sealed',expires:5000});
  assert.equal((await b.take('first')).verifier,'sealed');assert.equal(await a.take('first'),null);
  await a.put('second',{uid:'u'});await b.put('third',{uid:'u'});assert.equal(await a.take('second'),null);
  await a.clear('u');assert.equal(await b.take('third'),null);
});
test('Calendar leases serialize different cloud processes and release after failures',async()=>{
  const {db}=database(),a=new FirestoreCalendarCoordination({db,now:()=>1}),b=new FirestoreCalendarCoordination({db,now:()=>1});let release;
  const first=a.locked('u',()=>new Promise(r=>release=r));while(!release)await new Promise(r=>setTimeout(r,1));
  await assert.rejects(b.locked('u',()=>{}),e=>e.code==='CALENDAR_BUSY');release();await first;
  await assert.rejects(a.locked('u',()=>{throw Error('test');}));assert.equal(await b.locked('u',()=>42),42);
});
