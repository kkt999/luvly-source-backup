// Add only bounded editorial metadata; existing read/write permissions stay intact.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadEnvFile} from 'node:process';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getSecurityRules} from 'firebase-admin/security-rules';
const base=dirname(fileURLToPath(import.meta.url));loadEnvFile(resolve(base,'.env'));
const credentials=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credentials.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(credentials)});
try{
 const api=getSecurityRules(app),current=await api.getFirestoreRuleset();
 if(current.source.length!==1)throw Error('Unexpected multi-file rules');
 const before=current.source[0].content;
 const local=readFileSync(resolve(base,'../firestore.rules'),'utf8');
 const helper=local.slice(local.indexOf('    function validProductDetails('),local.indexOf('    function validDress('));
 if(!helper.startsWith('    function validProductDetails('))throw Error('Missing helper');
 if(before.includes('function validProductDetails(')){console.log('Product detail rules already present; no change.');}
 else{
  const oldList="['name','category','description','colour','sizes','priceCents','imageUrl','photoRevision','arModelId','availability','published','revision','createdBy','createdAt','updatedBy','updatedAt']";
  const newList=oldList.replace("'description',","'description','productDetails',");
  if(before.split(oldList).length!==2||before.split('    function validDress(d) {').length!==2)throw Error('Unexpected remote product rules');
  const after=before.replace('    function validDress(d) {',helper+'    function validDress(d) {').replace(oldList,newList)
    .replace('&& d.get(\'arModelId\',',"&& validProductDetails(d.get('productDetails', {}))\n        && d.get('arModelId',");
  if(!after.includes("&& validProductDetails(d.get('productDetails', {}))"))throw Error('Validation insertion failed');
  const folder=resolve(base,'secrets/catalogue-backups');mkdirSync(folder,{recursive:true});
  writeFileSync(resolve(folder,`product-rules-before-${Date.now()}.rules`),before);
  console.log('Verified narrow change: four bounded product description fields; all authentication and role checks retained.');
  if(process.argv.includes('--publish')){
   if((await api.getFirestoreRuleset()).name!==current.name)throw Error('Rules changed concurrently');
   await api.releaseFirestoreRulesetFromSource(after);
   if((await api.getFirestoreRuleset()).source[0].content!==after)throw Error('Rules verification failed');
   console.log('Product detail rules published and reread successfully.');
  }
 }
}finally{await deleteApp(app);}
