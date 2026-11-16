import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {PromotionService,promotionQuote,validateCampaign,promotionDay,promotionUsePath} from './promotions.mjs';
import {PaymentService} from './payment_service.mjs';
import {PackageRentals} from './package_rentals.mjs';
import {RentalService,variantId,HOLD_MS} from './rental_service.mjs';
import {createHandler} from './http_app.mjs';
class Store{
 data=new Map();queue=Promise.resolve();
 async get(p){return structuredClone(this.data.get(p));}
 async list(c,uid){return [...this.data].filter(([p,v])=>p.startsWith(c+'/')&&(uid===undefined||v.uid===uid)).map(([,v])=>structuredClone(v));}
 atomic(fn){const run=this.queue.then(async()=>{const w=new Map();const result=await fn({get:p=>{assert.equal(w.size,0,'read after write');return this.get(p);},set:(p,v)=>w.set(p,structuredClone(v))});for(const[p,v]of w)this.data.set(p,v);return result;});this.queue=run.catch(()=>{});return run;}
}
const campaign={id:'welcome',revision:0,kind:'Offer',title:'A welcome for your wedding',description:'RM50 off an eligible bridal package.',code:'WELCOME50',discountType:'Fixed',value:5000,maxDiscountCents:0,minimumCents:89900,packageId:'bridal',startDate:'2026-10-01',endDate:'2026-10-31',active:true,banner:true};
const fails=code=>e=>e.code===code;
async function fixture(){
 const store=new Store();let now=Date.parse('2026-10-15T02:00:00Z');
 for(const[p,v]of Object.entries({'staffScheduling/staff':{jobRole:'FrontDesk',serviceTypes:['Dress Trial','Bridal Consultation']},'staff/manager':{active:true,role:'manager'},'staff/staff':{active:true,role:'staff'},'staff/revoked':{active:false,role:'manager'},'brides/bride':{name:'Bride'},'brides/other':{name:'Other'},'servicePackages/bridal':{id:'bridal',active:true},'appointments/visit':{uid:'bride',status:'Completed',assignedStaffId:'staff',startAt:new Date('2026-10-15T02:00:00Z')},'packageAppointments/visit':{selectionId:'selection'},'dresses/gown':{published:true,availability:'Available',sizes:'M'},[`rentalVariants/${variantId('gown','M')}`]:{id:variantId('gown','M'),quantity:5,allocations:{}},'packageSelections/selection':{id:'selection',uid:'bride',customerName:'Bride',packageId:'bridal',name:'Bridal',totalCents:89900,selectedGowns:[{dressId:'gown',size:'M',name:'Gown'}],selectedAccessories:[],services:[],appointmentIds:['visit'],invoiceId:null,rentalPlan:{pickupDate:'2026-10-20',eventDate:'2026-10-21',returnDate:'2026-10-22'},rentalPlanRevision:1}}))store.data.set(p,v);
 const rentals=new RentalService({store,now:()=>now}),payments=new PaymentService({store,rentals,now:()=>now,gateway:{}});
 const promos=new PromotionService({store,access:uid=>payments.access(uid),now:()=>now});
 const workflow=new PackageRentals({store,rentals,now:()=>now,paymentPolicy:true});
 await promos.save('manager',campaign);
 const confirm={appointmentId:'visit',requestId:'attempt',depositCents:42450,planRevision:1};
 async function paid(r){const p=`sandboxInvoices/${r.invoiceId}`,i=store.data.get(p);store.data.set(p,{...i,billCode:'bill',reference:`LV_${r.invoiceId}`});return payments.applyResult(r.invoiceId,'bill',{state:'SandboxPaid',environment:'sandbox',billCode:'bill',reference:`LV_${r.invoiceId}`,amountCents:i.amountCents,invoiceNo:'sandbox-reference'});}
 return {store,promos,rentals,workflow,confirm,paid,now:()=>now,advance:n=>now+=n};
}
test('campaign validation rejects unknown fields, invalid calendar days, price tampering and invalid caps',()=>{
 for(const patch of [{newCustomerOnly:'true'},{startDate:'2026-02-30'},{endDate:'2026-01-01'},{value:-1},{minimumCents:1.5},{discountType:'Percent',value:91},{discountType:'Percent',value:10,maxDiscountCents:0},{code:'bad code'},{active:'true'},{amountCents:1},{packageId:'../bad'}])assert.throws(()=>validateCampaign({...campaign,...patch}));
 assert.equal(promotionDay(Date.parse('2026-10-14T16:00:00Z')),'2026-10-15');
 const q=promotionQuote({...campaign,discountType:'Percent',value:10,maxDiscountCents:6000},'bridal',89900,Date.parse('2026-10-31T15:59:59Z'));
 assert.equal(q.discountCents,6000);assert.equal(q.totalCents,83900);
 assert.throws(()=>promotionQuote(campaign,'bridal',89900,Date.parse('2026-10-31T16:00:00Z')),fails('PROMOTION_UNAVAILABLE'));
 assert.throws(()=>promotionQuote(campaign,'other',89900,Date.parse('2026-10-15')),fails('PROMOTION_PACKAGE'));
 assert.throws(()=>promotionQuote(campaign,'bridal',89899,Date.parse('2026-10-15')),fails('PROMOTION_MINIMUM'));
 assert.throws(()=>promotionQuote({...campaign,value:89800},'bridal',89900,Date.parse('2026-10-15')),fails('PROMOTION_PRICE_REVIEW'));
});
test('manager-only CRUD, immutable unique code, optimistic revisions, deleted and draft campaigns hidden',async()=>{
 const f=await fixture();for(const uid of ['bride','staff','revoked'])await assert.rejects(f.promos.save(uid,{...campaign,id:'other'}),fails('MANAGER_REQUIRED'));
 await assert.rejects(f.promos.save('manager',{...campaign,id:'other'}),fails('PROMOTION_CODE_EXISTS'));
 await assert.rejects(f.promos.save('manager',{...campaign,revision:0}),fails('PROMOTION_CHANGED'));
 await assert.rejects(f.promos.save('manager',{...campaign,revision:1,code:'NEWCODE'}),fails('PROMOTION_CODE_IMMUTABLE'));
 await f.promos.save('manager',{...campaign,id:'draft',code:'DRAFT50',active:false});
 assert.equal((await f.promos.list('bride')).campaigns.length,1);assert.equal((await f.promos.list('staff')).campaigns.length,2);
 assert.equal((await f.promos.list('bride')).campaigns[0].createdBy,undefined);
 await f.promos.remove('manager','welcome',{revision:1});assert.equal((await f.promos.list('bride')).campaigns.length,0);
 await assert.rejects(f.promos.save('manager',{...campaign,id:'new'}),fails('PROMOTION_CODE_EXISTS'));
 await assert.rejects(f.promos.list('revoked'),fails('ACCOUNT_ACCESS_REQUIRED'));
});
test('apply is owner-only, one code replaces rather than stacks, removal restores original and old invoices stay immutable',async()=>{
 const f=await fixture();await assert.rejects(f.promos.apply('other','selection',{code:'WELCOME50',revision:0}),fails('SELECTION_ACCESS_DENIED'));
 await assert.rejects(f.promos.apply('bride','selection',{code:'WELCOME50',revision:0,totalCents:1}),fails('INVALID_PROMOTION'));
 assert.equal((await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0})).totalCents,84900);
 assert.equal((await f.promos.apply('bride','selection',{code:'WELCOME50',revision:1})).totalCents,84900);
 assert.equal((await f.promos.apply('bride','selection',{code:'',revision:2})).totalCents,89900);
 f.store.data.get('packageSelections/selection').invoiceId='legacy';
 await assert.rejects(f.promos.apply('bride','selection',{code:'WELCOME50',revision:3}),fails('PROMOTION_ORDER_LOCKED'));
 assert.equal(f.store.data.has('sandboxInvoices/legacy'),false);
});
test('verified deposit redeems once; balance is based on discounted total, security and fitting credit unchanged',async()=>{
 const f=await fixture();await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 const r=await f.workflow.confirm('staff','selection',f.confirm);
 assert.equal(r.totalCents,84900);assert.equal(r.balanceCents,42450);assert.equal(r.securityCents,30000);
 const path=promotionUsePath('welcome','bride');assert.equal(f.store.data.get(path).state,'Held');
 await f.paid(r);await f.paid(r);assert.equal(f.store.data.get(path).state,'Redeemed');
 assert.equal(f.store.data.get(`sandboxInvoices/${f.store.data.get(`rentals/${r.id}`).balanceInvoiceId}`).amountCents,42450);
 const copy={...f.store.data.get('packageSelections/selection'),id:'new',rentalId:null,invoiceId:null,promotion:null,promotionRevision:0,totalCents:89900};f.store.data.set('packageSelections/new',copy);
 await assert.rejects(f.promos.apply('bride','new',{code:'WELCOME50',revision:0}),fails('PROMOTION_USED'));
});
test('concurrent holds cannot share coupon; expiry releases entitlement; late paid callback cannot consume replacement',async()=>{
 const f=await fixture();await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 const s=f.store.data.get('packageSelections/selection');f.store.data.set('packageSelections/second',{...s,id:'second',appointmentIds:['secondVisit']});
 f.store.data.set('appointments/secondVisit',{...f.store.data.get('appointments/visit')});f.store.data.set('packageAppointments/secondVisit',{selectionId:'second'});
 const attempts=await Promise.allSettled([f.workflow.confirm('staff','selection',f.confirm),f.workflow.confirm('staff','second',{...f.confirm,appointmentId:'secondVisit'})]);
 assert.equal(attempts.filter(v=>v.status==='fulfilled').length,1);assert.equal(attempts[1].reason.code,'PROMOTION_HELD');
 const first=attempts[0].value;
 f.advance(HOLD_MS);await f.rentals.expire(first.id);
 const second=await f.workflow.confirm('staff','second',{...f.confirm,appointmentId:'secondVisit'});
 assert.ok((await f.paid(first)).reviewReason);assert.equal(f.store.data.get(promotionUsePath('welcome','bride')).rentalId,second.id);
 await f.paid(second);assert.equal(f.store.data.get(promotionUsePath('welcome','bride')).state,'Redeemed');
});
test('changed/expired promotion blocks new confirmation without touching stock; held quotation survives campaign deletion',async()=>{
 const f=await fixture();await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 await f.promos.save('manager',{...campaign,revision:1,value:6000});
 await assert.rejects(f.workflow.confirm('staff','selection',f.confirm),fails('PROMOTION_CHANGED'));
 assert.deepEqual(f.store.data.get(`rentalVariants/${variantId('gown','M')}`).allocations,{});
 await f.promos.apply('bride','selection',{code:'WELCOME50',revision:1});
 const r=await f.workflow.confirm('staff','selection',{...f.confirm,depositCents:41950});
 await f.promos.remove('manager','welcome',{revision:2});await f.paid(r);
 assert.equal(f.store.data.get(`rentals/${r.id}`).state,'Locked');
});
test('welcome offer is visible and usable only by accounts in their first 30 days',async()=>{
 const f=await fixture(),day=86400000;
 await f.promos.save('manager',{...campaign,revision:1,newCustomerOnly:true});
 const profile=f.store.data.get('brides/bride');
 for(const createdAt of [undefined, new Date(f.now()+1), new Date(f.now()-30*day)]){
  profile.createdAt=createdAt;
  assert.equal((await f.promos.list('bride')).campaigns.length,0);
  await assert.rejects(f.promos.apply('bride','selection',{code:'WELCOME50',revision:0}),fails('PROMOTION_NEW_CUSTOMER_ONLY'));
 }
 assert.equal((await f.promos.list('manager')).campaigns[0].newCustomerOnly,true);
 profile.createdAt=new Date(f.now()-30*day+1);
 assert.equal((await f.promos.list('bride')).campaigns[0].code,'WELCOME50');
 assert.equal((await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0})).totalCents,84900);
 f.advance(1);
 await assert.rejects(f.workflow.confirm('staff','selection',f.confirm),fails('PROMOTION_NEW_CUSTOMER_ONLY'));
 assert.deepEqual(f.store.data.get(`rentalVariants/${variantId('gown','M')}`).allocations,{});
 assert.equal((await f.promos.apply('bride','selection',{code:'',revision:1})).totalCents,89900);
});
test('welcome quote issued in time is honoured, redeemed offers are hidden and old admin edits keep the restriction',async()=>{
 const f=await fixture(),day=86400000;
 await f.promos.save('manager',{...campaign,revision:1,newCustomerOnly:true});
 await f.promos.save('manager',{...campaign,revision:2,title:'Welcome to Luvly'});
 assert.equal(f.store.data.get('campaigns/welcome').newCustomerOnly,true);
 f.store.data.get('brides/bride').createdAt=new Date(f.now()-30*day+1000);
 await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 const r=await f.workflow.confirm('staff','selection',f.confirm);
 f.advance(1000);
 await f.paid(r);
 assert.equal(f.store.data.get(`rentals/${r.id}`).state,'Locked');
 assert.equal(f.store.data.get(promotionUsePath('welcome','bride')).state,'Redeemed');
 const g=await fixture();
 g.store.data.get('brides/bride').createdAt=new Date(g.now());
 await g.promos.save('manager',{...campaign,revision:1,newCustomerOnly:true});
 await g.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 await g.paid(await g.workflow.confirm('staff','selection',g.confirm));
 assert.equal((await g.promos.list('bride')).campaigns.length,0);
});
test('promotion API requires auth and rejects arbitrary URLs, roles and unknown fields',async()=>{
 const f=await fixture(),server=createServer(createHandler({service:{},promotions:f.promos,verifyToken:async token=>({uid:token})}));
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{const base=`http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(base+'/v1/promotions')).status,401);
  assert.equal((await fetch(base+'/v1/promotions',{method:'POST',headers:{Authorization:'Bearer staff','Content-Type':'application/json'},body:JSON.stringify({...campaign,id:'another'})})).status,403);
  assert.equal((await fetch(base+'/v1/promotions',{method:'POST',headers:{Authorization:'Bearer manager','Content-Type':'application/json'},body:JSON.stringify({...campaign,id:'another',url:'https://external.test'})})).status,400);
 }finally{await new Promise(r=>server.close(r));}
});
test('discount precedes one-time fitting credit, and paid cancellation never silently restores coupon',async()=>{
 const f=await fixture();f.store.data.set('fittingCredits/visit',{uid:'bride',amountCents:5000});
 await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 const r=await f.workflow.confirm('staff','selection',{...f.confirm,depositCents:37450});
 assert.equal(r.fittingCreditCents,5000);assert.equal(r.balanceCents,42450);assert.equal(r.securityCents,30000);
 await f.paid(r);await f.rentals.cancel('staff',r.id);
 assert.equal(f.store.data.get(promotionUsePath('welcome','bride')).state,'Redeemed');
 assert.equal(f.store.data.get(`rentals/${r.id}`).refundReviewRequired,true);
});
test('unpaid cancellation immediately frees coupon use; announcements are scheduled but not redeemable',async()=>{
 const f=await fixture();await f.promos.apply('bride','selection',{code:'WELCOME50',revision:0});
 const r=await f.workflow.confirm('staff','selection',f.confirm);await f.rentals.cancel('staff',r.id);
 f.store.data.set('packageSelections/new',{...f.store.data.get('packageSelections/selection'),id:'new',invoiceId:null,rentalId:null,promotionRevision:0});
 assert.equal((await f.promos.apply('bride','new',{code:'WELCOME50',revision:0})).totalCents,84900);
 const news={...campaign,id:'news',kind:'Announcement',title:'Boutique opening update',code:'',value:0,maxDiscountCents:0,minimumCents:0,packageId:'',startDate:'2026-10-20'};
 await f.promos.save('manager',news);assert.equal((await f.promos.list('bride')).campaigns.some(p=>p.id==='news'),false);
 f.advance(6*86400000);assert.equal((await f.promos.list('bride')).campaigns.some(p=>p.id==='news'),true);
});
