// Local-only, exact-scope cleanup requested by the owner. No public API route.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {typedBackup,remainingBookings} from './reset_selected_test_packages.mjs';
import {GoogleCalendarGateway,tokenVault} from './calendar_service.mjs';

const root=dirname(fileURLToPath(import.meta.url));
const keep=['F7368480','464546B5'];
const targets=['BA7BF815','F75537E7','A9A72CDF','6033AF5F','D432F60B','63965743','76FFF7CA','0395C11C','6833933E','B1F11218'];
const short=id=>id.slice(-8).toUpperCase();
const hash=x=>createHash('sha256').update(x).digest('hex');
const safe=(v,label)=>{if(!v)throw Error(`Cleanup stopped: ${label}`);};
const backupDir=resolve(root,'secrets/cleanup-backups');
const version=d=>[d.updateTime.seconds,d.updateTime.nanoseconds].join(':');

async function main(){
  loadEnvFile(resolve(root,'.env'));
  safe(process.env.TOYYIBPAY_ENV==='sandbox'&&process.env.FIREBASE_PROJECT_ID==='luvly-44c77','sandbox boundary');
  const credential=JSON.parse(readFileSync(resolve(root,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
  safe(credential.project_id==='luvly-44c77','project boundary');
  const app=initializeApp({credential:cert(credential),projectId:credential.project_id});
  try{
    const db=getFirestore(app),owner=await db.collection('brides').where('email','==','khaither99@gmail.com').limit(2).get();
    safe(owner.size===1,'unique owner');const uid=owner.docs[0].id;
    safe(!(await db.doc(`staff/${uid}`).get()).exists,'customer boundary');
    if(process.argv[2]==='--apply-local'){
      const backupPath=resolve(process.argv[3]??'');
      safe(backupPath.toLowerCase().startsWith((backupDir+sep).toLowerCase()),'backup location');
      const plan=JSON.parse(readFileSync(backupPath,'utf8'));
      safe(plan.uid===uid&&plan.project==='luvly-44c77'&&plan.environment==='sandbox','backup owner');
      safe(JSON.stringify(plan.targets)===JSON.stringify(targets)&&JSON.stringify(plan.keep)===JSON.stringify(keep),'exact user scope');
      const selected=plan.remove.filter(d=>d.path.startsWith('packageSelections/'));
      safe(selected.length===10&&selected.every(d=>targets.includes(short(d.path.split('/')[1]))),'exact ten selections');
      const remove=plan.remove.filter(d=>!d.path.startsWith('calendarConnections/'));
      const retainedCalendar=plan.remove.filter(d=>d.path.startsWith('calendarConnections/'));
      safe(remove.length+plan.shared.length<400,'atomic write limit');
      await db.runTransaction(async tx=>{
        const entries=[...remove,...plan.shared];
        const current=await tx.getAll(...entries.map(d=>db.doc(d.path)));
        for(let i=0;i<entries.length;i++)safe(current[i].exists&&version(current[i])===entries[i].version&&
          hash(JSON.stringify(typedBackup(current[i].data())))===entries[i].hash,'document changed; prepare again');
        for(const d of remove)tx.delete(db.doc(d.path));
        for(const d of plan.shared)tx.update(db.doc(d.path),d.patch);
      });
      const remaining=await db.getAll(...remove.map(d=>db.doc(d.path)));
      safe(remaining.every(d=>!d.exists),'post-delete verification');
      const protectedRecords=[...plan.preserved,...retainedCalendar];
      const preserved=await db.getAll(...protectedRecords.map(d=>db.doc(d.path)));
      safe(preserved.every((d,i)=>d.exists&&hash(JSON.stringify(typedBackup(d.data())))===protectedRecords[i].hash),'preserved records verification');
      // Calendar deletion was not authorized: neither remote events nor local mappings are changed.
      const calendarDeleted=0,calendarPending=plan.remoteEvents.length;
      const ownAfter=await db.collection('packageSelections').where('uid','==',uid).get();
      const result={deletedSelections:10,remainingReferences:ownAfter.docs.map(d=>short(d.id)),
        appliedScope:'local-business-records-only',deletedDocuments:remove.length,sharedRecordsUpdated:plan.shared.length,calendarDeleted,calendarPending,backupPath};
      writeFileSync(backupPath+'.result.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));return;
    }
    safe(process.argv.length===2,'use no arguments to prepare, --apply-local <backup> to execute');
    const own={};
    for(const collection of ['packageSelections','appointments','sandboxInvoices','rentals','packageAppointments','fittingCredits','rentalExtensions']){
      const s=await db.collection(collection).where('uid','==',uid).limit(501).get();safe(s.size<=500,'bounded account query');own[collection]=s.docs;
    }
    const selected=own.packageSelections.filter(d=>targets.includes(short(d.id))),preservedSelections=own.packageSelections.filter(d=>keep.includes(short(d.id)));
    safe(selected.length===10&&preservedSelections.length===2,'target and preserve counts');
    const selectionIds=new Set(selected.map(d=>d.id));
    const links=own.packageAppointments.filter(d=>selectionIds.has(d.data().selectionId));
    const visitIds=new Set([...selected.flatMap(d=>d.data().appointmentIds??[]),...links.map(d=>d.id)]);
    safe(!own.packageSelections.some(d=>!selectionIds.has(d.id)&&(d.data().appointmentIds??[]).some(id=>visitIds.has(id))),'shared appointment');
    const rentals=own.rentals.filter(d=>selectionIds.has(d.data().packageSelectionId));
    safe(rentals.every(d=>!d.data().collectedAt&&!d.data().returnedAt),'no collected physical rental');
    const rentalIds=new Set(rentals.map(d=>d.id));
    const appointments=own.appointments.filter(d=>visitIds.has(d.id));safe(appointments.length===visitIds.size,'complete appointments');
    const explicitInvoices=new Set([...selected.flatMap(d=>[d.data().invoiceId,d.data().balanceInvoiceId,d.data().securityInvoiceId]),...appointments.map(d=>d.data().fittingInvoiceId)].filter(Boolean));
    const invoices=own.sandboxInvoices.filter(d=>selectionIds.has(d.data().packageSelectionId)||visitIds.has(d.data().appointmentId)||rentalIds.has(d.data().rentalId)||explicitInvoices.has(d.id));
    safe(invoices.every(d=>d.data().environment==='sandbox'&&(!d.data().packageSelectionId||selectionIds.has(d.data().packageSelectionId))&&(!d.data().rentalId||rentalIds.has(d.data().rentalId))),'sandbox invoice ownership');
    safe([...explicitInvoices].every(id=>invoices.some(d=>d.id===id)),'complete invoices');
    const credits=own.fittingCredits.filter(d=>visitIds.has(d.id)||rentalIds.has(d.data().consumedBy)||rentalIds.has(d.data().reservedBy));
    safe(credits.every(d=>(!d.data().consumedBy||rentalIds.has(d.data().consumedBy))&&(!d.data().reservedBy||rentalIds.has(d.data().reservedBy))),'shared fitting credit');
    const extensions=own.rentalExtensions.filter(d=>rentalIds.has(d.data().rentalId));
    const holdKeys=new Set(extensions.flatMap(d=>(d.data().holds??[]).map(h=>h.key)));
    const remove=new Map([...selected,...links,...appointments,...rentals,...invoices,...credits,...extensions].map(d=>[d.ref.path,d]));
    const shared=new Map();
    // Verify reverse links as well as owner-scoped forward references.
    for(const [collection,field,ids] of [['rentals','packageSelectionId',selectionIds],['sandboxInvoices','packageSelectionId',selectionIds],['packageAppointments','selectionId',selectionIds],['sandboxInvoices','appointmentId',visitIds]]){
      if(!ids.size)continue;const rows=await db.collection(collection).where(field,'in',[...ids]).get();
      safe(rows.docs.every(d=>d.data().uid===uid&&remove.has(d.ref.path)),'foreign or omitted reverse reference');
    }
    // Related audit entries are account-scoped by their exact parent references.
    for(const [collection,field,ids] of [['fittingQuoteAudit','selectionId',selectionIds],['fittingQuoteResponses','selectionId',selectionIds],['rentalServiceProgressAudit','selectionId',selectionIds],['rentalDateChanges','rentalId',rentalIds]]){
      if(!ids.size)continue;const rows=await db.collection(collection).where(field,'in',[...ids]).get();
      for(const d of rows.docs){safe(!d.data().uid||d.data().uid===uid,'audit ownership');remove.set(d.ref.path,d);}
    }
    for(const id of selectionIds){const d=await db.doc(`rentalServiceProgress/${id}`).get();if(d.exists)remove.set(d.ref.path,d);}
    for(const collection of ['rentalVariants','accessoryStock','appointmentAvailability','appointmentSlots']){
      const rows=await db.collection(collection).limit(501).get();safe(rows.size<=500,'bounded shared records');
      for(const d of rows.docs){const r=d.data();
        if(collection==='appointmentSlots'){if(visitIds.has(r.appointmentId)){safe(!r.uid||r.uid===uid,'slot owner');remove.set(d.ref.path,d);}continue;}
        if(collection==='appointmentAvailability'){
          const bookings=remainingBookings(r,visitIds);
          if(Object.keys(bookings).length!==Object.keys(r.bookings??{}).length)shared.set(d.ref.path,{snapshot:d,patch:{bookings,revision:(r.revision??0)+1}});
        }else{
          safe(!Object.keys(r.outstanding??{}).some(id=>rentalIds.has(id)),'outstanding physical items');
          const allocations=Object.fromEntries(Object.entries(r.allocations??{}).filter(([id])=>!rentalIds.has(id)&&!holdKeys.has(id)));
          if(Object.keys(allocations).length!==Object.keys(r.allocations??{}).length)shared.set(d.ref.path,{snapshot:d,patch:{allocations}});
        }
      }
    }
    for(const id of visitIds){const rows=await db.collection('appointmentMail').where('appointmentId','==',id).get();
      safe(!rows.docs.some(d=>d.data().state==='Sending'),'mail currently sending');for(const d of rows.docs)remove.set(d.ref.path,d);}
    const staff=await db.collection('staff').limit(501).get();safe(staff.size<=500,'bounded staff inboxes');
    const sources=[...selectionIds,...visitIds,...invoices.map(d=>d.id)];
    for(const account of new Set([uid,...staff.docs.map(d=>d.id)]))for(let n=0;n<sources.length;n+=30){
      const rows=await db.collection(`inboxes/${account}/items`).where('sourceId','in',sources.slice(n,n+30)).get();
      for(const d of rows.docs){const r=d.data();if(r.sourceType==='Package'&&selectionIds.has(r.sourceId)||r.sourceType==='Appointment'&&visitIds.has(r.sourceId)||r.sourceType==='Payment'&&invoices.some(i=>i.id===r.sourceId))remove.set(d.ref.path,d);}
    }
    const remoteEvents=[];let calendarPreparation='not connected';
    const connection=await db.doc(`calendarConnections/${uid}`).get(),c=connection.data();
    for(const id of visitIds){const d=await connection.ref.collection('events').doc(hash(`${uid}:${id}`)).get();if(d.exists)remove.set(d.ref.path,d);}
    if(c?.connected&&c.calendarId){
      try{
        const user=await getAuth(app).getUser(uid);safe(!user.disabled&&user.providerData.some(p=>p.providerId==='google.com'&&p.uid===c.subject),'calendar identity');
        const config=JSON.parse(readFileSync(resolve(root,'secrets/calendar-config.json'),'utf8'));
        const oauth=JSON.parse(readFileSync(resolve(root,'secrets/google-calendar-oauth.json'),'utf8')).web;
        const gateway=new GoogleCalendarGateway({credential:oauth,redirectUri:config.redirectUri});
        const token=tokenVault(readFileSync(resolve(root,'secrets/calendar-token.key'))).open(uid,c.token);
        for(const id of visitIds){const marker=hash(`${uid}:${id}`);let event;
          try{event=await gateway.request(token,`/calendars/${encodeURIComponent(c.calendarId)}/events/${marker}`);}catch(error){if(![404,410].includes(error.response?.status))throw error;}
          if(event&&event.status!=='cancelled'){safe(event.extendedProperties?.private?.luvlyAppointment===marker,'private calendar marker');remoteEvents.push({calendarId:c.calendarId,event});}
        }calendarPreparation='owned events backed up';
      }catch{calendarPreparation='remote calendar needs separate review';}
    }
    const preserved=[...own.packageSelections,...own.rentals,...own.sandboxInvoices,...own.appointments,...own.fittingCredits].filter(d=>!remove.has(d.ref.path));
    const encode=d=>({path:d.ref.path,version:version(d),hash:hash(JSON.stringify(typedBackup(d.data()))),data:typedBackup(d.data())});
    const summary={targets:targets.length,preserve:keep,byCollection:[...remove.values()].reduce((out,d)=>(out[d.ref.parent.id]=(out[d.ref.parent.id]??0)+1,out),{}),sharedRecords:shared.size,remoteCalendarEvents:remoteEvents.length,calendarPreparation};
    const plan={project:'luvly-44c77',environment:'sandbox',uid,targets,keep,createdAt:new Date().toISOString(),summary,
      remove:[...remove.values()].map(encode),shared:[...shared.values()].map(({snapshot,patch})=>({...encode(snapshot),patch})),preserved:preserved.map(encode),remoteEvents};
    safe(plan.remove.length+plan.shared.length<400,'atomic write limit');
    mkdirSync(backupDir,{recursive:true});const backupPath=resolve(backupDir,`demo-cleanup-20261030-${Date.now()}.json`),content=JSON.stringify(plan,null,2);
    writeFileSync(backupPath,content,{flag:'wx'});safe(hash(readFileSync(backupPath,'utf8'))===hash(content),'verified backup');
    console.log(JSON.stringify({...summary,backupVerified:true,backupPath},null,2));
  }finally{await deleteApp(app);}
}
main().catch(e=>{console.error(e.message?.startsWith('Cleanup stopped:')?e.message:'Cleanup failed; inspect local backup and database before retrying. No credentials logged.');process.exitCode=1;});
