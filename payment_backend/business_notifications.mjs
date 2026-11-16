import {createHash} from 'node:crypto';
import {hasBoutiqueOperationsAccess} from './appointment_access.mjs';
import {fittingContext} from './fitting_proposals.mjs';

const idOK=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
const tracked=/^(packageSelections|appointments|sandboxInvoices|rentals|rentalServiceProgress)\/([A-Za-z0-9_-]{1,150})$/;
const stamp=v=>v?.toMillis?.()??(v instanceof Date?v.getTime():v??0);
const digest=v=>createHash('sha256').update(v).digest('hex').slice(0,32);
const titles={
  ProposalReady:'Your fitting proposal is ready',ProposalAccepted:'A customer accepted the fitting proposal',
  ProposalChanges:'A customer requested changes to the fitting proposal',ProposalConsidering:'A customer is considering the fitting proposal',
  ProposalDeclined:'A customer declined the fitting proposal',InvoiceReady:'A payment is ready to review',
  PaymentVerified:'Payment has been verified',PaymentReview:'A payment needs review',
  AppointmentRequested:'An appointment needs attention',AppointmentConfirmed:'An appointment is confirmed',
  AppointmentChanged:'An appointment was updated',AppointmentCancelled:'An appointment was cancelled',
  AppointmentExpired:'An unpaid appointment has expired',RentalReserved:'Your rental booking is confirmed',
  RentalExpired:'Your rental hold has expired',RentalCancelled:'Your rental was cancelled',
  ItemsPrepared:'Your rental items have been prepared',ReturnRecorded:'Your rental return was recorded',
  RefundRecorded:'Your security refund reconciliation was recorded',
};

// Events contain routing identifiers and generic titles, never customer names,
// body measurements, staff notes, payment references or support message bodies.
export function businessEvents(collection,id,before,after) {
  if(!after)return [];
  const events=[];
  const add=(kind,version,sourceType,sourceId,audience='customer',at,extra={})=>events.push({
    kind,title:titles[kind],event:`${collection}:${id}:${kind}:${version}`,
    sourceType,sourceId,audience,createdAt:stamp(at)||undefined,...extra,
  });
  if(collection==='packageSelections') {
    const q=after.fittingQuote,old=before?.fittingQuote;
    if(q?.state==='AwaitingCustomer'&&(after.fittingWorkflowVersion!==2||q.context===fittingContext(after))&&
        (old?.revision!==q.revision||old?.state!==q.state))
      add('ProposalReady',q.revision,'Package',id,'customer',q.createdAt);
    const responses={Accepted:'ProposalAccepted',ChangesRequested:'ProposalChanges',Considering:'ProposalConsidering',Declined:'ProposalDeclined'};
    if(responses[q?.state]&&(old?.revision!==q.revision||old?.state!==q.state))
      add(responses[q.state],`${q.revision}:${q.response}`,'Package',id,'staff',q.respondedAt);
  } else if(collection==='sandboxInvoices') {
    if(!before&&['Quoted','AwaitingPayment'].includes(after.state)&&!after.paymentBlocked)
      add('InvoiceReady','issued','Payment',id,'customer',after.createdAt);
    if(after.state==='SandboxPaid'&&!after.reviewReason&&(before?.state!=='SandboxPaid'||before?.reviewReason))
      add('PaymentVerified','paid','Payment',id,'both',after.paidAt??after.updatedAt);
    if((after.state==='ReviewRequired'||after.reviewReason)&&
        (before?.state!==after.state||before?.reviewReason!==after.reviewReason))
      add('PaymentReview',digest(`${after.state}:${after.reviewReason}`),'Payment',id,'both',after.updatedAt);
  } else if(collection==='appointments') {
    const state={Requested:'AppointmentRequested',Confirmed:'AppointmentConfirmed',Cancelled:'AppointmentCancelled',Expired:'AppointmentExpired'}[after.status];
    if(state&&before?.status!==after.status)
      add(state,after.revision??1,'Appointment',id,after.status==='Requested'?'staff':'both',after.updatedAt??after.createdAt);
    else if(before&&['Requested','Confirmed','AwaitingPayment'].includes(after.status)&&
        (stamp(before.startAt)!==stamp(after.startAt)||before.assignedStaffId!==after.assignedStaffId))
      add('AppointmentChanged',after.revision??stamp(after.updatedAt),'Appointment',id,'both',after.updatedAt,{previousStaffId:before.assignedStaffId});
  } else if(collection==='rentals'&&idOK(after.packageSelectionId)) {
    const kind={Locked:'RentalReserved',Expired:'RentalExpired',Cancelled:'RentalCancelled'}[after.state];
    if(kind&&before?.state!==after.state)add(kind,'state','Package',after.packageSelectionId,'both',after.updatedAt);
    if(after.returnedAt&&!before?.returnedAt)add('ReturnRecorded','return','Package',after.packageSelectionId,'customer',after.returnedAt);
    if(after.securityState==='RefundRecorded'&&before?.securityState!=='RefundRecorded')
      add('RefundRecorded','refund','Package',after.packageSelectionId,'customer',after.refundRecordedAt);
  } else if(collection==='rentalServiceProgress'&&after.preparation==='Ready'&&before?.preparation!=='Ready') {
    add('ItemsPrepared',after.revision,'Package',id,'customer',after.updatedAt);
  }
  return events;
}

