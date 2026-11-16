import test from 'node:test';
import assert from 'node:assert/strict';
import {withBusinessNotifications,syncPendingBusiness,businessEvents} from './business_notifications.mjs';
import {StaffWorkspaceService} from './staff_workspace.mjs';
import {quoteFitting,respondFitting} from './fitting_proposals.mjs';

const plan='a'.repeat(32), bill='b'.repeat(32),visit='c'.repeat(32),now=1900000000000;
function fixture(){
  const data=new Map(Object.entries({
    'brides/bride':{name:'Private customer'},'brides/other':{name:'Other'},
    'staff/john':{active:true,role:'staff'},'staff/mary':{active:true,role:'staff'},
    'staffScheduling/john':{jobRole:'FrontDesk'},'staffScheduling/mary':{jobRole:'FrontDesk'},
    'staff/inactive':{active:false,role:'staff'},
    [`appointments/${visit}`]:{uid:'bride',status:'Confirmed',assignedStaffId:'mary'},
    [`packageSelections/${plan}`]:{id:plan,uid:'bride',appointmentIds:[visit],fittingQuote:{revision:1,state:'AwaitingCustomer',by:'john',createdAt:now}},
  }));
  let queue=Promise.resolve(),failCommit=false;
  const base={get:async p=>structuredClone(data.get(p)),inboxPage:async uid=>{
    const records=[...data].filter(([p])=>p.startsWith(`inboxes/${uid}/items/`)).map(([p,v])=>({...v,id:p.split('/').at(-1)}));
    return {records,unread:records.filter(n=>n.readAt===null).length,nextCursor:null};
  },pendingNotificationSources:async()=>[`packageSelections/${plan}`],atomic:update=>{
    const run=queue.then(async()=>{
      const writes=new Map();let writing=false;
      const result=await update({get:async p=>{assert(!writing,'Read after first Firestore write');return structuredClone(data.get(p));},
        set:(p,v)=>{writing=true;writes.set(p,structuredClone(v));},delete:p=>{writing=true;writes.set(p,null);}});
      if(failCommit)throw Error('Simulated commit failure');
      for(const[p,v]of writes)v===null?data.delete(p):data.set(p,v);
      return result;
    });queue=run.catch(()=>{});return run;
  }};
  const store=withBusinessNotifications(base,{now:()=>now});
  const workspace=new StaffWorkspaceService({store,now:()=>now});
  const inbox=uid=>base.inboxPage(uid);
  return {data,base,store,workspace,inbox,fail:()=>failCommit=true};
}

