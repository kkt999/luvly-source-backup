// Read-only deployment probe. Prints aggregate counts, never credentials,
// customer profiles, support messages, invoice references or payment links.
import {readFileSync,existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadEnvFile} from 'node:process';
import {FirestoreStore} from './firestore_store.mjs';
import {analyticsRange,calculateAnalytics} from './analytics.mjs';
const directory=dirname(fileURLToPath(import.meta.url));
try{
  if(existsSync(resolve(directory,'.env')))loadEnvFile(resolve(directory,'.env'));
  if(process.env.FIREBASE_PROJECT_ID!=='luvly-44c77'||process.env.TOYYIBPAY_ENV!=='sandbox')throw Error();
  const credential=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
  if(credential.project_id!=='luvly-44c77')throw Error();
  const {initializeApp,cert,deleteApp}=await import('firebase-admin/app');
  const {getFirestore}=await import('firebase-admin/firestore');
  const app=initializeApp({credential:cert(credential),projectId:'luvly-44c77'},'readonly-analytics-check');
  try{
    const data=await new FirestoreStore(getFirestore(app)).analyticsSnapshot(true);
    if(data.limited)throw Error();
    const now=Date.now(),result=calculateAnalytics(data,analyticsRange({},now),now);
    console.log(JSON.stringify({readOnly:true,range:result.range,
      sourceCounts:Object.fromEntries(Object.entries(data).filter(([,v])=>Array.isArray(v)).map(([key,v])=>[key,v.length])),
      totals:result.totals,quality:result.quality,responseBytes:Buffer.byteLength(JSON.stringify(result)),
      reportRows:result.reports.map(r=>({id:r.id,rows:r.rows.length})),
    },null,2));
  }finally{await deleteApp(app);}
}catch{console.error('Read-only analytics check failed. No data was changed and no credentials were printed.');process.exitCode=1;}
