import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {RecommendationProfilesService,validRecommendationProfile,emptyRecommendationProfile,sharedBodyType} from './recommendation_profiles.mjs';
import {StaffWorkspaceService} from './staff_workspace.mjs';
import {createHandler} from './http_app.mjs';
const fails=code=>e=>e.code===code;
function fixture(){
  const data=new Map(Object.entries({'brides/bride':{name:'Bride'},'brides/other':{name:'Other'},'staff/staff':{active:true,role:'staff'},'staff/manager':{active:true,role:'manager'},'staff/inactive':{active:false,role:'staff'}}));
  let queue=Promise.resolve();
  const store={atomic:fn=>{const op=queue.then(async()=>{const writes=new Map();let writing=false;
    const result=await fn({get:async p=>{assert(!writing);return structuredClone(data.get(p));},set:(p,r)=>{writing=true;writes.set(p,r);}});
    for(const[p,r]of writes)data.set(p,structuredClone(r));return result;});queue=op.catch(()=>{});return op;}};
  const workspace=new StaffWorkspaceService({store});
  return {data,service:new RecommendationProfilesService({store,access:(tx,uid)=>workspace.account(tx,uid),now:()=>1234})};
}
const preferences=()=>({...emptyRecommendationProfile(),measurements:{Bust:90,Waist:65,Hips:92},styles:['Mermaid'],colours:['Ivory'],maxPriceCents:60000,useProportions:true});
const input=(patch={})=>({requestId:'save1',revision:0,profile:preferences(),...patch});
test('new profiles have no invented body values; real preferences persist across devices and remain owner-bound',async()=>{
  const f=fixture();assert.deepEqual(await f.service.get('bride'),{revision:0,profile:emptyRecommendationProfile()});
  assert.equal((await f.service.save('bride',input())).revision,1);
  assert.deepEqual((await f.service.get('bride')).profile,preferences());assert.deepEqual((await f.service.get('other')).profile,emptyRecommendationProfile());
  assert.deepEqual([...f.data.keys()].filter(k=>k.startsWith('recommendationProfiles/')),['recommendationProfiles/bride']);
});
test('staff, managers, inactive staff and unknown accounts cannot read or write customer measurement profiles',async()=>{
  const f=fixture();for(const uid of ['staff','manager','inactive','unknown']){
    const code=['staff','manager'].includes(uid)?'CUSTOMER_PROFILE_REQUIRED':'ACCOUNT_ACCESS_REQUIRED';
    await assert.rejects(f.service.get(uid),fails(code));await assert.rejects(f.service.save(uid,input()),fails(code));
  }
});
test('reject forged owner/role, bad shapes, invalid measurement values, oversized lists and supplied scores',async()=>{
  const f=fixture();for(const patch of [{uid:'other'},{role:'manager'},{score:99},{revision:-1},{revision:1.1},{requestId:'../bride'}])await assert.rejects(f.service.save('bride',input(patch)),fails('INVALID_RECOMMENDATION_PROFILE'));
  for(const patch of [{measurements:{Bust:NaN}},{measurements:{Bust:Infinity}},{measurements:{Bust:0}},{measurements:{Shoulder:150}},{measurements:{fake:50}},{styles:['Unknown']},{styles:['A-Line','A-Line']},{colours:['IVORY']},{maxPriceCents:0},{maxPriceCents:5.5},{maxPriceCents:100000001},{useProportions:true,measurements:{Bust:90}},{measurements:null},{styles:'Mermaid'},{score:95}]){
    assert(!validRecommendationProfile({...preferences(),...patch}));await assert.rejects(f.service.save('bride',input({profile:{...preferences(),...patch}})),fails('INVALID_RECOMMENDATION_PROFILE'));
  }
});
test('manual measurements without body analysis and completely empty preferences are valid',()=>{
  assert(validRecommendationProfile(emptyRecommendationProfile()));assert(validRecommendationProfile({...emptyRecommendationProfile(),measurements:{Height:165,Shoulder:40}}));
});
test('report participation is explicit, atomic and withdrawable; projection never contains measurements',async()=>{
  const f=fixture();await f.service.save('bride',input());
  assert.equal(f.data.get('bodyTypeSummaries/bride').bodyType,null);
  const profile={...preferences(),shareProportionStats:true};
  await f.service.save('bride',input({revision:1,requestId:'share',profile}));
  assert.deepEqual(f.data.get('bodyTypeSummaries/bride'),{bodyType:'Hourglass',algorithmVersion:'style-rules-v1',updatedAt:1234});
  await assert.rejects(f.service.save('bride',input({requestId:'stale',profile})),fails('RECOMMENDATION_PROFILE_CHANGED'));
  assert.equal(f.data.get('bodyTypeSummaries/bride').bodyType,'Hourglass');
  await f.service.save('bride',input({revision:2,requestId:'withdraw',profile:preferences()}));
  assert.equal(f.data.get('bodyTypeSummaries/bride').bodyType,null);
  assert(!validRecommendationProfile({...profile,useProportions:false}));
  assert(!validRecommendationProfile({...profile,shareProportionStats:'yes'}));
});
test('server categorisation matches the ordered proportion guide rules and old profiles default to private',async()=>{
  for(const [b,w,h,type]of [[90,65,92,'Hourglass'],[90,75,100,'Pear'],[105,75,95,'Inverted Triangle'],[95,80,95,'Rectangle'],[95,90,95,'Oval']])
    assert.equal(sharedBodyType({...preferences(),shareProportionStats:true,measurements:{Bust:b,Waist:w,Hips:h}}),type);
  const f=fixture(),profile=preferences();delete profile.shareProportionStats;
  f.data.set('recommendationProfiles/bride',{profile,revision:1});
  assert.equal((await f.service.get('bride')).profile.shareProportionStats,false);
});
test('concurrent edits conflict; uncertain retries are idempotent; clearing retains revision',async()=>{
  const f=fixture(),r=await Promise.allSettled([f.service.save('bride',input()),f.service.save('bride',input({requestId:'save2'}))]);
  assert.equal(r.filter(v=>v.status==='fulfilled').length,1);assert.equal(r.find(v=>v.status==='rejected').reason.code,'RECOMMENDATION_PROFILE_CHANGED');
  assert.equal((await f.service.save('bride',input())).revision,1);
  await assert.rejects(f.service.save('bride',input({profile:emptyRecommendationProfile()})),fails('REQUEST_CONFLICT'));
  const cleared=await f.service.save('bride',input({revision:1,requestId:'clear',profile:emptyRecommendationProfile()}));assert.equal(cleared.revision,2);assert.deepEqual(cleared.profile.measurements,{});
  await assert.rejects(f.service.save('bride',input({requestId:'stale'})),fails('RECOMMENDATION_PROFILE_CHANGED'));
});
test('corrupt persisted input is unavailable, never replaced silently with default values',async()=>{
  const f=fixture();f.data.set('recommendationProfiles/bride',{revision:1,profile:{...preferences(),measurements:{Bust:'90'}}});await assert.rejects(f.service.get('bride'),fails('RECOMMENDATION_PROFILE_UNAVAILABLE'));
});
test('HTTP verifies identity and rejects unauthenticated, query-owner and body-owner access',async()=>{
  const f=fixture(),server=createServer(createHandler({recommendationProfiles:f.service,service:{},verifyToken:async token=>({uid:token})}));
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  try{
    const base=`http://127.0.0.1:${server.address().port}/v1/my-recommendation-profile`,headers={Authorization:'Bearer bride','Content-Type':'application/json'};
    assert.equal((await fetch(base)).status,401);assert.equal((await fetch(base+'?uid=other',{headers})).status,400);
    assert.equal((await fetch(base,{method:'POST',headers,body:JSON.stringify(input({uid:'other'}))})).status,400);
    const saved=await fetch(base,{method:'POST',headers,body:JSON.stringify(input())});assert.equal(saved.status,200);assert.equal((await saved.json()).revision,1);
    const other=await fetch(base,{headers:{Authorization:'Bearer other'}});assert.deepEqual((await other.json()).profile,emptyRecommendationProfile());
    assert.equal((await fetch(base,{headers:{Authorization:'Bearer manager'}})).status,403);
    assert.equal((await fetch(base,{method:'POST',headers,body:JSON.stringify({text:'x'.repeat(9000)})})).status,413);
  }finally{await new Promise(r=>server.close(r));}
});
