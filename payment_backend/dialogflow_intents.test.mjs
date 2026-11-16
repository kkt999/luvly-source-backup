import test from 'node:test';
import assert from 'node:assert/strict';
import {dialogflowIntentPlan} from './dialogflow_intents.mjs';
import {helpGuide} from './support_assistant.mjs';

test('local Dialogflow training plan covers ten topics, welcome and human handoff in three languages',()=>{
 const plan=dialogflowIntentPlan();assert.equal(plan.length,36);
 assert.equal(new Set(plan.map(p=>p.intent.displayName)).size,12);
 for(const languageCode of ['en','zh-CN','ms']){
  const rows=plan.filter(p=>p.languageCode===languageCode);assert.equal(rows.length,12);
  for(const row of rows){assert.equal(row.intent.webhookState,'WEBHOOK_STATE_DISABLED');assert.equal(row.intent.trainingPhrases.length,10);}
  for(const a of helpGuide.articles){const row=rows.find(r=>r.intent.displayName===`Luvly.faq.${a.id}`);assert.ok(row);assert.equal(row.intent.messages[0].text.text[0],a.answer[{en:'en','zh-CN':'zh',ms:'ms'}[languageCode]]);}
 }
});