async function deliver(tx,event,row,read,now) {
  let selection=row,booking=row;
  if(event.sourceType==='Payment') {
    selection=idOK(row.packageSelectionId)?await read(`packageSelections/${row.packageSelectionId}`):null;
    booking=idOK(row.appointmentId)?await read(`appointments/${row.appointmentId}`):null;
    if(event.kind==='InvoiceReady'&&(row.paymentBlocked||row.holdExpiresAt&&row.holdExpiresAt<=now()||
        ['Cancelled','Expired','NoShow'].includes(booking?.status)))return;
  } else if(event.sourceType==='Package') {
    selection=await read(`packageSelections/${event.sourceId}`);
    const visitId=selection?.fittingDecision?.appointmentId??selection?.appointmentIds?.at(-1);
    booking=idOK(visitId)?await read(`appointments/${visitId}`):null;
  }
  const customer=row.uid??selection?.uid??booking?.uid;
  const recipients=new Set();
  if(event.audience!=='staff'&&idOK(customer)&&await read(`brides/${customer}`)&&!await read(`staff/${customer}`))recipients.add(customer);
  if(event.audience!=='customer') {
    for(const uid of new Set([event.previousStaffId,row.createdBy,row.confirmedBy,selection?.fittingQuote?.by,
      selection?.fittingDecision?.by,booking?.assignedStaffId,booking?.staffId,
      row.assignedStaffId].filter(idOK))) {
      const actor=await read(`staff/${uid}`);
      if(actor?.active===true&&['staff','manager'].includes(actor.role) &&
          (!['Payment','Package'].includes(event.sourceType) ||
            await hasBoutiqueOperationsAccess({get:read},uid,actor)))recipients.add(uid);
    }
  }
  for(const uid of recipients) {
    const path=`inboxes/${uid}/items/${digest(`${event.event}:${uid}`)}`;
    if(await read(path))continue; // A retry never resets an acknowledged notice.
    tx.set(path,{kind:event.kind,title:event.title,sourceType:event.sourceType,
      sourceId:event.sourceId,createdAt:event.createdAt??now(),readAt:null});
  }
}

// Buffer transaction writes so that notification ownership, deduplication and
// relationship reads all finish before Firestore's first write. Business data
// and its notification then commit or roll back together.
export function withBusinessNotifications(base,{now=Date.now}={}) {
  const atomic=update=>base.atomic(async raw=>{
    const pending=new Map(),originals=new Map();
    const original=async path=>{
      if(!originals.has(path))originals.set(path,await raw.get(path));
      return originals.get(path);
    };
    const tx={...raw,get:original,set:(path,row)=>pending.set(path,row),delete:path=>pending.set(path,null)};
    const result=await update(tx);
    const read=path=>pending.has(path)?Promise.resolve(pending.get(path)):original(path);
    for(const [path,row] of [...pending]) {
      const match=tracked.exec(path);
      if(!match||!row)continue;
      for(const event of businessEvents(match[1],match[2],await original(path),row))
        await deliver(tx,event,row,read,now);
    }
    for(const [path,row] of pending)row===null?raw.delete(path):raw.set(path,row);
    return result;
  });
  return new Proxy(base,{get(target,key){
    if(key==='atomic')return atomic;
    const value=target[key];return typeof value==='function'?value.bind(target):value;
  }});
}

// Recover currently actionable records created before this feature was enabled.
// Re-read each source in a transaction to avoid announcing a stale proposal.
export async function syncPendingBusiness(store,uid) {
  if(typeof store.pendingNotificationSources!=='function')return;
  const paths=await store.pendingNotificationSources(uid);
  if(!paths.length)return;
  await store.atomic(async tx=>{
    for(const path of paths) {
      const match=tracked.exec(path),row=await tx.get(path);
      if(!match||!row)continue;
      const events=businessEvents(match[1],match[2],undefined,row).filter(e=>
        e.kind==='ProposalReady'||e.kind==='InvoiceReady'||
        ['ProposalAccepted','ProposalChanges','ProposalConsidering','ProposalDeclined'].includes(e.kind));
      for(const event of events)await deliver(tx,event,row,tx.get,Date.now);
    }
  });
}
