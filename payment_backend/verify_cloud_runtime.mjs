// Administrator read-only API verification. Tokens and identities never printed.
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {stableBackendOrigin} from './backend_origin.mjs';
loadEnvFile(new URL('.env',import.meta.url));
const app=initializeApp({credential:cert(JSON.parse(readFileSync(new URL(process.env.GOOGLE_APPLICATION_CREDENTIALS,import.meta.url))))});
try{
  const db=getFirestore(app),auth=getAuth(app),staff=(await db.collection('staff').get()).docs;
  const options=readFileSync(new URL('../lib/firebase_options.dart',import.meta.url),'utf8');
  const apiKey=/FirebaseOptions web = FirebaseOptions\(\s*apiKey: '([^']+)'/.exec(options)[1];
  const checks=[];
  async function check(label,path,expected,token){
    const r=await fetch(stableBackendOrigin+path,{headers:token?{Authorization:'Bearer '+token}:{},redirect:'error',signal:AbortSignal.timeout(30000)});
    const j=await r.json().catch(()=>null);checks.push({label,status:r.status,ok:r.status===expected});return j;
  }
  async function token(uid){
    const customToken=await auth.createCustomToken(uid);
    const r=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key='+apiKey,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:customToken,returnSecureToken:true})});
    const j=await r.json();if(!r.ok||!j.idToken)throw Error('Verification sign-in failed');return j.idToken;
  }
  await check('Health','/health',200);await check('Unauthenticated API denied','/v1/notifications',401);
  const manager=staff.find(d=>d.data().active===true&&d.data().role==='manager');
  if(!manager)throw Error('Manager check unavailable');
  const mt=await token(manager.id),report=await check('Manager reporting','/v1/analytics',200,mt);
  if(!Array.isArray(report?.bodyTypes)||report.bodyTypes.length!==5||JSON.stringify(report).includes('"measurements":'))throw Error('Invalid report');
  await check('Manager cannot access customer measurement profile','/v1/my-recommendation-profile',403,mt);
  const employee=staff.find(d=>d.data().active===true&&d.data().role==='staff');
  if(employee){const st=await token(employee.id);await check('Staff dashboard','/v1/dashboard',200,st);await check('Staff denied manager report','/v1/analytics',403,st);}
  const brides=await db.collection('brides').limit(5).get();let checked=false;
  for(const d of brides.docs){try{await auth.getUser(d.id);}catch{continue;}
    const ct=await token(d.id);await check('Customer planning','/v1/my-planning',200,ct);
    await check('Customer own recommendation profile','/v1/my-recommendation-profile',200,ct);
    await check('Customer notifications','/v1/notifications',200,ct);
    await check('Customer denied manager report','/v1/analytics',403,ct);checked=true;break;
  }
  if(!checked)throw Error('Customer read-only check unavailable');
  console.log(JSON.stringify({origin:stableBackendOrigin,checks,allPassed:checks.every(x=>x.ok)},null,2));
  if(checks.some(x=>!x.ok))process.exitCode=1;
}catch{console.error('Cloud read-only API verification failed; no business records changed or tokens logged.');process.exitCode=1;}
finally{await deleteApp(app);}
