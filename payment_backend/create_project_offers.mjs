// Admin bootstrap, not an app endpoint. Dry run unless --apply is explicit.
// Uses the existing local service credential; never creates an account/role.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {FirestoreStore} from './firestore_store.mjs';
import {createProjectOffers} from './project_promotions.mjs';
const directory=dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory,'.env'));
const credential=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credential.project_id!=='luvly-44c77'||process.env.FIREBASE_PROJECT_ID!=='luvly-44c77'||process.env.TOYYIBPAY_ENV!=='sandbox')throw Error('SANDBOX_PROJECT_REQUIRED');
const db=getFirestore(initializeApp({credential:cert(credential),projectId:credential.project_id}));
try{
 const apply=process.argv.includes('--apply');
 console.log(JSON.stringify({mode:apply?'Apply':'Dry run',offers:await createProjectOffers(new FirestoreStore(db),{apply})}));
}catch{console.error('Offers were not confirmed. Inspect current packages/codes before retrying; no automatic overwrite.');process.exitCode=1;}
finally{await db.terminate();}
