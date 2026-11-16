// Read-only Hosting preflight; never writes project settings or releases.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
const base=dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(key)});
try {
  const token=await app.options.credential.getAccessToken();
  const response=await fetch('https://firebasehosting.googleapis.com/v1beta1/projects/luvly-44c77/sites',{
    headers:{Authorization:`Bearer ${token.access_token}`},signal:AbortSignal.timeout(20000)});
  const data=await response.json();
  console.log(JSON.stringify({status:response.status,sites:data.sites?.map(s=>({name:s.name,defaultUrl:s.defaultUrl,type:s.type})),
    error:data.error?{code:data.error.code,status:data.error.status,message:data.error.message}:undefined}));
}finally{await deleteApp(app);}
