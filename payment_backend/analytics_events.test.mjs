import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import {AnalyticsEvents,serveAnalyticsEvents} from './analytics_events.mjs';
import {createHandler} from './http_app.mjs';
import {HttpError} from './payment_service.mjs';

function fixture(){
 const listeners=new Map(), roles={manager:'manager',staff:'staff',bride:'bride'};let opens=0,closes=0;
 const store={get:async path=>{
    const [collection,uid]=path.split('/');
    if(collection==='staffScheduling'&&['staff','manager'].includes(uid))return {jobRole:'FrontDesk'};
    return collection==='staff'&&roles[uid]?{active:true,role:roles[uid]}:null;
  },
  watchAnalytics:(name,next,error)=>{
   opens++;const item={next,error};if(!listeners.has(name))listeners.set(name,new Set());listeners.get(name).add(item);
   queueMicrotask(next);return ()=>{closes++;listeners.get(name).delete(item);};
 }};
 const access=async uid=>{if(!roles[uid])throw new HttpError(403,'ACCOUNT_ACCESS_REQUIRED');return {role:roles[uid]};};
 const events=new AnalyticsEvents({store,access,idleMs:5,debounceMs:2});
 return {events,roles,counts:()=>({opens,closes}),change:name=>{for(const x of listeners.get(name)??[])x.next();},fail:name=>{for(const x of listeners.get(name)??[])x.error(new Error('Never expose raw SDK detail'));}};
}
test('source listeners are shared, role-scoped, debounced and cleaned after last viewer',async()=>{
 const f=fixture(),a=[],b=[],staff=[];
 const x=await f.events.subscribe('manager',e=>a.push(e)),y=await f.events.subscribe('manager',e=>b.push(e));
 const z=await f.events.subscribe('staff',e=>staff.push(e));await delay(1);
 assert.equal(f.counts().opens,10);assert.ok(a.includes('ready'));assert.ok(b.includes('ready'));
 f.change('sandboxInvoices');f.change('sandboxInvoices');await delay(8);
 assert.equal(a.filter(v=>v==='changed').length,1);assert.equal(b.filter(v=>v==='changed').length,1);
 assert.ok(!staff.includes('changed'));
 x.close();await delay(8);assert.equal(f.counts().closes,0);
 y.close();z.close();await delay(12);assert.equal(f.counts().closes,10);f.events.close();
});
test('unauthorised viewers cannot start listeners; source error signals unavailable without data',async()=>{
 const f=fixture();await assert.rejects(f.events.subscribe('bride',()=>{}));await assert.rejects(f.events.subscribe('missing',()=>{}));
 assert.equal(f.counts().opens,0);
 const received=[];await f.events.subscribe('manager',e=>received.push(e));await delay(1);
 f.fail('brides');assert.ok(received.includes('unavailable'));assert.equal(f.counts().closes,7);
 assert.ok(!JSON.stringify(received).includes('SDK'));f.events.close();
});
test('HTTP event stream authenticates, rejects query tokens/origins and never sends business rows',async t=>{
 const f=fixture(),server=createServer(createHandler({service:{},analyticsEvents:f.events,verifyToken:async uid=>({uid}),allowedOrigins:['https://portal.test']}));
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>{f.events.close();server.closeAllConnections();server.close();});
 const url=`http://127.0.0.1:${server.address().port}/v1/analytics/events`;
 assert.equal((await fetch(url)).status,401);
 assert.equal((await fetch(url,{headers:{authorization:'Bearer bride'}})).status,403);
 assert.equal((await fetch(url+'?token=manager',{headers:{authorization:'Bearer manager'}})).status,400);
 assert.equal((await fetch(url,{headers:{authorization:'Bearer manager',origin:'https://evil.test'}})).status,403);
 const abort=new AbortController();const result=await fetch(url,{headers:{authorization:'Bearer manager',origin:'https://portal.test'},signal:abort.signal});
 assert.equal(result.headers.get('content-type'),'text/event-stream; charset=utf-8');assert.equal(result.headers.get('cache-control'),'no-store, no-transform');
 const reader=result.body.getReader(),first=await reader.read();assert.match(new TextDecoder().decode(first.value),/data: (ready|connecting)/);
 f.change('sandboxInvoices');await delay(8);const second=await reader.read();
 const text=new TextDecoder().decode(second.value);assert.match(text,/data: changed/);
 for(const value of ['invoiceNo','customer','amountCents','uid'])assert.ok(!text.includes(value));
 abort.abort();await delay(12);assert.equal(f.counts().closes,7);
});
test('live session rechecks token and role, expires and releases listeners',async t=>{
 const f=fixture();let valid=true;
 const server=createServer(async(req,res)=>{try{await serveAnalyticsEvents({req,res,events:f.events,uid:'manager',verifySession:async()=>{if(!valid)throw Error('revoked');},heartbeatMs:5,durationMs:50});}catch{res.writeHead(403);res.end();}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>{f.events.close();server.closeAllConnections();server.close();});
 const url=`http://127.0.0.1:${server.address().port}`;
 const result=await fetch(url);valid=false;
 assert.match(await result.text(),/data: access-denied/);await delay(12);assert.equal(f.counts().closes,7);
 valid=true;f.roles.manager='staff';const changed=await fetch(url);f.roles.manager='manager';
 assert.match(await changed.text(),/data: access-denied/);
 const expiring=await fetch(url);assert.match(await expiring.text(),/data: ready/);await delay(12);f.events.close();
});
