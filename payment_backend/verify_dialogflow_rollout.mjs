// Deployment smoke check: synthetic questions only; no account, payment or IAM writes.
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {inflateRawSync} from 'node:zlib';
import {randomBytes} from 'node:crypto';
import {dialogflowAuth,DialogflowHelpRouter} from './support_assistant.mjs';

const directory=dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(directory,'.env'));
const config={provider:'DialogflowES',projectId:'luvly-44c77',credentialPath:resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS)};
const auth=dialogflowAuth(config);
async function api(path,method='GET'){
 const access=await auth.getAccessToken();
 const response=await fetch('https://dialogflow.googleapis.com/v2/'+path,{
  method,redirect:'error',signal:AbortSignal.timeout(20000),
  headers:{Authorization:'Bearer '+access.token,'Content-Type':'application/json'},
  ...(method==='POST'?{body:'{}'}:{}),
 });
 if(!response.ok)throw Error('GOOGLE_HTTP_'+response.status);
 return response.json();
}
// Read only agent.json from the in-memory export; never print/save legacy keys.
function exportedAgent(base64){
 const zip=Buffer.from(base64,'base64');
 if(zip.length>4*1024*1024)throw Error('EXPORT_TOO_LARGE');
 let end=zip.length-22;
 while(end>=Math.max(0,zip.length-65557) && zip.readUInt32LE(end)!==0x06054b50)end--;
 if(end<0 || zip.readUInt32LE(end)!==0x06054b50)throw Error('INVALID_EXPORT');
 let cursor=zip.readUInt32LE(end+16);
 for(let i=0;i<zip.readUInt16LE(end+10);i++){
  if(zip.readUInt32LE(cursor)!==0x02014b50)throw Error('INVALID_EXPORT');
  const nameLength=zip.readUInt16LE(cursor+28),extra=zip.readUInt16LE(cursor+30),comment=zip.readUInt16LE(cursor+32);
  const name=zip.subarray(cursor+46,cursor+46+nameLength).toString('utf8');
  if(name==='agent.json'){
   const offset=zip.readUInt32LE(cursor+42),method=zip.readUInt16LE(cursor+10),size=zip.readUInt32LE(cursor+20);
   const start=offset+30+zip.readUInt16LE(offset+26)+zip.readUInt16LE(offset+28);
   const bytes=zip.subarray(start,start+size);
   const json=method===0?bytes:method===8?inflateRawSync(bytes,{maxOutputLength:262144}):null;
   if(!json)throw Error('INVALID_EXPORT');
   return JSON.parse(json.toString('utf8'));
  }
  cursor+=46+nameLength+extra+comment;
 }
 throw Error('AGENT_NOT_EXPORTED');
}
try{
 const agent=await api('projects/luvly-44c77/agent');
 const fulfillment=await api('projects/luvly-44c77/agent/fulfillment');
 const listed=await api('projects/luvly-44c77/agent/intents?pageSize=100');
 const names=(listed.intents??[]).map(i=>i.displayName);
 const expected=['accessories','appointments','ar','calendar','cancellation','dates','fitting','payments','receipts','sizes'].map(id=>'Luvly.faq.'+id).concat(['Luvly.handoff','Luvly.welcome']);
 if(agent.tier!=='TIER_STANDARD' || fulfillment.enabled===true || expected.some(name=>!names.includes(name)) || !names.includes('Default Fallback Intent') || !names.includes('Default Welcome Intent'))throw Error('AGENT_NOT_READY');
 let exported=await api('projects/luvly-44c77/agent:export','POST');
 for(let i=0;i<15 && !exported.done;i++){
  if(!/^projects\/luvly-44c77\/operations\/[A-Za-z0-9_-]+$/.test(exported.name??''))throw Error('INVALID_OPERATION');
  await new Promise(resolve=>setTimeout(resolve,1000));exported=await api(exported.name);
 }
 if(!exported.done || exported.error || !exported.response?.agentContent)throw Error('EXPORT_NOT_READY');
 const settings=exportedAgent(exported.response.agentContent);
 if(settings.disableInteractionLogs!==true || settings.disableStackdriverLogs!==true)throw Error('LOGGING_NOT_DISABLED');
 console.log(JSON.stringify({check:'agent',tier:agent.tier,intents:names.length,languages:[agent.defaultLanguageCode,...(agent.supportedLanguageCodes??[])],loggingDisabled:true,webhookDisabled:true,defaultsPreserved:true}));
 const router=new DialogflowHelpRouter(config,{auth});
 const cases=[
  {language:'en',message:'How much is the first gown fitting?',expected:'fitting'},
  {language:'zh',message:'第一次试穿婚纱要多少钱？',expected:'fitting'},
  {language:'ms',message:'Berapakah bayaran sesi pertama mencuba gaun?',expected:'fitting'},
  {language:'en',message:'I want to speak to a human',handoff:true},
  {language:'en',message:'How do I repair a spaceship engine?',handoff:true},
 ];
 for(const item of cases){
  const result=await router.route(item.message,[],item.language,randomBytes(16).toString('hex'));
  const passed=item.expected?result.articleIds.includes(item.expected):result.handoff===true;
  console.log(JSON.stringify({check:'synthetic-question',language:item.language,expected:item.expected??'handoff',...result,passed}));
  if(!passed)throw Error('MATCH_NOT_READY');
 }
 console.log(JSON.stringify({verified:true,syntheticCloudQuestions:cases.length,customerDataUsed:false}));
}catch(error){
 const code=/^[A-Z_0-9]+$/.test(error.message)?error.message:'VERIFICATION_FAILED';
 console.error(JSON.stringify({verified:false,code}));process.exitCode=1;
}
