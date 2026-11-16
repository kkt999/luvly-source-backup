import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
import {malaysiaDay, fittingBeforeRental} from './booking_dates.mjs';
import {POLICY_VERSION, FITTING_FEE} from './bridal_payment_policy.mjs';
import {appointmentTypes,makeupTrial,offersService} from './workforce.mjs';
import {taskBusy} from './task_time.mjs';
import {activeEmployee as active,hasAppointmentStaffAccess} from './appointment_access.mjs';

const check=(ok,code,status=409)=>{if(!ok)throw new HttpError(status,code);};
const idOK=v=>typeof v==='string' && /^[A-Za-z0-9_-]{1,150}$/.test(v);
const hash=v=>createHash('sha256').update(v).digest('hex').slice(0,32);
const millis=v=>v?.toMillis?.() ?? +v;
export const bookingHours=[10,11,12,14,15,16];
export function employeeAvailable(entry,hour) {
  if(!entry)return true; // Normal business hours unless an exception exists.
  return entry.available ? hour>=entry.startHour && hour+1<=entry.endHour :
    !(hour<entry.endHour && hour+1>entry.startHour);
}
export function validateBookingTime(start,now) {
  check(Number.isSafeInteger(start) && start>now && start<now+180*86400000 &&
    start%3600000===0 && bookingHours.includes(new Date(start+8*3600000).getUTCHours()),'INVALID_BOOKING',400);
}
function validDay(day,now) {
  check(typeof day==='string' && /^\d{4}-\d{2}-\d{2}$/.test(day) &&
    Number.isFinite(Date.parse(day+'T00:00:00Z')) && new Date(day+'T00:00:00Z').toISOString().slice(0,10)===day && day>=malaysiaDay(now) &&
    day<=malaysiaDay(now+179*86400000),'INVALID_AVAILABILITY_DATE',400);
}

