import test from 'node:test';
import assert from 'node:assert/strict';
import {projectOffers,createProjectOffers} from './project_promotions.mjs';
const now=Date.parse('2026-10-16T04:00:00Z');
class Store{
 data=new Map(projectOffers.map(p=>[`servicePackages/${p.campaign.packageId}`,{id:p.campaign.packageId,name:p.expectedPackageName,basePriceCents:p.expectedPackagePrice,active:true,includedGownCount:1}]));
 async atomic(fn){const writes=new Map();const result=await fn({get:async p=>{assert.equal(writes.size,0);return structuredClone(this.data.get(p));},set:(p,v)=>writes.set(p,structuredClone(v))});for(const[p,v]of writes)this.data.set(p,v);return result;}
}
test('offer preview writes nothing; explicit apply creates exactly three campaigns and indexes once',async()=>{
 const store=new Store();const preview=await createProjectOffers(store,{now});assert.equal(store.data.size,3);
 assert.deepEqual(preview.map(p=>p.standardTotalCents),[84900,169900,284900]);
 await createProjectOffers(store,{apply:true,now});assert.equal(store.data.size,9);
 const repeated=await createProjectOffers(store,{apply:true,now});assert.equal(store.data.size,9);assert.ok(repeated.every(p=>p.action==='Already exists'));
});
test('a changed package or existing code prevents all writes',async()=>{
 const store=new Store();store.data.get('servicePackages/luxe-bridal').basePriceCents=299800;
 await assert.rejects(createProjectOffers(store,{apply:true,now}),/PACKAGE_CHANGED/);assert.equal(store.data.size,3);
 const other=new Store();other.data.set('promotionCodes/LUXE150',{id:'existing-campaign'});
 await assert.rejects(createProjectOffers(other,{apply:true,now}),/CODE_ALREADY_ASSIGNED/);assert.equal(other.data.size,4);
});
test('manager changes or deletion cannot be silently overwritten by rerunning setup',async()=>{
 const store=new Store();await createProjectOffers(store,{apply:true,now});
 const path=`campaigns/${projectOffers[0].campaign.id}`;store.data.get(path).active=false;
 await assert.rejects(createProjectOffers(store,{apply:true,now}),/EXISTING_CAMPAIGN_CHANGED/);assert.equal(store.data.get(path).active,false);
});
