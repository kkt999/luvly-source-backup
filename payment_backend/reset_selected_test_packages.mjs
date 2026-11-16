// One-off, locally authorised sandbox cleanup. No public HTTP route.
// Default is read-only. --apply requires a verified local backup and exact
// document version preconditions; newly created selections are never targets.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore,Timestamp,GeoPoint,DocumentReference} from 'firebase-admin/firestore';
import {GoogleCalendarGateway,tokenVault} from './calendar_service.mjs';
import {analyticsMillis} from './analytics.mjs';

export const authorisedSelections=Object.freeze([
  'bbb28e8873b8be108d280ab732eeba75','4c1ba5a7867446a57fc2b5fb833d1e68',
  '7c8dcfea84405d97fa8f6b006db03646','4d5383119c53cd592ac00c9b650c6132',
  '487bbc5355b5ee569c751c11bc047008','cbb2bec7837025543687cba9f7f01da0',
  'dff31261fac85695de8f3fafeaa06be3','f52bb4870aaa91802c964893fc088bf2',
  '80853e9b8ed5cdc853a7fced4d9fc14c','83657688ca3b6981b39dcfde40e30d05',
  '3e24af5aa1719882c7a64885081f2bba',
]);
export function typedBackup(v){
  if(v===null)return {t:'null'};
  if(v instanceof Timestamp)return {t:'timestamp',seconds:v.seconds,nanoseconds:v.nanoseconds};
  if(v instanceof GeoPoint)return {t:'geopoint',latitude:v.latitude,longitude:v.longitude};
  if(v instanceof DocumentReference)return {t:'reference',path:v.path};
  if(Buffer.isBuffer(v))return {t:'bytes',v:v.toString('base64')};
  if(v instanceof Date)return {t:'date',v:v.toISOString()};
  if(Array.isArray(v))return {t:'array',v:v.map(typedBackup)};
  if(typeof v==='object')return {t:'map',v:Object.fromEntries(Object.entries(v).map(([k,x])=>[k,typedBackup(x)]))};
  if(['string','boolean','number'].includes(typeof v))return {t:typeof v,v};
  throw Error('Unsupported backup value');
}
export function remainingBookings(record,ids){
  return Object.fromEntries(Object.entries(record.bookings??{}).filter(([,b])=>!ids.has(b.appointmentId)));
}
const hash=v=>createHash('sha256').update(v).digest('hex');
const requireSafe=(ok)=>{if(!ok)throw Error('Cleanup safety check failed');};
const root=dirname(fileURLToPath(import.meta.url));
let stage='configuration';

