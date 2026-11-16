// Narrow, guarded addition of one catalogue model ID. Access permissions stay intact.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadEnvFile} from 'node:process';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getSecurityRules} from 'firebase-admin/security-rules';
const base=dirname(fileURLToPath(import.meta.url));loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(key)});
try{
 const api=getSecurityRules(app),current=await api.getFirestoreRuleset();
 if(current.source.length!==1)throw Error('Unexpected multi-file rules');
 const before=current.source[0].content;
 const original="d.get('arModelId', '') in ['', 'princess-wedding', 'francine-reference']";
 const allowed="d.get('arModelId', '') in ['', 'princess-wedding', 'francine-reference', 'elegant-local-review']";
 if(before.includes(allowed)){console.log('Catalogue model whitelist already up to date.');}
 else{
  if(before.split(original).length!==2)throw Error('Unexpected remote whitelist');
  const after=before.replace(original,allowed);
  const dir=resolve(base,'secrets/catalogue-backups');mkdirSync(dir,{recursive:true});
  writeFileSync(resolve(dir,`model-link-rules-before-${Date.now()}.rules`),before);
  console.log('Verified only change: add elegant-local-review to bounded catalogue model IDs; authentication and writes unchanged.');
  if(process.argv.includes('--publish')){
   if((await api.getFirestoreRuleset()).name!==current.name)throw Error('Rules changed concurrently');
   await api.releaseFirestoreRulesetFromSource(after);
   if((await api.getFirestoreRuleset()).source[0].content!==after)throw Error('Rules verification failed');
   console.log('Narrow model-link rule published and verified.');
  }
 }
}finally{await deleteApp(app);}
