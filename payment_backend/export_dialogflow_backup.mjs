// Read-only agent export. No agent settings, intents, IAM or billing are changed.
import {loadEnvFile} from 'node:process';
import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {JWT} from 'google-auth-library';
const directory=dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory,'.env'));
const key=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('WRONG_PROJECT');
const token=await new JWT({email:key.client_email,key:key.private_key,scopes:['https://www.googleapis.com/auth/dialogflow']}).getAccessToken();
async function request(path,method='GET'){
 const r=await fetch('https://dialogflow.googleapis.com/v2/'+path,{method,headers:{Authorization:'Bearer '+token.token,'Content-Type':'application/json'},...(method==='POST'?{body:'{}'}:{}),redirect:'error',signal:AbortSignal.timeout(15000)});
 const data=await r.json();if(!r.ok)throw Error(`EXPORT_${r.status}`);return data;
}
try{
 let result=await request('projects/luvly-44c77/agent:export','POST');
 for(let i=0;i<10 && !result.done;i++){
  if(!/^projects\/luvly-44c77\/operations\/[A-Za-z0-9_-]+$/.test(result.name??''))throw Error('INVALID_OPERATION');
  await new Promise(resolve=>setTimeout(resolve,1000));result=await request(result.name);
 }
 if(result.error || !result.done || typeof result.response?.agentContent!=='string')throw Error('EXPORT_NOT_READY');
 const output=resolve(directory,'secrets/dialogflow-before-import.zip');
 mkdirSync(dirname(output),{recursive:true});writeFileSync(output,Buffer.from(result.response.agentContent,'base64'),{flag:'wx'});
 console.log(JSON.stringify({exported:true,path:output}));
}catch(error){console.log(JSON.stringify({exported:false,code:/^EXPORT_\d+$|^EXPORT_NOT_READY$|^INVALID_OPERATION$/.test(error.message)?error.message:error.code==='EEXIST'?'BACKUP_ALREADY_EXISTS':'EXPORT_UNAVAILABLE'}));process.exitCode=1;}
