// Read-only deployment probe. Never prints customer identifiers, content,
// credentials, invoice references or payment links. Not a signed-in UI test.
import {readFileSync,existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadEnvFile} from 'node:process';
import {FirestoreStore} from './firestore_store.mjs';
import {customerPlanning} from './customer_planning.mjs';
const directory=dirname(fileURLToPath(import.meta.url));
try{
  if(existsSync(resolve(directory,'.env')))loadEnvFile(resolve(directory,'.env'));
  if(process.env.FIREBASE_PROJECT_ID!=='luvly-44c77'||process.env.TOYYIBPAY_ENV!=='sandbox')throw Error();
  const credential=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
  if(credential.project_id!=='luvly-44c77')throw Error();
  const {initializeApp,cert,deleteApp}=await import('firebase-admin/app');
  const {getFirestore}=await import('firebase-admin/firestore');
  const app=initializeApp({credential:cert(credential),projectId:'luvly-44c77'},'readonly-customer-planning-check');
  try{
    const db=getFirestore(app),store=new FirestoreStore(db);
    const owners=await db.collection('brides').limit(101).get();
    if(owners.size>100)throw Error();
    const snapshots=[];
    for(const owner of owners.docs){
      const source=await store.customerPlanningSnapshot(owner.id);
      if(source.limited)throw Error();
      const result=customerPlanning(source,owner.id,Date.now());
      if(result.uid!==owner.id)throw Error();
      snapshots.push(result);
    }
    console.log(JSON.stringify({readOnly:true,customersChecked:snapshots.length,
      plans:snapshots.reduce((sum,s)=>sum+s.plans.length,0),
      visits:snapshots.reduce((sum,s)=>sum+s.appointments.length,0),
      plansWithDates:snapshots.reduce((sum,s)=>sum+s.plans.filter(p=>p.eventDate).length,0),
      plansNeedingReview:snapshots.reduce((sum,s)=>sum+s.plans.filter(p=>p.needsReview).length,0),
      rentalStates:snapshots.flatMap(s=>s.plans).reduce((out,p)=>(out[p.rentalState]=(out[p.rentalState]??0)+1,out),{}),
      maxResponseBytes:Math.max(0,...snapshots.map(s=>Buffer.byteLength(JSON.stringify(s)))),
    },null,2));
  }finally{await deleteApp(app);}
}catch{console.error('Read-only customer planning check failed. No records changed and no credentials printed.');process.exitCode=1;}
