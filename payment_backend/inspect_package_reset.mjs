// Read-only target audit before a user-requested cleanup. No contacts or keys
// are printed. This command cannot delete or mutate any document.
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {analyticsMillis} from './analytics.mjs';
const dir=dirname(fileURLToPath(import.meta.url));
let app;
try{
  loadEnvFile(resolve(dir,'.env'));
  if(process.env.FIREBASE_PROJECT_ID!=='luvly-44c77'||process.env.TOYYIBPAY_ENV!=='sandbox')throw Error();
  const credential=JSON.parse(readFileSync(resolve(dir,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
  if(credential.project_id!=='luvly-44c77')throw Error();
  app=initializeApp({credential:cert(credential),projectId:credential.project_id},'readonly-package-reset-audit');
  const db=getFirestore(app),name=process.argv[2];
  if(name!=='kkt')throw Error();
  const owners=await db.collection('brides').where('name','==',name).limit(2).get();
  if(owners.size!==1)throw Error();
  const uid=owners.docs[0].id;
  const result=await db.runTransaction(async tx=>{
    const names=['packageSelections','appointments','sandboxInvoices','rentals','packageAppointments'];
    const reads=await Promise.all(names.map(c=>tx.get(db.collection(c).where('uid','==',uid).limit(201))));
    if(reads.some(s=>s.size>200))throw Error();
    const data=Object.fromEntries(names.map((c,i)=>[c,reads[i].docs.map(d=>({...d.data(),id:d.id}))]));
    const time=v=>{const ms=analyticsMillis(v);return ms===null?null:new Date(ms+8*3600000).toISOString().replace('T',' ').slice(0,16)+' MYT';};
    const selections=data.packageSelections.map(s=>{
      const appointmentIds=new Set([...(s.appointmentIds??[]),...data.packageAppointments.filter(a=>a.selectionId===s.id).map(a=>a.id)]);
      const appointments=data.appointments.filter(a=>appointmentIds.has(a.id));
      const invoices=data.sandboxInvoices.filter(i=>i.packageSelectionId===s.id||[s.invoiceId,s.balanceInvoiceId,s.securityInvoiceId].includes(i.id)||appointmentIds.has(i.appointmentId));
      const rentals=data.rentals.filter(r=>r.packageSelectionId===s.id||r.id===s.rentalId);
      return {id:s.id,name:s.name,eventDate:s.rentalPlan?.eventDate??null,createdAt:time(s.createdAt),
        linkedAppointments:appointments.map(a=>({status:a.status,startAt:time(a.startAt)})),
        linkedInvoices:invoices.map(i=>({state:i.state,purpose:i.purpose,amountCents:i.amountCents})),
        linkedRentals:rentals.map(r=>({state:r.state,collected:!!r.collectedAt,returned:!!r.returnedAt})),
        missingAppointmentReferences:[...appointmentIds].filter(id=>!data.appointments.some(a=>a.id===id)).length,
        linked:Boolean(appointmentIds.size||invoices.length||rentals.length||s.invoiceId||s.rentalId),
      };
    }).sort((a,b)=>String(a.createdAt).localeCompare(String(b.createdAt)));
    return {readOnly:true,uniqueAccountMatched:true,accountName:name,totalSelections:selections.length,
      linkedSelections:selections.filter(s=>s.linked).length,unlinkedSelections:selections.filter(s=>!s.linked).length,
      totalOwnAppointments:data.appointments.length,totalOwnInvoices:data.sandboxInvoices.length,totalOwnRentals:data.rentals.length,selections};
  },{readOnly:true});
  console.log(JSON.stringify(result,null,2));
}catch{console.error('Audit could not uniquely verify the requested targets. No data changed; no credentials printed.');process.exitCode=1;}
finally{if(app)await deleteApp(app);}
