// Explicit isolated QA only: synthetic ratios; never use real customer data.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {randomBytes} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {stableBackendOrigin} from './backend_origin.mjs';
if(process.argv[2]!=='--run-isolated-qa')throw Error('Explicit isolated QA mode required');
loadEnvFile(new URL('.env',import.meta.url));
if(process.env.FIREBASE_PROJECT_ID!=='luvly-44c77'||process.env.TOYYIBPAY_ENV!=='sandbox')throw Error('Sandbox project required');
const key=JSON.parse(readFileSync(new URL(process.env.GOOGLE_APPLICATION_CREDENTIALS,import.meta.url)));
assert.equal(key.project_id,'luvly-44c77');
const app=initializeApp({credential:cert(key),projectId:'luvly-44c77'}),db=getFirestore(app),auth=getAuth(app);
const uid='qa_bodyscan_'+randomBytes(10).toString('hex'),created=[];
const options=readFileSync(new URL('../lib/firebase_options.dart',import.meta.url),'utf8');
const apiKey=/FirebaseOptions web = FirebaseOptions\(\s*apiKey: '([^']+)'/.exec(options)[1];
async function tokenFor(owner){
  await auth.createUser({uid:owner,displayName:'Isolated body scan QA'});created.push(owner);
  await db.doc('brides/'+owner).set({uid:owner,role:'bride',name:'Isolated body scan QA',phone:'0100000000'});
  const custom=await auth.createCustomToken(owner);
  const r=await fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key='+apiKey,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:custom,returnSecureToken:true})});
  const j=await r.json();assert(r.ok&&j.idToken);return j.idToken;
}
async function api(token,body,expected=200){
  const r=await fetch(stableBackendOrigin+'/v1/my-recommendation-profile',{method:body?'POST':'GET',headers:{...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(30000)});
  const j=await r.json();assert.equal(r.status,expected,'Unexpected QA profile HTTP response');return j;
}
try{
  await api(null,null,401);
  const token=await tokenFor(uid),other=await tokenFor(uid+'_other');
  const old=await api(token);assert.equal(old.profile.bodyScan,null);
  const manual={...old.profile,measurements:{Bust:90},styles:['A-Line']};
  const saved=await api(token,{revision:old.revision,requestId:'qa-manual',profile:manual});
  const scan={algorithmVersion:'joint-ratios-v2',shoulderHipRatio:1.7,torsoShoulderRatio:1.2,sampleCount:15,durationMs:5000,relativeSpread:.01,capturedAt:Date.now()};
  const profile={...saved.profile,bodyScan:scan,useScanProportions:true};
  const input={revision:saved.revision,requestId:'qa-scan',profile};
  const updated=await api(token,input);assert.deepEqual(updated.profile.measurements,{Bust:90});
  assert.deepEqual((await api(token)).profile.bodyScan,scan);
  assert.equal((await api(token,input)).revision,updated.revision);
  assert.equal((await api(other)).profile.bodyScan,null);
  await api(token,{...input,requestId:'qa-stale'},409);
  await api(token,{revision:updated.revision,requestId:'qa-invalid',profile:{...profile,bodyScan:{...scan,Bust:90}}},400);
  const summary=(await db.doc('bodyTypeSummaries/'+uid).get()).data();
  assert.equal(summary.bodyType,null);assert.equal('bodyScan' in summary,false);assert.equal('measurements' in summary,false);
  const cleared=await api(token,{revision:updated.revision,requestId:'qa-remove',profile:{...profile,bodyScan:null,useScanProportions:false}});
  assert.equal(cleared.profile.bodyScan,null);assert.deepEqual(cleared.profile.measurements,{Bust:90});assert.deepEqual(cleared.profile.styles,['A-Line']);
  console.log(JSON.stringify({isolatedQa:true,syntheticScan:true,allPassed:true,checks:['Authentication required','Private cross-device profile persistence','Manual measurements and preferences preserved','Retry idempotency and stale edit protection','Other owner cannot see scan','Forged measurement payload rejected','Scan excluded from manager category projection','Remove and save clears scan']}));
}catch(e){console.error('Isolated body scan QA failed:',String(e.message).replaceAll(uid,'[QA account]'));process.exitCode=1;}
finally{
  try{
    for(const owner of created){assert(owner===uid||owner===uid+'_other');assert(owner.startsWith('qa_bodyscan_'));
      const batch=db.batch();for(const collection of ['recommendationProfiles','bodyTypeSummaries','brides'])batch.delete(db.doc(collection+'/'+owner));await batch.commit();await auth.deleteUser(owner);
    }
    console.log('Isolated QA accounts and synthetic body profiles removed.');
  }catch{console.error('Isolated QA cleanup needs administrator review.');process.exitCode=1;}
  await deleteApp(app);
}
