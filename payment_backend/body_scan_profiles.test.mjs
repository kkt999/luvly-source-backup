import test from 'node:test';
import assert from 'node:assert/strict';
import {validBodyScan,validRecommendationProfile,emptyRecommendationProfile,sharedBodyType,RecommendationProfilesService} from './recommendation_profiles.mjs';

const scan=()=>({algorithmVersion:'joint-ratios-v1',shoulderHipRatio:1.7,torsoShoulderRatio:1.2,sampleCount:30,durationMs:2400,relativeSpread:.01,capturedAt:1793500000000});
const profile=()=>({...emptyRecommendationProfile(),measurements:{Bust:90},bodyScan:scan(),useScanProportions:true});
test('versioned slow-phone evidence is valid; legacy rules and insufficient evidence stay rejected',()=>{
  const v2={...scan(),algorithmVersion:'joint-ratios-v2',sampleCount:15,durationMs:5000};
  assert(validBodyScan(v2));assert(validBodyScan(scan()));
  for(const p of [{sampleCount:14},{durationMs:2999},{durationMs:15001},{relativeSpread:.036},{algorithmVersion:'joint-ratios-v1'}])assert(!validBodyScan({...v2,...p}));
});
test('scan accepts bounded joint ratios and rejects unstable, forged, nonfinite or measurement payloads',()=>{
  assert(validBodyScan(scan()));assert(validRecommendationProfile(profile()));
  for(const patch of [{Bust:90},{uid:'other'},{algorithmVersion:'ruler'},{relativeSpread:.036},{shoulderHipRatio:NaN},{torsoShoulderRatio:Infinity},{sampleCount:29},{sampleCount:30.1},{durationMs:1999},{durationMs:10001},{capturedAt:0}])
    assert(!validRecommendationProfile({...profile(),bodyScan:{...scan(),...patch}}));
  assert(!validRecommendationProfile({...profile(),bodyScan:null}));
  assert(!validRecommendationProfile({...profile(),useScanProportions:'yes'}));
});
test('scan ratios never become circumference-based report categories or overwrite actual measurements',()=>{
  const p=profile();assert.equal(sharedBodyType(p),null);assert.deepEqual(p.measurements,{Bust:90});
  assert(!validRecommendationProfile({...p,shareProportionStats:true}));
  const manual={...p,measurements:{Bust:90,Waist:65,Hips:92},useProportions:true,shareProportionStats:true};
  assert.equal(sharedBodyType(manual),'Hourglass');
});
test('owner-only persistence, idempotent retry, concurrency and clearing retain unrelated preferences',async()=>{
  const data=new Map();let queue=Promise.resolve();
  const store={atomic:fn=>{const op=queue.then(async()=>{const writes=new Map();const result=await fn({get:async p=>structuredClone(data.get(p)),set:(p,v)=>writes.set(p,structuredClone(v))});for(const[p,v]of writes)data.set(p,v);return result;});queue=op.catch(()=>{});return op;}};
  const service=new RecommendationProfilesService({store,access:async(_tx,uid)=>({staff:uid==='staff'}),now:()=>1793500000000});
  const input={revision:0,requestId:'scan1',profile:{...profile(),styles:['A-Line']}};
  const result=await service.save('bride',input);assert.equal(result.revision,1);
  assert.deepEqual((await service.get('bride')).profile,input.profile);
  assert.equal((await service.save('bride',input)).revision,1);
  assert.equal((await service.get('other')).profile.bodyScan,null);
  await assert.rejects(service.get('staff'),e=>e.code==='CUSTOMER_PROFILE_REQUIRED');
  await assert.rejects(service.save('staff',input),e=>e.code==='CUSTOMER_PROFILE_REQUIRED');
  await assert.rejects(service.save('bride',{...input,requestId:'stale'}),e=>e.code==='RECOMMENDATION_PROFILE_CHANGED');
  assert.deepEqual(data.get('bodyTypeSummaries/bride'),{bodyType:null,algorithmVersion:'style-rules-v1',updatedAt:1793500000000});
  const cleared={...input.profile,bodyScan:null,useScanProportions:false};
  await service.save('bride',{revision:1,requestId:'clear',profile:cleared});
  assert.deepEqual((await service.get('bride')).profile,cleared);
  assert.equal(data.has('recommendationProfiles/staff'),false);
});