// One boutique visit per hour, matching the previous appointmentSlots contract.
// Active staff normally work the existing business-hour slots. Per-day windows
// override normal hours; unavailable exceptions block only their time range.
export class BookingService {
  constructor({store,now=Date.now,feePolicy=false,workforce}) {Object.assign(this,{store,now,feePolicy,workforce});}
  outcome(id,b) {return {appointmentId:id,status:b.status,invoiceId:b.fittingInvoiceId ?? null,expiresAt:b.paymentExpiresAt ?? null};}
  async fee(tx,id,booking,bride,{included=false,consent}={}) {
    if(!this.feePolicy)return {booking,commit:()=>{}};
    check(consent===POLICY_VERSION,'PAYMENT_TERMS_REQUIRED',400);
    if(booking.type!=='Dress Trial' || included)return {booking:{...booking,feePolicyVersion:POLICY_VERSION,feeIncluded:included},commit:()=>{}};
    const invoiceId=hash(`fitting:${id}`),expiresAt=Math.min(this.now()+15*60000,millis(booking.startAt));
    const next={...booking,status:'AwaitingPayment',feePolicyVersion:POLICY_VERSION,fittingInvoiceId:invoiceId,paymentExpiresAt:expiresAt};
    return {booking:next,commit:()=>tx.set(`sandboxInvoices/${invoiceId}`,{id:invoiceId,uid:booking.uid,customerName:bride.name,
      appointmentId:id,purpose:'FittingFee',title:'Gown fitting appointment · 60 minutes',amountCents:FITTING_FEE,
      state:'Quoted',environment:'sandbox',holdExpiresAt:expiresAt,createdAt:this.now(),policyVersion:POLICY_VERSION})};
  }
  async day(uid,day,type) {
    check(type===undefined||appointmentTypes.includes(type),'INVALID_BOOKING',400);
    validDay(day,this.now());
    const staff=await this.store.get(`staff/${uid}`),bride=await this.store.get(`brides/${uid}`);
    check(active(staff) || (!staff && bride),'ACCOUNT_ACCESS_REQUIRED',403);
    const record=await this.store.get(`appointmentAvailability/${day}`) ?? {entries:{},bookings:{},revision:0};
    const available=[];
    const strict=this.workforce&&(await this.store.get('schedulingSettings/policy'))?.requireServiceAssignments===true;
    const employees=await this.store.activeStaffIds();
    for(const hour of bookingHours) {
      const start=Date.parse(day+'T00:00:00Z')+(hour-8)*3600000;
      const occupied=await this.store.get(`appointmentSlots/${start}`);
      const pending=occupied ? await this.store.get(`appointments/${occupied.appointmentId}`) : null;
      const expired=pending && ['AwaitingPayment','Expired'].includes(pending.status) && pending.paymentExpiresAt<=this.now();
      if(start<=this.now() || (!expired && (record.bookings?.[hour] || occupied)))continue;
      for(const employee of employees) {
        const profile=this.workforce?await this.store.get(`staffScheduling/${employee}`):null;
        if(!taskBusy(record,employee,hour) && employeeAvailable(record.entries?.[employee],hour) && active(await this.store.get(`staff/${employee}`)) && (type?[type]:appointmentTypes).some(t=>offersService(profile,t,strict))) {
          available.push(hour);break;
        }
      }
    }
    return {day,hours:available,revision:record.revision, ...(active(staff)?{
      own:record.entries?.[uid] ?? null,
      assignedHours:Object.entries(record.bookings ?? {}).filter(([,b])=>b.staffId===uid).map(([h])=>+h),
    }:{})};
  }
  async calendar(uid,month,scope='default') {
    check(['default','own','all'].includes(scope),'INVALID_SCHEDULE_SCOPE',400);
    const now=this.now(),today=malaysiaDay(now),until=malaysiaDay(now+179*86400000);
    check(typeof month==='string' && /^\d{4}-\d{2}$/.test(month) &&
      Number.isFinite(Date.parse(month+'-01T00:00:00Z')) && new Date(month+'-01T00:00:00Z').toISOString().slice(0,7)===month &&
      month>=today.slice(0,7) && month<=until.slice(0,7),'INVALID_SCHEDULE_MONTH',400);
    check(active(await this.store.get(`staff/${uid}`)),'STAFF_REQUIRED',403);
    const first=new Date(month+'-01T00:00:00Z'),days=[];
    for(let d=new Date(first);d.toISOString().slice(0,7)===month;d.setUTCDate(d.getUTCDate()+1))days.push(d.toISOString().slice(0,10));
    const snapshot=await this.store.scheduleSnapshot(uid,days,scope);
    check(active(snapshot.actor),'STAFF_REQUIRED',403);
    check(!snapshot.limited,'SCHEDULE_LIMIT');
    check(scope!=='all'||snapshot.canViewAll===true,'SCHEDULE_ACCESS_DENIED',403);
    const appointments=snapshot.appointments.filter(b=>(snapshot.all||b.assignedStaffId===uid) &&
      Number.isFinite(millis(b.startAt)) && malaysiaDay(millis(b.startAt)).startsWith(month) &&
      ['Requested','AwaitingPayment','Confirmed','Completed','Cancelled','Declined','Expired','NoShow'].includes(b.status))
      .map(b=>({id:b.id,name:typeof b.name==='string'?b.name.slice(0,100):'',type:typeof b.type==='string'?b.type.slice(0,100):'',
        startAt:millis(b.startAt),...(snapshot.all?{assignedStaffName:typeof b.assignedStaffName==='string'?b.assignedStaffName.slice(0,100):''}:{}),...(Number.isInteger(b.revision)?{revision:b.revision}:{}),status:b.status==='AwaitingPayment' && b.paymentExpiresAt<=now?'Expired':b.status}));
    appointments.sort((a,b)=>a.startAt-b.startAt);
    return {month,today,editableUntil:until,limited:false,canViewAll:snapshot.canViewAll===true,scope:snapshot.all?'all':'own',days:days.map(day=>{
      const own=snapshot.days.find(d=>d.day===day)?.own ?? null;
      return {day,own:own?{available:own.available,startHour:own.startHour,endHour:own.endHour}:null,
        appointments:appointments.filter(b=>malaysiaDay(b.startAt)===day)};
    })};
  }
  async availability(uid,input) {
    check(!this.workforce,'TIME_OFF_REQUEST_REQUIRED',403);
    check(input && Object.keys(input).every(k=>['day','startHour','endHour','available','revision'].includes(k)),'INVALID_AVAILABILITY',400);
    validDay(input.day,this.now());
    const {startHour,endHour,available,revision}=input;
    check(Number.isInteger(startHour)&&Number.isInteger(endHour)&&startHour>=9&&endHour<=18&&endHour>startHour &&
      typeof available==='boolean' && Number.isInteger(revision)&&revision>=0,'INVALID_AVAILABILITY',400);
    return this.store.atomic(async tx=>{
      check(active(await tx.get(`staff/${uid}`)),'STAFF_REQUIRED',403);
      const path=`appointmentAvailability/${input.day}`;
      const record=await tx.get(path) ?? {entries:{},bookings:{},revision:0};
      check(record.revision===revision,'AVAILABILITY_CHANGED');
      check(Object.keys(record.entries).length<20 || record.entries[uid],'AVAILABILITY_LIMIT');
      check(!Object.entries(record.bookings ?? {}).some(([h,b])=>b.staffId===uid &&
        !employeeAvailable({available,startHour,endHour},+h)),'AVAILABILITY_HAS_BOOKINGS');
      const next={...record,day:input.day,entries:{...record.entries,[uid]:{startHour,endHour,available}},revision:revision+1,updatedAt:this.now()};
      tx.set(path,next);
      return {day:input.day,revision:next.revision};
    });
  }
  async prepare(tx,start,appointmentId,uid,type='Dress Trial',{preferredStaffId}={}) {
    validateBookingTime(start,this.now());
    const day=malaysiaDay(start),hour=new Date(start+8*3600000).getUTCHours();
    const path=`appointmentAvailability/${day}`,slot=`appointmentSlots/${start}`;
    const occupied=await tx.get(slot),record=await tx.get(path) ?? {entries:{},bookings:{},revision:0,day};
    const pending=occupied ? await tx.get(`appointments/${occupied.appointmentId}`) : null;
    const expired=pending && ['AwaitingPayment','Expired'].includes(pending.status) && pending.paymentExpiresAt<=this.now();
    check((!occupied && !record?.bookings?.[hour]) || (expired && (!record.bookings?.[hour] || record.bookings[hour].appointmentId===occupied.appointmentId)),'SLOT_UNAVAILABLE');
    let staffId;
    const strict=this.workforce&&(await tx.get('schedulingSettings/policy'))?.requireServiceAssignments===true;
    const employees=await this.store.activeStaffIds();
    if(employees.includes(preferredStaffId))employees.splice(0,employees.length,preferredStaffId,...employees.filter(id=>id!==preferredStaffId));
    for(const employee of employees) {
      const profile=this.workforce?await tx.get(`staffScheduling/${employee}`):null;
      if(!taskBusy(record,employee,hour) && employeeAvailable(record.entries?.[employee],hour) && active(await tx.get(`staff/${employee}`)) && offersService(profile,type,strict)) {
        staffId=employee;break;
      }
    }
    check(staffId,'NO_STAFF_AVAILABLE');
    return {staffId,day,hour,record,commit:({releaseHour}={})=>{
      if(expired && pending.status==='AwaitingPayment')tx.set(`appointments/${occupied.appointmentId}`,{...pending,status:'Expired',revision:pending.revision+1,updatedAt:new Date(this.now())});
      tx.set(slot,{appointmentId,uid,startAt:new Date(start)});
      const bookings={...record.bookings};
      if(releaseHour!==undefined&&bookings[releaseHour]?.appointmentId===appointmentId)delete bookings[releaseHour];
      bookings[hour]={appointmentId,staffId,uid};
      tx.set(path,{...record,bookings,revision:record.revision+1});
    }};
  }
  email(tx,id,booking,bride,event) {
    // A durable notification queue. No claim of delivery without a configured sender.
    if(typeof bride?.email==='string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(bride.email))
      tx.set(`appointmentMail/${id}-${booking.revision}`,{id:`${id}-${booking.revision}`,appointmentId:id,
        to:bride.email,event,type:booking.type,startAt:millis(booking.startAt),bookingRevision:booking.revision,
        ...(event==='Rescheduled'?{previousStartAt:booking.rescheduleHistory.at(-1).fromStartAt}:{}),
        fittingFeeVerified:!!booking.fittingInvoiceId && ['Confirmed','Rescheduled'].includes(event),state:'Queued',createdAt:this.now()});
  }
  async moveContext(tx,uid,id){
    check(idOK(id),'INVALID_BOOKING',400);
    const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),b=await tx.get(`appointments/${id}`);
    check(!staff&&bride&&b?.uid===uid,'BOOKING_ACCESS_DENIED',403);
    const now=this.now();
    let reason=b.status==='AwaitingPayment'?'RESCHEDULE_PAYMENT_REQUIRED':
      b.status!=='Confirmed'||b.actualAttendedAt||b.completedAt||millis(b.startAt)<=now?'RESCHEDULE_NOT_AVAILABLE':null;
    const oldStart=millis(b.startAt),oldDay=malaysiaDay(oldStart),oldHour=new Date(oldStart+8*3600000).getUTCHours();
    const record=await tx.get(`appointmentAvailability/${oldDay}`),slot=await tx.get(`appointmentSlots/${b.slotKey}`);
    if(!reason&&(b.slotKey!==String(oldStart)||slot?.appointmentId!==id||record?.bookings?.[oldHour]?.appointmentId!==id))reason='BOOKING_RESERVATION_CHANGED';
    const fee=b.fittingInvoiceId?await tx.get(`sandboxInvoices/${b.fittingInvoiceId}`):null;
    if(!reason&&b.fittingInvoiceId&&(!fee||fee.uid!==uid||fee.appointmentId!==id||fee.purpose!=='FittingFee'||fee.amountCents!==FITTING_FEE||fee.state!=='SandboxPaid'||fee.reviewReason||fee.reviewResolution||fee.paymentBlocked))reason='RESCHEDULE_PAYMENT_REVIEW';
    const link=await tx.get(`packageAppointments/${id}`);
    const selection=link?await tx.get(`packageSelections/${link.selectionId}`):null;
    const rental=selection?.rentalId?await tx.get(`rentals/${selection.rentalId}`):null;
    let latestDay=malaysiaDay(now+179*86400000);
    if(link){
      if(!selection||selection.uid!==uid||link.uid&&link.uid!==uid||!selection.appointmentIds?.includes(id))reason??='APPOINTMENT_PACKAGE_REVIEW_REQUIRED';
      if(b.feeIncluded===true&&(!rental||rental.uid!==uid||rental.state!=='Locked'||!['DepositPaid','Paid'].includes(rental.paymentState)||rental.collectedAt||rental.returnedAt))reason??='APPOINTMENT_PACKAGE_REVIEW_REQUIRED';
      if(selection?.selectedGowns?.length||selection?.selectedAccessories?.length){
        const plan=b.feeIncluded===true?rental:selection.rentalPlan;
        const date=value=>typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00:00Z'))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
        if(!date(plan?.pickupDate)||!date(plan?.eventDate))reason??='APPOINTMENT_PACKAGE_REVIEW_REQUIRED';
        else{
          const previous=day=>malaysiaDay(Date.parse(day+'T00:00:00Z')-86400000);
          const cutoff=[b.feeIncluded===true?plan.pickupDate:previous(plan.pickupDate),previous(plan.eventDate)].sort()[0];
          if(cutoff<latestDay)latestDay=cutoff;
        }
      }
    }else if(b.feeIncluded===true||(b.type!==makeupTrial&&/^Package:.*\nSelection:/s.test(b.notes??'')))reason??='APPOINTMENT_PACKAGE_REVIEW_REQUIRED';
    if(!reason&&latestDay<malaysiaDay(now))reason='FITTING_DATE_CONFLICT';
    return {b,bride,oldStart,oldDay,oldHour,record,fee,latestDay,reason};
  }
  async rescheduleContext(uid,id){
    return this.store.atomic(async tx=>{
      const c=await this.moveContext(tx,uid,id);
      return {appointmentId:id,type:c.b.type,startAt:c.oldStart,revision:c.b.revision,serverNow:this.now(),
        eligible:!c.reason,reason:c.reason,latestDay:c.latestDay,feePreserved:c.fee?.state==='SandboxPaid',
        history:(c.b.rescheduleHistory??[]).slice(-20).map(h=>({fromStartAt:h.fromStartAt,toStartAt:h.toStartAt,at:h.at}))};
    });
  }
  async reschedule(uid,id,input){
    check(idOK(id)&&input&&Object.keys(input).every(k=>['requestId','revision','startAt'].includes(k))&&idOK(input.requestId)&&Number.isSafeInteger(input.revision)&&input.revision>=1&&Number.isSafeInteger(input.startAt),'INVALID_RESCHEDULE',400);
    const path=`appointmentReschedules/${hash(`${uid}:${id}:${input.requestId}`)}`,fingerprint=JSON.stringify([input.revision,input.startAt]);
    return this.store.atomic(async tx=>{
      const actor=await tx.get(`brides/${uid}`),staff=await tx.get(`staff/${uid}`),b=await tx.get(`appointments/${id}`),prior=await tx.get(path);
      check(actor&&!staff&&b?.uid===uid,'BOOKING_ACCESS_DENIED',403);
      if(prior){check(prior.fingerprint===fingerprint,'REQUEST_CONFLICT');return {...this.outcome(id,b),revision:b.revision,startAt:millis(b.startAt)};}
      check(b.revision===input.revision,'BOOKING_CHANGED');
      const c=await this.moveContext(tx,uid,id);check(!c.reason,c.reason);
      validateBookingTime(input.startAt,this.now());
      check(input.startAt!==c.oldStart,'RESCHEDULE_SAME_TIME',400);
      check(malaysiaDay(input.startAt)<=c.latestDay,'FITTING_DATE_CONFLICT');
      const reservation=await this.prepare(tx,input.startAt,id,uid,b.type,{preferredStaffId:b.assignedStaffId});
      const change={fromStartAt:c.oldStart,toStartAt:input.startAt,fromStaffId:b.assignedStaffId??null,toStaffId:reservation.staffId,at:this.now(),by:uid,revision:b.revision+1};
      const next={...b,startAt:new Date(input.startAt),slotKey:String(input.startAt),assignedStaffId:reservation.staffId,revision:b.revision+1,
        updatedBy:uid,updatedAt:new Date(this.now()),rescheduleCount:(b.rescheduleCount??0)+1,rescheduleHistory:[...(b.rescheduleHistory??[]),change].slice(-20)};
      reservation.commit({releaseHour:c.oldDay===reservation.day?c.oldHour:undefined});
      tx.delete(`appointmentSlots/${b.slotKey}`);
      if(c.oldDay!==reservation.day){const bookings={...c.record.bookings};delete bookings[c.oldHour];tx.set(`appointmentAvailability/${c.oldDay}`,{...c.record,bookings,revision:c.record.revision+1});}
      tx.set(`appointments/${id}`,next);
      tx.set(path,{appointmentId:id,uid,fingerprint,...change});
      this.email(tx,id,next,c.bride,'Rescheduled');
      return {...this.outcome(id,next),revision:next.revision,startAt:input.startAt};
    });
  }
  async create(uid,input) {
    check(input && Object.keys(input).every(k=>['requestId','type','startAt','notes','dressId','feePolicyVersion'].includes(k)) &&
      idOK(input.requestId) && appointmentTypes.includes(input.type) &&
      typeof input.notes==='string' && input.notes.length<=1000 &&
      (input.dressId===undefined || input.dressId==='' || (input.type!==makeupTrial && idOK(input.dressId))),'INVALID_BOOKING',400);
    validateBookingTime(input.startAt,this.now());
    const id=hash(`${uid}:booking:${input.requestId}`),fingerprint=JSON.stringify(input);
    return this.store.atomic(async tx=>{
      const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),prior=await tx.get(`appointments/${id}`);
      check(!staff && bride,'BRIDE_REQUIRED',403);
      if(prior){check(prior.fingerprint===fingerprint,'REQUEST_CONFLICT');return this.outcome(id,prior);}
      check(bride.name?.trim() && bride.phone?.length>=9,'CUSTOMER_PROFILE_REQUIRED');
      const dress=input.dressId?await tx.get(`dresses/${input.dressId}`):null;
      if(input.dressId)check(dress?.published && dress.availability==='Available','DRESS_UNAVAILABLE');
      const reservation=await this.prepare(tx,input.startAt,id,uid,input.type);
      let booking={uid,name:bride.name,phone:bride.phone,type:input.type,startAt:new Date(input.startAt),slotKey:String(input.startAt),
        notes:input.notes.trim(),dressId:input.dressId ?? '',dressName:dress?.name ?? '',status:'Confirmed',response:'',revision:1,
        assignedStaffId:reservation.staffId,confirmation:'Automatic',updatedBy:uid,createdAt:new Date(this.now()),updatedAt:new Date(this.now()),fingerprint};
      const fee=await this.fee(tx,id,booking,bride,{consent:input.feePolicyVersion});booking=fee.booking;
      reservation.commit();fee.commit();tx.set(`appointments/${id}`,booking);
      if(booking.status==='Confirmed')this.email(tx,id,booking,bride,'Confirmed');
      return this.outcome(id,booking);
    });
  }
  async transition(uid,id,input) {
    check(idOK(id) && input && Object.keys(input).every(k=>['status','revision','response'].includes(k)) &&
      ['Cancelled','Completed','NoShow'].includes(input.status) && Number.isInteger(input.revision) &&
      typeof input.response==='string' && input.response.length<=500,'INVALID_BOOKING_TRANSITION',400);
    return this.store.atomic(async tx=>{
      const b=await tx.get(`appointments/${id}`),staff=await tx.get(`staff/${uid}`);
      const permitted = staff
        ? await hasAppointmentStaffAccess(tx, uid, staff, b)
        : b?.uid === uid;
      check(permitted,'BOOKING_ACCESS_DENIED',403);
      check(input.status==='Cancelled'||active(staff),'INVALID_BOOKING_TRANSITION');
      if(b.status===input.status)return {status:b.status};
      check(b.revision===input.revision,'BOOKING_CHANGED');
      check(input.status==='Cancelled' ? ['Requested','Confirmed','AwaitingPayment'].includes(b.status) :
        active(staff) && b.status==='Confirmed' && millis(b.startAt)+(input.status==='NoShow'?3600000:0)<=this.now(),'INVALID_BOOKING_TRANSITION');
      check(input.status!=='NoShow'||input.response.trim().length>=10,'NO_SHOW_REASON_REQUIRED',400);
      const start=millis(b.startAt),path=`appointmentAvailability/${malaysiaDay(start)}`,hour=new Date(start+8*3600000).getUTCHours();
      const record=await tx.get(path),slot=await tx.get(`appointmentSlots/${b.slotKey}`),bride=await tx.get(`brides/${b.uid}`);
      const fee=b.fittingInvoiceId ? await tx.get(`sandboxInvoices/${b.fittingInvoiceId}`) : null;
      const credit=await tx.get(`fittingCredits/${id}`);
      check(!(input.status==='Cancelled' && credit?.consumedBy),'PACKAGE_CANCELLATION_REVIEW_REQUIRED');
      const next={...b,status:input.status,revision:b.revision+1,response:active(staff)?input.response.trim():b.response,
        updatedBy:uid,updatedAt:new Date(this.now())};
      if(['Cancelled','NoShow'].includes(input.status) && fee?.state==='SandboxPaid')next.refundReviewRequired=true;
      if(input.status==='Completed')Object.assign(next,{actualAttendedAt:new Date(this.now()),completedAt:new Date(this.now())});
      if(['Cancelled','NoShow','Completed'].includes(input.status)) {
        if(slot?.appointmentId===id)tx.delete(`appointmentSlots/${b.slotKey}`);
        if(record?.bookings?.[hour]?.appointmentId===id) {
          const bookings={...record.bookings};delete bookings[hour];
          tx.set(path,{...record,bookings,revision:record.revision+1});
        }
      }
      tx.set(`appointments/${id}`,next);this.email(tx,id,next,bride,input.status);
      if(['Cancelled','NoShow'].includes(input.status) && fee?.state==='SandboxPaid')tx.set(`sandboxInvoices/${fee.id}`,{...fee,reviewReason:input.status==='NoShow'?'Appointment missed; paid fitting fee needs manager review':'Appointment cancelled; paid fitting fee needs staff refund review'});
      if(input.status==='Cancelled' && fee && fee.state!=='SandboxPaid')tx.set(`sandboxInvoices/${fee.id}`,{...fee,paymentBlocked:true});
      return {status:next.status};
    });
  }
  async settle(tx,invoice,result,b) {
    if(invoice.purpose!=='FittingFee' || result.state!=='SandboxPaid')return null;
    check(b?.fittingInvoiceId===invoice.id && b.uid===invoice.uid && invoice.amountCents===FITTING_FEE,'FITTING_PAYMENT_BINDING');
    const slot=await tx.get(`appointmentSlots/${b.slotKey}`),bride=await tx.get(`brides/${b.uid}`);
    const record=await tx.get(`appointmentAvailability/${malaysiaDay(millis(b.startAt))}`);
    const employee=await tx.get(`staff/${b.assignedStaffId}`);
    const hour=new Date(millis(b.startAt)+8*3600000).getUTCHours();
    if(b.status!=='AwaitingPayment' || b.paymentExpiresAt<=this.now() || slot?.appointmentId!==invoice.appointmentId || record?.bookings?.[hour]?.appointmentId!==invoice.appointmentId || !active(employee) || !employeeAvailable(record.entries?.[b.assignedStaffId],hour)) {
      tx.set(`appointments/${invoice.appointmentId}`,{...b,refundReviewRequired:true});
      return 'Fitting payment verified after cancellation or hold expiry; staff refund review required';
    }
    const next={...b,status:'Confirmed',revision:b.revision+1,updatedAt:new Date(this.now())};
    tx.set(`appointments/${invoice.appointmentId}`,next);
    tx.set(`fittingCredits/${invoice.appointmentId}`,{uid:b.uid,invoiceId:invoice.id,amountCents:FITTING_FEE,consumedBy:null,reservedBy:null});
    this.email(tx,invoice.appointmentId,next,bride,'Confirmed');return null;
  }
  async expirePayment(id) {
    return this.store.atomic(async tx=>{
      const b=await tx.get(`appointments/${id}`);
      if(b?.status!=='AwaitingPayment' || b.paymentExpiresAt>this.now())return;
      const path=`appointmentAvailability/${malaysiaDay(millis(b.startAt))}`,record=await tx.get(path),slot=await tx.get(`appointmentSlots/${b.slotKey}`);
      const hour=new Date(millis(b.startAt)+8*3600000).getUTCHours();
      if(slot?.appointmentId===id)tx.delete(`appointmentSlots/${b.slotKey}`);
      if(record?.bookings?.[hour]?.appointmentId===id){const bookings={...record.bookings};delete bookings[hour];tx.set(path,{...record,bookings,revision:record.revision+1});}
      tx.set(`appointments/${id}`,{...b,status:'Expired',revision:b.revision+1,updatedAt:new Date(this.now())});
    });
  }
  async recheck(id) {
    return this.store.atomic(async tx=>{
      const b=await tx.get(`appointments/${id}`);
      if(b?.status!=='Requested' || millis(b.startAt)<=this.now())return;
      const bride=await tx.get(`brides/${b.uid}`),link=await tx.get(`packageAppointments/${id}`);
      if(!bride)return;
      if(link) {
        const s=await tx.get(`packageSelections/${link.selectionId}`);
        check(s?.uid===b.uid,'SELECTION_ACCESS_DENIED');
        if(s.selectedGowns?.length || s.selectedAccessories?.length)check(s.rentalPlan && fittingBeforeRental(millis(b.startAt),s.rentalPlan),'FITTING_DATE_CONFLICT');
        for(const g of s.selectedGowns ?? []) {
          const d=await tx.get(`dresses/${g.dressId}`);
          check(d?.published===true && d.availability==='Available' && d.sizes.split(', ').includes(g.size),'PACKAGE_GOWN_UNAVAILABLE');
        }
      }else if(b.dressId){
        const d=await tx.get(`dresses/${b.dressId}`);check(d?.published===true && d.availability==='Available','DRESS_UNAVAILABLE');
      }
      const reservation=await this.prepare(tx,millis(b.startAt),id,b.uid,b.type);
      const next={...b,status:'Confirmed',revision:b.revision+1,assignedStaffId:reservation.staffId,confirmation:'Automatic',updatedAt:new Date(this.now())};
      reservation.commit();tx.set(`appointments/${id}`,next);this.email(tx,id,next,bride,'Confirmed');
    });
  }
  start() {
    let busy=false;
    const tick=async()=>{if(busy)return;busy=true;try{
      if(this.store.pendingFittingIds)for(const id of await this.store.pendingFittingIds())await this.expirePayment(id);
      for(const id of await this.store.pendingBookingIds())try{await this.recheck(id);}catch{/* Invalid/unavailable legacy requests remain unchanged. */}
    }catch{/* Retry while backend is online. */}finally{busy=false;}};
    void tick();const timer=setInterval(tick,30000);timer.unref();return()=>clearInterval(timer);
  }
}
