// Only advertises newly implemented local orbit capabilities; no model upload.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore,FieldValue} from 'firebase-admin/firestore';
const base=dirname(fileURLToPath(import.meta.url));loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const ids=['francine-reference','elegant-local-review'];
const app=initializeApp({credential:cert(key)});
try{
 const db=getFirestore(app),refs=ids.map(id=>db.doc(`arDressModels/${id}`));
 const before=await db.getAll(...refs);
 if(before.some(d=>d.data()?.kind!=='ARReference'||!Array.isArray(d.data()?.supportedViews)))throw Error('Unexpected model metadata');
 if(process.argv.includes('--apply')){
  const dir=resolve(base,'secrets/catalogue-backups');mkdirSync(dir,{recursive:true});
  writeFileSync(resolve(dir,`orbit-metadata-before-${Date.now()}.json`),JSON.stringify(before.map(d=>({id:d.id,data:d.data()})),null,2));
  await db.runTransaction(async tx=>{
   const current=await tx.getAll(...refs);
   for(const d of current){
    if(d.data()?.kind!=='ARReference')throw Error('Model changed');
    if(!d.data().supportedViews.includes('Orbit360'))tx.update(d.ref,{supportedViews:FieldValue.arrayUnion('Orbit360'),updatedAt:FieldValue.serverTimestamp()});
   }
  });
 }
 const after=await db.getAll(...refs);
 console.log(JSON.stringify(after.map(d=>({id:d.id,supportedViews:d.data().supportedViews,visibility:d.data().visibility}))));
 if(process.argv.includes('--apply')&&after.some(d=>!d.data().supportedViews.includes('Orbit360')))throw Error('Orbit metadata verification failed');
}finally{await deleteApp(app);}
