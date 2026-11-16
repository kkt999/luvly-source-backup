// Generates new FAQ intents only. Never copies agent credentials or default intents.
import {mkdirSync,writeFileSync,existsSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {dialogflowIntentPlan} from './dialogflow_intents.mjs';
const directory=dirname(fileURLToPath(import.meta.url));
const output=resolve(directory,'../output/dialogflow-support-20261015');
if(existsSync(output))throw Error('OUTPUT_ALREADY_EXISTS');
const stableId=s=>{const h=createHash('sha256').update('luvly-support-v1:'+s).digest('hex');return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;};
const write=(file,data)=>writeFileSync(resolve(output,file),JSON.stringify(data,null,2)+'\n',{flag:'wx'});
mkdirSync(resolve(output,'intents'),{recursive:true});
write('package.json',{version:'1.0.0'});
// Explicit public settings only; no secondaryKey, tokens, IDs or webhook credentials.
write('agent.json',{displayName:'LuvlySupport',description:'Luvly bridal FAQ with customer-reviewed staff handoff.',
 language:'en',defaultTimezone:'Asia/Hong_Kong',supportedLanguages:['zh-CN','ms'],isPrivate:true,
 disableInteractionLogs:true,disableStackdriverLogs:true,mlMinConfidence:.6,enableOnePlatformApi:true,
 onePlatformApiVersion:'v2',analyzeQueryTextSentiment:false,enabledKnowledgeBaseNames:[],
 webhook:{available:false,useForDomains:false,cloudFunctionsEnabled:false},enableSpellCorrection:false});
const plan=dialogflowIntentPlan(),names=[...new Set(plan.map(p=>p.intent.displayName))];
for(const name of names){
 const rows=plan.filter(p=>p.intent.displayName===name);
 const messages=rows.map(row=>({type:'0',lang:row.languageCode,speech:row.intent.messages[0].text.text,title:'',textToSpeech:'',condition:''}));
 write(`intents/${name}.json`,{id:stableId(name),name,auto:true,contexts:[],responses:[{resetContexts:false,
  action:name,affectedContexts:[],parameters:[],messages,speech:[]}],priority:500000,webhookUsed:false,
  webhookForSlotFilling:false,fallbackIntent:false,events:[],conditionalResponses:[],condition:'',conditionalFollowupEvents:[]});
 for(const row of rows)write(`intents/${name}_usersays_${row.languageCode}.json`,row.intent.trainingPhrases.map((p,index)=>({
  id:stableId(name+':'+row.languageCode+':'+index),data:[{text:p.parts[0].text,userDefined:false}],isTemplate:false,count:0,lang:row.languageCode,updated:0})));
}
console.log(JSON.stringify({output,intents:names.length,languages:3,trainingPhrases:plan.reduce((n,r)=>n+r.intent.trainingPhrases.length,0),containsDefaultIntents:false,containsCredentials:false}));
