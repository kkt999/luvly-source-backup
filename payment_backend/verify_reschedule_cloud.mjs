// Isolated administrator QA. No real customer visit, fee or rental is changed.
// The QA account has no email/contact destination, so no external email is sent.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {randomBytes} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {stableBackendOrigin} from './backend_origin.mjs';
import {malaysiaDay} from './booking_dates.mjs';
if(process.argv[2]!=='--run-isolated-qa')throw Error('Explicit isolated QA mode required');
loadEnvFile(new URL('.env',import.meta.url));
if(process.env.FIREBASE_PROJECT_ID!=='luvly-44c77'||process.env.TOYYIBPAY_ENV!=='sandbox')throw Error('Sandbox project required');
const key=JSON.parse(readFileSync(new URL(process.env.GOOGLE_APPLICATION_CREDENTIALS,import.meta.url)));
assert.equal(key.project_id,'luvly-44c77');
const app=initializeApp({credential:cert(key),projectId:'luvly-44c77'}),db=getFirestore(app),auth=getAuth(app);
const uid='qa_reschedule_'+randomBytes(10).toString('hex');
let id,token,userCreated=false;const assigned=new Set(),touchedDays=new Set(),newDays=new Set(),checks=[];
const options=readFileSync(new URL('../lib/firebase_options.dart',import.meta.url),'utf8');
const apiKey=/FirebaseOptions web = FirebaseOptions\(\s*apiKey: '([^']+)'/.exec(options)[1];
async function api(path,body){const r=await fetch(stableBackendOrigin+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(30000)});
  const j=await r.json();if(!r.ok)throw Error('QA API failed '+r.status+' '+j.error);return j;}
