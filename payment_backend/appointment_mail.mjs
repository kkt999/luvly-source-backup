import {readFileSync,existsSync} from 'node:fs';
import nodemailer from 'nodemailer';
import {makeupTrial} from './workforce.mjs';

export function appointmentMessage(row) {
  const date=new Date(row.startAt+8*3600000).toISOString().slice(0,16).replace('T',' ');
  if(row.event==='Rescheduled'){
    const previous=new Date(row.previousStartAt+8*3600000).toISOString().slice(0,16).replace('T',' ');
    const policy=row.type===makeupTrial?'There is no online payment to reschedule.':'Any verified fitting fee remains linked; no new payment is taken by this change. Your rental dates are unchanged.';
    return {subject:'Luvly · Appointment rescheduled',text:`Your Luvly ${row.type} appointment has been rescheduled.\n\nPrevious: ${previous} MYT (UTC+8)\nNew time: ${date} MYT (UTC+8)\nDuration: 60 minutes\n\nThis is the same appointment. ${policy} View the latest details in Bookings.\n\nLuvly Bridal Boutique`};
  }
  const confirmed=row.type===makeupTrial ? 'Please arrive 10 minutes early. Contact Luvly to confirm the service price before your visit. You can manage your appointment in Bookings.' : row.fittingFeeVerified ? 'Please arrive 10 minutes early. Your RM50 fitting fee has been verified. After attendance it may be credited once towards a package booking deposit. No gown stock is locked by this visit. View or cancel under Bookings.' : 'Please arrive 10 minutes early. View or cancel this visit under Bookings in Luvly. This confirms your visit only; no payment has been taken and no gown stock is locked.';
  return {subject:`Luvly · Appointment ${row.event.toLowerCase()}`,
    text:`Your Luvly ${row.type} appointment is ${row.event==='NoShow'?'recorded as not attended':row.event.toLowerCase()}.\n\nDate and time: ${date} MYT (UTC+8)\nDuration: 60 minutes\n\n${row.event==='Confirmed'?confirmed:row.event==='NoShow'?'We recorded that this visit was not attended. Contact Luvly if this is incorrect. Any paid fee is reviewed separately; no refund is automatic. You can book another available time.':row.event==='Cancelled'?'This visit has been cancelled. Any existing invoice or refund is reviewed separately. You can book another available time in Luvly.':'Thank you for visiting Luvly. View any invoices separately in Payments & receipts.'}\n\nLuvly Bridal Boutique`};
}
export class AppointmentMail {
  constructor({db,transport,from,now=Date.now}){Object.assign(this,{db,transport,from,now});}
  async send(id) {
    const ref=this.db.doc(`appointmentMail/${id}`);
    const row=await this.db.runTransaction(async tx=>{
      const r=(await tx.get(ref)).data();if(r?.state!=='Queued')return null;
      const b=(await tx.get(this.db.doc(`appointments/${r.appointmentId}`))).data();
      const status=r.event==='Rescheduled'?'Confirmed':r.event;
      const start=b?.startAt?.toMillis?.()??(b?.startAt==null?null:+b.startAt);
      if(!b || b.status!==status || r.bookingRevision!==undefined&&b.revision!==r.bookingRevision || start!==null&&start!==r.startAt){tx.update(ref,{state:'Superseded'});return null;}
      tx.update(ref,{state:'Sending',startedAt:this.now()});return r;
    });
    if(!row)return;
    // Sending is never automatically requeued: a timeout/crash might occur
    // after Gmail accepted the mail. Avoid duplicate automatic notifications.
    try{
      const result=await this.transport.sendMail({from:{name:'Luvly Bridal',address:this.from},to:row.to,
        messageId:`<${id}@luvly-44c77.firebaseapp.com>`,...appointmentMessage(row)});
      await ref.update({state:result.accepted?.length?'Sent':'ReviewRequired',sentAt:this.now()});
    }catch{await ref.update({state:'ReviewRequired'});}
  }
  start(){let busy=false;const tick=async()=>{if(busy)return;busy=true;try{
    const rows=await this.db.collection('appointmentMail').where('state','==','Queued').limit(10).get();
    for(const d of rows.docs)await this.send(d.id);
  }catch{/* No SMTP response or secrets logged. */}finally{busy=false;}};
  void tick();const timer=setInterval(tick,15000);timer.unref();return()=>clearInterval(timer);}
}
export function gmailMail(db,path) {
  if(!existsSync(path))return null;
  const config=JSON.parse(readFileSync(path,'utf8'));
  if(config.enabled!==true)return null;
  const pass=String(config.appPassword ?? '').replace(/\s/g,'');
  if(!/^[A-Za-z0-9._%+-]+@gmail\.com$/i.test(config.email ?? '') || !/^[a-zA-Z]{16}$/.test(pass))throw Error('MAIL_CONFIG_INVALID');
  return new AppointmentMail({db,from:config.email,transport:nodemailer.createTransport({
    host:'smtp.gmail.com',port:465,secure:true,auth:{user:config.email,pass},
    connectionTimeout:10000,greetingTimeout:10000,socketTimeout:20000,logger:false,debug:false,
  })});
}
