import {createHash} from 'node:crypto';
import {syncPendingBusiness} from './business_notifications.mjs';
import {HttpError} from './payment_service.mjs';
import {staffPhoneForSave,validContactName} from './contact_validation.mjs';
import {activeEmployee,availableAt} from './workforce.mjs';
import {malaysiaDay} from './booking_dates.mjs';
import {taskBusy,taskQualified} from './task_time.mjs';

const check=(v,code,status=409)=>{if(!v)throw new HttpError(status,code);};
const hash=v=>createHash('sha256').update(v).digest('hex').slice(0,32);
const idOK=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
const keys=(v,allowed)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>allowed.includes(k));
const text=(v,min,max)=>typeof v==='string'&&v.trim().length>=min&&v.length<=max&&!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
const revision=v=>Number.isInteger(v)&&v>=0;
const ms=v=>v?.toMillis?.()??+v;
const liveVisit=(b,now)=>['Requested','Confirmed','AwaitingPayment'].includes(b.status)&&!(b.status==='AwaitingPayment'&&b.paymentExpiresAt<=now);
export const taskTypes=['Fitting preparation','Alteration','Bridal makeup','Front desk','Other'];
export const taskStatuses=['Scheduled','In Progress','Completed','Cancelled'];
const noticeTitles={TaskAssigned:'You have a new task',TaskChanged:'Your task was updated',TaskRemoved:'A task assignment was removed',TaskProgress:'An assigned task was updated',SupportNew:'A new support ticket needs attention',SupportReply:'You have a support reply',SupportClosed:'A support conversation was closed'};

// Inbox bodies never contain customer names, measurements or message contents.
// Only the owning account reads/acknowledges entries; source pages recheck access.
export function notify(tx,recipients,event,kind,sourceType,sourceId,now,actor){
  for(const uid of new Set(recipients.filter(u=>u&&u!==actor))){
    tx.set(`inboxes/${uid}/items/${hash(event+':'+uid)}`,{kind,title:noticeTitles[kind],sourceType,sourceId,createdAt:now,readAt:null});
  }
}

