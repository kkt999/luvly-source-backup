import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
const check=(ok,code,status=400)=>{if(!ok)throw new HttpError(status,code);};
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,100}$/.test(v);
const text=(v,min,max)=>typeof v==='string'&&v===v.trim()&&v.length>=min&&v.length<=max&&!/[\x00-\x1f\x7f]/.test(v);
const cents=v=>Number.isSafeInteger(v)&&v>=0&&v<=100000000;
const fields=['id','revision','kind','title','description','code','discountType','value','maxDiscountCents','minimumCents','packageId','startDate','endDate','active','banner','newCustomerOnly'];
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>keys.includes(k));
const validDay=v=>typeof v==='string'&&/^\d{4}-\d\d-\d\d$/.test(v)&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
export const promotionDay=now=>new Date(now+8*3600000).toISOString().slice(0,10);
const live=(p,now)=>p&&!p.deleted&&p.active&&p.startDate<=promotionDay(now)&&p.endDate>=promotionDay(now);
const welcomeWindowMs=30*24*60*60*1000;
function newCustomer(bride,now){
 const date=bride?.createdAt,created=date instanceof Date?date.getTime():date?.toMillis?.();
 return Number.isSafeInteger(created)&&created>0&&created<=now&&now-created<welcomeWindowMs;
}
export const promotionUsePath=(campaignId,uid)=>`promotionUses/${campaignId}_${createHash('sha256').update(uid).digest('hex').slice(0,32)}`;
export function validateCampaign(p){
 check(exact(p,fields)&&id(p.id)&&Number.isInteger(p.revision)&&p.revision>=0,'INVALID_PROMOTION');
 check(['Offer','Announcement'].includes(p.kind)&&text(p.title,3,80)&&text(p.description,10,500),'INVALID_PROMOTION');
 check(validDay(p.startDate)&&validDay(p.endDate)&&p.startDate<=p.endDate&&typeof p.active==='boolean'&&typeof p.banner==='boolean','INVALID_PROMOTION_DATES');
 check(p.packageId===''||id(p.packageId),'INVALID_PROMOTION');
 check(!Object.hasOwn(p,'newCustomerOnly')||(typeof p.newCustomerOnly==='boolean'&&(!p.newCustomerOnly||p.kind==='Offer')),'INVALID_PROMOTION');
 if(p.kind==='Offer'){
  check(typeof p.code==='string'&&/^[A-Z0-9]{4,20}$/.test(p.code)&&['Fixed','Percent'].includes(p.discountType)&&cents(p.minimumCents),'INVALID_PROMOTION');
  check(Number.isSafeInteger(p.value)&&p.value>0&&(p.discountType==='Percent'?p.value<=90:p.value<=100000000)&&cents(p.maxDiscountCents)&&(p.discountType!=='Percent'||p.maxDiscountCents>=100),'INVALID_PROMOTION_VALUE');
 }else check(p.code===''&&p.discountType==='Fixed'&&p.value===0&&p.minimumCents===0&&p.maxDiscountCents===0,'INVALID_PROMOTION');
 return p;
}
export function promotionQuote(p,packageId,subtotalCents,now){
 check(live(p,now)&&p.kind==='Offer','PROMOTION_UNAVAILABLE',409);
 check(!p.packageId||p.packageId===packageId,'PROMOTION_PACKAGE',409);
 check(cents(subtotalCents)&&subtotalCents>=p.minimumCents,'PROMOTION_MINIMUM',409);
 const discountCents=p.discountType==='Fixed'?p.value:Math.min(Math.floor(subtotalCents*p.value/100),p.maxDiscountCents);
 check(discountCents>=1&&subtotalCents-discountCents>=200,'PROMOTION_PRICE_REVIEW',409);
 return {id:p.id,code:p.code,title:p.title,revision:p.revision,subtotalCents,discountCents,totalCents:subtotalCents-discountCents};
}
async function availableUse(tx,p,uid,now,rentalId){
 const path=promotionUsePath(p.id,uid),use=await tx.get(path);
 check(use?.state!=='Redeemed','PROMOTION_USED',409);
 if(use?.state==='Held'&&use.rentalId!==rentalId&&use.expiresAt>now){
  const old=await tx.get(`rentals/${use.rentalId}`);
  check(['Cancelled','Expired','PaymentReview'].includes(old?.state),'PROMOTION_HELD',409);
 }
 return path;
}
// Read-only preparation: caller commits only after ALL transaction reads.
export async function preparePromotion(tx,selection,rentalId,expiresAt,now){
 if(!selection.promotion)return ()=>{};
 const p=await tx.get(`campaigns/${selection.promotion.id}`);
 const quote=promotionQuote(p,selection.packageId,selection.promotion.subtotalCents,now);
 check(quote.revision===selection.promotion.revision&&quote.discountCents===selection.promotion.discountCents&&quote.totalCents===selection.totalCents,'PROMOTION_CHANGED',409);
 if(p.newCustomerOnly)check(newCustomer(await tx.get('brides/'+selection.uid),now),'PROMOTION_NEW_CUSTOMER_ONLY',409);
 const path=await availableUse(tx,p,selection.uid,now,rentalId);
 return ()=>tx.set(path,{uid:selection.uid,campaignId:p.id,rentalId,expiresAt,state:'Held',updatedAt:now});
}
export async function preparePromotionPaid(tx,rental,now){
 if(!rental.promotion)return {ok:true,commit:()=>{}};
 const path=promotionUsePath(rental.promotion.id,rental.uid),use=await tx.get(path);
 return {ok:use?.state==='Held'&&use.rentalId===rental.id&&use.expiresAt>now,
  commit:()=>tx.set(path,{...use,state:'Redeemed',redeemedAt:now,updatedAt:now})};
}
export class PromotionService{
 constructor({store,access,now=Date.now}){Object.assign(this,{store,access,now});}
 async list(uid){
  const actor=await this.access(uid),rows=await this.store.list('campaigns');
  const now=this.now();
  const campaigns=rows.filter(p=>!p.deleted&&(actor.role!=='bride'||live(p,now))).sort((a,b)=>b.startDate.localeCompare(a.startDate)||a.title.localeCompare(b.title));
  const bride=actor.role==='bride'&&campaigns.some(p=>p.newCustomerOnly)
   ? await this.store.get('brides/'+uid)
   : null;
  // Never expose internal actor metadata or another customer's use record.
  const publicRows=await Promise.all(campaigns.map(async p=>{
   if(actor.role==='bride'&&p.newCustomerOnly){
    if(!newCustomer(bride,now))return null;
    if((await this.store.get(promotionUsePath(p.id,uid)))?.state==='Redeemed')return null;
   }
   const linked=p.packageId?await this.store.get(`servicePackages/${p.packageId}`):null;
   if(actor.role==='bride'&&p.packageId&&!linked?.active)return null;
   return {...Object.fromEntries(fields.map(k=>[k,p[k]])),packageName:linked?.name??(p.packageId?'Linked package unavailable':'All gown packages')};
  }));
  return {campaigns:publicRows.filter(Boolean),limited:rows.length>=100};
 }
 async save(uid,input){
  validateCampaign(input);
  return this.store.atomic(async tx=>{
   const staff=await tx.get(`staff/${uid}`),old=await tx.get(`campaigns/${input.id}`);
   check(staff?.active===true&&staff.role==='manager','MANAGER_REQUIRED',403);
   check(!old?.deleted&&(old?.revision??0)===input.revision,'PROMOTION_CHANGED',409);
   check(!old||(old.code===input.code&&old.kind===input.kind),'PROMOTION_CODE_IMMUTABLE',409);
   const code=input.code?await tx.get(`promotionCodes/${input.code}`):null;
   check(!code||code.id===input.id,'PROMOTION_CODE_EXISTS',409);
   if(input.packageId)check(!!await tx.get(`servicePackages/${input.packageId}`),'PACKAGE_UNAVAILABLE',409);
   // Older manager clients omit the flag when editing. Preserve the saved restriction.
   const next={...input,...(input.newCustomerOnly===undefined&&old?.newCustomerOnly===true?{newCustomerOnly:true}:{}),
    revision:input.revision+1,createdAt:old?.createdAt??this.now(),createdBy:old?.createdBy??uid,updatedAt:this.now(),updatedBy:uid};
   tx.set(`campaigns/${input.id}`,next);
   if(input.code)tx.set(`promotionCodes/${input.code}`,{id:input.id});
   return next;
  });
 }
 async remove(uid,idValue,input){
  check(id(idValue)&&exact(input,['revision'])&&Number.isInteger(input.revision),'INVALID_PROMOTION');
  return this.store.atomic(async tx=>{
   const staff=await tx.get(`staff/${uid}`),p=await tx.get(`campaigns/${idValue}`);
   check(staff?.active===true&&staff.role==='manager','MANAGER_REQUIRED',403);
   check(p&&!p.deleted&&p.revision===input.revision,'PROMOTION_CHANGED',409);
   // Keep a tombstone and code binding: historical discounts and receipts survive.
   tx.set(`campaigns/${idValue}`,{...p,active:false,deleted:true,revision:p.revision+1,updatedAt:this.now(),updatedBy:uid});
   return {deleted:true};
  });
 }
 async apply(uid,selectionId,input){
  check(id(selectionId)&&exact(input,['code','revision'])&&typeof input.code==='string'&&/^(?:[A-Z0-9]{4,20})?$/.test(input.code)&&Number.isInteger(input.revision),'INVALID_PROMOTION');
  return this.store.atomic(async tx=>{
   const staff=await tx.get(`staff/${uid}`),bride=await tx.get(`brides/${uid}`),s=await tx.get(`packageSelections/${selectionId}`);
   check(!staff&&bride&&s?.uid===uid,'SELECTION_ACCESS_DENIED',403);
   check(!s.invoiceId&&!s.rentalId&&s.selectedGowns?.length>0,'PROMOTION_ORDER_LOCKED',409);
   check((s.promotionRevision??0)===input.revision,'PROMOTION_CHANGED',409);
   const subtotal=s.promotion?.subtotalCents??s.totalCents;
   let quote=null;
   if(input.code){
    const ref=await tx.get(`promotionCodes/${input.code}`),p=ref?await tx.get(`campaigns/${ref.id}`):null;
    const now=this.now();
    quote=promotionQuote(p,s.packageId,subtotal,now);
    if(p.newCustomerOnly)check(newCustomer(bride,now),'PROMOTION_NEW_CUSTOMER_ONLY',409);
    await availableUse(tx,p,uid,now);
   }
   const next={...s,promotion:quote,totalCents:quote?.totalCents??subtotal,promotionRevision:input.revision+1};
   tx.set(`packageSelections/${selectionId}`,next);
   return {promotion:quote,totalCents:next.totalCents,revision:next.promotionRevision};
  });
 }
}
