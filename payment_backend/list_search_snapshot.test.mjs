import test from 'node:test';
import assert from 'node:assert/strict';
import {FirestoreStore} from './firestore_store.mjs';

function store(count,{dresses=false}={}) {
  const reads=[];
  const query={
    where(...args){reads.push(args);return this;},
    limit(limit){assert.equal(limit,1001);return this;},
    async get(){return {docs:Array.from({length:Math.min(count,1001)},(_,i)=>({id:`id${i}`,data:()=>({id:`id${i}`,uid:'customer',published:dresses})}))};},
  };
  return {store:new FirestoreStore({collection:name=>{reads.push(name);return query;}}),reads};
}
test('package list search is not silently restricted to the first 100 selections',async()=>{
  const fixture=store(125);
  const rows=await fixture.store.list('packageSelections','customer');
  assert.equal(rows.length,125);
  assert.deepEqual(fixture.reads,['packageSelections',['uid','==','customer']]);
});
test('gown list includes beyond 100 while retaining published query',async()=>{
  const fixture=store(125,{dresses:true});
  assert.equal((await fixture.store.listDresses()).length,125);
  assert.deepEqual(fixture.reads,['dresses',['published','==',true]]);
});
test('oversized search feeds reject partial results instead of returning misleading matches',async()=>{
  await assert.rejects(store(1001).store.list('packageSelections'),e=>e.status===409 && e.code==='LIST_LIMIT');
  await assert.rejects(store(1001).store.listDresses(),e=>e.status===409 && e.code==='LIST_LIMIT');
  assert.equal((await store(1000).store.list('servicePackages')).length,1000);
});
