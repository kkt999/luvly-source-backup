import {readFileSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,dirname} from 'node:path';
import {JWT} from 'google-auth-library';
import {HttpError} from './payment_service.mjs';
import {needsPersonalSupport} from './gemini_assistant.mjs';

export const helpGuide=JSON.parse(readFileSync(new URL('../assets/support/guide.json',import.meta.url),'utf8'));
const ids=new Set(helpGuide.articles.map(a=>a.id));
const hash=v=>createHash('sha256').update(v).digest('hex');
const check=(v,code,status=400)=>{if(!v)throw new HttpError(status,code);};
const languages=['en','zh','ms'];
const projectId='luvly-44c77';
const copy={
 en:{welcome:'I can explain fittings, package payments, rental dates, accessories, size guidance, Calendar and receipts. For your own order, payment or refund, please contact the Luvly team.',privacy:'Please do not send passwords, verification codes, API keys or bank/card details. This message was not sent to AI. Contact the team through a support ticket for account-specific help.'},
 zh:{welcome:'我可以说明试穿、套餐付款、租期、配饰、尺码指南、日历和收据。关于你自己的订单、付款或退款，请联系 Luvly 人工客服。',privacy:'请勿发送密码、验证码、API 密钥或银行／银行卡资料。这条消息没有发送给 AI。涉及账户的具体问题，请通过人工客服工单处理。'},
 ms:{welcome:'Saya boleh menerangkan sesi mencuba, bayaran pakej, tarikh sewaan, aksesori, panduan saiz, Calendar dan resit. Untuk pesanan, bayaran atau bayaran balik peribadi, sila hubungi staf Luvly.',privacy:'Jangan hantar kata laluan, kod pengesahan, kunci API atau butiran bank/kad. Mesej ini tidak dihantar kepada AI. Gunakan tiket sokongan untuk urusan akaun peribadi.'},
};
export function assistantLanguage(value,message){return languages.includes(value)?value:/[\u3400-\u9fff]/u.test(message)?'zh':/\b(saya|boleh|berapa|gaun|sewa|bayar|janji|saiz|stok|batal)\b/i.test(message)?'ms':'en';}
export function guideMatch(message,history=[]){
 let q=message.toLowerCase();
 const score=q=>helpGuide.articles.map(a=>({id:a.id,n:a.keywords.filter(k=>/[a-z]/i.test(k)?new RegExp(`\\b${k.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}${k.length<4?'\\b':''}`,'i').test(q):q.includes(k.toLowerCase())).length})).filter(r=>r.n>0).sort((a,b)=>b.n-a.n).slice(0,2).map(r=>r.id);
 let found=score(q);
 if(!found.length && /^(and|then|what next|how much|然后|还有|接下来|多少钱|dan|seterusnya)[?？\s\S]{0,30}$/i.test(q) && history.length)found=score(history.at(-1).toLowerCase());
 return {articleIds:found,handoff:/\b(refund|deducted|charged|my payment|my order|cancel it|staff|human)\b|退款|扣款|我的订单|我的付款|人工|帮我取消|bayaran balik|staf|pesanan saya/i.test(q) || !found.length};
}
export function safeQuestion(text){
 if(/(?:^|\s)(?=[A-Za-z0-9_.-]*[0-9_.-])[A-Za-z0-9_.-]{40,}(?=$|\s)/.test(text))return null;
 if(/AIza[A-Za-z0-9_-]{20,}|\b(?:password|secret|otp|verification code|card number|cvv|pin)\s*[:=]?\s*\d{3,}|(?:密码|验证码|卡号)\s*[:：]?\s*\S+|\b(?:password|api key|secret)\s*[:=]\s*\S+/i.test(text))return null;
 return text.replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,'[email removed]')
   .replace(/(?:\+?\d[\d ()-]{7,}\d)/g,'[number removed]').replace(/https?:\/\/\S+/gi,'[link removed]');
}
export function assistantConfig(path,{credentialPath}={}){
 try{
  if(!existsSync(path))return null;
  const c=JSON.parse(readFileSync(path,'utf8'));
  if(c.enabled!==true || c.provider!=='DialogflowES' || c.freeTierProjectConfirmed!==true || c.projectId!==projectId ||
    !Number.isInteger(c.dailyRequestLimit) || c.dailyRequestLimit<1 || c.dailyRequestLimit>20 ||
    !Number.isInteger(c.perUserDailyLimit) || c.perUserDailyLimit<1 || c.perUserDailyLimit>10)return null;
  return {...c,credentialPath:credentialPath ?? resolve(dirname(path),'dialogflow-service-account.json')};
 }catch{return null;}
}
export function dialogflowAuth(config){
 const key=JSON.parse(readFileSync(config.credentialPath,'utf8'));
 if(key.type!=='service_account' || key.project_id!==projectId ||
   !key.client_email?.endsWith(`@${projectId}.iam.gserviceaccount.com`) || typeof key.private_key!=='string')throw Error('AI_SETUP_REQUIRED');
 // Never inherit an ADC quota project or a client-supplied consumer project.
 return new JWT({email:key.client_email,key:key.private_key,scopes:['https://www.googleapis.com/auth/dialogflow']});
}
export class DialogflowHelpRouter{
 constructor(config,{fetchImpl=fetch,auth}={}){this.config=config;this.fetch=fetchImpl;this.auth=auth;}
 async request(path,{method='GET',body,token,signal}={}){
  const response=await this.fetch(`https://dialogflow.googleapis.com/v2/projects/${projectId}/agent${path}`,{
   method,redirect:'error',signal,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
   ...(body?{body:JSON.stringify(body)}:{}),
  });
  if(!response.ok)throw Error(response.status===429?'AI_QUOTA':'AI_UNAVAILABLE');
  const chunks=[];let length=0;
  for await(const chunk of response.body){length+=chunk.length;if(length>65536)throw Error('AI_INVALID_REPLY');chunks.push(Buffer.from(chunk));}
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
 }
 async route(message,_history,language,session){
  if(this.config.projectId!==projectId || this.config.provider!=='DialogflowES' || !/^[a-f0-9]{32}$/.test(session))throw Error('AI_SETUP_REQUIRED');
  if([...message].length>256)throw Error('AI_MESSAGE_TOO_LONG');
  const signal=AbortSignal.timeout(12000),auth=this.auth ?? dialogflowAuth(this.config);
  const tokenResult=await Promise.race([auth.getAccessToken(),new Promise((_,reject)=>{
   signal.addEventListener('abort',()=>reject(Error('AI_UNAVAILABLE')),{once:true});
  })]);
  signal.throwIfAborted();
  const token=typeof tokenResult==='string'?tokenResult:tokenResult?.token;
  if(!token)throw Error('AI_SETUP_REQUIRED');
  // Recheck the free edition on EVERY query, before detectIntent. Never upgrade.
  const agent=await this.request('',{token,signal});
  if(agent.tier!=='TIER_STANDARD')throw Error('AI_FREE_EDITION_REQUIRED');
  if(agent.enableLogging===true)throw Error('AI_DISABLE_LOGGING_REQUIRED');
  const code={en:'en',zh:'zh-CN',ms:'ms'}[language];
  // BCP-47 language tags are case-insensitive; Google may return zh-cn.
  if(!code || ![agent.defaultLanguageCode,...(agent.supportedLanguageCodes??[])].some(value=>typeof value==='string' && value.toLowerCase()===code.toLowerCase()))throw Error('AI_LANGUAGE_UNAVAILABLE');
  const fulfillment=await this.request('/fulfillment',{token,signal});
  if(fulfillment.enabled===true)throw Error('AI_DISABLE_WEBHOOK_REQUIRED');
  const json=await this.request(`/sessions/${session}:detectIntent`,{token,signal,method:'POST',body:{
   queryInput:{text:{text:message,languageCode:code}},queryParams:{timeZone:'Asia/Kuala_Lumpur'},
  }});
  const result=json.queryResult,name=result?.intent?.displayName;
  if(!result || result.intent?.isFallback || !Number.isFinite(result.intentDetectionConfidence) || result.intentDetectionConfidence<0.6)return {articleIds:[],handoff:true};
  const id=typeof name==='string' && name.startsWith('Luvly.faq.')?name.slice(10):null;
  // Ignore fulfillment text, parameters and webhook payloads. Only allow known guide IDs.
  if(ids.has(id))return {articleIds:[id],handoff:false};
  return {articleIds:[],handoff:name!=='Luvly.welcome'};
 }
}
export class SupportAssistant{
 constructor({store,access,config=()=>null,gateway=c=>new DialogflowHelpRouter(c),now=Date.now,provider='Dialogflow ES',consentVersion=2}){Object.assign(this,{store,access,config,gateway,now,provider,consentVersion});this.inFlight=0;this.replies=new Map();}
 async status(uid){await this.access(uid);return {aiConfigured:!!this.config(),guideVersion:helpGuide.version,provider:this.provider,consentVersion:this.consentVersion};}
 response(result,language){
  const articles=result.articleIds.map(id=>helpGuide.articles.find(a=>a.id===id));
  return {mode:result.mode,notice:result.notice ?? null,language,guideVersion:helpGuide.version,handoff:result.handoff,
   answer:result.notice==='Privacy'?copy[language].privacy:result.answer??(articles.length?articles.map(a=>a.answer[language]).join('\n\n'):copy[language].welcome),
   sources:articles.map(a=>({id:a.id,title:a.title[language],excerpt:a.answer[language]}))};
 }
 async ask(uid,input){
  await this.access(uid);
  check(input && Object.keys(input).every(k=>['message','history','language','mode','requestId','consentVersion'].includes(k)) &&
   typeof input.message==='string' && input.message.trim().length>0 && input.message.length<=800 && !/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/.test(input.message) &&
   Array.isArray(input.history) && input.history.length<=4 && input.history.every(q=>typeof q==='string' && q.length<=800) &&
   ['auto',...languages].includes(input.language) && ['Guide','AI'].includes(input.mode) && typeof input.requestId==='string' && /^[a-f0-9]{32}$/.test(input.requestId),'INVALID_ASSISTANT_MESSAGE');
  const language=assistantLanguage(input.language,input.message),base={...guideMatch(input.message,input.history),mode:'Guide'};
  const fallback=notice=>this.response({...base,notice},language);
  const question=safeQuestion(input.message),history=input.history.map(safeQuestion);
  if(question===null || history.some(q=>q===null))return this.response({articleIds:[],mode:'Guide',handoff:true,notice:'Privacy'},language);
  if(input.mode==='Guide')return fallback(null);
  check(input.consentVersion===this.consentVersion,'AI_CONSENT_REQUIRED');
  if([...question].length>256)return fallback('ShortenQuestion');
  const config=this.config();if(!config)return fallback('SetupRequired');
  if(config.apiKey && [input.message,...input.history].some(q=>q.includes(config.apiKey)))return this.response({articleIds:[],mode:'Guide',handoff:true,notice:'Privacy'},language);
  if(config.provider==='Gemini' && needsPersonalSupport(question))return this.response({...base,handoff:true,mode:'Guide',notice:'PersonalSupport'},language);
  if(this.inFlight>=2)return fallback('Busy');
  this.inFlight++;
  const namespace=config.provider==='Gemini'?'gemini-v3:':'';
  const fingerprint=hash(JSON.stringify([question,history,language])),day=new Date(this.now()).toISOString().slice(0,10),requestPath=`assistantRequests/${hash(namespace+uid+':'+input.requestId)}`;
  let intent;
  try{intent=await this.store.atomic(async tx=>{
   const prior=await tx.get(requestPath);
   if(prior){check(prior.fingerprint===fingerprint,'ASSISTANT_REQUEST_CONFLICT',409);return prior.result ? {cached:prior.result} : {notice:'Busy'};}
   const usagePrefix=config.provider==='Gemini'?'gemini-':'';
   const globalPath=`assistantUsage/${usagePrefix}global-${day}`,userPath=`assistantUsage/${usagePrefix}${hash(uid).slice(0,32)}-${day}`;
   const global=await tx.get(globalPath),user=await tx.get(userPath);
   if((global?.count??0)>=config.dailyRequestLimit || (user?.count??0)>=config.perUserDailyLimit)return {notice:'Quota'};
   tx.set(globalPath,{count:(global?.count??0)+1});tx.set(userPath,{count:(user?.count??0)+1});
   tx.set(requestPath,{fingerprint,state:'Calling',createdAt:this.now(),expiresAt:new Date(this.now()+30*86400000)});return {call:true};
  });}catch(e){this.inFlight--;if(e instanceof HttpError)throw e;return fallback('Unavailable');}
  if(intent.cached){this.inFlight--;const cached=this.replies.get(requestPath);return this.response(cached?.until>this.now() && cached.fingerprint===fingerprint?cached.result:intent.cached,language);}
  if(intent.notice){this.inFlight--;return fallback(intent.notice);}
  let result;
  try{const routed=await this.gateway(config).route(question,config.provider==='Gemini'?history.filter(q=>!needsPersonalSupport(q)):[],language,hash(uid+':'+input.requestId).slice(0,32));
   check(routed && Array.isArray(routed.articleIds) && routed.articleIds.length<=3 && routed.articleIds.every(id=>ids.has(id)) && typeof routed.handoff==='boolean' && (routed.answer===undefined || typeof routed.answer==='string' && routed.answer.length<=2400),'AI_INVALID_REPLY');
   result={articleIds:routed.articleIds,handoff:routed.handoff || (config.provider==='Gemini'?false:base.handoff),mode:'AI',...(routed.answer?{answer:routed.answer}:{})};
   if(config.provider==='Gemini' && !routed.answer)result={...result,mode:'Guide',notice:'OutsideScope'};
  }
  catch(error){result={...base,mode:'Guide',notice:error.message==='AI_QUOTA'?'Quota':'Unavailable'};}
  finally{this.inFlight--;}
  // Generated text is memory-only for 10 minutes. Persist policy IDs, not chat text.
  for(const [key,cached] of this.replies)if(cached.until<=this.now())this.replies.delete(key);
  if(this.replies.size>=100)this.replies.delete(this.replies.keys().next().value);
  const cachedReply={fingerprint,result,until:this.now()+600000};
  this.replies.set(requestPath,cachedReply);
  const cleanup=setTimeout(()=>{if(this.replies.get(requestPath)===cachedReply)this.replies.delete(requestPath);},600000);cleanup.unref?.();
  const durable=result.answer?{articleIds:result.articleIds,handoff:result.handoff,mode:'Guide',notice:'AlreadyAnswered'}:result;
  try{await this.store.atomic(async tx=>{const prior=await tx.get(requestPath);if(prior?.state==='Calling')tx.set(requestPath,{...prior,state:'Complete',result:durable});});}catch{/* No automatic provider retry after ambiguous completion. */}
  return this.response(result,language);
 }
}
