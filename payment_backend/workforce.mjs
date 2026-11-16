import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
import {malaysiaDay} from './booking_dates.mjs';
import {taskBusy,taskQualified} from './task_time.mjs';
import {activeEmployee,canViewAllAppointments} from './appointment_access.mjs';
export {activeEmployee} from './appointment_access.mjs';

const check=(ok,code,status=409)=>{if(!ok)throw new HttpError(status,code);};
export const jobRoles=['FrontDesk','Consultant','FittingSpecialist','MakeupArtist'];
export const makeupTrial='Makeup Trial';
export const appointmentTypes=['Dress Trial','Bridal Consultation',makeupTrial];
export const schedulingServices=['Dress Trial','Bridal Consultation','Bridal Makeup'];
export function staffResponsibilities(input) {
  const {jobRole, jobTitle, serviceTypes} = input;
  if (!Array.isArray(serviceTypes) || serviceTypes.length > schedulingServices.length ||
      new Set(serviceTypes).size !== serviceTypes.length ||
      !serviceTypes.every(type => schedulingServices.includes(type))) return null;
  if (jobRoles.includes(jobRole) && jobTitle === undefined) return {jobRole, serviceTypes};
  if (jobRole !== 'Other' || typeof jobTitle !== 'string') return null;
  const title = jobTitle.trim();
  if (title.length > 80 || !/\p{L}/u.test(title) || /[\u0000-\u001f\u007f-\u009f]/.test(title)) return null;
  return {jobRole, jobTitle: title, serviceTypes};
}
const hours=[10,11,12,14,15,16];
export const availableAt=(e,h)=>!e || (e.available?h>=e.startHour&&h+1<=e.endHour:!(h<e.endHour&&h+1>e.startHour));
export const offersService=(p,type,strict=false)=>type===makeupTrial
  ? p?.serviceTypes?.includes('Bridal Makeup')===true
  : (!p&&!strict) || p?.serviceTypes?.includes(type)===true;