export class StaffWorkspaceService {
  constructor({store,auth,now=Date.now}){Object.assign(this,{store,auth,now});}
  async staff(tx,uid,manager=false){const a=await tx.get(`staff/${uid}`);check(activeEmployee(a)&&(!manager||a.role==='manager'),manager?'MANAGER_REQUIRED':'STAFF_REQUIRED',403);return a;}
  async account(tx,uid){const s=await tx.get(`staff/${uid}`);if(s){check(activeEmployee(s),'ACCOUNT_ACCESS_REQUIRED',403);return {staff:true,row:s};}const b=await tx.get(`brides/${uid}`);check(b,'ACCOUNT_ACCESS_REQUIRED',403);return {staff:false,row:b};}
  profileRow(uid,r,email){return {uid,name:r.name??'',phone:r.phone??'',email:email??r.email??'',role:r.role,revision:r.accountRevision??0};}
  async profile(uid){
    await this.store.atomic(tx=>this.staff(tx,uid));
    let u;try{u=await this.auth.getUser(uid);}catch{throw new HttpError(503,'STAFF_AUTH_UNAVAILABLE');}
    check(!u.disabled,'STAFF_REQUIRED',403);const row=await this.store.atomic(tx=>this.staff(tx,uid));return this.profileRow(uid,row,u.email);
  }
  async saveProfile(uid,input){
    check(keys(input,['name','phone','revision'])&&validContactName(input.name)&&typeof input.phone==='string'&&revision(input.revision),'INVALID_SELF_PROFILE',400);
    await this.store.atomic(tx=>this.staff(tx,uid));
    let auth;try{auth=await this.auth.getUser(uid);}catch{throw new HttpError(503,'STAFF_AUTH_UNAVAILABLE');}
    check(!auth.disabled,'STAFF_REQUIRED',403);
    return this.store.atomic(async tx=>{
      const r=await this.staff(tx,uid);check(!r.accountPending,'STAFF_ACCOUNT_SYNC_REQUIRED');check((r.accountRevision??0)===input.revision,'STAFF_ACCOUNT_CHANGED');
      const phone = staffPhoneForSave(input.phone, r.phone);
      check(phone !== null, 'INVALID_SELF_PROFILE', 400);
      // An email can only come from Firebase Auth after the owner verifies it.
      const email=auth.emailVerified&&auth.email?auth.email.toLowerCase():r.email??auth.email??'';
      const claimPath=e=>`staffAccountEmails/${createHash('sha256').update(e.toLowerCase()).digest('hex')}`;
      const newClaim=email&&email!==r.email?await tx.get(claimPath(email)):null;
      const oldClaim=r.email&&email!==r.email?await tx.get(claimPath(r.email)):null;
      check(!newClaim||newClaim.uid===uid,'STAFF_EMAIL_IN_USE');
      const next={...r,name:input.name.trim(),phone,email,accountRevision:input.revision+1,updatedBy:uid,updatedAt:this.now(),accountHistory:[...(r.accountHistory??[]),{action:'Updated own profile',by:uid,at:this.now()}].slice(-40)};
      if(email&&email!==r.email){if(oldClaim?.uid===uid)tx.delete(claimPath(r.email));tx.set(claimPath(email),{...newClaim,uid});}
      tx.set(`staff/${uid}`,next);return this.profileRow(uid,next,auth.email);
    });
  }
  async taskList(uid){return this.store.atomic(async tx=>{
    const actor=await this.staff(tx,uid),manager=actor.role==='manager';
    const rows=await tx.workspaceTasks(manager?undefined:uid),roster=manager?await tx.staffRoster():[];
    check(rows.length<=500,'TASK_LIST_LIMIT');
    return {uid,manager,staff:roster.filter(activeEmployee).map(r=>({id:r.id,name:r.name??''})),records:rows.filter(t=>t.workspaceVersion===1&&(manager||t.assignedStaffId===uid)).sort((a,b)=>a.startAt-b.startAt)};
  });}
  validateTask(i){
    check(keys(i,['requestId','revision','title','description','type','staffUid','day','startHour','endHour'])&&idOK(i.requestId)&&revision(i.revision)&&text(i.title,3,100)&&text(i.description,0,1000)&&taskTypes.includes(i.type)&&idOK(i.staffUid)&&typeof i.day==='string'&&/^\d{4}-\d\d-\d\d$/.test(i.day),'INVALID_TASK',400);
    const start=Date.parse(i.day+'T00:00:00+08:00')+i.startHour*3600000;
    check(Number.isInteger(i.startHour)&&Number.isInteger(i.endHour)&&((i.startHour>=10&&i.endHour<=13)||(i.startHour>=14&&i.endHour<=17))&&i.endHour>i.startHour&&Number.isFinite(start)&&malaysiaDay(start)===i.day&&start>this.now()&&start<this.now()+180*86400000,'INVALID_TASK_TIME',400);
    return start;
  }
  async saveTask(uid,id,input){
    const startAt=this.validateTask(input);check(id===null||idOK(id),'INVALID_TASK',400);
    const target=id??hash(`task:${uid}:${input.requestId}`),fingerprint=hash(JSON.stringify(input));
    return this.store.atomic(async tx=>{
      await this.staff(tx,uid,true);const path=`tasks/${target}`,old=await tx.get(path);
      if(!id&&old){check(old.createdBy===uid&&old.creationFingerprint===fingerprint,'REQUEST_CONFLICT');return {record:old};}
      check(id?old?.workspaceVersion===1&&old.status==='Scheduled'&&old.revision===input.revision&&old.startAt>this.now():input.revision===0,'TASK_CHANGED');
      const employee=await this.staff(tx,input.staffUid),profile=await tx.get(`staffScheduling/${input.staffUid}`),visits=await tx.staffAppointments(input.staffUid);
      check(taskQualified(profile,input.type),'TASK_SKILL_REQUIRED');
      const dayPath=`appointmentAvailability/${input.day}`,day=await tx.get(dayPath)??{entries:{},bookings:{},revision:0,day:input.day};
      const oldDayPath=old?`appointmentAvailability/${old.day}`:dayPath,oldDay=oldDayPath===dayPath?day:await tx.get(oldDayPath);
      for(let h=input.startHour;h<input.endHour;h++){
        check(availableAt(day.entries?.[input.staffUid],h)&&!taskBusy(day,input.staffUid,h,target),'TASK_STAFF_UNAVAILABLE');
        check(!Object.entries(day.bookings??{}).some(([hour,b])=>b.staffId===input.staffUid&&+hour===h)&&!visits.some(b=>liveVisit(b,this.now())&&ms(b.startAt)<startAt+(h-input.startHour+1)*3600000&&ms(b.startAt)+3600000>startAt+(h-input.startHour)*3600000),'TASK_APPOINTMENT_CONFLICT');
      }
      const row={id:target,workspaceVersion:1,title:input.title.trim(),description:input.description.trim(),type:input.type,assignedStaffId:input.staffUid,staffName:employee.name??'',day:input.day,startHour:input.startHour,endHour:input.endHour,startAt,endAt:startAt+(input.endHour-input.startHour)*3600000,status:'Scheduled',revision:(old?.revision??0)+1,createdBy:old?.createdBy??uid,createdAt:old?.createdAt??this.now(),creationFingerprint:old?.creationFingerprint??fingerprint,updatedBy:uid,updatedAt:this.now()};
      const blocks={...day.taskBlocks};delete blocks[target];blocks[target]={staffId:input.staffUid,startHour:input.startHour,endHour:input.endHour};
      if(old&&oldDayPath!==dayPath){const prior={...oldDay?.taskBlocks};delete prior[target];tx.set(oldDayPath,{...oldDay,taskBlocks:prior,revision:(oldDay?.revision??0)+1});}
      tx.set(dayPath,{...day,taskBlocks:blocks,revision:day.revision+1});tx.set(path,row);
      notify(tx,[row.assignedStaffId],`task:${target}:${row.revision}`,old?'TaskChanged':'TaskAssigned','Task',target,this.now(),uid);
      if(old&&old.assignedStaffId!==row.assignedStaffId)notify(tx,[old.assignedStaffId],`task-removed:${target}:${row.revision}`,'TaskRemoved','Task',target,this.now(),uid);
      return {record:row};
    });
  }
  async taskStatus(uid,id,input){
    check(idOK(id)&&keys(input,['revision','status','note'])&&revision(input.revision)&&['In Progress','Completed','Cancelled'].includes(input.status)&&text(input.note,0,500),'INVALID_TASK',400);
    return this.store.atomic(async tx=>{
      const actor=await this.staff(tx,uid),row=await tx.get(`tasks/${id}`);check(row?.workspaceVersion===1,'TASK_NOT_FOUND',404);
      check(actor.role==='manager'||row.assignedStaffId===uid,'TASK_ACCESS_DENIED',403);check(row.revision===input.revision,'TASK_CHANGED');
      check(input.status==='Cancelled'?actor.role==='manager'&&['Scheduled','In Progress'].includes(row.status):input.status==='In Progress'?row.status==='Scheduled'&&row.startAt<=this.now():row.status==='In Progress','INVALID_TASK_TRANSITION');
      const path=`appointmentAvailability/${row.day}`,day=await tx.get(path),blocks={...day?.taskBlocks};
      const next={...row,status:input.status,progressNote:input.note.trim(),revision:row.revision+1,updatedBy:uid,updatedAt:this.now()};
      if(['Completed','Cancelled'].includes(input.status)){delete blocks[id];tx.set(path,{...day,taskBlocks:blocks,revision:(day?.revision??0)+1});}
      tx.set(`tasks/${id}`,next);notify(tx,[row.assignedStaffId,row.createdBy],`task:${id}:${next.revision}`,input.status==='Cancelled'?'TaskRemoved':'TaskProgress','Task',id,this.now(),uid);return {record:next};
    });
  }
  async notifications(uid,cursor){
    check(cursor===undefined||idOK(cursor),'INVALID_NOTIFICATION',400);
    await this.store.atomic(tx=>this.account(tx,uid));
    if(cursor===undefined)await syncPendingBusiness(this.store,uid);
    const result=await this.store.inboxPage(uid,cursor);
    // Recheck active access after the database read; never trust a cached role.
    await this.store.atomic(tx=>this.account(tx,uid));return {uid,...result};
  }
  async readNotification(uid,id){check(idOK(id),'INVALID_NOTIFICATION',400);return this.store.atomic(async tx=>{
    await this.account(tx,uid);const path=`inboxes/${uid}/items/${id}`,row=await tx.get(path);check(row,'NOTIFICATION_NOT_FOUND',404);
    if(row.readAt===null)tx.set(path,{...row,readAt:this.now()});return {read:true};
  });}
  async support(uid,id,input){
    check(keys(input,['requestId','action','subject','category','body','revision'])&&idOK(input.requestId)&&['Create','Reply','Close'].includes(input.action)&&text(input.body??'',0,2000),'INVALID_SUPPORT_MESSAGE',400);
    const creating=input.action==='Create',ticketId=creating?hash(`support:${uid}:${input.requestId}`):id;
    check(!creating||id===null,'INVALID_SUPPORT_MESSAGE',400);
    check(idOK(ticketId),'INVALID_SUPPORT_MESSAGE',400);
    if(creating)check(text(input.subject,3,120)&&['Appointments','Dresses & AR','Account','Other'].includes(input.category)&&text(input.body,1,2000),'INVALID_SUPPORT_MESSAGE',400);
    if(input.action==='Reply')check(text(input.body,1,2000),'INVALID_SUPPORT_MESSAGE',400);
    if(input.action==='Close')check(revision(input.revision),'INVALID_SUPPORT_MESSAGE',400);
    const event=hash(`support-event:${uid}:${input.requestId}`),fingerprint=hash(JSON.stringify({ticketId,...input}));
    return this.store.atomic(async tx=>{
      const account=await this.account(tx,uid),path=`supportTickets/${ticketId}`,ticket=await tx.get(path),op=await tx.get(`supportNotificationOperations/${event}`);
      check(creating?!account.staff:ticket&&(account.staff||ticket.uid===uid),'SUPPORT_ACCESS_DENIED',403);
      if(op){check(op.fingerprint===fingerprint,'REQUEST_CONFLICT');return {id:ticketId,saved:true};}
      check(creating?!ticket:ticket.status!=='Closed','SUPPORT_CHANGED');
      if(input.action==='Close')check(ticket.revision===input.revision,'SUPPORT_CHANGED');
      const roster=account.staff?[]:(await tx.staffRoster()).filter(activeEmployee).map(r=>r.id);
      const updated={...(ticket??{}),...(creating?{uid,name:account.row.name??'',subject:input.subject.trim(),category:input.category,createdAt:new Date(this.now())}:{}),status:input.action==='Close'?'Closed':account.staff?'In Progress':'Open',revision:(ticket?.revision??0)+1,updatedBy:uid,updatedAt:new Date(this.now())};
      if(input.action!=='Close'){
        updated.lastMessageId=event;tx.set(`${path}/messages/${event}`,{body:input.body.trim(),senderId:uid,senderName:account.row.name??'',senderRole:account.staff?'staff':'bride',sentAt:new Date(this.now())});
      }
      tx.set(path,updated);tx.set(`supportNotificationOperations/${event}`,{fingerprint,createdAt:this.now()});
      notify(tx,account.staff?[ticket.uid]:roster,event,input.action==='Close'?'SupportClosed':creating?'SupportNew':'SupportReply','Support',ticketId,this.now(),uid);
      return {id:ticketId,saved:true};
    });
  }
}
