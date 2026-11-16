import {HttpError} from './payment_service.mjs';
import {malaysiaDay} from './booking_dates.mjs';
import {MAX_PACKAGE_GOWNS} from './package_gown_catalogue.mjs';

const valid=(ok)=>{if(!ok)throw new HttpError(400,'INVALID_FITTING_ASSESSMENT');};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>keys.includes(k));
const fit=['NotAssessed','Tight','Good','Loose'];
const text=v=>typeof v==='string'&&v.length<=300&&!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v);
export function validateFittingAssessment(value,selection,{mode,outcome,adjustment,now}) {
  if(value===undefined)return undefined; // Existing clients and historical decisions remain valid.
  valid(mode==='Attended'&&exact(value,['schemaVersion','bodyCm','gowns','followUp','targetDate'])&&value.schemaVersion===1);
  valid(exact(value.bodyCm,['bust','waist','hips'])&&Object.values(value.bodyCm).every(n=>
    typeof n==='number'&&Number.isFinite(n)&&n>=20&&n<=300&&Math.abs(n*10000-Math.round(n*10000))<0.00001));
  valid(Array.isArray(value.gowns)&&value.gowns.length<=MAX_PACKAGE_GOWNS&&value.gowns.length===(selection.selectedGowns??[]).length);
  const seen=new Set();
  const gowns=value.gowns.map(g=>{
    valid(exact(g,['dressId','size','fit','adjustmentNotes'])&&typeof g.dressId==='string'&&!seen.has(g.dressId));
    seen.add(g.dressId);
    valid((selection.selectedGowns??[]).some(s=>s.dressId===g.dressId&&s.size===g.size));
    valid(exact(g.fit,['bust','waist','hips','length'])&&['bust','waist','hips'].every(k=>fit.includes(g.fit[k]))&&
      ['NotAssessed','Long','Good','Short'].includes(g.fit.length)&&text(g.adjustmentNotes)&&(!g.adjustmentNotes.trim()||g.adjustmentNotes.trim().length>=3));
    return {dressId:g.dressId,size:g.size,fit:{bust:g.fit.bust,waist:g.fit.waist,hips:g.fit.hips,length:g.fit.length},adjustmentNotes:g.adjustmentNotes.trim()};
  });
  valid(['NotDecided','Required','NotRequired'].includes(value.followUp));
  const needs=outcome==='Selected'&&adjustment!=='None';
  valid(needs||value.followUp==='NotDecided'&&value.targetDate===null&&gowns.every(g=>!g.adjustmentNotes));
  if(needs)valid(gowns.some(g=>g.adjustmentNotes.length>=3));
  if(value.targetDate!==null){
    valid(typeof value.targetDate==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value.targetDate));
    const day=new Date(`${value.targetDate}T00:00:00Z`);
    valid(Number.isFinite(+day)&&day.toISOString().slice(0,10)===value.targetDate&&value.targetDate>=malaysiaDay(now)&&
      typeof selection.rentalPlan?.pickupDate==='string'&&value.targetDate<=selection.rentalPlan.pickupDate);
  }
  return {schemaVersion:1,bodyCm:{...value.bodyCm},gowns,followUp:value.followUp,targetDate:value.targetDate};
}

// Proposal/customer copy contains garment instructions, never body measurements.
export function fittingAdjustmentPlan(selection){
  const a=selection.fittingDecision?.assessment;
  if(!a||selection.fittingDecision.adjustment==='None')return null;
  return {gowns:a.gowns.filter(g=>g.adjustmentNotes).map(g=>({dressId:g.dressId,size:g.size,
    name:selection.selectedGowns.find(s=>s.dressId===g.dressId)?.name??'Gown',instructions:g.adjustmentNotes})),
    followUp:a.followUp,targetDate:a.targetDate};
}
