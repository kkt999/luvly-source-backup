import {hasPackageFittingAccess} from './appointment_access.mjs';
import {HttpError} from './payment_service.mjs';
import {packageDates} from './package_rentals.mjs';
import {stockStatus,requireSelectedAvailability} from './rental_availability.mjs';
import {variantId} from './rental_service.mjs';
import {MAX_PACKAGE_GOWNS, packageGownRows, rentableSizes} from './package_gown_catalogue.mjs';
const check=(v,code,status=409)=>{if(!v)throw new HttpError(status,code);};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>keys.includes(k));
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(v);
const active=s=>s?.active===true&&['staff','manager'].includes(s.role);

export async function fittingGownOptions(workflow,uid,selectionId,input){
  check(id(selectionId)&&exact(input,[]) ,'INVALID_GOWN_SELECTION',400);
  return workflow.store.atomic(async tx=>{
    const actor=await tx.get(`staff/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
    check(active(actor),'STAFF_REQUIRED',403);check(!!s,'SELECTION_ACCESS_DENIED',404);
    check(await hasPackageFittingAccess(tx, uid, actor, s),'SELECTION_ACCESS_DENIED',403);
    check(!s.invoiceId&&!s.rentalId,'FITTING_ORDER_LOCKED');
    const p=await tx.get(`servicePackages/${s.packageId}`);
    check(p?.active&&p.revision===s.packageRevision,'PACKAGE_CHANGED');
    check(p.includedGownCount>0,'PACKAGE_GOWN_COUNT');
    const dates=packageDates(s,s.rentalPlan,workflow.now());
    const gowns=await Promise.all((await packageGownRows(tx,p)).map(async d=>{
      const dressId=d.id;
      if(!d?.published||d.availability!=='Available'||typeof d.sizes!=='string')return null;
      const sizes=await Promise.all((p.allCatalogueGowns ? rentableSizes(d) : d.sizes.split(', ')).map(async size=>({size,
        status:stockStatus(await tx.get(`rentalVariants/${variantId(dressId,size)}`),dates,workflow.now())})));
      return {dressId,name:d.name,colour:d.colour,category:d.category,imageUrl:d.imageUrl??'',photoRevision:d.photoRevision??0,revision:d.revision,sizes};
    }));
    return {gowns:gowns.filter(Boolean),includedGownCount:p.includedGownCount,packageRevision:p.revision,
      selectionRevision:s.selectionRevision??0,planRevision:s.rentalPlanRevision??0,reserved:false};
  });
}

export function validateGownChange(input){
  check(exact(input,['gowns','selectionRevision','planRevision','packageRevision'])&&
    ['selectionRevision','planRevision','packageRevision'].every(k=>Number.isSafeInteger(input[k])&&input[k]>=0)&&
    Array.isArray(input.gowns)&&input.gowns.length>0&&input.gowns.length<=MAX_PACKAGE_GOWNS&&
    input.gowns.every(g=>exact(g,['dressId','size','revision'])&&id(g.dressId)&&typeof g.size==='string'&&g.size===g.size.trim()&&g.size.length>0&&g.size.length<=40&&Number.isSafeInteger(g.revision)&&g.revision>0)&&
    new Set(input.gowns.map(g=>g.dressId)).size===input.gowns.length,'INVALID_GOWN_SELECTION',400);
}

// Change only included gowns: no catalogue, price, dates, payment or reservation writes.
export async function prepareFittingGownChange(tx,s,input,uid,now){
  check((s.selectionRevision??0)===input.selectionRevision,'FITTING_SELECTION_CHANGED');
  check((s.rentalPlanRevision??0)===input.planRevision,'RENTAL_PLAN_CHANGED');
  const p=await tx.get(`servicePackages/${s.packageId}`);
  check(p?.active&&p.revision===input.packageRevision&&s.packageRevision===p.revision,'PACKAGE_CHANGED');
  check(input.gowns.length===p.includedGownCount,'PACKAGE_GOWN_COUNT');
  check(input.gowns.some(g=>!(s.selectedGowns??[]).some(old=>old.dressId===g.dressId&&old.size===g.size)), 'FITTING_GOWNS_UNCHANGED');
  check((s.selectionHistory??[]).length<50,'FITTING_SELECTION_LIMIT');
  const selectedGowns=[];
  for(const g of input.gowns){
    check(p.allCatalogueGowns || p.eligibleDressIds?.includes(g.dressId),'PACKAGE_GOWN_NOT_ELIGIBLE');
    const d=await tx.get(`dresses/${g.dressId}`);
    check(d?.published&&d.availability==='Available'&&d.revision===g.revision&&typeof d.sizes==='string'&&
      (p.allCatalogueGowns ? rentableSizes(d) : d.sizes.split(', ')).includes(g.size),'PACKAGE_GOWN_CHANGED');
    selectedGowns.push({dressId:g.dressId,size:g.size,revision:d.revision,name:d.name,colour:d.colour,category:d.category,imageUrl:d.imageUrl??'',photoRevision:d.photoRevision??0});
  }
  const next={...s,selectedGowns,selectionRevision:input.selectionRevision+1,
    selectionHistory:[...(s.selectionHistory??[]),{packageId:s.packageId,name:s.name,rentalPlan:s.rentalPlan,
      selectedGowns:s.selectedGowns??[],selectedAccessories:s.selectedAccessories??[],services:s.services??[],totalCents:s.totalCents,
      reason:'FittingGownChange',by:uid,at:now}]};
  await requireSelectedAvailability(tx,next,packageDates(next,next.rentalPlan,now),now);
  return next;
}