test('proposal and reminder commit together, only to its customer, without private notes',async()=>{
  const f=fixture();f.data.delete(`packageSelections/${plan}`);
  await f.store.atomic(tx=>tx.set(`packageSelections/${plan}`,{uid:'bride',fittingQuote:{revision:1,state:'AwaitingCustomer',by:'john',createdAt:now,note:'PRIVATE NOTE'}}));
  const n=(await f.inbox('bride')).records;
  assert.equal(n.length,1);assert.equal(n[0].sourceId,plan);assert.equal(n[0].sourceType,'Package');
  assert.equal((await f.inbox('other')).unread,0);assert.equal((await f.inbox('john')).unread,0);
  assert(!JSON.stringify(n).includes('PRIVATE'));
});
test('real fitting proposal and customer acceptance transactions produce both sides of the workflow',async()=>{
  const f=fixture(),workflow={store:f.store,now:()=>now};
  f.data.set(`packageSelections/${plan}`,{id:plan,uid:'bride',totalCents:74900,selectedGowns:[],services:[],appointmentIds:[visit],
    fittingWorkflowVersion:2,fittingDecisionRevision:1,fittingDecision:{outcome:'Selected',adjustment:'None'}});
  await quoteFitting(workflow,'john',plan,{requestId:'quote-1',revision:0,decisionRevision:1,note:'Customer chose this gown after the fitting.',lines:[]});
  assert.equal((await f.inbox('bride')).records[0].kind,'ProposalReady');
  await respondFitting(workflow,'bride',plan,{revision:1,response:'Accept'});
  assert.equal((await f.inbox('john')).records[0].kind,'ProposalAccepted');
  await respondFitting(workflow,'bride',plan,{revision:1,response:'Accept'});
  assert.equal((await f.inbox('john')).records.length,1);
});
test('customer acceptance notifies responsible active staff rather than every employee',async()=>{
  const f=fixture();await f.store.atomic(async tx=>{const s=await tx.get(`packageSelections/${plan}`);tx.set(`packageSelections/${plan}`,{...s,fittingQuote:{...s.fittingQuote,state:'Accepted',response:'Accept',respondedAt:now}});});
  assert.equal((await f.inbox('john')).unread,1);assert.equal((await f.inbox('mary')).unread,1);
  assert.equal((await f.inbox('inactive')).unread,0);assert.equal((await f.inbox('other')).unread,0);
});
test('repeated callbacks and reconciliation never recreate an unread receipt',async()=>{
  const f=fixture();const row={uid:'bride',packageSelectionId:plan,appointmentId:visit,state:'Quoted',createdAt:now,reference:'PRIVATE-BANK-REF'};
  await f.store.atomic(tx=>tx.set(`sandboxInvoices/${bill}`,row));
  await f.store.atomic(tx=>tx.set(`sandboxInvoices/${bill}`,{...row,state:'SandboxPaid',paidAt:now}));
  const paid=(await f.inbox('bride')).records.find(n=>n.kind==='PaymentVerified');
  await f.workspace.readNotification('bride',paid.id);
  await f.store.atomic(tx=>tx.set(`sandboxInvoices/${bill}`,{...row,state:'SandboxPaid',paidAt:now,updatedAt:now+1}));
  const notifications=(await f.inbox('bride')).records;
  assert.equal(notifications.filter(n=>n.kind==='PaymentVerified').length,1);
  assert.equal(notifications.find(n=>n.id===paid.id).readAt,now);
  assert(!JSON.stringify(notifications).includes('PRIVATE-BANK'));
  await assert.rejects(f.workspace.readNotification('other',paid.id),e=>e.code==='NOTIFICATION_NOT_FOUND');
});
test('failed business transaction cannot leave a successful notification',async()=>{
  const f=fixture(),before=structuredClone([...f.data]);f.fail();
  await assert.rejects(f.store.atomic(tx=>tx.set(`sandboxInvoices/${bill}`,{uid:'bride',state:'Quoted'})),/commit failure/);
  assert.deepEqual([...f.data],before);
});
test('existing pending proposal is recovered once and read acknowledgement survives refresh',async()=>{
  const f=fixture();await syncPendingBusiness(f.store,'bride');
  const n=(await f.inbox('bride')).records[0];assert(n);
  await f.workspace.readNotification('bride',n.id);
  await syncPendingBusiness(f.store,'bride');
  assert.equal((await f.inbox('bride')).records.length,1);assert.equal((await f.inbox('bride')).unread,0);
});
test('unavailable accounts do not receive staff alerts',async()=>{
  const f=fixture();f.data.set('staff/john',{role:'staff',active:false});
  await f.store.atomic(tx=>tx.set(`packageSelections/${plan}`,{uid:'bride',fittingQuote:{revision:1,state:'Accepted',by:'john',respondedAt:now}}));
  assert.equal((await f.inbox('john')).unread,0);
});
test('appointment rescheduling, prepared items and return generate actionable record types',()=>{
  assert.equal(businessEvents('appointments',visit,{status:'Confirmed',startAt:1},{status:'Confirmed',startAt:2,revision:3})[0].sourceType,'Appointment');
  assert.equal(businessEvents('rentalServiceProgress',plan,{preparation:'Preparing'},{preparation:'Ready',revision:2})[0].kind,'ItemsPrepared');
  assert.equal(businessEvents('rentals','r',{state:'Locked'},{state:'Locked',returnedAt:now,packageSelectionId:plan})[0].kind,'ReturnRecorded');
  assert.deepEqual(businessEvents('packageSelections',plan,{note:'one'},{note:'two'}),[]);
  assert.deepEqual(businessEvents('packageSelections',plan,null,{fittingWorkflowVersion:2,fittingQuote:{state:'AwaitingCustomer',revision:1,context:'stale'}}),[]);
});
test('a paid invoice requiring review never produces an ordinary success receipt',()=>{
  const events=businessEvents('sandboxInvoices',bill,{state:'Quoted'},{state:'SandboxPaid',reviewReason:'Late payment',paidAt:now});
  assert.deepEqual(events.map(e=>e.kind),['PaymentReview']);
});
