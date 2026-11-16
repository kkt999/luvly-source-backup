import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';
import {inspectReviewMedia} from './review_media.mjs';
import {hasReviewProfanity,reviewPolicyVersion} from './review_text_moderation.mjs';
const hash=s=>createHash('sha256').update(s).digest('hex'),key=s=>typeof s==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(s);
const check=(ok,code,status=400)=>{if(!ok)throw new HttpError(status,code);};
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>keys.includes(k));
const text=(s,max)=>typeof s==='string'&&s.length<=max&&!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(s);
const published=r=>!r.withdrawn&&!r.moderation?.hidden&&(!r.safety||r.safety.state==='Allowed');
const reportReasons=['Profanity','Harassment','Hate','Threats','Sexual','Privacy','Spam','Other'];
const moderationReasons=['Privacy','Spam','Unrelated','Abusive','Restored',...reportReasons];
// actor() verifies active staff from the authoritative account document first.
// This capability is review-specific; it grants no staff-account or finance access.
const canHandleReviews=actor=>['staff','manager'].includes(actor?.role);
export const customerReviewId=(uid,rentalId)=>hash(`${uid}:${rentalId}`).slice(0,32);
const title=(r,s)=>String(s?.name||r.gowns?.map(g=>g.name??'Gown').join(', ')||'Gown rental').slice(0,120);
const eligible=r=>r?.state==='Locked'&&r.fulfilment==='Returned'&&Number.isFinite(r.returnedAt)&&r.returnedAt>0&&!!r.collectedAt;
// Product membership comes from the items actually rented, never client input.
export const reviewGownIds=r=>[...new Set((Array.isArray(r?.gowns)?r.gowns:[]).map(g=>g?.dressId).filter(key))].sort();
const uploadPath=(reviewId,id)=>`customerReviewUploads/${reviewId}_${id}`;

