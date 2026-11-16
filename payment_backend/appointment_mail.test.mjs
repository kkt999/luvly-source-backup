import test from 'node:test';
import assert from 'node:assert/strict';
import {AppointmentMail,appointmentMessage} from './appointment_mail.mjs';
const input={appointmentId:'booking',event:'Confirmed',type:'Dress Trial',startAt:Date.parse('2026-10-15T02:00:00Z'),to:'demo@example.com',state:'Queued'};
function fixture(transport){
 const rows=new Map([['appointmentMail/booking-1',{...input}],['appointments/booking',{status:'Confirmed'}]]);
 const doc=path=>({path,get:async()=>({data:()=>structuredClone(rows.get(path))}),update:async d=>rows.set(path,{...rows.get(path),...d})});
 const db={doc,runTransaction:async fn=>fn({get:ref=>ref.get(),update:(ref,d)=>ref.update(d)})};
 return {rows,service:new AppointmentMail({db,transport,from:'sender@gmail.com',now:()=>1000})};
}
test('confirmation mail clearly separates appointment, payment and stock and uses MYT',()=>{
 const m=appointmentMessage(input);assert.match(m.text,/2026-10-15 10:00 MYT/);assert.match(m.text,/no gown stock is locked/);assert.match(m.text,/60 minutes/);
 assert.match(appointmentMessage({...input,event:'Cancelled'}).text,/Any existing invoice or refund/);
 assert.doesNotMatch(appointmentMessage({...input,fittingFeeVerified:true}).text,/sandbox|university|test transaction|Reference: booking/i);
});
test('queued mail sends once, with stable Message-ID; sent means accepted not guaranteed delivery',async()=>{
 const sent=[];const f=fixture({sendMail:async m=>{sent.push(m);return {accepted:[input.to]};}});
 await f.service.send('booking-1');await f.service.send('booking-1');assert.equal(sent.length,1);assert.equal(f.rows.get('appointmentMail/booking-1').state,'Sent');
 assert.equal(sent[0].to,input.to);assert.match(sent[0].messageId,/booking-1/);
});
test('superseded and ambiguous sending are not automatically duplicated',async()=>{
 let calls=0;const f=fixture({sendMail:async()=>{calls++;throw Error('private SMTP error');}});
 await f.service.send('booking-1');await f.service.send('booking-1');assert.equal(calls,1);assert.equal(f.rows.get('appointmentMail/booking-1').state,'ReviewRequired');
 f.rows.set('appointmentMail/booking-1',{...input});f.rows.set('appointments/booking',{status:'Cancelled'});
 await f.service.send('booking-1');assert.equal(calls,1);assert.equal(f.rows.get('appointmentMail/booking-1').state,'Superseded');
});
test('reschedule email gives old/new MYT time without charging again; stale confirmations are superseded',async()=>{
 const sent=[],f=fixture({sendMail:async m=>{sent.push(m);return {accepted:[input.to]};}});
 f.rows.set('appointments/booking',{status:'Confirmed',revision:3,startAt:new Date(input.startAt+3600000)});
 await f.service.send('booking-1');assert.equal(sent.length,0);assert.equal(f.rows.get('appointmentMail/booking-1').state,'Superseded');
 f.rows.set('appointmentMail/booking-3',{...input,event:'Rescheduled',bookingRevision:3,startAt:input.startAt+3600000,previousStartAt:input.startAt});
 await f.service.send('booking-3');await f.service.send('booking-3');assert.equal(sent.length,1);
 assert.match(sent[0].text,/Previous: 2026-10-15 10:00 MYT/);assert.match(sent[0].text,/New time: 2026-10-15 11:00 MYT/);assert.match(sent[0].text,/no new payment/);
});
