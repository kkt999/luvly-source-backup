import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { PackageService, validatePackage, priceSelection } from './package_service.mjs';
import { PaymentService } from './payment_service.mjs';
import { createHandler } from './http_app.mjs';
import {variantId,rentalDates} from './rental_service.mjs';
import {packagePaymentQuote} from './bridal_payment_policy.mjs';
import {accessoryCatalogue,priceAccessories} from './accessory_catalogue.mjs';

const initialPackage = () => ({ id: 'essential', revision: 0, name: 'Essential Bridal', description: 'Dress rental and a personal bridal consultation.', basePriceCents: 250000, active: true,
  services: [
    { id: 'dress', name: 'Dress rental', description: 'One dress', kind: 'Required', priceCents: 0 },
    { id: 'styling', name: 'Accessories styling', description: '', kind: 'Optional', priceCents: 15000 },
    { id: 'makeup', name: 'Makeup trial', description: '', kind: 'Add-on', priceCents: 35000 },
  ] });
class MemoryStore {
  constructor() { this.data = new Map(Object.entries({
    'staff/manager': { active: true, role: 'manager' }, 'staff/staff': { active: true, role: 'staff' },
    'staff/revoked': { active: false, role: 'staff' },
    'staffScheduling/staff': { jobRole: 'FrontDesk' },
    'brides/bride': { name: 'Jane', phone: '0123456789', email: 'jane@example.com' },
    'brides/other': { name: 'Other', phone: '0123456789', email: 'other@example.com' },
    'brides/revoked': { name: 'Revoked' },
  })); this.queue = Promise.resolve(); }
  async get(path) { return structuredClone(this.data.get(path)); }
  async activeStaffIds(){return [...this.data].filter(([p,d])=>p.startsWith('staff/')&&d.active&&['staff','manager'].includes(d.role)).map(([p])=>p.split('/')[1]).sort();}
  async listDresses() { return [...this.data].filter(([p]) => p.startsWith('dresses/')).map(([p, d]) => ({ ...structuredClone(d), id: p.split('/')[1] })); }
  async list(collection, uid) { return [...this.data].filter(([path, d]) => path.startsWith(collection + '/') && (uid === undefined || d.uid === uid)).map(([, d]) => structuredClone(d)); }
  atomic(fn) {
    const run = this.queue.then(async () => {
      const writes = new Map();
      const result = await fn({ get: path => { assert.equal(writes.size, 0, 'Firestore reads precede all writes'); return this.get(path); },
        listDresses: () => { assert.equal(writes.size, 0); return this.listDresses(); },
        hasPackageSelections: async id => {assert.equal(writes.size, 0); return [...this.data].some(([path,d])=>path.startsWith('packageSelections/') && d.packageId===id);},
        delete: path => writes.set(path, undefined), set: (path, d) => writes.set(path, structuredClone(d)) });
      for (const [path, d] of writes) {if(d===undefined)this.data.delete(path);else this.data.set(path, d);}
      return result;
    }); this.queue = run.catch(() => {}); return run;
  }
}
const fail = code => e => e.code === code;
const gown = (name = 'Ivory bridal gown') => ({ name, category: 'A-Line', colour: 'Ivory', sizes: 'S, M', description: 'A bridal gown for a fitting.', priceCents: 990000, imageUrl: '', photoRevision: 1, revision: 2, published: true, availability: 'Available' });
async function gownFixture(count = 1) {
  const f = await fixture();
  f.store.data.set('dresses/gown1', gown());
  f.store.data.set('dresses/gown2', gown('Second gown'));
  for (const id of ['gown1', 'gown2']) {
    f.store.data.set(`rentalVariants/${variantId(id, 'M')}`, {quantity: 1, allocations: {}});
  }
  f.packageData = await f.service.save('manager', { ...initialPackage(), revision: 1, includedGownCount: count, eligibleDressIds: ['gown1', 'gown2'] });
  f.input = { ...f.input, revision: 2, gowns: [{ dressId: 'gown1', size: 'M', revision: 2 }] };
  if (count === 2) f.input.gowns.push({ dressId: 'gown2', size: 'S', revision: 2 });
  return f;
}
const now = Date.UTC(2026, 9, 10, 0);
const availabilityPlan={pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18'};
test('all three approved prices preview read-only with catalogue veil upgrades',async()=>{
  const {store,service}=await fixture();
  const rows=[
    ['bridal-essentials',89900,82900,74900,1],
    ['signature-bridal',179900,172900,164900,1],
    ['luxe-bridal',299900,287900,279900,2],
  ];
  for(const [id,old,base,withoutVeil,count] of rows){
    const original={...initialPackage(),id,revision:7,basePriceCents:old,includedGownCount:count,
      allCatalogueGowns:true,eligibleDressIds:[],
      services:[initialPackage().services[0],initialPackage().services[2],
        {id:'veil-accessories',name:'Veil and accessory rental',description:'',kind:'Optional',priceCents:15000}]};
    if(id==='bridal-essentials')original.services[2].id='veil-rental';
    store.data.set(`servicePackages/${id}`,original);
    await assert.rejects(service.approvedPricing('bride',id),fail('MANAGER_REQUIRED'));
    const p=await service.approvedPricing('manager',id);
    validatePackage(p);
    assert.equal(p.revision,7);
    assert.equal(p.includedGownCount,count);
    assert.deepEqual(p.services[1],original.services[1]);
    assert.deepEqual(await store.get(`servicePackages/${id}`),original);
    const v=accessoryCatalogue.version;
    const total=(removed,addons,items)=>{
      const pricing=priceSelection(p,removed,addons);
      return pricing.totalCents+priceAccessories(pricing.services,items,v).accessoryExtraCents;
    };
    const veil=itemId=>({serviceId:'veil-rental',itemId});
    const standard=accessoryCatalogue.items.find(item=>item.id==='veil-short').priceCents;
    const upgraded=accessoryCatalogue.items.find(item=>item.id==='veil-long').priceCents;
    assert.equal(total([],[],[veil('veil-short')]),base);
    assert.equal(total(['veil-rental'],[],[]),withoutVeil);
    assert.equal(total([],[],[veil('veil-long')]),base+upgraded-standard);
    assert.equal(total([],['accessory-rental'],[veil('veil-short'),
      {serviceId:'accessory-rental',itemId:'ring-solitaire'},
      {serviceId:'accessory-rental',itemId:'hair-comb'}]),base+5000);
    assert.throws(()=>total([],[],[veil('ring-halo')]),fail('INVALID_ACCESSORY_SELECTION'));
    assert.throws(()=>total(['veil-rental'],['accessory-rental'],[]),fail('PACKAGE_ACCESSORY_SELECTION_REQUIRED'));
    assert.throws(()=>total(['veil-rental'],[],[veil('veil-long')]),fail('INVALID_ACCESSORY_SELECTION'));
  }
  await assert.rejects(service.approvedPricing('manager','essential'),fail('APPROVED_PACKAGE_PRICING_UNAVAILABLE'));
});
test('approved item pricing charges actual choices and preserves existing allowance records',async()=>{
  const f=await gownFixture(2);
  f.store.data.set(`rentalVariants/${variantId('gown2','S')}`,{quantity:1,allocations:{}});
  const old=await f.service.select('bride',f.input);
  const config={...initialPackage(),revision:2,includedGownCount:2,eligibleDressIds:['gown1','gown2'],
    services:[initialPackage().services[0],
      {id:'veil',name:'Veil Rental',kind:'Optional',description:'',priceCents:8000,serviceType:'package-veil'},
      {id:'extras',name:'Bridal Accessories',kind:'Add-on',description:'',priceCents:0,serviceType:'item-priced-accessories'}]};
  await assert.rejects(f.service.save('manager',config),fail('PACKAGE_ACCESSORY_APPROVAL_REQUIRED'));
  await assert.rejects(f.service.save('manager',{...config,accessoryPricingApproved:true,
    services:[...config.services,initialPackage().services[1]]}),fail('INVALID_PACKAGE_ACCESSORY_PRICING'));
  await f.service.save('manager',{...config,accessoryPricingApproved:true});
  assert.equal((await f.service.catalogue('bride',true)).packages.length,0);
  assert.equal((await f.service.catalogue('bride',true,true)).packages.length,1);
  assert.equal((await f.store.get(`packageSelections/${old.id}`)).totalCents,old.totalCents);
  for(const {id} of accessoryCatalogue.items)f.store.data.set(`accessoryStock/${id}`,{quantity:1,allocations:{}});
  const input={...f.input,revision:3,rentalPlan:availabilityPlan,removedIds:['veil'],addonIds:[],
    expectedTotalCents:242000,accessoryCatalogueVersion:accessoryCatalogue.version};
  let seq=0;
  const save=patch=>f.service.select('bride',{...input,requestId:`item-${++seq}`,...patch});
  assert.equal((await save({})).totalCents,242000);
  await assert.rejects(save({addonIds:['extras']}),fail('PACKAGE_ACCESSORY_SELECTION_REQUIRED'));
  await assert.rejects(save({removedIds:[]}),fail('PACKAGE_ACCESSORY_SELECTION_REQUIRED'));
  const row=(itemId,serviceId='extras')=>({itemId,serviceId});
  const included=await save({removedIds:[],expectedTotalCents:250000,accessories:[row('veil-long','veil')]});
  assert.equal(included.accessoryExtraCents,0);
  await assert.rejects(save({removedIds:[],accessories:[row('veil-short','veil'),row('veil-long','veil')]}),fail('INVALID_ACCESSORY_SELECTION'));
  const tests=[
    [5500,['tiara']],
    [5000,['ring-solitaire','hair-comb']],
    [15000,['tiara','necklace-floral','ring-halo']],
    [17000,['tiara','necklace-floral','ring-halo','earrings-pearl']],
  ];
  for(const [cents,ids] of tests){
    const chosen=await save({addonIds:['extras'],accessories:ids.map(id=>row(id)),expectedTotalCents:242000+cents});
    assert.equal(chosen.accessoryCharges[0].extraCents,cents);
    assert.equal(chosen.accessoryCharges[0].allowanceCents,undefined);
    assert.equal(chosen.totalCents,242000+cents);
    const due=packagePaymentQuote(chosen.totalCents,2,5000);
    assert.equal(due.depositCents,Math.round(chosen.totalCents/2)-5000);
    assert.equal(due.securityCents,60000);
  }
  await assert.rejects(save({addonIds:['extras'],accessories:[row('tiara')]}),fail('PACKAGE_CHANGED'));
  await assert.rejects(save({addonIds:['extras'],accessories:[{...row('tiara'),priceCents:1}]}),fail('INVALID_ACCESSORY_SELECTION'));
  f.store.data.set('accessoryStock/tiara',{quantity:0,allocations:{}});
  await assert.rejects(save({addonIds:['extras'],accessories:[row('tiara')],expectedTotalCents:247500}),fail('RENTAL_STOCK_UNAVAILABLE'));
});
async function availabilityFixture() {
  const f=await gownFixture();
  f.query={packageId:f.packageData.id,revision:2,removedIds:['styling'],addonIds:['makeup'],rentalPlan:availabilityPlan};
  f.variant=`rentalVariants/${variantId('gown1','M')}`;
  f.store.data.set(f.variant,{quantity:1,allocations:{}});
  f.dated={...f.input,rentalPlan:availabilityPlan};
  return f;
}
test('date-first availability is read-only, size-specific and never exposes allocations',async()=>{
  const f=await availabilityFixture(),before=structuredClone([...f.store.data]);
  const result=await f.service.availability('bride',f.query);
  assert.deepEqual(result.gowns[0].sizes,[{size:'S',status:'Unconfirmed'},{size:'M',status:'Available'}]);
  assert.equal(result.reserved,false);
  assert.deepEqual([...f.store.data],before);
  assert.equal(/allocations|quantity|customerName|uid/.test(JSON.stringify(result)),false);
});
test('early stock check includes all cleaning days and excludes expired holds',async()=>{
  const f=await availabilityFixture(),dates=rentalDates(availabilityPlan,now);
  f.store.data.get(f.variant).allocations={other:{state:'Locked',quantity:1,startDay:dates.endDay-1,endDay:dates.endDay+1}};
  const status=async()=>(await f.service.availability('bride',f.query)).gowns[0].sizes[1].status;
  assert.equal(await status(),'Unavailable');
  f.store.data.get(f.variant).allocations.other.startDay=dates.endDay;
  assert.equal(await status(),'Available');
  Object.assign(f.store.data.get(f.variant).allocations.other,{state:'Held',startDay:dates.startDay,expiresAt:now});
  assert.equal(await status(),'Available');
  f.store.data.get(f.variant).allocations.other.expiresAt=now+1;
  assert.equal(await status(),'Unavailable');
});

test('early accessory status distinguishes missing stock, zero stock and overlapping rentals without exposing bookings',async()=>{
  const f=await availabilityFixture(), dates=rentalDates(availabilityPlan,now);
  f.store.data.set('accessoryStock/ring-halo',{quantity:0});
  f.store.data.set('accessoryStock/necklace-pearl',{quantity:1,allocations:{privateBooking:{state:'Locked',quantity:1,startDay:dates.startDay,endDay:dates.endDay}}});
  f.store.data.set('accessoryStock/veil-short',{quantity:1});
  const before=structuredClone([...f.store.data]);
  const result=await f.service.availability('bride',f.query);
  const status=id=>result.accessories.find(a=>a.itemId===id).status;
  assert.equal(status('ring-solitaire'),'Unconfirmed');
  assert.equal(status('ring-halo'),'Unavailable');
  assert.equal(status('necklace-pearl'),'Unavailable');
  assert.equal(status('veil-short'),'Available');
  assert.equal(/privateBooking|allocations|quantity/.test(JSON.stringify(result)),false);
  assert.deepEqual([...f.store.data],before);
});
test('availability validates identity, package revision, services, dates and unknown request fields',async()=>{
  const f=await availabilityFixture();
  for(const uid of ['staff','manager','unknown','revoked'])await assert.rejects(f.service.availability(uid,f.query),fail('BRIDE_REQUIRED'));
  await assert.rejects(f.service.availability('bride',{...f.query,revision:1}),fail('PACKAGE_CHANGED'));
  await assert.rejects(f.service.availability('bride',{...f.query,rentalPlan:{...availabilityPlan,returnDate:'2026-10-20'}}),fail('PACKAGE_RENTAL_PERIOD'));
  await assert.rejects(f.service.availability('bride',{...f.query,rentalPlan:{...availabilityPlan,returnDate:'2026-02-30'}}),fail('INVALID_RENTAL_DATE'));
  await assert.rejects(f.service.availability('bride',{...f.query,quantity:1}),fail('INVALID_SELECTION'));
  await assert.rejects(f.service.availability('bride',{...f.query,removedIds:['dress']}),fail('MANDATORY_SERVICE'));
});
test('dated selection saves dates with gowns atomically, creates no hold and keeps retry identity',async()=>{
  const f=await availabilityFixture(),s=await f.service.select('bride',f.dated);
  assert.deepEqual(s.rentalPlan,availabilityPlan);assert.equal(s.rentalPlanRevision,1);
  assert.equal(s.selectionFlowVersion,1);assert.deepEqual(f.store.data.get(f.variant).allocations,{});
  assert.deepEqual(await f.service.select('bride',f.dated),s);
  await assert.rejects(f.service.select('bride',{...f.dated,rentalPlan:{...availabilityPlan,pickupDate:'2026-10-17'}}),fail('REQUEST_CONFLICT'));
  assert.equal([...f.store.data.keys()].some(p=>/^(rentals|sandboxInvoices)\//.test(p)),false);
});
test('snapshot is not a reservation: competing stock is rechecked at save without partial writes',async()=>{
  const f=await availabilityFixture();await f.service.availability('bride',f.query);
  f.store.data.get(f.variant).quantity=0;
  const before=structuredClone([...f.store.data]);
  await assert.rejects(f.service.select('bride',f.dated),fail('RENTAL_STOCK_UNAVAILABLE'));
  assert.deepEqual([...f.store.data],before);
  f.store.data.delete(f.variant);
  await assert.rejects(f.service.select('bride',f.dated),fail('INVENTORY_NOT_CONFIGURED'));
});
test('date-first booking rechecks stock before any fitting fee or appointment is written',async()=>{
  const f=await availabilityFixture(),s=await f.service.select('bride',f.dated);
  f.store.data.get(f.variant).quantity=0;
  const before=structuredClone([...f.store.data]);
  await assert.rejects(f.service.book('bride',s.id,booking()),fail('RENTAL_STOCK_UNAVAILABLE'));
  assert.deepEqual([...f.store.data],before);
});
test('dated reselection checks revision, stock, visit dates and paid lock before replacing saved choices',async()=>{
  const f=await availabilityFixture(),s=await f.service.select('bride',f.dated);
  const input={requestId:'revise-dates',revision:0,packageRevision:2,removedIds:['styling'],addonIds:['makeup'],gowns:f.input.gowns,accessories:[],previewOnly:true,rentalPlan:availabilityPlan,planRevision:1};
  await assert.rejects(f.service.revise('bride',s.id,{...input,planRevision:0}),fail('RENTAL_PLAN_CHANGED'));
  f.store.data.get(f.variant).quantity=0;
  await assert.rejects(f.service.revise('bride',s.id,input),fail('RENTAL_STOCK_UNAVAILABLE'));
  f.store.data.get(f.variant).quantity=1;
  const saved=f.store.data.get(`packageSelections/${s.id}`);
  saved.appointmentIds=['existing'];f.store.data.set('appointments/existing',{uid:'bride',status:'Confirmed',startAt:new Date('2026-10-16T02:00:00Z')});
  await assert.rejects(f.service.revise('bride',s.id,input),fail('FITTING_DATE_CONFLICT'));
  saved.appointmentIds=[];
  const quote=await f.service.revise('bride',s.id,input);
  await f.service.revise('bride',s.id,{...input,previewOnly:false,expectedTotalCents:quote.totalCents});
  assert.equal(f.store.data.get(`packageSelections/${s.id}`).rentalPlanRevision,2);
  f.store.data.get(`packageSelections/${s.id}`).invoiceId='paid-invoice';
  await assert.rejects(f.service.revise('bride',s.id,input),fail('FITTING_ORDER_LOCKED'));
});
test('availability HTTP route authenticates and rejects query overrides',async t=>{
  const f=await availabilityFixture();
  const server=createServer(createHandler({service:f.payments,packages:f.service,verifyToken:async token=>{if(token!=='bride')throw Error();return {uid:'bride'};}}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>server.close(r)));
  const url=`http://127.0.0.1:${server.address().port}/v1/package-availability`;
  const post=(suffix='',auth=true)=>fetch(url+suffix,{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer bride'}:{})},body:JSON.stringify(f.query)});
  assert.equal((await post('',false)).status,401);
  assert.equal((await post('?uid=other')).status,400);
  const response=await post();assert.equal(response.status,200);assert.equal((await response.json()).reserved,false);
});
test('accessories persist with authoritative extra and invoice; retries cannot alter a paid snapshot', async () => {
  const f = await fixture();
  f.store.data.get('servicePackages/essential').services[1].priceCents = 7000;
  const input = {...f.input, removedIds: [], addonIds: [], accessoryCatalogueVersion: 1,
    accessories: [{serviceId:'styling', itemId:'tiara'}, {serviceId:'styling', itemId:'necklace-floral'}]};
  const selection = await f.service.select('bride', input);
  assert.equal(selection.totalCents, 254500);
  assert.equal(selection.selectedAccessories.length, 2);
  assert.equal(selection.accessoryExtraCents, 4500);
  assert.deepEqual(await f.service.select('bride', input), selection);
  await assert.rejects(f.service.select('bride', {...input, accessories: []}), fail('REQUEST_CONFLICT'));
  f.store.data.set('appointments/accessory-booking', {uid:'bride', status:'Confirmed', startAt: now + 86400000});
  f.store.data.get('packageSelections/' + selection.id).appointmentIds = ['accessory-booking'];
  await assert.rejects(f.service.invoice('staff', selection.id, {appointmentId:'accessory-booking'}),fail('PACKAGE_RENTAL_CONFIRMATION_REQUIRED'));
  f.store.data.get('servicePackages/essential').services[1].priceCents = 99000;
  assert.equal((await f.service.selections('bride')).selections[0].totalCents, 254500);
});
const booking = () => ({ requestId: 'request-book', type: 'Bridal Consultation', startAt: now + 86400000 + 2 * 3600000, notes: 'Please advise on the fitting.' });
async function preparationFixture() {
  const f=await fixture();
  f.selection=await f.service.select('bride',f.input);
  const row=f.store.data.get(`packageSelections/${f.selection.id}`);
  Object.assign(row,{selectedGowns:[{dressId:'gown1',size:'M'}],rentalId:'rental-a',fittingDecision:{state:'Approved'}});
  f.store.data.set('rentals/rental-a',{state:'Locked',paymentState:'DepositPaid',balanceCents:12345});
  f.body={requestId:'prepare-one',revision:0,alteration:'NotRequired',preparation:'Preparing',note:'Check veil and steam the selected gown.'};
  return f;
}
test('service preparation persists only internal progress/audit, not rental, payment or attendance',async()=>{
  const f=await preparationFixture();
  const before=structuredClone([...f.store.data]);
  const result=await f.service.serviceProgress('staff',f.selection.id,f.body);
  assert.equal(result.revision,1);assert.equal(result.by,'staff');
  assert.equal(f.store.data.get(`rentalServiceProgress/${f.selection.id}`).preparation,'Preparing');
  assert.deepEqual([...f.store.data].filter(([path])=>!path.startsWith('rentalServiceProgress')),before);
  assert.equal((await f.service.selections('staff')).selections[0].serviceProgress.note,f.body.note);
  assert.equal(Object.hasOwn((await f.service.selections('bride')).selections[0],'serviceProgress'),false);
  assert.equal([...f.store.data.keys()].filter(p=>p.startsWith('rentalServiceProgressAudit/')).length,1);
});
test('service preparation restricts writes to active staff and rejects client authority/price fields',async()=>{
  const f=await preparationFixture();
  for(const user of ['bride','other','revoked','unknown']) await assert.rejects(f.service.serviceProgress(user,f.selection.id,f.body),fail('STAFF_REQUIRED'));
  for(const patch of [{uid:'bride'},{paymentState:'Paid'},{by:'manager'},{revision:-1},{note:''},{alteration:'Done'},{preparation:'Collected'}]) {
    await assert.rejects(f.service.serviceProgress('staff',f.selection.id,{...f.body,...patch}),fail('INVALID_SERVICE_PROGRESS'));
  }
  assert.equal([...f.store.data.keys()].some(p=>p.startsWith('rentalServiceProgress/')),false);
});
test('preparation has optimistic concurrency and safe same-request retries',async()=>{
  const f=await preparationFixture();
  const result=await f.service.serviceProgress('staff',f.selection.id,f.body);
  assert.deepEqual(await f.service.serviceProgress('staff',f.selection.id,f.body),result);
  await assert.rejects(f.service.serviceProgress('staff',f.selection.id,{...f.body,note:'Changed note'}),fail('REQUEST_CONFLICT'));
  await assert.rejects(f.service.serviceProgress('manager',f.selection.id,f.body),fail('REQUEST_CONFLICT'));
  await assert.rejects(f.service.serviceProgress('staff',f.selection.id,{...f.body,requestId:'stale'}),fail('SERVICE_PROGRESS_CHANGED'));
  const updated=await f.service.serviceProgress('manager',f.selection.id,{...f.body,requestId:'next',revision:1,alteration:'Completed',preparation:'Ready'});
  assert.equal(updated.revision,2);
  assert.equal(f.store.data.get(`rentalServiceProgressAudit/${f.selection.id}_2`).previous.revision,1);
});
test('prepared items require approved fitting, reserved stock and completed/not-needed alterations',async()=>{
  const f=await preparationFixture();
  const ready={...f.body,preparation:'Ready'};
  const row=f.store.data.get(`packageSelections/${f.selection.id}`),rental=f.store.data.get('rentals/rental-a');
  row.fittingDecision=null;
  await assert.rejects(f.service.serviceProgress('staff',f.selection.id,ready),fail('SERVICE_NOT_READY'));
  row.fittingDecision={state:'Approved'};rental.state='Held';
  await assert.rejects(f.service.serviceProgress('staff',f.selection.id,ready),fail('SERVICE_NOT_READY'));
  rental.state='Locked';
  await assert.rejects(f.service.serviceProgress('staff',f.selection.id,{...ready,alteration:'InProgress'}),fail('SERVICE_NOT_READY'));
  await f.service.serviceProgress('staff',f.selection.id,ready);
  assert.equal(rental.paymentState,'DepositPaid'); // Physical preparation is not payment verification.
});
test('collected/returned/cancelled/expired/review rentals lock preparation; missing items cannot be prepared',async()=>{
  for(const patch of [{fulfilment:'Collected'},{fulfilment:'Returned'},{collectedAt:now},{returnedAt:now},{state:'Cancelled'},{state:'Expired'},{state:'PaymentReview'}]){
    const f=await preparationFixture();Object.assign(f.store.data.get('rentals/rental-a'),patch);
    await assert.rejects(f.service.serviceProgress('staff',f.selection.id,f.body),fail('SERVICE_PROGRESS_CLOSED'));
  }
  const f=await preparationFixture();f.store.data.get(`packageSelections/${f.selection.id}`).selectedGowns=[];
  await assert.rejects(f.service.serviceProgress('staff',f.selection.id,f.body),fail('SERVICE_ITEMS_REQUIRED'));
});
test('service preparation HTTP endpoint requires authentication and rejects scope query',async()=>{
  const f=await preparationFixture();
  const server=createServer(createHandler({service:f.payments,packages:f.service,verifyToken:async token=>({uid:token})}));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try{
    const url=`http://127.0.0.1:${server.address().port}/v1/package-selections/${f.selection.id}/service-progress`;
    const send=(suffix='',token)=>fetch(url+suffix,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:JSON.stringify(f.body)});
    assert.equal((await send()).status,401);
    assert.equal((await send('?uid=manager','staff')).status,400);
    assert.equal((await send('','bride')).status,403);
    assert.equal((await send('','staff')).status,200);
  }finally{await new Promise(resolve=>server.close(resolve));}
});
test('a replacement rental never inherits old preparation, while revision and audit are retained',async()=>{
  const f=await preparationFixture();
  await f.service.serviceProgress('staff',f.selection.id,{...f.body,preparation:'Ready'});
  f.store.data.get(`packageSelections/${f.selection.id}`).rentalId='replacement';
  f.store.data.set('rentals/replacement',{state:'Locked'});
  const row=(await f.service.selections('staff')).selections[0];
  assert.equal(row.serviceProgress,null);assert.equal(row.serviceProgressRevision,1);
  const next=await f.service.serviceProgress('staff',f.selection.id,{...f.body,requestId:'replacement-prep',revision:1});
  assert.equal(next.rentalId,'replacement');assert.equal(next.revision,2);
  assert.equal(f.store.data.get(`rentalServiceProgressAudit/${f.selection.id}_2`).previous.preparation,'Ready');
});
async function fixture() {
  const store = new MemoryStore();
  for(let d=0;d<180;d++)store.data.set(`appointmentAvailability/${new Date(now+d*86400000).toISOString().slice(0,10)}`,{entries:{staff:{available:true,startHour:10,endHour:17}},bookings:{},revision:1});
  const gateway = { createBill: async x => ({ reference: x.reference, amountCents: x.amountCents, billCode: 'test123', checkoutUrl: 'https://dev.toyyibpay.com/test123', environment: 'sandbox' }),
    reconcile: async x => ({ state: 'SandboxPaid', environment: 'sandbox', reference: x.reference, billCode: x.billCode, amountCents: x.amountCents, invoiceNo: 'TEST-RECEIPT' }) };
  const payments = new PaymentService({ store, gateway, returnUrl: 'https://example.com/return', callbackUrl: 'https://example.com/callback', now: () => now });
  const service = new PackageService({ store, paymentService: payments, now: () => now });
  const packageData = await service.save('manager', initialPackage());
  const input = { requestId: 'choose-1', packageId: packageData.id, revision: 1, removedIds: ['styling'], addonIds: ['makeup'] };
  return { store, gateway, payments, service, packageData, input };
}
test('standard and customized totals; required removal, unknown add-ons and duplicates rejected', () => {
  const p = initialPackage();
  assert.equal(priceSelection(p, [], []).totalCents, 250000);
  assert.equal(priceSelection(p, ['styling'], ['makeup']).totalCents, 270000);
  for (const [removed, added, error] of [[['dress'], [], 'MANDATORY_SERVICE'], [[], ['unknown'], 'INVALID_ADDON'], [[], ['makeup', 'makeup'], 'DUPLICATE_SERVICE'], [['styling', 'styling'], [], 'DUPLICATE_SERVICE']]) assert.throws(() => priceSelection(p, removed, added), fail(error));
});

test('gown catalogue authenticates, filters unpublished/unavailable and exposes only public fields', async () => {
  const f = await gownFixture();
  f.store.data.set('dresses/private', { ...gown(), published: false });
  f.store.data.set('dresses/unavailable', { ...gown(), availability: 'Unavailable' });
  f.store.data.get('dresses/gown1').internalNotes = 'not public';
  const result = await f.service.gowns('bride');
  assert.deepEqual(result.dresses.map(d => d.id), ['gown1', 'gown2']);
  assert(!Object.hasOwn(result.dresses[0], 'internalNotes'));
  await assert.rejects(f.service.gowns('revoked'), fail('ACCOUNT_ACCESS_REQUIRED'));
});

test('staff assistance is not a selectable gown size', async () => {
  const f = await gownFixture();
  const before = [...f.store.data.keys()].filter(k => k.startsWith('rentalVariants/'));
  await assert.rejects(f.service.select('bride', { ...f.input, gowns: [{ ...f.input.gowns[0], size: 'Staff to confirm' }] }), fail('PACKAGE_GOWN_SIZE'));
  assert.deepEqual([...f.store.data.keys()].filter(k => k.startsWith('rentalVariants/')), before);
});

test('included gowns and sizes are snapshotted without adding catalogue prices; retries are safe', async () => {
  const f = await gownFixture(2);
  const saved = await f.service.select('bride', f.input);
  assert.equal(saved.totalCents, 270000);
  assert.equal(saved.includedGownCount, 2);
  assert.deepEqual(saved.selectedGowns.map(g => [g.name, g.size]), [['Ivory bridal gown', 'M'], ['Second gown', 'S']]);
  f.store.data.get('dresses/gown1').name = 'Changed later';
  const retry = await f.service.select('bride', { ...f.input, gowns: [...f.input.gowns].reverse() });
  assert.equal(retry.id, saved.id);
  assert.equal(retry.selectedGowns[0].name, 'Ivory bridal gown');
  await assert.rejects(f.service.select('bride', { ...f.input, gowns: [{ ...f.input.gowns[0], size: 'S' }, f.input.gowns[1]] }), fail('REQUEST_CONFLICT'));
  f.store.data.get(`packageSelections/${saved.id}`).rentalPlan={pickupDate:'2026-10-16',eventDate:'2026-10-17',returnDate:'2026-10-18'};
  const a = await f.service.book('bride', saved.id, booking());
  f.store.data.get(`appointments/${a.appointmentId}`).status = 'Confirmed';
  await assert.rejects(f.service.invoice('manager', saved.id, { appointmentId: a.appointmentId }),fail('PACKAGE_RENTAL_CONFIRMATION_REQUIRED'));
  await assert.rejects(f.payments.createQuote('manager', { appointmentId: a.appointmentId, purpose: 'DressPayment', amountCents: 990000 }), fail('APPOINTMENT_HAS_PACKAGE'));
});

test('gown selection rejects missing, repeated, forged, wrong-size, stale and ineligible choices', async () => {
  const f = await gownFixture();
  const choice = f.input.gowns[0];
  for (const [gowns, code] of [
    [[], 'PACKAGE_GOWN_COUNT'],
    [[choice, choice], 'INVALID_GOWN_SELECTION'],
    [[{ ...choice, priceCents: 0 }], 'INVALID_GOWN_SELECTION'],
    [[{ ...choice, dressId: 'not-in-package' }], 'PACKAGE_GOWN_NOT_ELIGIBLE'],
    [[{ ...choice, size: 'XL' }], 'PACKAGE_GOWN_SIZE'],
    [[{ ...choice, revision: 1 }], 'PACKAGE_GOWN_CHANGED'],
  ]) await assert.rejects(f.service.select('bride', { ...f.input, gowns }), fail(code));
  for (const change of [{ published: false }, { availability: 'Unavailable' }]) {
    f.store.data.set('dresses/gown1', { ...gown(), ...change });
    await assert.rejects(f.service.select('bride', f.input), fail('PACKAGE_GOWN_UNAVAILABLE'));
  }
  f.store.data.delete('dresses/gown1');
  await assert.rejects(f.service.select('bride', f.input), fail('PACKAGE_GOWN_UNAVAILABLE'));
  assert.equal((await f.service.selections('bride')).selections.length, 0);
});
test('rental package booking rejects a fitting after the wedding before writing an appointment',async()=>{
  const f=await gownFixture(),s=await f.service.select('bride',f.input);
  await assert.rejects(f.service.book('bride',s.id,{...booking(),startAt:Date.parse('2026-10-18T02:00:00Z')}),fail('RENTAL_PLAN_REQUIRED'));
  f.store.data.get(`packageSelections/${s.id}`).rentalPlan={pickupDate:'2026-10-19',eventDate:'2026-10-20',returnDate:'2026-10-21'};
  for(const startAt of [Date.parse('2026-10-19T02:00:00Z'),Date.parse('2026-10-21T02:00:00Z')]) {
    await assert.rejects(f.service.book('bride',s.id,{...booking(),startAt}),fail('FITTING_DATE_CONFLICT'));
  }
  assert.equal(f.store.data.get(`packageSelections/${s.id}`).appointmentIds.length,0);
  const result=await f.service.book('bride',s.id,{...booking(),startAt:Date.parse('2026-10-18T02:00:00Z')});
  assert.ok(result.appointmentId);
});

test('gown eligibility config validates counts and IDs and blocks stale clients from clearing entitlement', async () => {
  for (const fields of [{ includedGownCount: -1 }, { includedGownCount: 101 }, { includedGownCount: '1' },
    { includedGownCount: 1, eligibleDressIds: ['x', 'x'] }, { includedGownCount: 0, eligibleDressIds: ['x'] }]) {
    assert.throws(() => validatePackage({ ...initialPackage(), ...fields }), fail('INVALID_PACKAGE_GOWNS'));
  }
  const f = await gownFixture();
  await assert.rejects(f.service.save('manager', { ...initialPackage(), revision: 2 }), fail('PACKAGE_CLIENT_UPDATE_REQUIRED'));
  await assert.rejects(f.service.save('manager', { ...initialPackage(), revision: 2, includedGownCount: 1, eligibleDressIds: ['missing'] }), fail('PACKAGE_GOWN_UNAVAILABLE'));
});
test('draft stays hidden and publishing requires enough distinct stocked, published gowns', async () => {
  const f = await fixture();
  const variant = id => `rentalVariants/${variantId(id, 'M')}`;
  f.store.data.set('dresses/first', gown());
  f.store.data.set('dresses/second', { ...gown(), published: false });
  f.store.data.set(variant('first'), {quantity: 3});
  const input = { ...initialPackage(), id: 'duo', active: false, includedGownCount: 2, eligibleDressIds: ['first'] };
  const draft = await f.service.save('manager', input);
  assert.equal(draft.draft, true);
  assert.equal((await f.service.catalogue('bride')).packages.some(p => p.id === input.id), false);
  const publish = {...input, active: true, revision: 1};
  await assert.rejects(f.service.save('manager', publish), fail('PACKAGE_GOWNS_NOT_READY'));
  publish.eligibleDressIds = ['first', 'second'];
  f.store.data.set(variant('second'), {quantity: 1});
  await assert.rejects(f.service.save('manager', publish), fail('PACKAGE_GOWNS_NOT_READY'));
  f.store.data.get('dresses/second').published = true;
  f.store.data.set(variant('second'), {quantity: 0});
  await assert.rejects(f.service.save('manager', publish), fail('PACKAGE_GOWNS_NOT_READY'));
  f.store.data.set(variant('second'), {quantity: 1});
  const published = await f.service.save('manager', publish);
  assert.equal(published.draft, false);
  assert.equal((await f.service.catalogue('bride')).packages.some(p => p.id === input.id), true);
  f.store.data.delete('dresses/second');
  const paused = await f.service.save('manager', {...publish, revision: 2, active: false});
  assert.equal(paused.active, false);
  assert.equal(paused.draft, false);
});
test('catalogue-wide packages allow four stocked styles and follow changes in stock', async () => {
  const f = await fixture();
  const ids = ['first', 'second', 'third', 'fourth'];
  const variant = id => `rentalVariants/${variantId(id, 'M')}`;
  for (const id of ids) {
    f.store.data.set(`dresses/${id}`, gown(id));
    f.store.data.set(variant(id), {quantity: 3});
  }
  f.store.data.set('dresses/fifth', gown('fifth'));
  f.store.data.set(variant('fifth'), {quantity: 0});
  f.store.data.set('dresses/hidden', {...gown(), published: false});
  f.store.data.set(variant('hidden'), {quantity: 1});
  f.store.data.set('dresses/custom', {...gown(), sizes: 'Made to measure'});
  f.store.data.set(`rentalVariants/${variantId('custom', 'Made to measure')}`, {quantity: 1});
  f.store.data.set('dresses/unavailable', {...gown(), availability: 'Unavailable'});
  f.store.data.set(variant('unavailable'), {quantity: 1});
  assert.deepEqual(await f.service.gownLimit('manager'), {maxGowns: 4});
  await assert.rejects(f.service.gownLimit('staff'), fail('MANAGER_REQUIRED'));
  const input = {...initialPackage(), revision: 1, allCatalogueGowns: true,
    includedGownCount: 4, eligibleDressIds: []};
  for (const active of [false, true]) {
    await assert.rejects(f.service.save('manager', {...input, active, includedGownCount: 5}),
      fail('PACKAGE_GOWN_LIMIT_CHANGED'));
  }
  const published = await f.service.save('manager', input);
  assert.deepEqual(published.eligibleDressIds, []);
  const selection = {...f.input, revision: published.revision, rentalPlan: availabilityPlan,
    gowns: ids.map(dressId => ({dressId, size: 'M', revision: 2}))};
  const query = {packageId: selection.packageId, revision: selection.revision,
    removedIds: selection.removedIds, addonIds: selection.addonIds, rentalPlan: selection.rentalPlan};
  const availableIds = async () => (await f.service.availability('bride', query)).gowns
    .filter(dress => dress.sizes.some(size => size.status === 'Available')).map(dress => dress.dressId);
  assert.deepEqual(await availableIds(), ids);
  const saved = await f.service.select('bride', selection);
  assert.deepEqual(saved.selectedGowns.map(dress => dress.dressId), ids);
  assert.equal(packagePaymentQuote(saved.totalCents, saved.selectedGowns.length).securityCents, 120000);
  f.store.data.set(variant('fourth'), {quantity: 0});
  await assert.rejects(f.service.select('bride', {...selection, requestId: 'no-stock'}),
    fail('RENTAL_STOCK_UNAVAILABLE'));
  f.store.data.set(variant('fifth'), {quantity: 1});
  assert.deepEqual(await availableIds(), [...ids.slice(0, 3), 'fifth']);
  assert.deepEqual(await f.service.gownLimit('manager'), {maxGowns: 4});
});
test('typed services drive rental days and accessory charges independently of their display name', async () => {
  const f = await availabilityFixture();
  const services = [
    ...initialPackage().services,
    {id: 'veil', name: 'Ceremony finish', kind: 'Required', description: '', priceCents: 0,
      serviceType: 'veil-rental', accessoryAllowanceCents: 6000},
    {id: 'day', name: 'Extend rental by one day', kind: 'Add-on', description: '', priceCents: 8000,
      serviceType: 'extra-rental-day'},
  ];
  const updated = await f.service.save('manager', {
    ...initialPackage(), revision: 2, includedGownCount: 1,
    eligibleDressIds: ['gown1', 'gown2'], services,
  });
  assert.equal((await f.service.catalogue('bride')).packages.length, 0);
  assert.equal((await f.service.catalogue('bride', true)).packages[0].revision, updated.revision);
  assert.equal((await f.service.catalogue('staff')).packages.length, 1);
  const plan = {...availabilityPlan, returnDate: '2026-10-19'};
  f.store.data.set('accessoryStock/veil-short', {quantity: 1, allocations: {}});
  const input = {...f.dated, revision: updated.revision, removedIds: ['styling'], addonIds: ['day'],
    rentalPlan: plan, accessories: [{serviceId: 'veil', itemId: 'veil-short'}], accessoryCatalogueVersion: 1};
  await assert.rejects(f.service.select('bride', input), fail('PACKAGE_CLIENT_UPDATE_REQUIRED'));
  await assert.rejects(f.service.select('bride', {...input, expectedTotalCents: 243000}), fail('PACKAGE_CHANGED'));
  const total = 250000 - 15000 + 8000 + 2000;
  const saved = await f.service.select('bride', {...input, expectedTotalCents: total});
  assert.equal(saved.totalCents, total);
  assert.equal(saved.accessoryCharges.find(c => c.serviceId === 'veil').extraCents, 2000);
  assert.equal(saved.rentalPlan.returnDate, plan.returnDate);
  const oldClientRows = services.map(({serviceType, accessoryAllowanceCents, ...s}) => s);
  await assert.rejects(f.service.save('manager', {
    ...initialPackage(), revision: 3, includedGownCount: 1,
    eligibleDressIds: ['gown1', 'gown2'], services: oldClientRows,
  }), fail('PACKAGE_CLIENT_UPDATE_REQUIRED'));
});
test('invalid prices, services, missing fields and unexpected fields cannot enter catalogue', () => {
  const cases = [p => p.basePriceCents = -1, p => p.basePriceCents = '250000', p => p.basePriceCents = 15000,
    p => p.services[0].kind = 'Optional', p => p.services.push({ ...p.services[0] }), p => p.name = '  Wedding ',
    p => p.services[1].priceCents = 1.5, p => p.uid = 'attacker', p => p.services[0].priceCents = 100, p => p.services = []];
  for (const mutate of cases) { const p = initialPackage(); mutate(p); assert.throws(() => validatePackage(p)); }
});
test('only active managers manage packages; staff retain read-only catalogue access', async () => {
  const f = await fixture();
  await f.service.save('manager', { ...f.packageData, createdAt: undefined }).catch(e => assert.equal(e.code, 'INVALID_PACKAGE'));
  for (const uid of ['staff', 'bride', 'other', 'revoked', 'unknown']) {
    await assert.rejects(f.service.save(uid, initialPackage()), fail('MANAGER_REQUIRED'));
    await assert.rejects(f.service.save(uid, {...initialPackage(),revision:1,active:false}), fail('MANAGER_REQUIRED'));
  }
  assert.equal((await f.service.catalogue('staff')).packages.length,1);
  const updated = await f.service.save('manager', { ...initialPackage(), revision: 1, name: 'Revised Bridal' });
  assert.equal(updated.revision, 2); assert.equal(updated.updatedBy, 'manager');
  await assert.rejects(f.service.save('manager', { ...initialPackage(), revision: 1 }), fail('PACKAGE_CHANGED'));
  f.store.data.get('staff/manager').active=false;
  await assert.rejects(f.service.save('manager', {...initialPackage(),revision:2}),fail('MANAGER_REQUIRED'));
});
test('inactive packages are hidden from brides; old selections and prices remain intact', async () => {
  const f = await fixture(); const selected = await f.service.select('bride', f.input);
  await f.service.save('manager', { ...initialPackage(), revision: 1, active: false, basePriceCents: 300000 });
  assert.equal((await f.service.catalogue('bride')).packages.length, 0);
  assert.equal((await f.service.catalogue('staff')).packages.length, 1);
  assert.equal((await f.service.selections('bride')).selections[0].totalCents, selected.totalCents);
  await assert.rejects(f.service.select('bride', { ...f.input, requestId: 'new' }), fail('PACKAGE_UNAVAILABLE'));
  assert.equal((await f.service.select('bride', f.input)).id, selected.id);
});

test('manager deletion rejects all non-managers and stale versions, deletes only unused packages with audit snapshot', async () => {
  const f=await fixture(), before=structuredClone([...f.store.data]);
  for(const uid of ['staff','revoked','bride','unknown']) await assert.rejects(f.service.remove(uid,'essential',{revision:1}),fail('MANAGER_REQUIRED'));
  await assert.rejects(f.service.remove('manager','essential',{revision:2}),fail('PACKAGE_CHANGED'));
  await assert.rejects(f.service.remove('manager','essential',{revision:1,force:true}),fail('INVALID_PACKAGE'));
  assert.deepEqual([...f.store.data],before);
  assert.deepEqual(await f.service.remove('manager','essential',{revision:1}),{deleted:true,packageId:'essential'});
  assert.equal(await f.store.get('servicePackages/essential'),undefined);
  assert.equal((await f.service.catalogue('staff')).packages.length,0);
  const audit=(await f.store.list('packageCatalogueAudit'))[0];
  assert.equal(audit.actorId,'manager');assert.equal(audit.snapshot.name,initialPackage().name);
  await assert.rejects(f.service.select('bride',f.input),fail('PACKAGE_UNAVAILABLE'));
});

test('referenced packages cannot be deleted; deactivation retains customer plans and invoices', async()=>{
  const f=await fixture(), selected=await f.service.select('bride',f.input);
  const before=structuredClone([...f.store.data]);
  await assert.rejects(f.service.remove('manager','essential',{revision:1}),fail('PACKAGE_IN_USE'));
  assert.deepEqual([...f.store.data],before);
  await f.service.save('manager',{...initialPackage(),revision:1,active:false});
  await assert.rejects(f.service.remove('manager','essential',{revision:2}),fail('PACKAGE_IN_USE'));
  assert.deepEqual((await f.service.selections('bride')).selections[0].totalCents,selected.totalCents);
});

test('concurrent customer selection and deletion cannot create an orphaned plan',async()=>{
  for(const deleteFirst of [false,true]){
    const f=await fixture();
    const actions=deleteFirst
      ? [()=>f.service.remove('manager','essential',{revision:1}),()=>f.service.select('bride',f.input)]
      : [()=>f.service.select('bride',f.input),()=>f.service.remove('manager','essential',{revision:1})];
    const results=await Promise.allSettled(actions.map(run=>run()));
    assert.equal(results[0].status,'fulfilled');assert.equal(results[1].status,'rejected');
    assert.equal(results[1].reason.code,deleteFirst?'PACKAGE_UNAVAILABLE':'PACKAGE_IN_USE');
  }
});
test('price changes require a fresh review; client price and owner overrides rejected', async () => {
  const f = await fixture();
  await f.service.save('manager', { ...initialPackage(), revision: 1, basePriceCents: 300000 });
  await assert.rejects(f.service.select('bride', f.input), fail('PACKAGE_CHANGED'));
  for (const fields of [{ uid: 'other' }, { totalCents: 1 }, { removedIds: null }]) await assert.rejects(f.service.select('bride', { ...f.input, ...fields }), fail('INVALID_SELECTION'));
});
test('selection retries and concurrent submissions produce one immutable selection', async () => {
  const f = await fixture();
  const values = await Promise.all([f.service.select('bride', f.input), f.service.select('bride', f.input)]);
  assert.equal(values[0].id, values[1].id);
  assert.equal((await f.service.selections('bride')).selections.length, 1);
  await assert.rejects(f.service.select('bride', { ...f.input, addonIds: [] }), fail('REQUEST_CONFLICT'));
});
test('customer selections are isolated; staff cannot impersonate bride and revocation applies', async () => {
  const f = await fixture(); await f.service.select('bride', f.input);
  assert.equal((await f.service.selections('other')).selections.length, 0);
  assert.equal((await f.service.selections('staff')).selections.length, 1);
  for (const uid of ['staff', 'manager', 'revoked']) await assert.rejects(f.service.select(uid, f.input), fail('BRIDE_REQUIRED'));
  await assert.rejects(f.service.selections('revoked'), fail('ACCOUNT_ACCESS_REQUIRED'));
});
test('package booking stores server contact, request state and selection link; retries are idempotent', async () => {
  const f = await fixture(); const s = await f.service.select('bride', f.input);
  const a = await f.service.book('bride', s.id, booking());
  assert.deepEqual(await f.service.book('bride', s.id, booking()), a);
  const saved = await f.store.get(`appointments/${a.appointmentId}`);
  assert.equal(saved.status, 'Confirmed'); assert.equal(saved.name, 'Jane'); assert.match(saved.notes, /Essential Bridal/);
  assert.deepEqual((await f.service.selections('bride')).selections[0].appointments.map(b => b.status), ['Confirmed']);
  await assert.rejects(f.service.book('other', s.id, booking()), fail('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.service.book('bride', s.id, { ...booking(), requestId: 'duplicate' }), fail('PACKAGE_BOOKING_EXISTS'));
});
test('past, outside-hours, occupied and forged package bookings are rejected', async () => {
  const f = await fixture(); const s = await f.service.select('bride', f.input);
  for (const changes of [{ startAt: now - 1 }, { startAt: now + 3600000 }, { startAt: booking().startAt + 1 }, { notes: 'x'.repeat(701) }, { uid: 'other' }]) await assert.rejects(f.service.book('bride', s.id, { ...booking(), ...changes }), fail('INVALID_BOOKING'));
  f.store.data.set(`appointmentSlots/${booking().startAt}`, { appointmentId: 'occupied' });
  await assert.rejects(f.service.book('bride', s.id, booking()), fail('SLOT_UNAVAILABLE'));
});
test('package and standalone bookings share the same atomic boutique capacity',async()=>{
 const f=await fixture(),s=await f.service.select('bride',f.input);
 const results=await Promise.allSettled([
   f.service.book('bride',s.id,booking()),
   f.service.bookings.create('other',{requestId:'standalone',type:'Dress Trial',startAt:booking().startAt,notes:''}),
 ]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(results.find(r=>r.status==='rejected').reason.code,'SLOT_UNAVAILABLE');
});
test('linked visits follow the same appointment access policy', async () => {
  const f = await fixture();
  const selection = await f.service.select('bride', f.input);
  const visit = await f.service.book('bride', selection.id, {...booking(), type:'Dress Trial'});
  const row = f.store.data.get(`appointments/${visit.appointmentId}`);
  f.store.data.set('staff/artist', {active:true,role:'staff'});
  f.store.data.set('staffScheduling/artist', {jobRole:'MakeupArtist'});
  for (const uid of ['staff','manager','bride']) {
    assert.equal((await f.service.selections(uid)).selections[0].appointments[0].id,visit.appointmentId);
  }
  assert.deepEqual((await f.service.selections('artist')).selections,[]);
  await assert.rejects(f.service.assignedFitting('artist',selection.id),fail('SELECTION_ACCESS_DENIED'));
  await assert.rejects(f.service.invoice('artist',selection.id,{appointmentId:visit.appointmentId}),fail('OPERATIONS_ACCESS_REQUIRED'));
  row.assignedStaffId='artist';
  row.status='Confirmed';
  const fitting = await f.service.assignedFitting('artist',selection.id);
  assert.equal(fitting.appointments[0].id,visit.appointmentId);
  for (const field of ['totalCents','invoice','invoiceId','rental','rentalId','services','fittingQuote']) assert(!Object.hasOwn(fitting,field));
});
test('package invoice uses saved total, requires linked confirmed appointment and active staff role', async () => {
  const f = await fixture(); const s = await f.service.select('bride', f.input);
  const a = await f.service.book('bride', s.id, booking());
  const input = { appointmentId: a.appointmentId };
  for (const uid of ['bride', 'other', 'revoked', 'unknown']) await assert.rejects(f.service.invoice(uid, s.id, input), fail('STAFF_REQUIRED'));
  f.store.data.get(`appointments/${a.appointmentId}`).status = 'Cancelled';
  await assert.rejects(f.service.invoice('staff', s.id, input), fail('CONFIRMED_APPOINTMENT_REQUIRED'));
  await assert.rejects(f.service.invoice('manager', s.id, input), fail('CONFIRMED_APPOINTMENT_REQUIRED'));
  f.store.data.get(`appointments/${a.appointmentId}`).status = 'Confirmed';
  await assert.rejects(f.service.invoice('manager', s.id, { ...input, amountCents: 1 }), fail('INVALID_QUOTE'));
  await assert.rejects(f.service.invoice('staff', s.id, { ...input, amountCents: 1 }), fail('INVALID_QUOTE'));
  await assert.rejects(f.service.invoice('staff', s.id, { ...input, state: 'SandboxPaid' }), fail('INVALID_QUOTE'));
  const result = await f.service.invoice('staff', s.id, input);
  assert.equal(f.store.data.get(`sandboxInvoices/${result.id}`).createdBy, 'staff');
  assert.equal((await f.service.invoice('staff', s.id, input)).id, result.id);
  assert.equal(result.amountCents, 270000); assert.equal(result.state, 'Quoted');
  assert.equal((await f.service.invoice('manager', s.id, input)).id, result.id);
  await assert.rejects(f.payments.createQuote('manager', { ...input, purpose: 'DressPayment', amountCents: 270000 }), fail('APPOINTMENT_HAS_PACKAGE'));
  await assert.rejects(f.payments.checkout('other', result.id), fail('INVOICE_ACCESS_DENIED'));
  const checkout = await f.payments.checkout('bride', result.id);
  assert.equal(checkout.amountCents, 270000);
  const paid = await f.payments.refresh('bride', result.id);
  assert.equal(paid.state, 'SandboxPaid');
  assert.equal((await f.service.selections('bride')).selections[0].invoice.invoiceNo, 'TEST-RECEIPT');
  assert.equal(f.store.data.get(`appointments/${a.appointmentId}`).status, 'Confirmed');
});
test('HTTP package endpoints authenticate, reject cross-account book and preserve fixed quote contract', async () => {
  const f = await fixture();
  const server = createServer(createHandler({ service: f.payments, packages: f.service, verifyToken: async token => { if (!['bride', 'manager', 'staff', 'other'].includes(token)) throw Error(); return { uid: token }; } }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  async function req(path, uid, body) { return fetch(origin + path, { method: body ? 'POST' : 'GET', headers: { ...(uid ? { Authorization: `Bearer ${uid}` } : {}), 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) }); }
  try {
    assert.equal((await req('/v1/packages')).status, 401);
    assert.equal((await req('/v1/package-gown-limit')).status, 401);
    assert.equal((await req('/v1/package-gown-limit', 'staff')).status, 403);
    assert.deepEqual(await (await req('/v1/package-gown-limit', 'manager')).json(), {maxGowns: 0});
    assert.equal((await req('/v1/packages', 'bride')).status, 200);
    const selected = await (await req('/v1/package-selections', 'bride', f.input)).json();
    assert.equal((await req(`/v1/package-selections/${selected.id}/book`, 'other', booking())).status, 403);
    assert.equal((await req('/v1/packages', 'bride', initialPackage())).status, 403);
    assert.equal((await req('/v1/packages', 'staff', {...initialPackage(),revision:1})).status,403);
    assert.equal((await req('/v1/packages/essential/delete', 'staff', {revision:1})).status,403);
    assert.equal((await req('/v1/packages/essential/delete', 'manager', {revision:1})).status,409);
    assert.equal((await req('/v1/packages/essential/delete', undefined, {revision:1})).status,401);
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});

test('catalogue price revisions and package publication preserve historical prices', async () => {
  const {store,service} = await fixture();
  const servicePrice = {id:'consultation',revision:0,name:'Bridal consultation',description:'',
    active:true,method:'fixed',serviceType:'custom',priceCents:25000};
  await assert.rejects(service.serviceCatalogue.save('bride',servicePrice),fail('MANAGER_REQUIRED'));
  await assert.rejects(service.serviceCatalogue.save('manager',{...servicePrice,priceCents:-1}),fail('INVALID_BRIDAL_SERVICE_PRICE'));
  const first = await service.serviceCatalogue.save('manager',servicePrice);
  const id = 'service-priced';
  const configuration = {id,name:'Service priced package',description:'A personal bridal consultation.',
    active:true,includedGownCount:0,services:[{id:'consultation',name:first.name,description:'',
      serviceType:'custom',kind:'Required',priceCents:0}],
    pricing:{components:[{serviceId:first.id,catalogueId:first.id,revision:1,quantity:1}],
      gownPrices:[],bundleDiscount:{kind:'percent',value:1000}}};
  const rev0 = {draftRevision:0,publishedRevision:0};
  await service.publication.save('manager',id,{...rev0,configuration:{...configuration,name:''}},'draft');
  await assert.rejects(service.publication.save('manager',id,{...rev0,configuration},'draft'),fail('PACKAGE_CHANGED'));
  assert.equal(await store.get(`servicePackages/${id}`),undefined);
  assert.equal((await service.catalogue('manager',true,true,true,true)).packages.find(p=>p.id===id).draft,true);
  await service.publication.save('manager',id,{draftRevision:1,publishedRevision:0,configuration},'draft');
  const revision = {draftRevision:2,publishedRevision:0};
  const preview = await service.publication.save('manager',id,{...revision,configuration},'preview');
  assert.equal(preview.configuration.basePriceCents,22500);
  const publish = {...revision,confirmed:true,reviewedSnapshot:preview.reviewId};
  await assert.rejects(service.publication.save('staff',id,publish,'publish'),fail('MANAGER_REQUIRED'));
  await assert.rejects(service.publication.save('manager',id,{...publish,confirmed:false},'publish'),fail('PACKAGE_PUBLISH_CONFIRMATION_REQUIRED'));
  const published = await service.publication.save('manager',id,publish,'publish');
  assert.equal(published.revision,1);
  await assert.rejects(service.publication.save('manager',id,publish,'publish'),fail('PACKAGE_CHANGED'));
  assert.ok(!(await service.catalogue('bride',true,true,true)).packages.some(p=>p.id===id));
  assert.ok((await service.catalogue('bride',true,true,true,true)).packages.some(p=>p.id===id));
  const quote = await service.select('bride',{requestId:'new-priced',packageId:id,revision:1,
    removedIds:[],addonIds:[],expectedTotalCents:22500});
  assert.equal(quote.pricingSnapshot.lines[0].unitPriceCents,25000);
  const nextPrice = await service.serviceCatalogue.save('manager',{...servicePrice,revision:1,priceCents:30000});
  assert.equal(nextPrice.revision,2);
  await service.publication.save('manager',id,{draftRevision:0,publishedRevision:1,configuration},'draft');
  assert.equal((await service.publication.get('manager',id)).published.basePriceCents,22500);
  await assert.rejects(service.publication.save('manager',id,{draftRevision:1,publishedRevision:1,configuration},'preview'),fail('BRIDAL_SERVICE_PRICE_CHANGED'));
  const changed = structuredClone(configuration);
  changed.pricing.components[0].revision = 2;
  await service.publication.save('manager',id,{draftRevision:1,publishedRevision:1,configuration:changed},'draft');
  const phase2 = {draftRevision:2,publishedRevision:1};
  const revised = await service.publication.save('manager',id,{...phase2,configuration:changed},'preview');
  assert.equal(revised.configuration.basePriceCents,27000);
  await service.publication.save('manager',id,{...phase2,confirmed:true,reviewedSnapshot:revised.reviewId},'publish');
  assert.equal((await service.publication.version('manager',id,1)).basePriceCents,22500);
  assert.equal((await store.get(`packageSelections/${quote.id}`)).totalCents,22500);
  const disabled = await service.serviceCatalogue.save('manager',{...servicePrice,revision:2,active:false});
  assert.equal(disabled.active,false);
  assert.equal((await store.get('bridalServicePrices/consultation/revisions/1')).priceCents,25000);
});

test('approved service-based prices require real price components and a nonnegative discount', async () => {
  const {store,service} = await gownFixture(2);
  await service.serviceCatalogue.save('manager',{id:'service',revision:0,name:'Consultation',description:'',
    active:true,method:'per-session',serviceType:'custom',priceCents:4000});
  for (const [id,target,count] of [['bridal-essentials',82900,1],['signature-bridal',172900,1],['luxe-bridal',287900,2]]) {
    const configuration = {id,name:'Bridal package',description:'Personal fitting and gown rental.',
      active:true,includedGownCount:count,allCatalogueGowns:true,
      services:[{id:'service',name:'Consultation',description:'',serviceType:'custom',kind:'Required',priceCents:0},
        {id:'veil',name:'Veil Rental',description:'',serviceType:'package-veil',kind:'Optional',priceCents:8000,standardVeilId:'veil-short'}],
      pricing:{components:[{serviceId:'service',catalogueId:'service',revision:1,quantity:1}],
        matchApprovedPrice:true,gownPrices:[{dressId:'gown1',revision:2},...(count===2?[{dressId:'gown2',revision:2}]:[])]}};
    const result=await service.publication.save('manager',id,{draftRevision:0,publishedRevision:0,configuration},'preview');
    assert.equal(result.configuration.basePriceCents,target);
    assert.equal(priceSelection(result.configuration,['veil'],[]).totalCents,target-8000);
    assert.equal(result.pricingSnapshot.discountCents,result.pricingSnapshot.subtotalCents-target);
    assert.equal(await store.get(`servicePackages/${id}`),undefined);
    await assert.rejects(service.publication.save('manager',id,{draftRevision:0,publishedRevision:0,
      configuration:{...configuration,pricing:{...configuration.pricing,components:[]}}},'preview'),fail('PACKAGE_PRICING_CONFIGURATION_REQUIRED'));
  }
  store.data.get('dresses/gown1').priceCents = 100;
  const id='luxe-bridal';
  const configuration={id,name:'Bridal package',description:'Personal fitting and gown rental.',
    active:true,includedGownCount:1,allCatalogueGowns:true,services:[],
    pricing:{components:[],matchApprovedPrice:true,gownPrices:[{dressId:'gown1',revision:2}]}};
  await assert.rejects(service.publication.save('manager',id,{draftRevision:0,publishedRevision:0,configuration},'preview'),
    fail('APPROVED_PACKAGE_SUBTOTAL_TOO_LOW'));
});

test('custom quote validates stock and recalculates standalone service, gown and veil prices', async () => {
  const {store,service,input:existing} = await gownFixture();
  await service.serviceCatalogue.save('manager',{id:'consultation',revision:0,name:'Bridal consultation',description:'',
    active:true,method:'per-session',serviceType:'custom',priceCents:10000});
  store.data.set('accessoryStock/veil-short',{quantity:1,allocations:{}});
  const input={requestId:'custom-pick',packageId:'custom-bridal',revision:1,
    gowns:existing.gowns,rentalPlan:availabilityPlan,removedIds:[],addonIds:['custom-veil'],
    customServices:[{id:'consultation',revision:1,quantity:2}],accessoryCatalogueVersion:accessoryCatalogue.version,
    accessories:[{serviceId:'custom-veil',itemId:'veil-short'}]};
  await assert.rejects(service.select('staff',input,{previewOnly:true}),fail('BRIDE_REQUIRED'));
  await assert.rejects(service.select('bride',{...input,accessories:[]},{previewOnly:true}),
    fail('PACKAGE_ACCESSORY_SELECTION_REQUIRED'));
  const result=await service.select('bride',input,{previewOnly:true});
  assert.equal(result.totalCents,gown().priceCents+20000+8000);
  assert.equal(result.pricingSnapshot.discountCents,0);
  assert.equal((await store.list('packageSelections')).length,0);
  await assert.rejects(service.select('bride',{...input,quoteId:result.quoteId,expectedTotalCents:1}),fail('PACKAGE_CHANGED'));
  await assert.rejects(service.select('other',{...input,quoteId:result.quoteId,expectedTotalCents:result.totalCents}),fail('PACKAGE_CHANGED'));
  const order=await service.select('bride',{...input,quoteId:result.quoteId,expectedTotalCents:result.totalCents});
  assert.equal(order.packageType,'Custom');
  assert.equal(order.invoiceId,null);
  assert.equal(order.rentalId,undefined);
  assert.equal((await store.get(`rentalVariants/${variantId('gown1','M')}`)).allocations[order.id],undefined);
  assert.equal((await service.select('bride',{...input,quoteId:result.quoteId,expectedTotalCents:result.totalCents})).id,order.id);
  const revised={...input,requestId:'change-custom',revision:0,packageRevision:1,planRevision:1,
    previewOnly:true,addonIds:[],accessories:[],customServices:[]};
  const preview=await service.revise('bride',order.id,revised);
  assert.equal(preview.totalCents,gown().priceCents);
  await assert.rejects(service.revise('other',order.id,revised),fail('SELECTION_ACCESS_DENIED'));
  await service.revise('bride',order.id,{...revised,previewOnly:false,expectedTotalCents:preview.totalCents});
  assert.equal((await store.get(`packageSelections/${order.id}`)).totalCents,gown().priceCents);
  const booked = await service.book('bride',order.id,booking());
  const saved = await store.get(`packageSelections/${order.id}`);
  assert.deepEqual(saved.appointmentIds,[booked.appointmentId]);
  assert.equal(saved.totalCents,gown().priceCents);
  await assert.rejects(service.invoice('manager',order.id,{appointmentId:booked.appointmentId}),
    fail('PACKAGE_RENTAL_CONFIRMATION_REQUIRED'));
});

test('a standard gown allowance prices a count without selecting gown models', async () => {
  const {service, store} = await gownFixture(2);
  const id = 'count-based-package';
  const version = {draftRevision:0,publishedRevision:0};
  const price = {id:'consultation',revision:0,name:'Bridal consultation',description:'',
    active:true,method:'fixed',serviceType:'custom',priceCents:20000};
  await service.serviceCatalogue.save('manager',price);
  const config = {id, name:'Count based package',description:'Two catalogue gowns and a consultation.',
    active:true,includedGownCount:2,allCatalogueGowns:true,
    services:[{id:'consultation',name:price.name,description:'',kind:'Required',priceCents:0,serviceType:'custom'}],
    pricing:{gownPrices:[],useStandardGownAllowance:true,
      components:[{serviceId:price.id,catalogueId:price.id,revision:1,quantity:1}],
      bundleDiscount:{kind:'fixed',value:5000}}};
  await assert.rejects(service.publication.save('manager',id,{...version,configuration:config},'preview'),
    fail('PACKAGE_GOWN_ALLOWANCE_REQUIRED'));
  const allowance={...price,id:'standard-gown-allowance',name:'Standard gown allowance',
    method:'per-gown',priceCents:50000,customEligible:false};
  await assert.rejects(service.serviceCatalogue.save('staff',allowance),fail('MANAGER_REQUIRED'));
  await assert.rejects(service.serviceCatalogue.save('manager',{...allowance,customEligible:true}),
    fail('INVALID_BRIDAL_SERVICE_PRICE'));
  await service.serviceCatalogue.save('manager',allowance);
  assert.deepEqual([...new Set((await service.customOptions('bride')).services.map(s=>s.id))],[price.id]);
  await service.publication.save('manager',id,{...version,configuration:config},'draft');
  const savedVersion={...version,draftRevision:1};
  const preview=await service.publication.save('manager',id,{...savedVersion,configuration:config},'preview');
  assert.equal(preview.pricingSnapshot.subtotalCents,120000);
  assert.equal(preview.configuration.basePriceCents,115000);
  assert.equal(preview.pricingSnapshot.gownLines[0].quantity,2);
  const publication={...savedVersion,confirmed:true,reviewedSnapshot:preview.reviewId};
  await service.serviceCatalogue.save('manager',{...allowance,revision:1,priceCents:51000});
  await assert.rejects(service.publication.save('manager',id,publication,'publish'),fail('PACKAGE_REVIEW_CHANGED'));
  assert.equal(await store.get(`servicePackages/${id}`),undefined);
});

test('catalogue exposes active custom services and requires explicit safe standalone approval', async () => {
  const {service} = await fixture();
  const base = {revision:0,description:'',method:'fixed',serviceType:'custom',priceCents:10000,active:true};
  await service.serviceCatalogue.save('manager',{...base,id:'consultation',name:'Consultation',standaloneEligible:true});
  await service.serviceCatalogue.save('manager',{...base,id:'unflagged',name:'Existing service'});
  await service.serviceCatalogue.save('manager',{...base,id:'inactive',name:'Inactive',active:false});
  await service.serviceCatalogue.save('manager',{...base,id:'manager-only',name:'Manager only',customEligible:false});
  await assert.rejects(service.serviceCatalogue.save('manager',{...base,id:'extra-fitting',
    name:'Additional fitting',serviceType:'extra-fitting',standaloneEligible:true}),fail('INVALID_STANDALONE_ELIGIBILITY'));
  await assert.rejects(service.serviceCatalogue.save('manager',{...base,id:'offered-only',
    name:'Not offered',customEligible:false,standaloneEligible:true}),fail('INVALID_STANDALONE_ELIGIBILITY'));
  const options=(await service.customOptions('bride')).services;
  assert.equal(options.find(row=>row.id==='consultation').standaloneEligible,true);
  assert.equal(options.find(row=>row.id==='unflagged').standaloneEligible,false);
  assert.equal(options.some(row=>['inactive','manager-only'].includes(row.id)),false);
});

test('Manager can enable standalone makeup without changing its catalogue price', async t => {
  const {service, payments, store} = await fixture();
  const route = '/v1/bridal-service-prices';
  const server = createServer(createHandler({
    service: payments, packages: service, verifyToken: async uid => ({uid}),
  }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = 'http://127.0.0.1:' + server.address().port;
  const send = (path, uid, body) => fetch(origin + path, {
    headers: {Authorization: 'Bearer ' + uid, 'Content-Type': 'application/json'},
    ...(body && {method: 'POST', body: JSON.stringify(body)}),
  });

  const row = {
    id: 'wedding-makeup', revision: 1, name: 'Bridal Makeup & Hairstyling',
    description: '', method: 'fixed', serviceType: 'makeup-hair',
    priceCents: 50000, active: true, customEligible: true,
  };
  store.data.set('bridalServicePrices/' + row.id, row);

  const saved = await send(route, 'manager', {...row, standaloneEligible: true});
  assert.equal(saved.status, 200);
  assert.equal((await saved.json()).standaloneEligible, true);

  const {services} = await (await send(route, 'manager')).json();
  const persisted = services.find(service => service.id === row.id);
  assert.equal(persisted.standaloneEligible, true);
  assert.equal(persisted.priceCents, row.priceCents);
  assert.equal(persisted.revision, 2);

  const options = await (await send('/v1/custom-package-options', 'bride')).json();
  assert.equal(options.services.find(service => service.id === row.id).standaloneEligible, true);
});

test('service-only consultation uses event date, proper appointment and existing package invoice without a fitting fee', async () => {
  const {service,store,payments}=await fixture();
  service.bookings.feePolicy=true;
  await service.serviceCatalogue.save('manager',{id:'consultation',revision:0,name:'Bridal consultation',
    description:'',active:true,customEligible:true,standaloneEligible:true,method:'fixed',
    serviceType:'custom',priceCents:10000});
  const input={requestId:'service-only',packageId:'custom-bridal',revision:1,removedIds:[],addonIds:[],
    gowns:[],accessories:[],customServices:[{id:'consultation',revision:1,quantity:1}],
    rentalPlan:{eventDate:availabilityPlan.eventDate}};
  await assert.rejects(service.select('bride',{...input,customServices:[]},{previewOnly:true}),fail('INVALID_CUSTOM_PACKAGE'));
  await assert.rejects(service.select('bride',{...input,rentalPlan:availabilityPlan},{previewOnly:true}),fail('INVALID_CUSTOM_EVENT_DATE'));
  await assert.rejects(service.select('bride',{...input,addonIds:['custom-veil']},{previewOnly:true}),fail('CUSTOM_SERVICE_REQUIRES_GOWN'));
  const quote=await service.select('bride',input,{previewOnly:true});
  assert.equal(quote.totalCents,10000);
  assert.deepEqual(quote.pricingSnapshot.gownLines,[]);
  const order=await service.select('bride',{...input,quoteId:quote.quoteId,expectedTotalCents:quote.totalCents});
  assert.equal(order.status,'Quoted');
  assert.equal(order.serviceOnly,true);
  assert.deepEqual(order.appointmentIds,[]);
  await assert.rejects(service.book('bride',order.id,{...booking(),type:'Dress Trial',feePolicyVersion:1}),fail('SERVICE_APPOINTMENT_TEAM_REVIEW'));
  const booked=await service.book('bride',order.id,{...booking(),feePolicyVersion:1});
  assert.equal(booked.status,'Confirmed');
  assert.equal(booked.invoiceId,null);
  const invoice=await service.invoice('manager',order.id,{appointmentId:booked.appointmentId});
  assert.equal(invoice.amountCents,10000);
  assert.equal(invoice.purpose,'PackagePayment');
  const checkout=await payments.checkout('bride',invoice.id);
  assert.equal(checkout.amountCents,10000);
  assert.equal((await payments.refresh('bride',invoice.id)).state,'SandboxPaid');
  assert.equal((await store.list('rentals')).length,0);
  assert.equal((await store.list('sandboxInvoices')).length,1);
});

test('wedding-day makeup and multi-service quotes stay pending team scheduling and dependent services require gowns', async () => {
  const {service}=await gownFixture();
  const base={revision:0,description:'',active:true,method:'fixed',priceCents:50000};
  await service.serviceCatalogue.save('manager',{...base,id:'makeup-hair',name:'Wedding makeup',
    serviceType:'makeup-hair',standaloneEligible:true});
  await service.serviceCatalogue.save('manager',{...base,id:'extra-fitting',name:'Additional fitting',
    serviceType:'extra-fitting',method:'per-session',priceCents:8000});
  const input={requestId:'makeup-only',packageId:'custom-bridal',revision:1,removedIds:[],addonIds:[],
    gowns:[],accessories:[],customServices:[{id:'makeup-hair',revision:1,quantity:1}],
    rentalPlan:{eventDate:availabilityPlan.eventDate}};
  await assert.rejects(service.select('bride',{...input,customServices:[{id:'extra-fitting',revision:1,quantity:1}]},{previewOnly:true}),
    fail('CUSTOM_SERVICE_REQUIRES_GOWN'));
  const quoted=await service.select('bride',input,{previewOnly:true});
  const saved=await service.select('bride',{...input,quoteId:quoted.quoteId,expectedTotalCents:50000});
  assert.equal(saved.serviceAppointmentType,null);
  await assert.rejects(service.book('bride',saved.id,booking()),fail('SERVICE_APPOINTMENT_TEAM_REVIEW'));
  const revise={...input,requestId:'add-gown',revision:0,packageRevision:1,planRevision:1,previewOnly:true,
    gowns:[{dressId:'gown1',size:'M',revision:2}],rentalPlan:availabilityPlan};
  const combined=await service.revise('bride',saved.id,revise);
  assert.ok(combined.totalCents>50000);
  await service.revise('bride',saved.id,{...revise,previewOnly:false,expectedTotalCents:combined.totalCents});
  const selection=(await service.selections('bride')).selections.find(row=>row.id===saved.id);
  assert.equal(selection.serviceOnly,false);
  assert.deepEqual(selection.customServices,input.customServices);
});

test('a service-only makeup trial requires staff assigned to makeup before booking', async () => {
  const {service,store}=await fixture();
  service.bookings.workforce={};
  service.bookings.feePolicy=true;
  await service.serviceCatalogue.save('manager',{id:'makeup-trial',revision:0,name:'Makeup trial',
    description:'',active:true,customEligible:true,standaloneEligible:true,method:'fixed',
    serviceType:'makeup-trial',priceCents:20000});
  const input={requestId:'trial-only',packageId:'custom-bridal',revision:1,removedIds:[],addonIds:[],
    gowns:[],accessories:[],customServices:[{id:'makeup-trial',revision:1,quantity:1}],
    rentalPlan:{eventDate:availabilityPlan.eventDate}};
  const quote=await service.select('bride',input,{previewOnly:true});
  const plan=await service.select('bride',{...input,quoteId:quote.quoteId,expectedTotalCents:20000});
  assert.equal(plan.serviceAppointmentType,'Makeup Trial');
  const time={...booking(),type:'Makeup Trial',feePolicyVersion:1};
  await assert.rejects(service.book('bride',plan.id,time),fail('NO_STAFF_AVAILABLE'));
  store.data.set('staffScheduling/staff',{jobRole:'MakeupArtist',serviceTypes:['Bridal Makeup']});
  const visit=await service.book('bride',plan.id,time);
  assert.equal(visit.status,'Confirmed');
  assert.equal(visit.invoiceId,null);
  assert.equal((await store.list('rentals')).length,0);
});