export class CustomerReviews {
  get policyVersion(){return reviewPolicyVersion;}
  get staffHandlingVersion(){return 1;}
  constructor({store,bucket,moderator,now=Date.now,inspect=inspectReviewMedia}){Object.assign(this,{store,bucket,moderator,now,inspect});}
  async actor(tx,uid){
    check(key(uid),'SIGN_IN_REQUIRED',401);
    const staff=await tx.get(`staff/${uid}`);
    if(staff){check(staff.active===true&&['staff','manager'].includes(staff.role),'ACCOUNT_ACCESS_REQUIRED',403);return {role:staff.role,name:staff.name??'Luvly'};}
    const bride=await tx.get(`brides/${uid}`);check(!!bride,'ACCOUNT_ACCESS_REQUIRED',403);return {role:'bride',name:bride.name??'Customer'};
  }
  async owned(tx,uid,rentalId){
    const actor=await this.actor(tx,uid);check(actor.role==='bride','CUSTOMER_REVIEW_REQUIRED',403);
    const rental=await tx.get(`rentals/${rentalId}`);check(rental?.uid===uid,'REVIEW_RENTAL_NOT_FOUND',404);check(eligible(rental),'REVIEW_NOT_ELIGIBLE',409);
    return {actor,rental,id:customerReviewId(uid,rentalId)};
  }
  async authorizeUpload(uid,rentalId){check(key(rentalId),'INVALID_REVIEW');await this.store.atomic(tx=>this.owned(tx,uid,rentalId));}
  async product(actor,dressId){
    if(dressId===undefined)return;
    check(key(dressId),'INVALID_REVIEW');
    const dress=await this.store.get(`dresses/${dressId}`);
    check(!!dress&&(dress.published===true||canHandleReviews(actor)),'REVIEW_PRODUCT_NOT_FOUND',404);
  }
  async options(uid,dressId){
    const actor=await this.store.atomic(tx=>this.actor(tx,uid));check(actor.role==='bride','CUSTOMER_REVIEW_REQUIRED',403);
    await this.product(actor,dressId);
    const rentals=await this.store.list('rentals',uid),records=[];
    for(const r of rentals.filter(r=>eligible(r)&&(dressId===undefined||reviewGownIds(r).includes(dressId)))){
      const review=await this.store.get(`customerReviews/${customerReviewId(uid,r.id)}`);
      const selection=r.packageSelectionId?await this.store.get(`packageSelections/${r.packageSelectionId}`):null;
      records.push({rentalId:r.id,title:title(r,selection),eventDate:r.eventDate??'',review:review?this.public(review,uid,actor):null});
    }
    return {rentals:records};
  }
  public(r,uid,actor){
    const owner=r.uid===uid,manage=canHandleReviews(actor);
    return {id:r.id,title:r.title,author:r.author,stars:r.stars,text:r.text,createdAt:r.createdAt,updatedAt:r.updatedAt,revision:r.revision,
      media:r.media??[],reply:r.reply?{text:r.reply.text,at:r.reply.at}:null,owner,contentVersion:r.contentVersion??1,canReport:actor.role==='bride'&&!owner&&published(r),
      ...(owner||manage?{rentalId:r.rentalId,withdrawn:!!r.withdrawn,hidden:!!r.moderation?.hidden,moderationReason:r.moderation?.reason??'',safety:r.safety?{state:r.safety.state,category:r.safety.category}:null}:{}),
      ...(manage?{openReports:r.reportSummary?.open??0}:{}),
      canManage:manage};
  }
  async list(uid,scope='all',dressId){
    check(['all','mine','manage'].includes(scope),'INVALID_REVIEW');
    const actor=await this.store.atomic(tx=>this.actor(tx,uid));check(scope!=='manage'||canHandleReviews(actor),'REVIEW_ACCESS_REQUIRED',403);
    await this.product(actor,dressId);
    const rows=dressId===undefined?await this.store.list('customerReviews'):await this.store.reviewsForDress(dressId);const visible=rows.filter(published);
    const records=(scope==='mine'?rows.filter(r=>r.uid===uid):scope==='manage'?rows:visible).sort((a,b)=>b.createdAt-a.createdAt);
    const mine=actor.role==='bride'?await this.store.list('customerReviewReports',uid):[];
    return {reviews:records.map(r=>{const row=this.public(r,uid,actor);const reported=mine.some(m=>m.reviewId===r.id&&m.contentVersion===(r.contentVersion??1));return {...row,reported,canReport:row.canReport&&!reported};}),summary:{count:visible.length,average:visible.length?visible.reduce((n,r)=>n+r.stars,0)/visible.length:0,...(dressId===undefined?{}:{distribution:Object.fromEntries([5,4,3,2,1].map(star=>[star,visible.filter(r=>r.stars===star).length]))})},canManage:canHandleReviews(actor),...(scope==='manage'?{pendingCount:rows.filter(r=>r.safety?.state==='Pending').length,openReports:rows.reduce((n,r)=>n+(r.reportSummary?.open??0),0),textModeration:this.moderator?.status?.()??{configured:false}}:{})};
  }
  async ratings(uid){
    await this.store.atomic(tx=>this.actor(tx,uid));
    const dresses=await this.store.listDresses(),rows=await this.store.list('customerReviews');
    const totals=new Map(dresses.filter(d=>d.published===true).map(d=>[d.id,{dressId:d.id,count:0,total:0}]));
    for(const r of rows){
      if(!published(r)||!Number.isInteger(r.stars)||r.stars<1||r.stars>5)continue;
      for(const id of new Set(Array.isArray(r.gownIds)?r.gownIds:[])){
        const entry=totals.get(id);if(entry){entry.count++;entry.total+=r.stars;}
      }
    }
    return {ratings:[...totals.values()].map(r=>({dressId:r.dressId,count:r.count,average:r.count?r.total/r.count:0})).sort((a,b)=>a.dressId.localeCompare(b.dressId))};
  }
  async upload(uid,rentalId,uploadId,bytes,mime){
    check(key(rentalId)&&/^[a-f0-9]{32}$/.test(uploadId),'INVALID_REVIEW');
    await this.authorizeUpload(uid,rentalId);
    const info=await this.inspect(bytes,mime),fingerprint=hash(bytes),id=customerReviewId(uid,rentalId),path=`customer-reviews/${id}/${uploadId}.${mime==='image/jpeg'?'jpg':'mp4'}`;
    const old=await this.store.atomic(async tx=>{
      await this.owned(tx,uid,rentalId);
      const old=await tx.get(uploadPath(id,uploadId)),rows=await tx.reviewUploads(id);
      if(old?.status==='Ready'){check(old.hash===fingerprint,'REQUEST_CONFLICT',409);return old;}
      check(!old||['Reserved','Failed'].includes(old.status),'REVIEW_UPLOAD_EXPIRED',409);
      check(!old||old.hash===fingerprint,'REQUEST_CONFLICT',409);
      check(old?.status!=='Reserved'||this.now()-old.updatedAt>120000,'REVIEW_UPLOAD_IN_PROGRESS',409);
      check(rows.filter(r=>['Ready','Reserved'].includes(r.status)).length<12||old?.status==='Reserved','REVIEW_UPLOAD_LIMIT',409);
      tx.set(uploadPath(id,uploadId),{id:uploadId,reviewId:id,uid,path,hash:fingerprint,...info,bytes:bytes.length,status:'Reserved',createdAt:old?.createdAt??this.now(),updatedAt:this.now()});return null;
    });
    if(old)return {media:this.mediaPublic(old)};
    try{
      await this.bucket.put(path,bytes,mime,fingerprint);
      const row=await this.store.atomic(async tx=>{
        await this.owned(tx,uid,rentalId);const row=await tx.get(uploadPath(id,uploadId));
        check(row?.status==='Reserved'&&row.hash===fingerprint,'REQUEST_CONFLICT',409);
        const next={...row,status:'Ready',updatedAt:this.now()};tx.set(uploadPath(id,uploadId),next);return next;
      });return {media:this.mediaPublic(row)};
    }catch(e){await this.store.atomic(async tx=>{const r=await tx.get(uploadPath(id,uploadId));if(r?.status==='Reserved')tx.set(uploadPath(id,uploadId),{...r,status:'Failed',updatedAt:this.now()});});throw e;}
  }
  mediaPublic(r){return {id:r.id,mime:r.mime,width:r.width,height:r.height,bytes:r.bytes,...(r.duration?{duration:r.duration}:{})};}
  async save(uid,rentalId,input){
    check(key(rentalId)&&exact(input,['requestId','revision','stars','text','mediaIds','consent','policyVersion'])&&key(input.requestId)&&Number.isInteger(input.revision)&&input.revision>=0&&Number.isInteger(input.stars)&&input.stars>=1&&input.stars<=5&&text(input.text,1000)&&input.consent===true&&Array.isArray(input.mediaIds)&&input.mediaIds.length<=6&&new Set(input.mediaIds).size===input.mediaIds.length&&input.mediaIds.every(id=>typeof id==='string'&&/^[a-f0-9]{32}$/.test(id)),'INVALID_REVIEW');
    check(input.policyVersion===reviewPolicyVersion,'REVIEW_POLICY_REQUIRED',409);
    const id=customerReviewId(uid,rentalId),fingerprint=hash(JSON.stringify(input));
    // Check authority, version and attachments BEFORE any external API call.
    // The external call is never made inside a retryable Firestore transaction.
    const prior=await this.store.atomic(async tx=>{
      await this.owned(tx,uid,rentalId);const old=await tx.get(`customerReviews/${id}`),op=await tx.get(`customerReviewOperations/${hash(uid+':'+input.requestId)}`);
      if(op){check(op.reviewId===id&&op.hash===fingerprint,'REQUEST_CONFLICT',409);return old;}
      check((old?.revision??0)===input.revision,'REVIEW_CHANGED',409);
      const media=await Promise.all(input.mediaIds.map(m=>tx.get(uploadPath(id,m))));check(media.every(m=>m?.status==='Ready'&&m.uid===uid&&m.reviewId===id),'INVALID_REVIEW_MEDIA');
      check(media.filter(m=>m.mime==='image/jpeg').length<=5&&media.filter(m=>m.mime==='video/mp4').length<=1,'REVIEW_MEDIA_LIMIT');return null;
    });
    if(prior)return {review:this.public(prior,uid,{role:'bride'})};
    const safety=await this.checkText(uid,input.text.trim());
    check(safety.state!=='Blocked','REVIEW_TEXT_BLOCKED',422);
    const row=await this.store.atomic(async tx=>{
      const {actor,rental}=await this.owned(tx,uid,rentalId),old=await tx.get(`customerReviews/${id}`),op=await tx.get(`customerReviewOperations/${hash(uid+':'+input.requestId)}`);
      if(op){check(op.reviewId===id&&op.hash===fingerprint,'REQUEST_CONFLICT',409);return old;}
      check((old?.revision??0)===input.revision,'REVIEW_CHANGED',409);
      const selection=rental.packageSelectionId?await tx.get(`packageSelections/${rental.packageSelectionId}`):null;
      const media=await Promise.all(input.mediaIds.map(m=>tx.get(uploadPath(id,m))));
      check(media.every(m=>m?.status==='Ready'&&m.uid===uid&&m.reviewId===id),'INVALID_REVIEW_MEDIA');
      check(media.filter(m=>m.mime==='image/jpeg').length<=5&&media.filter(m=>m.mime==='video/mp4').length<=1,'REVIEW_MEDIA_LIMIT');
      const next={...old,id,uid,rentalId,packageId:selection?.packageId??'',title:title(rental,selection),author:actor.name.trim().split(/\s+/)[0].slice(0,40)||'Customer',stars:input.stars,text:input.text.trim(),media:media.map(m=>this.mediaPublic(m)),withdrawn:false,revision:input.revision+1,contentVersion:(old?.contentVersion??(old?1:0))+1,safety:{...safety,at:this.now(),textHash:hash(input.text.trim())},createdAt:old?.createdAt??this.now(),updatedAt:this.now(),consentAt:this.now(),policyVersion:reviewPolicyVersion};
      next.gownIds=reviewGownIds(rental);
      tx.set(`customerReviews/${id}`,next);tx.set(`customerReviewOperations/${hash(uid+':'+input.requestId)}`,{reviewId:id,hash:fingerprint,at:this.now()});return next;
    });
    await this.cleanup(id).catch(()=>{});return {review:this.public(row,uid,{role:'bride'})};
  }
  async action(uid,id,action,input){
    check(/^[a-f0-9]{32}$/.test(id)&&['withdraw','reply','moderate','approve'].includes(action)&&exact(input,['revision','requestId','text','hidden','category','reason','consent','policyVersion'])&&key(input.requestId)&&Number.isInteger(input.revision),'INVALID_REVIEW');
    if(action==='reply'){
      const replay=await this.store.atomic(async tx=>{const actor=await this.actor(tx,uid),r=await tx.get(`customerReviews/${id}`),op=await tx.get(`customerReviewOperations/${hash(uid+':'+input.requestId)}`);check(canHandleReviews(actor),'REVIEW_ACCESS_REQUIRED',403);check(!!r,'REVIEW_NOT_FOUND',404);if(op){check(op.reviewId===id&&op.hash===hash(JSON.stringify({action,id,input})),'REQUEST_CONFLICT',409);return {review:this.public(r,uid,actor)};}check(r.revision===input.revision,'REVIEW_CHANGED',409);return null;});
      if(replay)return replay;
      check(exact(input,['revision','requestId','text','consent','policyVersion'])&&text(input.text,1000)&&input.text.trim().length>0,'INVALID_REVIEW');
      check(input.consent===true&&input.policyVersion===reviewPolicyVersion,'REVIEW_POLICY_REQUIRED',409);
      const s=await this.checkText(uid,input.text);check(s.state!=='Blocked','REVIEW_TEXT_BLOCKED',422);check(s.state==='Allowed','REVIEW_REPLY_PENDING',409);
    }
    return this.store.atomic(async tx=>{
      const actor=await this.actor(tx,uid),old=await tx.get(`customerReviews/${id}`),op=await tx.get(`customerReviewOperations/${hash(uid+':'+input.requestId)}`);
      check(!!old,'REVIEW_NOT_FOUND',404);
      check(action==='withdraw'?old.uid===uid:canHandleReviews(actor),'REVIEW_ACCESS_REQUIRED',403);
      const fingerprint=hash(JSON.stringify({action,id,input}));
      if(op){check(op.reviewId===id&&op.hash===fingerprint,'REQUEST_CONFLICT',409);return {review:this.public(old,uid,actor)};}
      check(input.revision===old.revision,'REVIEW_CHANGED',409);
      const next={...old,revision:old.revision+1,updatedAt:this.now()};
      if(action==='withdraw'){check(exact(input,['revision','requestId']),'INVALID_REVIEW');next.withdrawn=true;}
      else if(action==='reply'){next.reply={text:input.text.trim(),at:this.now(),by:uid};}
      else if(action==='approve'){check(exact(input,['revision','requestId','reason'])&&text(input.reason,300)&&input.reason.trim().length>=5&&old.safety?.state==='Pending','INVALID_REVIEW_APPROVAL');check(!hasReviewProfanity(old.text),'REVIEW_TEXT_BLOCKED',422);next.safety={...old.safety,state:'Allowed',provider:'Manual',by:uid,at:this.now(),reason:input.reason.trim()};next.safetyHistory=[...(old.safetyHistory??[]),next.safety].slice(-20);}
      else {check(exact(input,['revision','requestId','hidden','category','reason'])&&typeof input.hidden==='boolean'&&moderationReasons.includes(input.category)&&text(input.reason,300)&&input.reason.trim().length>=5&&(!input.hidden||input.category!=='Restored'),'INVALID_REVIEW_MODERATION');next.moderation={hidden:input.hidden,category:input.category,reason:input.reason.trim(),by:uid,at:this.now()};next.moderationHistory=[...(old.moderationHistory??[]),next.moderation].slice(-20);}
      tx.set(`customerReviews/${id}`,next);tx.set(`customerReviewOperations/${hash(uid+':'+input.requestId)}`,{reviewId:id,hash:fingerprint,at:this.now()});return {review:this.public(next,uid,actor)};
    });
  }
  async checkText(uid,value){
    if(hasReviewProfanity(value))return {state:'Blocked',category:'Profanity',provider:'Local',policyVersion:reviewPolicyVersion};
    try{const s=await this.moderator?.check(uid,value);if(['Allowed','Blocked','Pending'].includes(s?.state))return s;}catch{/* Never publish on API or configuration failures. */}
    return {state:'Pending',category:'Unavailable',provider:'Manual',policyVersion:reviewPolicyVersion};
  }
  async report(uid,id,input){
    check(/^[a-f0-9]{32}$/.test(id)&&exact(input,['requestId','revision','category','details'])&&key(input.requestId)&&Number.isInteger(input.revision)&&reportReasons.includes(input.category)&&text(input.details,500)&&(input.category!=='Other'||input.details.trim().length>=5),'INVALID_REVIEW_REPORT');
    return this.store.atomic(async tx=>{
      const actor=await this.actor(tx,uid),r=await tx.get(`customerReviews/${id}`),opPath=`customerReviewOperations/${hash(uid+':'+input.requestId)}`,op=await tx.get(opPath),fingerprint=hash(JSON.stringify({kind:'report',id,input}));
      check(actor.role==='bride','CUSTOMER_REVIEW_REQUIRED',403);check(!!r&&r.uid!==uid,'REVIEW_REPORT_ACCESS',403);
      if(op){check(op.hash===fingerprint&&op.reviewId===id,'REQUEST_CONFLICT',409);return {reported:true,alreadyReported:true};}
      const contentVersion=r.contentVersion??1,reportId=hash(`${uid}:${id}:${contentVersion}`),path=`customerReviewReports/${reportId}`,prior=await tx.get(path);
      if(prior)return {reported:true,alreadyReported:true};
      check(published(r),'REVIEW_NOT_FOUND',404);check(input.revision===r.revision,'REVIEW_CHANGED',409);
      const usagePath=`reviewReportUsage/${hash(uid+':'+new Date(this.now()).toISOString().slice(0,10))}`,usage=await tx.get(usagePath);
      check((usage?.count??0)<10,'REVIEW_REPORT_LIMIT',429);
      const snapshot={id:r.id,title:r.title,author:r.author,stars:r.stars,text:r.text,media:r.media??[],reply:r.reply?{text:r.reply.text,at:r.reply.at}:null,revision:r.revision,contentVersion,createdAt:r.createdAt};
      tx.set(path,{id:reportId,uid,reviewId:id,contentVersion,category:input.category,details:input.details.trim(),snapshot,status:'Open',revision:1,createdAt:this.now()});
      tx.set(`customerReviews/${id}`,{...r,reportSummary:{open:(r.reportSummary?.open??0)+1,total:(r.reportSummary?.total??0)+1}});
      tx.set(usagePath,{count:(usage?.count??0)+1});tx.set(opPath,{hash:fingerprint,reviewId:id,at:this.now()});return {reported:true,alreadyReported:false};
    });
  }
  async reports(uid,status='Open'){
    const actor=await this.store.atomic(async tx=>{const a=await this.actor(tx,uid);check(canHandleReviews(a),'REVIEW_ACCESS_REQUIRED',403);return a;});check(['Open','Closed'].includes(status),'INVALID_REVIEW_REPORT');
    const rows=await this.store.list('customerReviewReports'),records=[];
    for(const r of rows.filter(r=>status==='Open'?r.status==='Open':r.status!=='Open').sort((a,b)=>b.createdAt-a.createdAt)){
      const current=await this.store.get(`customerReviews/${r.reviewId}`);
      records.push({id:r.id,reviewId:r.reviewId,revision:r.revision,category:r.category,details:r.details,status:r.status,createdAt:r.createdAt,snapshot:r.snapshot,current:current?this.public(current,uid,actor):null,resolution:r.resolution?{kind:r.resolution.kind,note:r.resolution.note,at:r.resolution.at}:null});
    }
    return {reports:records};
  }
  async resolveReport(uid,id,input){
    check(/^[a-f0-9]{64}$/.test(id)&&exact(input,['requestId','revision','reviewRevision','resolution','note'])&&key(input.requestId)&&Number.isInteger(input.revision)&&Number.isInteger(input.reviewRevision)&&['NoViolation','HideReview'].includes(input.resolution)&&text(input.note,500)&&input.note.trim().length>=5,'INVALID_REVIEW_REPORT');
    const result=await this.store.atomic(async tx=>{
      const actor=await this.actor(tx,uid);check(canHandleReviews(actor),'REVIEW_ACCESS_REQUIRED',403);
      const path=`customerReviewReports/${id}`,report=await tx.get(path),opPath=`customerReviewOperations/${hash(uid+':'+input.requestId)}`,op=await tx.get(opPath),fingerprint=hash(JSON.stringify({kind:'resolveReport',id,input}));check(!!report,'REVIEW_REPORT_NOT_FOUND',404);
      if(op){check(op.hash===fingerprint&&op.reviewId===report.reviewId,'REQUEST_CONFLICT',409);return {resolved:true};}
      const review=await tx.get(`customerReviews/${report.reviewId}`);check(!!review,'REVIEW_NOT_FOUND',404);check(report.status==='Open'&&report.revision===input.revision,'REVIEW_REPORT_CHANGED',409);
      if(input.resolution==='HideReview')check(review.revision===input.reviewRevision,'REVIEW_CHANGED',409);
      const next={...review,reportSummary:{...review.reportSummary,open:Math.max(0,(review.reportSummary?.open??0)-1)}};
      if(input.resolution==='HideReview'){next.revision=review.revision+1;next.updatedAt=this.now();next.moderation={hidden:true,category:report.category,reason:input.note.trim(),by:uid,at:this.now(),reportId:id};next.moderationHistory=[...(review.moderationHistory??[]),next.moderation].slice(-20);}
      tx.set(`customerReviews/${report.reviewId}`,next);
      tx.set(path,{...report,revision:report.revision+1,status:input.resolution==='HideReview'?'Resolved':'Dismissed',resolution:{kind:input.resolution,note:input.note.trim(),at:this.now(),by:uid,reviewRevision:review.revision}});
      tx.set(opPath,{hash:fingerprint,reviewId:report.reviewId,at:this.now()});return {resolved:true,reviewId:report.reviewId};
    });
    if(result.reviewId)await this.cleanup(result.reviewId).catch(()=>{});return {resolved:true};
  }
  async reportMediaUrl(uid,id,mediaId){
    check(/^[a-f0-9]{64}$/.test(id)&&/^[a-f0-9]{32}$/.test(mediaId),'INVALID_REVIEW_REPORT');
    const row=await this.store.atomic(async tx=>{const actor=await this.actor(tx,uid);check(canHandleReviews(actor),'REVIEW_ACCESS_REQUIRED',403);const r=await tx.get(`customerReviewReports/${id}`);check(r?.status==='Open'&&r.snapshot?.media?.some(m=>m.id===mediaId),'REVIEW_MEDIA_NOT_FOUND',404);const m=await tx.get(uploadPath(r.reviewId,mediaId));check(m?.status==='Ready'&&m.reviewId===r.reviewId,'REVIEW_MEDIA_NOT_FOUND',404);return m;});return {url:await this.bucket.url(row.path),expiresInSeconds:900};
  }
  async mediaUrl(uid,reviewId,mediaId){
    check(/^[a-f0-9]{32}$/.test(reviewId)&&/^[a-f0-9]{32}$/.test(mediaId),'INVALID_REVIEW');
    const row=await this.store.atomic(async tx=>{
      const actor=await this.actor(tx,uid),r=await tx.get(`customerReviews/${reviewId}`),m=await tx.get(uploadPath(reviewId,mediaId));
      check(m?.status==='Ready'&&r?.media?.some(v=>v.id===mediaId)&&(published(r)||r.uid===uid||canHandleReviews(actor)),'REVIEW_MEDIA_NOT_FOUND',404);return m;
    });return {url:await this.bucket.url(row.path),expiresInSeconds:900};
  }
  async cleanup(onlyId){
    // Never delete anything outside the review-specific prefix. A transaction
    // tombstone prevents a concurrent save from reattaching an object being GC'd.
    const rows=await this.store.reviewUploadRows(onlyId);
    for(const candidate of rows){
      const path=uploadPath(candidate.reviewId,candidate.id);
      const row=await this.store.atomic(async tx=>{
        const r=await tx.get(`customerReviews/${candidate.reviewId}`),m=await tx.get(path);
        if(!m||m.status==='Deleted'||r?.reportSummary?.open>0||r?.media?.some(v=>v.id===m.id)||m.updatedAt>(r?.updatedAt??0)&&this.now()-m.updatedAt<86400000)return null;
        if(!/^customer-reviews\/[a-f0-9]{32}\/[a-f0-9]{32}\.(jpg|mp4)$/.test(m.path))return null;
        tx.set(path,{...m,status:'Deleting'});return m;
      });
      if(row){await this.bucket.remove(row.path);await this.store.atomic(async tx=>{const m=await tx.get(path);if(m?.status==='Deleting')tx.set(path,{...m,status:'Deleted',updatedAt:this.now()});});}
    }
  }
  start(){let busy=false;const timer=setInterval(async()=>{if(busy)return;busy=true;try{await this.cleanup();}catch{/* Retry GC without logging content or object URLs. */}finally{busy=false;}},1800000);timer.unref();return()=>clearInterval(timer);}
}
