import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {GeminiHelpGateway,geminiConfig,geminiModel,validateGeminiAnswer,needsPersonalSupport} from './gemini_assistant.mjs';
import {SupportAssistant,assistantLanguage,helpGuide,safeQuestion} from './support_assistant.mjs';

const config={provider:'Gemini',model:geminiModel,apiKey:'test-only-not-a-real-key-0123456789',dailyRequestLimit:10,perUserDailyLimit:5};
const answer={kind:'answer',answer:'Yes — the RM50 fitting fee can be credited once after you attend your fitting.',articleIds:['fitting'],handoff:false};
const response=value=>({candidates:[{finishReason:'STOP',content:{parts:[{text:JSON.stringify(value)}]}}]});
const input=(patch={})=>({message:'Can that fee be credited?',history:['How much is the first fitting?'],language:'en',mode:'AI',consentVersion:3,requestId:'a'.repeat(32),...patch});
class MemoryStore {
 constructor(){this.data=new Map([['invoices/untouched',{state:'Unpaid',amountCents:5000}]]);}
 atomic(fn){return fn({get:async path=>structuredClone(this.data.get(path)),set:(path,data)=>this.data.set(path,structuredClone(data))});}
}
const fixture=(overrides={})=>{
 const store=overrides.store??new MemoryStore(),calls=[];
 const assistant=new SupportAssistant({store,access:async()=>{},provider:'Gemini',consentVersion:3,config:()=>config,
  gateway:()=>({route:async(...args)=>{calls.push(args);return {answer:answer.answer,articleIds:['fitting'],handoff:false};}}),...overrides});
 return {store,calls,assistant};
};
test('Gemini requires an explicit free-tier confirmation, enabled flag, key, bounded quotas and fixed model',()=>{
 const directory=mkdtempSync(join(tmpdir(),'luvly-gemini-')),path=join(directory,'config.json');
 try{
  const load=patch=>{writeFileSync(path,JSON.stringify({...config,enabled:true,freeTierProjectConfirmed:true,...patch}));return geminiConfig(path);};
  assert.equal(geminiConfig(path),null);
  for(const patch of [{enabled:false},{freeTierProjectConfirmed:false},{apiKey:''},{apiKey:'PASTE_YOUR_KEY_HERE'},{provider:'Other'},{model:'gemini-4-argon'},{dailyRequestLimit:21},{perUserDailyLimit:11},{apiKey:'test\r\nHeader: x'}])assert.equal(load(patch),null);
  assert.equal(load({}).model,geminiModel);
  assert.ok(load({apiKey:'AQ.'+'b'.repeat(50)}));
 }finally{rmSync(directory,{recursive:true});}
});
test('Gemini request is fixed-origin, stateless, text-only, bounded and has no tools or customer identity',async()=>{
 const calls=[];const gateway=new GeminiHelpGateway(config,{guide:helpGuide,fetchImpl:async(url,options)=>{calls.push({url,options});return Response.json(response(answer));}});
 const result=await gateway.route('Can that fee be credited?',['How much is a first fitting?'],'en');
 assert.equal(result.answer,answer.answer);assert.deepEqual(result.articleIds,['fitting']);
 assert.equal(calls.length,1);assert.equal(calls[0].url,`https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`);
 assert.equal(calls[0].options.redirect,'error');assert.equal(calls[0].options.headers['x-goog-api-key'],config.apiKey);
 assert.ok(!calls[0].url.includes(config.apiKey));
 const body=JSON.parse(calls[0].options.body);assert.deepEqual(Object.keys(body).sort(),['contents','generationConfig','systemInstruction']);
 assert.equal(body.generationConfig.maxOutputTokens,1536);assert.equal(body.generationConfig.candidateCount,1);
 assert.deepEqual(JSON.parse(body.contents[0].parts[0].text),{recentQuestions:['How much is a first fitting?'],currentQuestion:'Can that fee be credited?'});
 assert.match(body.systemInstruction.parts[0].text,/APPROVED POLICY DATA/);assert.doesNotMatch(JSON.stringify(body),/untouched|amountCents|apiKey/);
});
test('explicit response languages use trusted system instructions and Malaysian terminology',async()=>{
 const examples=[
  ['en',/Reply in English/, 'The fitting fee is RM50.'],
  ['zh',/Simplified Chinese with natural wording for Malaysian customers/, '试穿费为 RM50。'],
  ['ms',/Malaysian Bahasa Melayu \(Bahasa Malaysia\)/, 'Bayaran sesi mencuba ialah RM50.'],
 ];
 for(const [language,instruction,expected] of examples){
  const gateway=new GeminiHelpGateway(config,{guide:helpGuide,fetchImpl:async(_url,options)=>{
   const contents=JSON.parse(options.body);
   assert.match(contents.systemInstruction.parts[0].text,instruction);
   assert.doesNotMatch(contents.systemInstruction.parts[0].text,/My sample question/);
   return Response.json(response({...answer,answer:expected}));
  }});
  assert.equal((await gateway.route('My sample question',[],language)).answer,expected);
 }
});
test('Auto infers a fallback from bounded context and accepts only a supported Gemini response language',async()=>{
 assert.equal(assistantLanguage('auto','试穿费多少钱？'),'zh');
 assert.equal(assistantLanguage('auto','Bilakah saya boleh menempah sesi mencuba?'),'ms');
 assert.equal(assistantLanguage('auto','What is the deposit?',['试穿费多少钱？']),'en');
 assert.equal(assistantLanguage('auto','RM50?',['试穿费多少钱？']),'zh');
 assert.equal(assistantLanguage('en','试穿费多少钱？'),'en');
 const calls=[];
 let language='ms';
 const gateway=new GeminiHelpGateway(config,{guide:helpGuide,fetchImpl:async(_url,options)=>{
  calls.push(JSON.parse(options.body));
  return Response.json(response({...answer,answer:'Bayaran sesi mencuba ialah RM50.',language}));
 }});
 const reply=await gateway.route('RM50?',['Berapa bayaran sesi mencuba?'],'en',null,{autoLanguage:true});
 assert.equal(reply.language,'ms');
 assert.match(calls[0].systemInstruction.parts[0].text,/recent questions/);
 assert.match(calls[0].systemInstruction.parts[0].text,/supported languages are English/);
 assert.deepEqual(JSON.parse(calls[0].contents[0].parts[0].text),{
  recentQuestions:['Berapa bayaran sesi mencuba?'],currentQuestion:'RM50?',
 });
 language='id';
 await assert.rejects(gateway.route('RM50?',[],'en',null,{autoLanguage:true}),/AI_INVALID_REPLY_LANGUAGE/);
 await assert.rejects(gateway.route('RM50?',[],'en'),/AI_INVALID_REPLY/);
});
test('Auto assembles policy citations in the language chosen by Gemini and keeps the same conversation context',async()=>{
 const calls=[];
 const f=fixture({gateway:()=>({route:async(...args)=>{
  calls.push(args);
  return {answer:'试穿费为 RM50。',articleIds:['fitting'],handoff:false,language:'zh'};
 }})});
 const reply=await f.assistant.ask('bride',input({language:'auto',message:'RM50?',history:['试穿费是多少钱？']}),{conversationId:'b'.repeat(32)});
 assert.equal(calls[0][2],'zh');
 assert.deepEqual(calls[0][4],{autoLanguage:true});
 assert.equal(reply.language,'zh');
 assert.equal(reply.sources[0].title,helpGuide.articles.find(article=>article.id==='fitting').title.zh);
 assert.equal((await f.assistant.ask('bride',input({language:'ms',requestId:'c'.repeat(32)}))).language,'ms');
 assert.deepEqual(calls[1][4],{autoLanguage:false});
});
test('unsupported money, unknown citations, tool-like extra fields, invented action claims, links and invalid greetings are rejected',()=>{
 for(const patch of [{answer:'The fee is RM999.'},{articleIds:['invented']},{articleIds:[]},{articleIds:['fitting','fitting']},{answer:'I have confirmed your booking.'},{answer:'已为你退款'},{answer:'Visit https://example.com'},{answer:'<script>run()</script>'},{kind:'greeting',articleIds:[],answer:'Here is unrelated advice'}])assert.throws(()=>validateGeminiAnswer({...answer,...patch},helpGuide,'en','fitting?'));
 assert.throws(()=>validateGeminiAnswer({...answer,tools:['do-payment']},helpGuide,'en','fitting?'));
 assert.equal(validateGeminiAnswer({kind:'greeting',answer:'Hello! How can I help with your bridal visit?',articleIds:[],handoff:false},helpGuide,'en','Hello').handoff,false);
 assert.deepEqual(validateGeminiAnswer({kind:'handoff',answer:'Ask the team.',articleIds:[],handoff:true},helpGuide,'en','Fix a spaceship'),{articleIds:[],handoff:true});
});
test('quota, safety blocks, malformed/oversized output and non-STOP candidates fail without retry',async()=>{
 for(const make of [()=>new Response('private provider details',{status:429}),()=>Response.json({promptFeedback:{blockReason:'SAFETY'}}),()=>Response.json({candidates:[{finishReason:'MAX_TOKENS',content:{parts:[{text:'{}'}]}}]}),()=>Response.json({candidates:[{finishReason:'STOP',content:{parts:[{functionCall:{name:'pay'}}]}}]}),()=>new Response('x'.repeat(70000)),()=>Response.json(response({...answer,answer:'RM999'}))]){
  let calls=0;const gateway=new GeminiHelpGateway(config,{guide:helpGuide,fetchImpl:async()=>{calls++;return make();}});
  await assert.rejects(gateway.route('fitting?',[],'en'));assert.equal(calls,1);
 }
});
test('new consent is mandatory; generated reply differs from source but policy excerpts remain authoritative',async()=>{
 const f=fixture();assert.deepEqual(await f.assistant.status('bride'),{aiConfigured:true,guideVersion:helpGuide.version,provider:'Gemini',consentVersion:3});
 await assert.rejects(f.assistant.ask('bride',input({consentVersion:2})),e=>e.code==='AI_CONSENT_REQUIRED');
 assert.equal(f.calls.length,0);
 const r=await f.assistant.ask('bride',input());assert.equal(r.mode,'AI');assert.equal(r.answer,answer.answer);assert.match(r.sources[0].excerpt,/60-minute/);
 assert.deepEqual(f.calls[0][1],['How much is the first fitting?']);
 assert.deepEqual(f.store.data.get('invoices/untouched'),{state:'Unpaid',amountCents:5000});
});
test('secrets and personal actions never reach Gemini; common identifiers are removed from allowed recent context',async()=>{
 const f=fixture();assert.equal(safeQuestion('AQ.'+'x'.repeat(50)),null);
 for(const message of ['password: secretValue','check my payment','取消我的预约','semak bayaran saya']){
  const r=await f.assistant.ask('bride',input({message}));assert.equal(r.mode,'Guide');assert.equal(r.handoff,true);
 }
 assert.equal(f.calls.length,0);assert.equal(needsPersonalSupport('verify my invoice'),true);
 await f.assistant.ask('bride',input({history:['fitting bride@example.com +60123456789','check my payment']}));
 assert.equal(f.calls[0][1].length,1);assert.doesNotMatch(f.calls[0][1][0],/bride@example|60123456789/);
});
test('idempotency returns memory-cached reply, persists no generated text, and never re-calls after a restart',async()=>{
 const f=fixture();const first=await f.assistant.ask('bride',input());
 assert.deepEqual(await f.assistant.ask('bride',input()),first);assert.equal(f.calls.length,1);
 const stored=JSON.stringify([...f.store.data]);assert.doesNotMatch(stored,/credited once|Can that fee|How much is the first fitting/);
 const restarted=fixture({store:f.store});const again=await restarted.assistant.ask('bride',input());
 assert.equal(again.mode,'Guide');assert.equal(again.notice,'AlreadyAnswered');assert.equal(restarted.calls.length,0);
});
test('provider quota is an honestly labelled guide fallback and cannot auto-retry the same request',async()=>{
 let calls=0;const f=fixture({gateway:()=>({route:async()=>{calls++;throw Error('AI_QUOTA');}})});
 const r=await f.assistant.ask('bride',input());assert.equal(r.mode,'Guide');assert.equal(r.notice,'Quota');
 await f.assistant.ask('bride',input());assert.equal(calls,1);
});
test('Gemini does not replay a Dialogflow answer or consume the old provider budget',async()=>{
 const store=new MemoryStore();
 const old=new SupportAssistant({store,access:async()=>{},config:()=>({...config,provider:'DialogflowES'}),gateway:()=>({route:async()=>({articleIds:['dates'],handoff:false})})});
 await old.ask('bride',input({consentVersion:2}));
 const f=fixture({store});const reply=await f.assistant.ask('bride',input());
 assert.equal(f.calls.length,1);assert.equal(reply.answer,answer.answer);
 assert.ok([...store.data.keys()].some(k=>k.startsWith('assistantUsage/gemini-global-')));
});
