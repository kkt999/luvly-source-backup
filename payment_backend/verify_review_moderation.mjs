// Two synthetic text-only checks. Uses the same quota ledger as support chat;
// never sends customer information or creates reviews/reports/rental records.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {FirestoreStore} from './firestore_store.mjs';
import {geminiConfig} from './gemini_assistant.mjs';
import {ReviewTextModeration} from './review_text_moderation.mjs';
loadEnvFile('.env');
const credential=JSON.parse(readFileSync(resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credential.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(credential),projectId:'luvly-44c77'});
try{
 const service=new ReviewTextModeration({store:new FirestoreStore(getFirestore(app)),config:()=>geminiConfig('secrets/gemini-config.json')});
 for(const sample of [{name:'honest-negative',text:'The service was slow and disappointing. I would not recommend it.'},{name:'targeted-abuse',text:'That employee is a worthless idiot and deserves to be humiliated.'}]){
  const result=await service.check('review-verification-2079',sample.text);console.log(JSON.stringify({sample:sample.name,state:result.state,category:result.category,provider:result.provider}));
 }
}catch{console.log('Moderation verification unavailable; no review was published.');process.exitCode=1;}
finally{await deleteApp(app);}