async function remember(day){touchedDays.add(day);if(!(await db.doc('appointmentAvailability/'+day).get()).exists)newDays.add(day);}
try{
  await auth.createUser({uid,displayName:'Isolated rescheduling QA'});userCreated=true;
  await db.doc('brides/'+uid).set({uid,role:'bride',name:'Isolated rescheduling QA',phone:'0100000000'});
  const custom=await auth.createCustomToken(uid),r=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key='+apiKey,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:custom,returnSecureToken:true})});
  const login=await r.json();assert(r.ok&&login.idToken);token=login.idToken;
  const day=malaysiaDay(Date.now()+28*86400000);await remember(day);
  const availability=await api('/v1/appointment-availability?day='+day+'&type=Bridal%20Consultation');assert(availability.hours.length>=2,'Two qualified free slots required');
  const start=Date.parse(day+'T00:00:00Z')+(availability.hours[0]-8)*3600000,next=Date.parse(day+'T00:00:00Z')+(availability.hours[1]-8)*3600000;
  const b=await api('/v1/appointments',{requestId:'qa-create',type:'Bridal Consultation',startAt:start,notes:'Isolated rescheduling verification; not a customer appointment.',feePolicyVersion:1});id=b.appointmentId;
  assert.equal(b.status,'Confirmed');checks.push('Created isolated free consultation');
  let row=(await db.doc('appointments/'+id).get()).data();assigned.add(row.assignedStaffId);
  const context=await api('/v1/appointments/'+id+'/reschedule');assert(context.eligible);assert.equal(context.startAt,start);
  const input={requestId:'qa-same-day',revision:context.revision,startAt:next};
  const result=await api('/v1/appointments/'+id+'/reschedule',input);assert.equal(result.appointmentId,id);assert.equal(result.status,'Confirmed');assert.equal(result.startAt,next);checks.push('Moved same appointment within the day');
  assert(!(await db.doc('appointmentSlots/'+start).get()).exists);assert.equal((await db.doc('appointmentSlots/'+next).get()).data().appointmentId,id);
  const dayRow=(await db.doc('appointmentAvailability/'+day).get()).data();assert(!dayRow.bookings[availability.hours[0]]);assert.equal(dayRow.bookings[availability.hours[1]].appointmentId,id);checks.push('Old slot released; new reservation persisted');
  const retry=await api('/v1/appointments/'+id+'/reschedule',input);assert.equal(retry.revision,result.revision);checks.push('Uncertain retry was idempotent');
  const tomorrow=malaysiaDay(start+86400000);await remember(tomorrow);
  const otherSlots=await api('/v1/appointment-availability?day='+tomorrow+'&type=Bridal%20Consultation');assert(otherSlots.hours.length);
  const nextDay=Date.parse(tomorrow+'T00:00:00Z')+(otherSlots.hours[0]-8)*3600000;
  const moved=await api('/v1/appointments/'+id+'/reschedule',{requestId:'qa-cross-day',revision:result.revision,startAt:nextDay});
  assert.equal(moved.startAt,nextDay);row=(await db.doc('appointments/'+id).get()).data();assigned.add(row.assignedStaffId);
  assert.equal(row.rescheduleCount,2);assert.equal(row.rescheduleHistory.length,2);assert.equal(row.fittingInvoiceId,undefined);checks.push('Cross-day move preserved history with no invoice');
  const inbox=await db.collection(`inboxes/${uid}/items`).where('sourceId','==',id).get();assert(inbox.docs.some(d=>d.data().kind==='AppointmentChanged'));checks.push('Customer update notification persisted');
  await api('/v1/appointments/'+id+'/transition',{status:'Cancelled',revision:moved.revision,response:''});checks.push('QA reservation released for cleanup');
  console.log(JSON.stringify({isolatedQa:true,checks,allPassed:true}));
}catch(e){console.error('Isolated reschedule check failed:',String(e.message).replaceAll(uid,'[QA account]'));process.exitCode=1;}
finally{
  try{
    assert(uid.startsWith('qa_reschedule_'));
    if(id){
      // Cancel on failure if possible, before deleting the private QA source.
      const ref=db.doc('appointments/'+id),row=(await ref.get()).data();
      if(row&&row.uid!==uid)throw Error('Unexpected appointment owner; left untouched');
      if(row?.uid===uid){
        assigned.add(row.assignedStaffId);
        for(const change of row.rescheduleHistory??[])for(const staffId of [change.fromStaffId,change.toStaffId])if(staffId)assigned.add(staffId);
        await db.runTransaction(async tx=>{const r=(await tx.get(ref)).data();if(r?.uid!==uid)return;
          const slot=db.doc('appointmentSlots/'+r.slotKey),s=(await tx.get(slot)).data();
          const day=malaysiaDay(r.startAt),dayRef=db.doc('appointmentAvailability/'+day),d=(await tx.get(dayRef)).data(),hour=new Date((r.startAt.toMillis?.()??+r.startAt)+8*3600000).getUTCHours();
          if(s?.appointmentId===id&&s.uid===uid)tx.delete(slot);
          if(d?.bookings?.[hour]?.appointmentId===id){const bookings={...d.bookings};delete bookings[hour];tx.set(dayRef,{...d,bookings,revision:d.revision+1});}
          tx.delete(ref);
        });
      }
      for(const collection of ['appointmentReschedules','appointmentMail']){
        const docs=await db.collection(collection).where('appointmentId','==',id).get();
        for(const d of docs.docs)if(collection==='appointmentMail'||d.data().uid===uid)await d.ref.delete();
      }
      for(const owner of new Set([uid,...assigned].filter(Boolean))){const docs=await db.collection(`inboxes/${owner}/items`).where('sourceId','==',id).get();for(const d of docs.docs)if(d.data().sourceType==='Appointment')await d.ref.delete();}
    }
    for(const day of newDays)await db.runTransaction(async tx=>{const ref=db.doc('appointmentAvailability/'+day),d=(await tx.get(ref)).data();if(d&&Object.keys(d.entries??{}).length===0&&Object.keys(d.bookings??{}).length===0&&Object.keys(d.taskBlocks??{}).length===0)tx.delete(ref);});
    await db.doc('brides/'+uid).delete();
    if(userCreated)await auth.deleteUser(uid);
    console.log('Isolated QA account, visit, audit and notifications cleaned up.');
  }catch{console.error('QA cleanup needs administrator review; no real customer visit was targeted.');process.exitCode=1;}
  await deleteApp(app);
}
