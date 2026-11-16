import test from 'node:test';
import assert from 'node:assert/strict';
import {validateFittingAssessment,fittingAdjustmentPlan} from './fitting_assessment.mjs';
import {fittingContext} from './fitting_proposals.mjs';
const selection={selectedGowns:[{dressId:'one',size:'M',name:'Ivory gown'},{dressId:'two',size:'S',name:'Satin gown'}],rentalPlan:{pickupDate:'2026-10-25'}};
const options={mode:'Attended',outcome:'Selected',adjustment:'Basic',now:Date.parse('2026-10-20T02:00:00Z')};
function record(){return {schemaVersion:1,bodyCm:{bust:84.9884},gowns:selection.selectedGowns.map((g,i)=>({dressId:g.dressId,size:g.size,
  fit:{bust:'NotAssessed',waist:i?'Good':'Loose',hips:'NotAssessed',length:i?'Good':'Long'},adjustmentNotes:i?'':'Take in waist by 2 cm; shorten hem after checking shoes.'})),followUp:'Required',targetDate:'2026-10-24'};}
const invalid=e=>e.code==='INVALID_FITTING_ASSESSMENT';
test('optional true measurements and individual gown fit records remain separate; missing data stays unknown',()=>{
  const a=validateFittingAssessment(record(),selection,options);
  assert.deepEqual(a.bodyCm,{bust:84.9884});assert.equal(Object.hasOwn(a.bodyCm,'waist'),false);
  assert.equal(a.gowns[0].fit.waist,'Loose');assert.equal(a.gowns[1].fit.waist,'Good');
  const empty=record();empty.bodyCm={};for(const g of empty.gowns){g.adjustmentNotes='';for(const k of Object.keys(g.fit))g.fit[k]='NotAssessed';}empty.followUp='NotDecided';empty.targetDate=null;
  assert.deepEqual(validateFittingAssessment(empty,selection,{...options,adjustment:'None'}),empty);
  assert.equal(validateFittingAssessment(undefined,selection,options),undefined);
});
test('reject invalid body data, unknown fields, forged sizes, duplicate gowns and unmeasured no-fitting claims',()=>{
  for(const n of [0,-1,19.9,301,NaN,Infinity,'85',null,84.12345]){const a=record();a.bodyCm.bust=n;assert.throws(()=>validateFittingAssessment(a,selection,options),invalid);}
  for(const mutate of [a=>a.bodyCm.height=170,a=>a.uid='other',a=>a.gowns.pop(),a=>a.gowns[0].size='XL',a=>a.gowns[0].dressId='elsewhere',a=>a.gowns[1]=a.gowns[0],a=>a.gowns[0].fit.bust='Perfect',a=>a.gowns[0].fit.rating=100,a=>a.gowns[0].adjustmentNotes='x']){
    const a=record();mutate(a);assert.throws(()=>validateFittingAssessment(a,selection,options),invalid);
  }
  assert.throws(()=>validateFittingAssessment(record(),selection,{...options,mode:'Waived'}),invalid);
});
test('adjustment scope and MYT completion dates must be consistent and cannot silently change decision or money',()=>{
  for(const target of ['2026-10-19','2026-10-26','2026-02-30','2026-10-24T00:00:00Z','tomorrow',undefined]){const a=record();a.targetDate=target;assert.throws(()=>validateFittingAssessment(a,selection,options),invalid);}
  for(const target of ['2026-10-20','2026-10-25',null]){const a=record();a.targetDate=target;assert.equal(validateFittingAssessment(a,selection,options).targetDate,target);}
  const a=record();assert.throws(()=>validateFittingAssessment(a,selection,{...options,adjustment:'None'}),invalid);
  assert.throws(()=>validateFittingAssessment(a,selection,{...options,outcome:'Considering'}),invalid);
  a.gowns[0].adjustmentNotes='';assert.throws(()=>validateFittingAssessment(a,selection,options),invalid);
});
test('customer proposal plan excludes body measurements and fit ratings; changed assessment invalidates context',()=>{
  const a=record(),s={...selection,totalCents:89900,fittingDecision:{outcome:'Selected',adjustment:'Basic',assessment:a}};
  const before=structuredClone(s),plan=fittingAdjustmentPlan(s);
  assert.deepEqual(plan,{gowns:[{dressId:'one',size:'M',name:'Ivory gown',instructions:a.gowns[0].adjustmentNotes}],followUp:'Required',targetDate:'2026-10-24'});
  assert.equal(JSON.stringify(plan).includes('bodyCm'),false);assert.equal(JSON.stringify(plan).includes('84.9884'),false);
  const context=fittingContext(s);s.fittingDecision.assessment.bodyCm.bust=86;assert.notEqual(fittingContext(s),context);
  assert.equal(fittingAdjustmentPlan({...s,fittingDecision:{adjustment:'None'}}),null);
  assert.equal(before.totalCents,s.totalCents);
});
