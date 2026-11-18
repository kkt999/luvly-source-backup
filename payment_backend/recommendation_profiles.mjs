import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
import {validMeasurementProvenance,retainMeasurementProvenance} from './measurement_provenance.mjs';

const check=(ok,code,status=400)=>{if(!ok)throw new HttpError(status,code);};
const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
const only=(v,keys)=>object(v)&&Object.keys(v).every(k=>keys.includes(k));
const styles=['A-Line','Ball Gown','Mermaid','Sheath'];
const colours=['White','Ivory','Off-white','Champagne','Blush','Nude','Silver','Gold','Red','Blue','Black','Multicolour'];
const limits={Height:[50,250],Weight:[10,500],Bust:[30,300],Waist:[30,300],Hips:[30,300],Shoulder:[15,100],'Arm length':[15,120]};
const choices=(v,allowed)=>Array.isArray(v)&&v.length<=allowed.length&&new Set(v).size===v.length&&v.every(s=>allowed.includes(s));
export function validBodyScan(s){
  const keys=['algorithmVersion','shoulderHipRatio','torsoShoulderRatio','sampleCount','durationMs','relativeSpread','capturedAt'];
  const range=(n,lo,hi)=>typeof n==='number'&&Number.isFinite(n)&&n>=lo&&n<=hi;
  const v2=s?.algorithmVersion==='joint-ratios-v2';
  return only(s,keys)&&Object.keys(s).length===keys.length&&['joint-ratios-v1','joint-ratios-v2'].includes(s.algorithmVersion)
    &&range(s.shoulderHipRatio,.6,2.4)&&range(s.torsoShoulderRatio,.5,2.6)
    &&range(s.relativeSpread,0,.035)&&Number.isSafeInteger(s.sampleCount)&&range(s.sampleCount,v2?15:30,90)
    &&Number.isSafeInteger(s.durationMs)&&range(s.durationMs,v2?3000:2000,v2?15000:10000)
    &&Number.isSafeInteger(s.capturedAt)&&range(s.capturedAt,1,4102444800000);
}
export function validRecommendationProfile(p){
  return only(p,['measurements','styles','colours','maxPriceCents','useProportions','shareProportionStats','bodyScan','useScanProportions','measurementProvenance'])
    &&only(p.measurements,Object.keys(limits))
    &&Object.entries(p.measurements).every(([k,n])=>typeof n==='number'&&Number.isFinite(n)&&n>=limits[k][0]&&n<=limits[k][1])
    &&validMeasurementProvenance(p.measurementProvenance,p.measurements)
    &&choices(p.styles,styles)&&choices(p.colours,colours)
    &&(p.maxPriceCents===null||Number.isSafeInteger(p.maxPriceCents)&&p.maxPriceCents>=1&&p.maxPriceCents<=100000000)
    &&typeof p.useProportions==='boolean'
    &&(p.shareProportionStats===undefined||typeof p.shareProportionStats==='boolean')
    &&(!p.shareProportionStats||p.useProportions)
    &&(p.bodyScan==null||validBodyScan(p.bodyScan))
    &&(p.useScanProportions===undefined||typeof p.useScanProportions==='boolean')
    &&(!p.useScanProportions||p.bodyScan!=null)
    &&(!p.useProportions||['Bust','Waist','Hips'].every(k=>k in p.measurements));
}
export const emptyRecommendationProfile=()=>({measurements:{},styles:[],colours:[],maxPriceCents:null,useProportions:false,shareProportionStats:false,bodyScan:null,useScanProportions:false});

// Same ordered rules as the customer's optional Dart proportion guide.
export function sharedBodyType(p){
  if(!validRecommendationProfile(p)||!p.useProportions||!p.shareProportionStats)return null;
  const {Bust:b,Waist:w,Hips:h}=p.measurements;
  if(w>=.9*Math.max(b,h))return 'Oval';
  if(h>b*1.05)return 'Pear';
  if(b>h*1.05)return 'Inverted Triangle';
  if(w<=.75*Math.min(b,h))return 'Hourglass';
  return 'Rectangle';
}

// Private owner-only data. Direct Firestore access stays denied by the default
// rules. Never copy measurements into public dresses, reviews or analytics.
export class RecommendationProfilesService{
  constructor({store,access,now=Date.now}){Object.assign(this,{store,access,now});}
  async customer(tx,uid){const a=await this.access(tx,uid);check(!a.staff,'CUSTOMER_PROFILE_REQUIRED',403);}
  public(row){return {revision:row?.revision??0,profile:{...emptyRecommendationProfile(),...row?.profile}};}
  async get(uid){return this.store.atomic(async tx=>{await this.customer(tx,uid);const row=await tx.get(`recommendationProfiles/${uid}`);check(!row||validRecommendationProfile(row.profile),'RECOMMENDATION_PROFILE_UNAVAILABLE',503);return this.public(row);});}
  async save(uid,input){
    check(only(input,['revision','requestId','profile'])&&Number.isSafeInteger(input.revision)&&input.revision>=0&&typeof input.requestId==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(input.requestId)&&validRecommendationProfile(input.profile),'INVALID_RECOMMENDATION_PROFILE');
    const fingerprint=createHash('sha256').update(JSON.stringify({revision:input.revision,profile:input.profile})).digest('hex');
    return this.store.atomic(async tx=>{
      await this.customer(tx,uid);const path=`recommendationProfiles/${uid}`,old=await tx.get(path);
      if(old?.requestId===input.requestId){check(old.fingerprint===fingerprint,'REQUEST_CONFLICT',409);return this.public(old);}
      check((old?.revision??0)===input.revision,'RECOMMENDATION_PROFILE_CHANGED',409);
      const profile=retainMeasurementProvenance(old?.profile,input.profile);
      const row={profile,revision:input.revision+1,requestId:input.requestId,fingerprint,updatedAt:this.now()};
      tx.set(path,row);
      // Backend-only projection. Managers receive category counts, never sizes
      // or owner IDs. A null category explicitly withdraws prior participation.
      tx.set(`bodyTypeSummaries/${uid}`,{bodyType:sharedBodyType(profile),algorithmVersion:'style-rules-v1',updatedAt:row.updatedAt});
      return this.public(row);
    });
  }
}