const millis=v=>v?.toMillis?.()??+v;
const fields=(v,keys)=>v && !Array.isArray(v) && typeof v==='object' && Object.keys(v).every(k=>keys.includes(k));
const idOK=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
const publicRequest=r=>Object.fromEntries(['id','uid','staffName','day','startHour','endHour','reason','state','revision','createdAt','reviewedAt','reviewNote'].filter(k=>r[k]!==undefined).map(k=>[k,r[k]]));
export class WorkforceService {
  constructor({store,now=Date.now}){Object.assign(this,{store,now});}
  async actor(tx,uid,manager=false){const a=await tx.get(`staff/${uid}`);check(activeEmployee(a)&&(!manager||a.role==='manager'),manager?'MANAGER_REQUIRED':'STAFF_REQUIRED',403);return a;}
  validDay(day){const d=typeof day==='string'&&/^\d{4}-\d\d-\d\d$/.test(day)?new Date(day+'T00:00:00Z'):null;
    check(d&&Number.isFinite(+d)&&d.toISOString().slice(0,10)===day&&day>=malaysiaDay(this.now())&&day<=malaysiaDay(this.now()+179*86400000),'INVALID_AVAILABILITY_DATE',400);}
  async roster(tx){const rows=await tx.staffRoster();check(rows.length<=100,'SCHEDULE_LIMIT');
    const result=[];for(const r of rows)if(activeEmployee(r))result.push({...r,profile:await tx.get(`staffScheduling/${r.id}`)});return result;}
  async context(uid){return this.store.atomic(async tx=>{const actor=await this.actor(tx,uid),profile=await tx.get(`staffScheduling/${uid}`),manager=actor.role==='manager';
    const policy=await tx.get('schedulingSettings/policy')??{revision:0,minimumOnDuty:1,minimumByRole:{},minimumByService:{},requireServiceAssignments:false};
    const requests=await tx.timeOffRequests(manager?undefined:uid);check(requests.length<=500,'SCHEDULE_LIMIT');
    const staff=manager?(await this.roster(tx)).map(r=>({uid:r.id,name:r.name??'',profile:r.profile??null})):[];
    const exceptions=manager?(await tx.schedulingDays()).filter(d=>d.day>=malaysiaDay(this.now())).flatMap(d=>Object.entries(d.entries??{}).filter(([,e])=>!e.timeOffId).map(([staffUid,e])=>({staffUid,staffName:staff.find(s=>s.uid===staffUid)?.name??staffUid,day:d.day,revision:d.revision,startHour:e.startHour,endHour:e.endHour,available:e.available}))):[];
    return {uid,manager,profile:profile??null,canViewAll:canViewAllAppointments(actor,profile),policy,staff,exceptions,
      requests:requests.sort((a,b)=>b.createdAt-a.createdAt).map(publicRequest)};});}
  async saveProfile(uid,input){
    const responsibilities = input && staffResponsibilities(input);
    check(fields(input,['uid','jobRole','jobTitle','serviceTypes','revision'])&&idOK(input.uid)&&responsibilities&&Number.isInteger(input.revision)&&input.revision>=0,'INVALID_STAFF_SCHEDULING',400);
    return this.store.atomic(async tx=>{await this.actor(tx,uid,true);check(activeEmployee(await tx.get(`staff/${input.uid}`)),'STAFF_REQUIRED');
      const old=await tx.get(`staffScheduling/${input.uid}`),policy=await tx.get('schedulingSettings/policy')??{revision:0,minimumOnDuty:1};
      if(tx.workspaceTasks)check(!(await tx.workspaceTasks(input.uid)).some(t=>['Scheduled','In Progress'].includes(t.status)&&!taskQualified(input,t.type)),'STAFF_HAS_WORK');
      check((old?.revision??0)===input.revision,'SCHEDULING_CHANGED');const roster=await this.roster(tx),days=await tx.schedulingDays(),visits=await tx.staffAppointments(input.uid);
      check(!visits.some(b=>['Confirmed','AwaitingPayment','Requested'].includes(b.status)&&millis(b.startAt)>this.now()&&!offersService(input,b.type,true)),'STAFF_HAS_SERVICE_BOOKINGS');
      const next={...responsibilities,revision:input.revision+1,updatedBy:uid,updatedAt:this.now()};
      const updated=roster.map(r=>r.id===input.uid?{...r,profile:next}:r);this.coverage(updated,{},policy);
      for(const d of days)if(d.day>=malaysiaDay(this.now()))this.coverage(updated,d.entries??{},policy);
      tx.set(`staffScheduling/${input.uid}`,next);tx.set('schedulingSettings/policy',{...policy,revision:policy.revision+1});return {profile:next};});}
  coverage(roster,entries,policy,affected=hours){for(const h of affected){
    const on=roster.filter(r=>availableAt(entries[r.id],h));
    check(on.length>=(policy.minimumOnDuty??1),'MINIMUM_STAFF_COVERAGE');
    for(const [role,n]of Object.entries(policy.minimumByRole??{}))check(on.filter(r=>r.profile?.jobRole===role).length>=n,'MINIMUM_ROLE_COVERAGE');
    for(const [type,n]of Object.entries(policy.minimumByService??{}))check(on.filter(r=>r.profile?.serviceTypes?.includes(type)).length>=n,'MINIMUM_SERVICE_COVERAGE');
  }}
  async savePolicy(uid,input){check(fields(input,['revision','minimumOnDuty','minimumByRole','minimumByService','requireServiceAssignments'])&&typeof input.requireServiceAssignments==='boolean'&&Number.isInteger(input.revision)&&input.revision>=0&&Number.isInteger(input.minimumOnDuty)&&input.minimumOnDuty>=1&&input.minimumOnDuty<=100&&fields(input.minimumByRole,jobRoles)&&fields(input.minimumByService,schedulingServices)&&[...Object.values(input.minimumByRole),...Object.values(input.minimumByService)].every(n=>Number.isInteger(n)&&n>=0&&n<=100),'INVALID_COVERAGE_POLICY',400);
    return this.store.atomic(async tx=>{await this.actor(tx,uid,true);const old=await tx.get('schedulingSettings/policy');check((old?.revision??0)===input.revision,'SCHEDULING_CHANGED');
      const roster=await this.roster(tx),days=await tx.schedulingDays();
      check(!input.requireServiceAssignments||roster.every(r=>r.profile),'STAFF_PROFILES_REQUIRED');this.coverage(roster,{},input);
      for(const d of days)if(d.day>=malaysiaDay(this.now()))this.coverage(roster,d.entries??{},input);
      const next={...input,revision:input.revision+1,updatedBy:uid,updatedAt:this.now()};tx.set('schedulingSettings/policy',next);return {policy:next};});}
  async request(uid,input){check(fields(input,['requestId','day','startHour','endHour','reason'])&&idOK(input.requestId)&&Number.isInteger(input.startHour)&&Number.isInteger(input.endHour)&&input.startHour>=9&&input.endHour<=18&&input.startHour<input.endHour&&typeof input.reason==='string'&&input.reason.trim().length>=5&&input.reason.length<=500,'INVALID_TIME_OFF',400);this.validDay(input.day);
    const id=createHash('sha256').update(`${uid}:${input.requestId}`).digest('hex').slice(0,32),fingerprint=JSON.stringify(input);
    return this.store.atomic(async tx=>{const actor=await this.actor(tx,uid),prior=await tx.get(`staffTimeOff/${id}`);if(prior){check(prior.fingerprint===fingerprint,'REQUEST_CONFLICT');return {request:publicRequest(prior)};}
      const record=await tx.get(`appointmentAvailability/${input.day}`)??{entries:{},bookings:{},revision:0},visits=await tx.staffAppointments(uid),roster=await this.roster(tx),policy=await tx.get('schedulingSettings/policy')??{minimumOnDuty:1};
      this.checkAbsence(uid,input,record,visits,roster,policy);
      const row={id,uid,staffName:actor.name??'',day:input.day,startHour:input.startHour,endHour:input.endHour,reason:input.reason.trim(),state:'Pending',revision:1,createdAt:this.now(),fingerprint};
      tx.set(`staffTimeOff/${id}`,row);return {request:publicRequest(row)};});}
  checkAbsence(uid,input,record,visits,roster,policy){
    const entry={available:false,startHour:input.startHour,endHour:input.endHour};
    const prior=record.entries?.[uid];
    check(!hours.some(h=>!availableAt(entry,h)&&taskBusy(record,uid,h)),'AVAILABILITY_HAS_TASKS');
    check(!prior||(prior.available===true&&prior.startHour<=10&&prior.endHour>=17),'TIME_OFF_DAY_HAS_EXCEPTION');
    check(!Object.entries(record.bookings??{}).some(([h,b])=>b.staffId===uid&&!availableAt(entry,+h)),'AVAILABILITY_HAS_BOOKINGS');
    check(!visits.some(b=>['Confirmed','AwaitingPayment','Requested'].includes(b.status)&&malaysiaDay(millis(b.startAt))===input.day&&!availableAt(entry,new Date(millis(b.startAt)+8*3600000).getUTCHours())&&!(b.status==='AwaitingPayment'&&b.paymentExpiresAt<=this.now())),'AVAILABILITY_HAS_BOOKINGS');
    this.coverage(roster,{...record.entries,[uid]:entry},policy,hours.filter(h=>!availableAt(entry,h)));
  }
  async review(uid,id,input){check(idOK(id)&&fields(input,['action','revision','note'])&&['Approve','Reject','Withdraw','CancelApproved'].includes(input.action)&&Number.isInteger(input.revision)&&typeof input.note==='string'&&input.note.length<=500,'INVALID_TIME_OFF_REVIEW',400);
    return this.store.atomic(async tx=>{const actor=await this.actor(tx,uid),r=await tx.get(`staffTimeOff/${id}`);check(r,'TIME_OFF_NOT_FOUND',404);check(r.revision===input.revision,'SCHEDULING_CHANGED');
      if(input.action==='Withdraw'){check(r.uid===uid&&r.state==='Pending','TIME_OFF_ACCESS_DENIED',403);const row={...r,state:'Withdrawn',revision:r.revision+1};tx.set(`staffTimeOff/${id}`,row);return {request:publicRequest(row)};}
      check(actor.role==='manager','MANAGER_REQUIRED',403);if(input.action!=='Reject')this.validDay(r.day);
      const record=await tx.get(`appointmentAvailability/${r.day}`)??{entries:{},bookings:{},revision:0};
      let nextRecord;
      if(input.action==='Approve'){check(r.state==='Pending','TIME_OFF_STATE');check(activeEmployee(await tx.get(`staff/${r.uid}`)),'STAFF_REQUIRED');
        const visits=await tx.staffAppointments(r.uid),roster=await this.roster(tx),policy=await tx.get('schedulingSettings/policy')??{minimumOnDuty:1};this.checkAbsence(r.uid,r,record,visits,roster,policy);
        nextRecord={...record,day:r.day,entries:{...record.entries,[r.uid]:{available:false,startHour:r.startHour,endHour:r.endHour,timeOffId:id}},revision:record.revision+1};
      }else if(input.action==='CancelApproved'){check(r.state==='Approved'&&record.entries?.[r.uid]?.timeOffId===id,'TIME_OFF_STATE');const entries={...record.entries};delete entries[r.uid];nextRecord={...record,entries,revision:record.revision+1};
      }else check(input.action==='Reject'&&r.state==='Pending','TIME_OFF_STATE');
      const state={Approve:'Approved',Reject:'Rejected',CancelApproved:'Cancelled'}[input.action],row={...r,state,revision:r.revision+1,reviewedBy:uid,reviewedAt:this.now(),reviewNote:input.note.trim()};
      if(nextRecord)tx.set(`appointmentAvailability/${r.day}`,{...nextRecord,updatedAt:this.now()});tx.set(`staffTimeOff/${id}`,row);return {request:publicRequest(row)};});}
  async restore(uid,input){check(fields(input,['staffUid','day','revision'])&&idOK(input.staffUid)&&Number.isInteger(input.revision),'INVALID_TIME_OFF',400);this.validDay(input.day);
    return this.store.atomic(async tx=>{await this.actor(tx,uid,true);const path=`appointmentAvailability/${input.day}`,record=await tx.get(path);check(record&&record.revision===input.revision,'SCHEDULING_CHANGED');const entry=record.entries?.[input.staffUid];check(entry&&!entry.timeOffId,'TIME_OFF_STATE');
      const entries={...record.entries};delete entries[input.staffUid];tx.set(path,{...record,entries,revision:record.revision+1,updatedBy:uid,updatedAt:this.now()});return {restored:true};});}
  async reassign(uid,id,input){check(idOK(id)&&fields(input,['staffUid','revision'])&&idOK(input.staffUid)&&Number.isInteger(input.revision),'INVALID_STAFF_SCHEDULING',400);
    return this.store.atomic(async tx=>{await this.actor(tx,uid,true);const b=await tx.get(`appointments/${id}`);check(b,'BOOKING_ACCESS_DENIED',404);
      check(b.revision===input.revision,'BOOKING_CHANGED');check(['Confirmed','AwaitingPayment'].includes(b.status)&&millis(b.startAt)>this.now()&&!(b.status==='AwaitingPayment'&&b.paymentExpiresAt<=this.now()),'INVALID_BOOKING_TRANSITION');
      const staff=await tx.get(`staff/${input.staffUid}`),profile=await tx.get(`staffScheduling/${input.staffUid}`),policy=await tx.get('schedulingSettings/policy');
      check(activeEmployee(staff)&&offersService(profile,b.type,policy?.requireServiceAssignments===true),'STAFF_SERVICE_REQUIRED');
      const day=malaysiaDay(millis(b.startAt)),hour=new Date(millis(b.startAt)+8*3600000).getUTCHours(),path=`appointmentAvailability/${day}`,record=await tx.get(path),slot=await tx.get(`appointmentSlots/${b.slotKey}`),visits=await tx.staffAppointments(input.staffUid);
      check(record?.bookings?.[hour]?.appointmentId===id&&slot?.appointmentId===id,'BOOKING_CHANGED');
      check(!taskBusy(record,input.staffUid,hour)&&availableAt(record.entries?.[input.staffUid],hour)&&!visits.some(v=>v.id!==id&&['Confirmed','AwaitingPayment'].includes(v.status)&&millis(v.startAt)<millis(b.startAt)+3600000&&millis(v.startAt)+3600000>millis(b.startAt)&&!(v.status==='AwaitingPayment'&&v.paymentExpiresAt<=this.now())),'STAFF_NOT_AVAILABLE');
      if(b.assignedStaffId===input.staffUid)return {assigned:true};
      tx.set(`appointments/${id}`,{...b,assignedStaffId:input.staffUid,revision:b.revision+1,updatedBy:uid,updatedAt:new Date(this.now()),assignmentHistory:[...(b.assignmentHistory??[]),{from:b.assignedStaffId,to:input.staffUid,by:uid,at:this.now()}].slice(-50)});
      tx.set(path,{...record,bookings:{...record.bookings,[hour]:{...record.bookings[hour],staffId:input.staffUid}},revision:record.revision+1});return {assigned:true};});}
}