async function run(){
  const apply=process.argv[2]==='--apply';
  requireSafe(process.argv.length===2||apply&&process.argv.length===3);
  loadEnvFile(resolve(root,'.env'));
  requireSafe(process.env.FIREBASE_PROJECT_ID==='luvly-44c77'&&process.env.TOYYIBPAY_ENV==='sandbox');
  const credential=JSON.parse(readFileSync(resolve(root,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
  requireSafe(credential.project_id==='luvly-44c77');
  const app=initializeApp({credential:cert(credential),projectId:credential.project_id},'authorised-test-package-reset');
  try{
    stage='account';
    const db=getFirestore(app),owners=await db.collection('brides').where('name','==','kkt').limit(2).get();
    requireSafe(owners.size===1);
    const uid=owners.docs[0].id,selectionIds=new Set(authorisedSelections);
    requireSafe(!(await db.doc(`staff/${uid}`).get()).exists);
    const own={};
    for(const collection of ['packageSelections','appointments','sandboxInvoices','rentals','packageAppointments','fittingCredits']){
      const rows=await db.collection(collection).where('uid','==',uid).limit(201).get();
      requireSafe(rows.size<=200);own[collection]=rows.docs;
    }
    stage='selection-boundary';
    const selected=own.packageSelections.filter(d=>selectionIds.has(d.id));
    requireSafe(selected.length===authorisedSelections.length);
    // Do not touch newly created packages, foreign owners or any physical rental.
    requireSafe(selected.every(d=>d.data().uid===uid&&!d.data().rentalId));
    requireSafe(!own.rentals.some(d=>selectionIds.has(d.data().packageSelectionId)));
    stage='appointment-boundary';
    const links=own.packageAppointments.filter(d=>selectionIds.has(d.data().selectionId));
    const appointmentIds=new Set([...selected.flatMap(d=>d.data().appointmentIds??[]),...links.map(d=>d.id)]);
    const appointments=own.appointments.filter(d=>appointmentIds.has(d.id));
    requireSafe(appointments.length===appointmentIds.size);
    requireSafe(!own.packageSelections.some(d=>!selectionIds.has(d.id)&&(d.data().appointmentIds??[]).some(id=>appointmentIds.has(id))));
    const explicitInvoices=new Set(selected.flatMap(d=>[d.data().invoiceId,d.data().balanceInvoiceId,d.data().securityInvoiceId]).filter(Boolean));
    for(const d of appointments)if(d.data().fittingInvoiceId)explicitInvoices.add(d.data().fittingInvoiceId);
    stage='invoice-boundary';
    const invoices=own.sandboxInvoices.filter(d=>selectionIds.has(d.data().packageSelectionId)||appointmentIds.has(d.data().appointmentId)||explicitInvoices.has(d.id));
    requireSafe(invoices.every(d=>d.data().environment==='sandbox'&&(!d.data().packageSelectionId||selectionIds.has(d.data().packageSelectionId))));
    requireSafe([...explicitInvoices].every(id=>invoices.some(d=>d.id===id)));
    stage='credit-boundary';
    const credits=own.fittingCredits.filter(d=>appointmentIds.has(d.id));
    requireSafe(credits.every(d=>!d.data().consumedBy&&!d.data().reservedBy));
    // Query all reverse links, not just the package's stored references.
    stage='reverse-links';
    for(const collection of ['rentals','sandboxInvoices','packageAppointments']){
      const field=collection==='packageAppointments'?'selectionId':'packageSelectionId';
      const rows=await db.collection(collection).where(field,'in',authorisedSelections).get();
      requireSafe(rows.docs.every(d=>d.data().uid===uid));
      if(collection==='rentals')requireSafe(rows.empty);
      if(collection==='sandboxInvoices')requireSafe(rows.docs.every(d=>invoices.some(i=>i.id===d.id)));
      if(collection==='packageAppointments')requireSafe(rows.docs.every(d=>links.some(i=>i.id===d.id)));
    }
    const appointmentKeys=[...appointmentIds];
    for(const collection of ['sandboxInvoices','fittingCredits']){
      const rows=await db.collection(collection).where('appointmentId','in',appointmentKeys).get();
      requireSafe(rows.docs.every(d=>d.data().uid===uid));
      requireSafe(rows.docs.every(d=>(collection==='sandboxInvoices'?invoices:credits).some(i=>i.id===d.id)));
    }
    const remove=new Map([...selected,...appointments,...links,...invoices,...credits].map(d=>[d.ref.path,d]));
    const shared=new Map();
    stage='schedule-slots';
    for(const d of appointments){
      const a=d.data(),start=analyticsMillis(a.startAt);requireSafe(start!==null);
      const day=new Date(start+8*3600000).toISOString().slice(0,10);
      const availability=await db.doc(`appointmentAvailability/${day}`).get();
      if(availability.exists){
        const old=availability.data(),bookings=remainingBookings(old,appointmentIds);
        if(Object.keys(bookings).length!==Object.keys(old.bookings??{}).length){
          requireSafe(Object.values(old.bookings??{}).filter(b=>appointmentIds.has(b.appointmentId)).every(b=>b.uid===undefined||b.uid===uid));
          shared.set(availability.ref.path,{snapshot:availability,patch:{bookings,revision:(old.revision??0)+1}});
        }
      }
      for(const slotKey of new Set([a.slotKey,String(start)].filter(Boolean))){
        requireSafe(/^\d+$/.test(slotKey));
        const slot=await db.doc(`appointmentSlots/${slotKey}`).get();
        if(slot.exists&&appointmentIds.has(slot.data().appointmentId)){
          requireSafe(slot.data().uid===undefined||slot.data().uid===uid);remove.set(slot.ref.path,slot);
        }
      }
    }
    const allSlots=await db.collection('appointmentSlots').where('uid','==',uid).limit(201).get();
    requireSafe(allSlots.size<=200);
    for(const d of allSlots.docs)if(appointmentIds.has(d.data().appointmentId))remove.set(d.ref.path,d);
    stage='mail-queue';
    for(const id of appointmentIds){
      const mail=await db.collection('appointmentMail').where('appointmentId','==',id).limit(101).get();
      requireSafe(mail.size<=100&&!mail.docs.some(d=>d.data().state==='Sending'));
      for(const d of mail.docs)remove.set(d.ref.path,d);
    }
    stage='calendar-records';
    const connection=await db.doc(`calendarConnections/${uid}`).get();
    const eventIds=appointmentKeys.map(id=>hash(`${uid}:${id}`));
    for(const id of eventIds){
      const event=await connection.ref.collection('events').doc(id).get();
      if(event.exists)remove.set(event.ref.path,event);
    }
    const summary={readOnly:!apply,selectedPackages:selected.length,appointments:appointments.length,
      sandboxInvoices:invoices.length,fittingCredits:credits.length,
      deleteByCollection:[...remove.values()].reduce((out,d)=>(out[d.ref.parent.id]=(out[d.ref.parent.id]??0)+1,out),{}),
      sharedScheduleDaysUpdated:shared.size,calendarEventsToCheck:connection.data()?.calendarId?eventIds.length:0,
      preserved:{newerOrOtherSelections:own.packageSelections.length-selected.length,
        unrelatedAppointments:own.appointments.length-appointments.length,unrelatedInvoices:own.sandboxInvoices.length-invoices.length},
    };
    if(!apply){console.log(JSON.stringify(summary,null,2));return;}
    requireSafe(remove.size+shared.size<400);
    // Capture every full Firestore field/type and version before any mutation.
    stage='verified-backup';
    const backup={schema:1,project:'luvly-44c77',environment:'sandbox',createdAt:new Date().toISOString(),uid,
      authorisedSelectionIds:authorisedSelections,summary,
      documents:[...remove.values(),...[...shared.values()].map(s=>s.snapshot)].map(d=>({path:d.ref.path,
        updateTime:{seconds:d.updateTime.seconds,nanoseconds:d.updateTime.nanoseconds},data:typedBackup(d.data())})),
      remoteCalendarEvents:[],
    };
    const backupDir=resolve(root,'secrets','cleanup-backups');mkdirSync(backupDir,{recursive:true});
    const backupPath=resolve(backupDir,`package-reset-${Date.now()}.json`);
    const saveBackup=()=>{
      const content=JSON.stringify(backup,null,2);writeFileSync(backupPath,content,{encoding:'utf8',flag:backup.remoteCalendarEvents.length?'w':'wx'});
      requireSafe(hash(readFileSync(backupPath,'utf8'))===hash(content));
    };
    saveBackup();
    // Cancel only deterministic, privately marked Luvly events; never a whole
    // calendar, unrelated visit, Google connection, token, or Google account.
    stage='owned-calendar-events';
    let calendarDeleted=0;
    const c=connection.data();
    if(c?.calendarId){
      requireSafe(c.connected===true&&typeof c.token==='string');
      const user=await getAuth(app).getUser(uid);
      requireSafe(!user.disabled&&user.providerData.find(p=>p.providerId==='google.com')?.uid===c.subject);
      const config=JSON.parse(readFileSync(resolve(root,'secrets/calendar-config.json'),'utf8'));
      const credential=JSON.parse(readFileSync(resolve(root,'secrets/google-calendar-oauth.json'),'utf8')).web;
      const gateway=new GoogleCalendarGateway({credential,redirectUri:config.redirectUri});
      const refresh=tokenVault(readFileSync(resolve(root,'secrets/calendar-token.key'))).open(uid,c.token);
      for(const id of eventIds){
        const path=`/calendars/${encodeURIComponent(c.calendarId)}/events/${id}`;
        let remote;
        try{remote=await gateway.request(refresh,path);}catch(e){if(![404,410].includes(e.response?.status))throw e;}
        if(!remote||remote.status==='cancelled')continue;
        requireSafe(remote.extendedProperties?.private?.luvlyAppointment===id);
        backup.remoteCalendarEvents.push({calendarId:c.calendarId,event:remote});saveBackup();
        try{await gateway.request(refresh,path,'DELETE');calendarDeleted++;}catch(e){if(![404,410].includes(e.response?.status))throw e;}
      }
    }
    // A single atomic commit, guarded by every original document version.
    stage='atomic-delete';
    const batch=db.batch();
    for(const d of remove.values())batch.delete(d.ref,{lastUpdateTime:d.updateTime});
    for(const {snapshot,patch} of shared.values())batch.update(snapshot.ref,patch,{lastUpdateTime:snapshot.updateTime});
    await batch.commit();
    stage='post-delete-verification';
    const remaining=await db.getAll(...[...remove.values()].map(d=>d.ref));
    requireSafe(remaining.every(d=>!d.exists));
    const after={};
    for(const name of ['packageSelections','appointments','sandboxInvoices'])after[name]=(await db.collection(name).where('uid','==',uid).get()).size;
    console.log(JSON.stringify({...summary,deleted:true,backupVerified:true,backupPath,
      calendarEventsDeleted:calendarDeleted,remainingOwnCounts:after},null,2));
  }finally{await deleteApp(app);}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  run().catch(()=>{console.error(`Cleanup stopped at ${stage}. Inspect the local backup and database before retrying; no credentials were printed.`);process.exitCode=1;});
}
