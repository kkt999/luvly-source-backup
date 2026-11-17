import {hasBoutiqueOperationsAccess} from './appointment_access.mjs';
import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
import {validateFittingAssessment,fittingAdjustmentPlan} from './fitting_assessment.mjs';
import {requiresServiceTiming,requiresAccessorySelection} from './package_service_types.mjs';
import {makeupConfirmation,validServiceConfirmation,checkMakeupTrialReferences} from './fitting_makeup.mjs';
const fail=(v,code,status=409)=>{if(!v)throw new HttpError(status,code);};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>keys.includes(k));
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);

async function quoteServicePlan(tx,selection,input) {
  const services=selection.services??[];
  const scheduled=services.filter(requiresServiceTiming);
  const confirmations=input??[];
  const byId=new Map(confirmations.map(row=>[row.serviceId,row]));
  fail(confirmations.length===scheduled.length&&byId.size===scheduled.length&&scheduled.every(service=>byId.has(service.id)),
    'PACKAGE_SERVICE_TIMING_REQUIRED',400);
  if(selection.selectionFlowVersion===1) {
    fail(services.filter(requiresAccessorySelection).every(service=>
      selection.selectedAccessories?.some(item=>item.serviceId===service.id)),
    'PACKAGE_ACCESSORY_SELECTION_REQUIRED');
  }
  return Promise.all(scheduled.map(service=>{
    const row=byId.get(service.id);
    return row.timing===undefined?makeupConfirmation(tx,selection,service,row):
      {serviceId:service.id,name:service.name,timing:row.timing.trim()};
  }));
}
export const fittingContext=s=>createHash('sha256').update(JSON.stringify([s.selectedGowns??[],s.selectedAccessories??[],s.services??[],s.totalCents,s.promotionRevision??0,s.rentalPlanRevision??0,s.selectionRevision??0,s.fittingDecision?.outcome,s.fittingDecision?.adjustment,...(s.fittingDecision?.assessment?[s.fittingDecision.assessment]:[])])).digest('hex');
export function agreedFittingTotal(s) {
  if(s.fittingWorkflowVersion!==2)return s.totalCents;
  const q=s.fittingQuote;
  fail(s.fittingDecision?.state==='Approved'&&q?.state==='Accepted'&&q.context===fittingContext(s)&&q.baseCents===s.totalCents,'FITTING_QUOTE_ACCEPTANCE_REQUIRED');
  fail(Number.isSafeInteger(q.extraCents)&&q.extraCents>=0&&q.totalCents===s.totalCents+q.extraCents&&q.totalCents<=100000000,'FITTING_QUOTE_CHANGED');
  return q.totalCents;
}
export function fittingPresentation(s,{includeSchedules=false}={}){
  const q=s.fittingQuote,current=!!q&&(q.context===fittingContext(s)||!!s.rentalId&&s.fittingAgreedContext===q.context);
  let agreed=s.totalCents;try{agreed=agreedFittingTotal(s);}catch{}
  if(s.rentalId&&s.fittingAgreedContext===q?.context&&Number.isSafeInteger(s.fittingAgreedTotalCents))agreed=s.fittingAgreedTotalCents;
  return {agreedTotalCents:agreed,fittingReady:s.fittingWorkflowVersion===2?current&&q.state==='Accepted'&&s.fittingDecision?.state==='Approved':s.fittingDecision?.state==='Approved',
    fittingQuote:q?{revision:q.revision,baseCents:q.baseCents,extraCents:q.extraCents,totalCents:q.totalCents,lines:q.lines,note:q.note,state:current?q.state:'Outdated',...(q.adjustmentPlan?{adjustmentPlan:q.adjustmentPlan}:{}),...(q.servicePlan?{servicePlan:includeSchedules?q.servicePlan:q.servicePlan.map(({serviceId,name,timing})=>({serviceId,name,timing}))}:{})}:null};
}
async function editable(tx,s) {
  fail(!!s,'SELECTION_ACCESS_DENIED',404);
  fail(!s.invoiceId&&!s.rentalId,'FITTING_ORDER_LOCKED');
}
export async function quoteFitting(workflow,uid,selectionId,input) {
  fail(id(selectionId)&&exact(input,['requestId','revision','decisionRevision','note','lines','serviceConfirmations'])&&id(input.requestId)&&Number.isSafeInteger(input.revision)&&input.revision>=0&&Number.isSafeInteger(input.decisionRevision)&&typeof input.note==='string'&&input.note.trim().length>=10&&input.note.length<=700&&Array.isArray(input.lines)&&input.lines.length<=8&&input.lines.every(l=>exact(l,['description','amountCents'])&&typeof l.description==='string'&&l.description.trim().length>=3&&l.description.length<=150&&Number.isSafeInteger(l.amountCents)&&l.amountCents>=0&&l.amountCents<=10000000),'INVALID_FITTING_QUOTE',400);
  fail(input.serviceConfirmations===undefined||
    Array.isArray(input.serviceConfirmations)&&input.serviceConfirmations.length<=12&&
    input.serviceConfirmations.every(validServiceConfirmation),
    'PACKAGE_SERVICE_TIMING_REQUIRED',400);
  return workflow.store.atomic(async tx=>{
    const actor=await tx.get(`staff/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
    fail(actor?.active===true&&['staff','manager'].includes(actor.role),'STAFF_REQUIRED',403);
    fail(await hasBoutiqueOperationsAccess(tx, uid, actor),'OPERATIONS_ACCESS_REQUIRED',403);
    await editable(tx,s);
    const fingerprint=JSON.stringify([input.revision,input.decisionRevision,input.note.trim(),input.lines,
      ...(input.serviceConfirmations===undefined?[]:[input.serviceConfirmations])]);
    if(s.fittingQuote?.requestId===input.requestId){fail(s.fittingQuote.by===uid&&s.fittingQuote.fingerprint===fingerprint,'REQUEST_CONFLICT');return {fittingQuote:s.fittingQuote};}
    fail(s.fittingWorkflowVersion===2&&s.fittingDecision?.outcome==='Selected'&&s.fittingDecision.state!=='Declined','FITTING_SELECTION_REQUIRED');
    fail((s.fittingQuoteRevision??0)===input.revision&&s.fittingDecisionRevision===input.decisionRevision,'FITTING_QUOTE_CHANGED');
    validateFittingAssessment(s.fittingDecision.assessment,s,{...s.fittingDecision,now:workflow.now()});
    fail(!s.fittingDecision.assessment||s.fittingDecision.adjustment==='None'||s.fittingDecision.assessment.followUp!=='NotDecided','FITTING_FOLLOW_UP_DECISION_REQUIRED');
    const extraCents=input.lines.reduce((sum,l)=>sum+l.amountCents,0);
    fail(extraCents===0||actor.role==='manager','MANAGER_QUOTE_REQUIRED',403);
    fail(s.fittingDecision.adjustment!=='Assessment'||actor.role==='manager','MANAGER_ASSESSMENT_REQUIRED',403);
    fail(s.fittingDecision.adjustment==='None'?input.lines.length===0:input.lines.length>0,'FITTING_ADJUSTMENT_DETAILS_REQUIRED',400);
    const totalCents=s.totalCents+extraCents;fail(Number.isSafeInteger(totalCents)&&totalCents>=200&&totalCents<=100000000,'INVALID_FITTING_QUOTE',400);
    const servicePlan=await quoteServicePlan(tx,s,input.serviceConfirmations);
    const quote={requestId:input.requestId,fingerprint,revision:input.revision+1,context:fittingContext(s),baseCents:s.totalCents,extraCents,totalCents,lines:input.lines.map(l=>({description:l.description.trim(),amountCents:l.amountCents})),note:input.note.trim(),state:'AwaitingCustomer',by:uid,byName:actor.name??'Team',createdAt:workflow.now(),adjustmentPlan:fittingAdjustmentPlan(s),...(servicePlan.length?{servicePlan}:{})};
    tx.set(`packageSelections/${selectionId}`,{...s,fittingQuote:quote,fittingQuoteRevision:quote.revision,fittingQuoteHistory:[...(s.fittingQuoteHistory??[]),...(s.fittingQuote?[s.fittingQuote]:[])].slice(-20),fittingDecision:{...s.fittingDecision,state:'AwaitingCustomer'},fittingDecisionRevision:s.fittingDecisionRevision+1});
    tx.set(`fittingQuoteAudit/${selectionId}_${quote.revision}`,{...quote,uid:s.uid,selectionId});return {fittingQuote:quote};
  });
}
export async function respondFitting(workflow,uid,selectionId,input) {
  fail(id(selectionId)&&exact(input,['revision','response','adjustmentPlanVersion','servicePlanVersion'])&&Number.isSafeInteger(input.revision)&&['Accept','Changes','Considering','Decline'].includes(input.response)&&
    (input.adjustmentPlanVersion===undefined||input.adjustmentPlanVersion===1)&&
    (input.servicePlanVersion===undefined||input.servicePlanVersion===1),'INVALID_FITTING_RESPONSE',400);
  return workflow.store.atomic(async tx=>{
    const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
    fail(!staff&&bride&&s?.uid===uid,'SELECTION_ACCESS_DENIED',403);await editable(tx,s);
    const q=s.fittingQuote;fail(q&&q.revision===input.revision&&q.context===fittingContext(s),'FITTING_QUOTE_CHANGED');
    if(q.response===input.response)return {fittingQuote:fittingPresentation(s).fittingQuote};fail(['AwaitingCustomer','Considering'].includes(q.state),'FITTING_QUOTE_CHANGED');
    if(input.response==='Accept'){
      await checkMakeupTrialReferences(tx,s);
      fail(!q.adjustmentPlan||input.adjustmentPlanVersion===1,'FITTING_PLAN_UPDATE_REQUIRED');
      fail(!q.servicePlan?.length||input.servicePlanVersion===1,'PACKAGE_SERVICE_PLAN_UPDATE_REQUIRED');
      validateFittingAssessment(s.fittingDecision.assessment,s,{...s.fittingDecision,now:workflow.now()});
    }
    const state={Accept:'Accepted',Changes:'ChangesRequested',Considering:'Considering',Decline:'Declined'}[input.response];
    const next={...q,response:input.response,state,respondedBy:uid,respondedAt:workflow.now()};
    tx.set(`packageSelections/${selectionId}`,{...s,fittingQuote:next,fittingDecision:{...s.fittingDecision,state:input.response==='Accept'?'Approved':state},fittingDecisionRevision:s.fittingDecisionRevision+1});
    tx.set(`fittingQuoteResponses/${selectionId}_${q.revision}`,{uid,selectionId,revision:q.revision,response:input.response,at:workflow.now()});return {fittingQuote:fittingPresentation({...s,fittingQuote:next}).fittingQuote};
  });
}
