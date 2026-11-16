// Synthetic rollout checks only. Never log keys, provider errors or customer data.
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {GeminiHelpGateway,geminiConfig,geminiModel} from './gemini_assistant.mjs';
import {helpGuide} from './support_assistant.mjs';
const config=geminiConfig(resolve(dirname(fileURLToPath(import.meta.url)),'secrets/gemini-config.json'));
let stage='configuration';
if(!config){console.log(JSON.stringify({verified:false,code:'GEMINI_SETUP_REQUIRED'}));process.exitCode=1;}
else try{
 stage='model-access';
 const model=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}`,{
  headers:{'x-goog-api-key':config.apiKey},redirect:'error',signal:AbortSignal.timeout(15000),
 });
 if(!model.ok){console.log(JSON.stringify({verified:false,stage:'model-access',httpStatus:model.status}));process.exitCode=1;}
 else {
  console.log(JSON.stringify({check:'model-access',httpStatus:model.status,model:geminiModel}));
  const gateway=new GeminiHelpGateway(config,{guide:helpGuide});
  const full=[
   {language:'en',message:'How much is the first gown fitting?',history:[],expected:'fitting'},
   {language:'en',message:'Can that fee be credited if I choose a package afterwards?',history:['How much is the first gown fitting?'],expected:'fitting'},
   {language:'zh',message:'第一次试穿婚纱要多少钱？',history:[],expected:'fitting'},
   {language:'ms',message:'Berapakah bayaran sesi pertama mencuba gaun?',history:[],expected:'fitting'},
   {language:'en',message:'Tell me how to repair a spaceship engine.',history:[],handoff:true},
  ];
  const cases=process.argv.includes('--full')?full:process.argv.includes('--remaining')?full.slice(2):[full[1]];
  for(const item of cases){
   stage='synthetic-'+item.language+(item.history.length?'-follow-up':'');
   console.log(JSON.stringify({check:'starting-synthetic-question',stage}));
   const r=await gateway.route(item.message,item.history,item.language);
   const passed=item.handoff?r.handoff===true && !r.answer:r.articleIds.includes(item.expected) && typeof r.answer==='string';
   console.log(JSON.stringify({check:'synthetic-question',language:item.language,followUp:item.history.length>0,articleIds:r.articleIds,handoff:r.handoff,generated:!!r.answer,passed}));
   if(!passed)throw Error('MATCH_NOT_READY');
  }
  console.log(JSON.stringify({verified:true,syntheticQuestions:cases.length,customerDataUsed:false}));
 }
}catch(error){console.log(JSON.stringify({verified:false,stage,code:/^AI_[A-Z_]+$|^MATCH_NOT_READY$/.test(error.message)?error.message:'CONNECTION_FAILED',errorType:error.name,networkCode:/^[A-Z_]+$/.test(error.cause?.code??'')?error.cause.code:undefined}));process.exitCode=1;}
