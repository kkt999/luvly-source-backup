import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {analyticsRange,analyticsDay,analyticsMillis,calculateAnalytics,AnalyticsService} from './analytics.mjs';
import {createHandler} from './http_app.mjs';
import {PaymentService} from './payment_service.mjs';
const now=Date.parse('2026-10-16T10:00:00Z'),date=Date.parse('2026-10-15T02:00:00Z');
const range=analyticsRange({from:'2026-10-15',to:'2026-10-16'},now);
const paid=(id,purpose,amountCents,extra={})=>({id,uid:'bride',appointmentId:'visit',packageSelectionId:'selection',
  environment:'sandbox',state:'SandboxPaid',invoiceNo:`SB-${id}`,purpose,amountCents,paidAt:date+3600000,...extra});
const fixture=()=>({
  appointments:[{id:'visit',uid:'bride',type:'Dress Trial',name:'Bride',status:'Completed',startAt:new Date(date)},
    {id:'future',uid:'other',type:'Dress Trial',name:'Upcoming Bride',status:'Confirmed',startAt:new Date(now+3600000)},
    {id:'cancelled',uid:'bride',type:'Dress Trial',status:'Cancelled',startAt:new Date(date)}],
  packageSelections:[{id:'selection',uid:'bride',packageId:'archived',name:'Historical Bridal Package',createdAt:date}],
  sandboxInvoices:[paid('fitting','FittingFee',5000),paid('deposit','BookingDeposit',39950),paid('balance','PackageBalance',44950),paid('security','SecurityDeposit',30000),
    paid('pending','PackageBalance',90000,{state:'Pending'}),paid('review','BookingDeposit',20000,{reviewReason:'Paid late'})],
  brides:[{id:'bride',bodyShape:'Apple',email:'private@example.com',measurements:{bust:90}},{id:'other'},{id:'third'},{id:'fourth'}],
  bodyTypeSummaries:[{id:'bride',bodyType:'Pear',algorithmVersion:'style-rules-v1'},{id:'third',bodyType:'Hourglass',algorithmVersion:'style-rules-v1'}],
  rentals:[{state:'Held',expiresAt:now-1},{state:'Held',expiresAt:now+1000},{collectedAt:date,returnDate:'2026-10-15'}],
  supportTickets:[{status:'Open'},{status:'Closed'}],
});
const run=data=>calculateAnalytics(data,range,now);
const error=code=>e=>e.code===code;

test('manual cancellation outcomes retain gross receipt history but are not classified as active package sales',()=>{
 const data=fixture();data.sandboxInvoices.find(i=>i.id==='deposit').reviewResolution={state:'RefundRecorded',refundCents:39950};
 const result=run(data);assert.equal(result.totals.grossCents,139900);assert.equal(result.totals.serviceCents,49950);
 assert.equal(result.totals.otherCents,59950);
});

