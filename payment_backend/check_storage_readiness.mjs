// Read-only checks; no uploads, media downloads, configuration or business writes.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname,resolve} from 'node:path';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getStorage} from 'firebase-admin/storage';
import {getFirestore} from 'firebase-admin/firestore';
const directory=dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory,'.env'));
const credential=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credential.project_id!=='luvly-44c77') throw Error('Wrong project');
const app=initializeApp({credential:cert(credential),projectId:'luvly-44c77'});
try {
  const bucket=getStorage(app).bucket('luvly-44c77.firebasestorage.app');
  const [metadata]=await bucket.getMetadata();
  console.log('PASS review bucket exists');
  for(const origin of ['http://localhost:5000','http://127.0.0.1:5000']) {
    const ok=(metadata.cors??[]).some(c=>c.origin?.includes(origin)&&['GET','HEAD'].every(m=>c.method?.includes(m)));
    console.log(`${ok?'PASS':'FAIL'} media CORS for ${origin}`);if(!ok)process.exitCode=1;
  }
  const [policy]=await bucket.iam.getPolicy();
  const publicBucket=(policy.bindings??[]).some(b=>(b.members??[]).some(m=>['allUsers','allAuthenticatedUsers'].includes(m)));
  console.log(`${publicBucket?'FAIL':'PASS'} bucket IAM does not grant public-wide access`);if(publicBucket)process.exitCode=1;
  await getFirestore(app).collection('customerReviewUploads').where('reviewId','==','0'.repeat(32)).where('status','in',['Ready','Reserved','Failed','Deleting']).limit(1).get();
  console.log('PASS review upload cleanup index available');
  console.log('Does not verify object ACLs, Storage Rules, signed playback or a real user upload.');
} catch(e) {console.log(`Storage readiness unavailable (code ${typeof e.code==='number'?e.code:'unknown'}); no changes made.`);process.exitCode=1;}
finally {await deleteApp(app);}