test('early attendance is reported by actual visit date; no-fitting approval does not invent a completed fitting',()=>{
  const data=fixture();data.appointments[0].startAt=new Date(now+3*86400000);data.appointments[0].actualAttendedAt=new Date(date);
  data.packageSelections[0].fittingDecision={mode:'Waived',state:'Approved'};
  const result=run(data);assert.equal(result.totals.completedFittings,1);assert.equal(result.totals.convertedFittings,1);
  assert.equal(result.reports.find(r=>r.id==='conversion').rows[0][1],'2026-10-15');
  data.appointments=[];assert.equal(run(data).totals.completedFittings,0);
});
test('strict MYT ranges reject reverse, future, impossible, oversized and unknown inputs',()=>{
  for(const input of [{from:'2026-02-30',to:'2026-03-01'},{from:'2026-10-17',to:'2026-10-16'},{to:'2026-10-17'},{from:'2019-12-31'},{from:10},{to:'2026-10-16T00:00:00Z'},{format:'csv'}])assert.throws(()=>analyticsRange(input,now),error('INVALID_REPORT_RANGE'));
  assert.throws(()=>analyticsRange({from:'2020-01-01',to:'2026-01-01'},now),error('REPORT_RANGE_TOO_LONG'));
  assert.equal(range.start,Date.parse('2026-10-14T16:00:00Z'));
  assert.equal(range.end,Date.parse('2026-10-16T16:00:00Z'));
  assert.equal(analyticsRange({},now).days,30);
  assert.equal(analyticsMillis({toMillis:()=>date}),date);assert.equal(analyticsMillis('2026-10-15'),null);
});
test('verified service collections exclude refundable security, pending and review receipts, without adding fitting credit twice',()=>{
  const result=run(fixture());
  assert.equal(result.totals.serviceCents,89900);
  assert.equal(result.totals.securityCents,30000);assert.equal(result.totals.otherCents,20000);
  assert.equal(result.totals.grossCents,139900);assert.equal(result.totals.paidCount,5);
  assert.equal(result.trend.reduce((s,b)=>s+b.serviceCents,0),89900);
  assert.equal(result.trend.reduce((s,b)=>s+b.securityCents,0),30000);
  assert.equal(result.details.service.totalCents,89900);
  assert.equal(result.details.service.receipts.reduce((sum,r)=>sum+r.amountCents,0),89900);
  assert.equal(result.details.security.receipts.reduce((sum,r)=>sum+r.amountCents,0),30000);
  assert.deepEqual(result.details.service.receipts.map(r=>r.id).sort(),['balance','deposit','fitting']);
  assert.equal(result.details.selections.length,result.totals.packageSelections);
  assert.equal(result.details.selections.filter(r=>r.paidBooking).length,result.totals.paidPackageBookings);
  assert.equal(result.details.conversion.length,result.totals.completedFittings);
  assert.equal(result.details.conversion.filter(r=>r.converted).length,result.totals.convertedFittings);
});
test('payment date, not creation date, controls collections and MYT boundary is inclusive/exclusive',()=>{
  const data=fixture();data.sandboxInvoices=[paid('old','DressPayment',100,{createdAt:now,paidAt:range.start-1}),
    paid('first','DressPayment',200,{createdAt:0,paidAt:range.start}),paid('later','DressPayment',400,{paidAt:range.end}),paid('future','DressPayment',800,{paidAt:now+1})];
  assert.equal(run(data).totals.serviceCents,200);
  assert.equal(analyticsDay(range.start),'2026-10-15');
});
test('missing metadata and wrong environment never silently become revenue',()=>{
  const data=fixture();data.sandboxInvoices=[paid('bad','DressPayment',100,{invoiceNo:null}),paid('bad2','DressPayment',100,{paidAt:null}),
    paid('bad3','DressPayment',100.5),paid('prod','DressPayment',100,{environment:'production'}),paid('failed','DressPayment',100,{state:'ReviewRequired'})];
  const result=run(data);assert.equal(result.totals.serviceCents,0);assert.equal(result.quality.paidMissingMetadata,4);
});
test('historical package names survive deleted/inactive catalogues and popularity is selections not stock',()=>{
  const data=fixture();data.packageSelections.push({...data.packageSelections[0],id:'unpaid'});
  const result=run(data);assert.equal(result.packages[0].name,'Historical Bridal Package');
  assert.equal(result.packages[0].selections,2);assert.equal(result.packages[0].paidBookings,1);
  assert.deepEqual(result.reports[0].rows[0],['Historical Bridal Package','2','1','100%']);
});
test('conversion is completed Dress Trial cohort, distinct verified linked post-fitting package payment',()=>{
  const data=fixture();data.sandboxInvoices.push(paid('repeat','PackagePayment',1000));
  data.appointments.push({id:'consult',uid:'bride',type:'Bridal Consultation',status:'Completed',startAt:date});
  const result=run(data);assert.equal(result.totals.completedFittings,1);assert.equal(result.totals.convertedFittings,1);assert.equal(result.totals.conversionPercent,100);
  data.sandboxInvoices=data.sandboxInvoices.filter(i=>!['BookingDeposit','PackagePayment'].includes(i.purpose));
  assert.equal(run(data).totals.convertedFittings,0);
});
test('mismatched ownership, unlinked and pre-fitting deposits cannot manufacture conversion',()=>{
  for(const patch of [{uid:'other'},{appointmentId:'other'},{packageSelectionId:'other'},{paidAt:date-1},{reviewReason:'Review'}]){
    const data=fixture();data.sandboxInvoices=[paid('deposit','BookingDeposit',1000,patch)];
    assert.equal(run(data).totals.convertedFittings,0,JSON.stringify(patch));
  }
});
test('only shared category projections count; legacy sizes remain private and snapshots are not date filtered',()=>{
  const result=run(fixture());assert.equal(result.totals.classifiedProfiles,2);assert.equal(result.quality.unclassifiedProfiles,2);
  assert.deepEqual(result.reports[3].rows[1],['Pear','1','50%']);assert.match(result.reports[3].basis,/not date-filtered/);
  const raw=JSON.stringify(result);assert.ok(!raw.includes('private@example.com'));assert.ok(!raw.includes('"measurements":'));
});
test('empty data has valid zero totals, no NaN and no invented customers or transactions',()=>{
  const result=run({});assert.equal(result.totals.serviceCents,0);assert.equal(result.totals.conversionPercent,0);
  assert.equal(result.reports[2].rows.length,0);assert.equal(result.packages.length,0);assert.ok(!JSON.stringify(result).includes('NaN'));
});
test('withdrawn, orphan, unknown-version and legacy-only profiles never inflate the distribution',()=>{
  const d=fixture();d.bodyTypeSummaries.push({id:'orphan',bodyType:'Pear',algorithmVersion:'style-rules-v1'},
    {id:'other',bodyType:'Oval',algorithmVersion:'unknown'}, {id:'fourth',bodyType:null,algorithmVersion:'style-rules-v1'});
  let r=run(d);assert.equal(r.totals.classifiedProfiles,2);
  d.bodyTypeSummaries=[];r=run(d);assert.equal(r.totals.classifiedProfiles,0);
  assert.equal(r.quality.unclassifiedProfiles,4);assert(r.bodyTypes.every(x=>x.count===0));
});
test('366-day trend buckets conserve every cent',()=>{
  const longRange=analyticsRange({from:'2025-10-16',to:'2026-10-16'},now);
  const result=calculateAnalytics(fixture(),longRange,now);
  assert.equal(result.trend.reduce((s,b)=>s+b.serviceCents+b.securityCents+b.otherCents,0),result.totals.grossCents);
});
function serviceFixture(){
  const data=fixture();let calls=0;const roles={manager:{active:true,role:'manager'},staff:{active:true,role:'staff'},revoked:{active:false,role:'manager'}};
  const store={get:async p=>p.startsWith('staff/')?roles[p.slice(6)]:p==='staffScheduling/staff'?{jobRole:'FrontDesk'}:{name:'Bride'},
    analyticsSnapshot:async manager=>{calls++;return manager?data:{appointments:data.appointments,rentals:data.rentals,supportTickets:data.supportTickets};}};
  const payments=new PaymentService({store});const analytics=new AnalyticsService({store,access:uid=>payments.access(uid),now:()=>now});
  return {analytics,data,store,roles,calls:()=>calls};
}
test('manager-only analytics refuses bride, staff and revoked staff before reading data',async()=>{
  const f=serviceFixture();for(const uid of ['bride','staff','revoked'])await assert.rejects(f.analytics.report(uid,{}));
  assert.equal(f.calls(),0);assert.equal((await f.analytics.report('manager',{})).environment,'sandbox');
});
test('staff dashboard returns operational summaries but no receipts, collections, profiles or body data',async()=>{
  const f=serviceFixture();const result=await f.analytics.dashboard('staff');
  assert.equal(result.operations.todayConfirmed,1);assert.equal(result.operations.activeHolds,1);assert.equal(result.operations.overdueReturns,1);
  const raw=JSON.stringify(result);for(const key of ['amountCents','serviceCents','bodyShape','invoiceNo','email','packageSelections'])assert.ok(!raw.includes(key));
});
test('specialist dashboard cannot expose all upcoming customer names',async()=>{
  const f=serviceFixture();f.roles.specialist={active:true,role:'staff'};
  await assert.rejects(f.analytics.dashboard('specialist'),error('OPERATIONS_ACCESS_REQUIRED'));
  assert.equal(f.calls(),0);
});
test('too many records fail explicitly rather than showing the first 100/5000 as a complete total',async()=>{
  const f=serviceFixture();f.data.limited=true;await assert.rejects(f.analytics.report('manager',{}),error('ANALYTICS_LIMIT_REACHED'));
});
test('access revoked while snapshot is loading cannot return privileged data',async()=>{
  const f=serviceFixture();f.store.analyticsSnapshot=async()=>{f.roles.manager.active=false;return f.data;};
  await assert.rejects(f.analytics.report('manager',{}),error('ACCOUNT_ACCESS_REQUIRED'));
});
test('HTTP analytics authenticates, enforces roles and rejects duplicate/unknown query fields',async t=>{
  const f=serviceFixture(),server=createServer(createHandler({service:{},analytics:f.analytics,verifyToken:async uid=>({uid})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>{server.closeAllConnections();server.close();});
  const url=`http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(url+'/v1/analytics')).status,401);
  for(const uid of ['bride','staff','revoked'])assert.equal((await fetch(url+'/v1/analytics',{headers:{authorization:`Bearer ${uid}`}})).status,403);
  for(const query of ['?from=2026-10-15&from=2026-10-16','?role=manager'])assert.equal((await fetch(url+'/v1/analytics'+query,{headers:{authorization:'Bearer manager'}})).status,400);
  const result=await fetch(url+'/v1/analytics?from=2026-10-15&to=2026-10-16',{headers:{authorization:'Bearer manager'}});assert.equal(result.status,200);assert.equal((await result.json()).totals.serviceCents,89900);
  assert.equal((await fetch(url+'/v1/dashboard',{headers:{authorization:'Bearer staff'}})).status,200);
});
