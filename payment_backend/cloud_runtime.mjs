import {mkdtempSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {OAuth2Client} from 'google-auth-library';
import {randomUUID} from 'node:crypto';

// Config comes from one Secret Manager version, never from the container image.
export function prepareCloudConfig(env=process.env){
  if(!env.K_SERVICE)return null;
  const value=JSON.parse(env.LUVLY_CONFIG_BUNDLE??'null');
  if(!value||value.projectId!=='luvly-44c77'||!value.paymentSecret)throw Error('CLOUD_CONFIG_REQUIRED');
  const directory=mkdtempSync(join(tmpdir(),'luvly-config-'));
  const allowed=['calendar-config.json','google-calendar-oauth.json','gemini-config.json','mail-config.json'];
  for(const name of allowed)if(value.files?.[name])writeFileSync(join(directory,name),JSON.stringify(value.files[name]),{mode:0o600});
  if(value.calendarKey)writeFileSync(join(directory,'calendar-token.key'),Buffer.from(value.calendarKey,'base64'),{mode:0o600});
  env.FIREBASE_PROJECT_ID=value.projectId;env.TOYYIBPAY_ENV='sandbox';
  env.TOYYIBPAY_SECRET_KEY=value.paymentSecret;env.TOYYIBPAY_CATEGORY_CODE=value.categoryCode;
  delete env.LUVLY_CONFIG_BUNDLE;
  return directory;
}

export async function maintenance({db,store,rentals,bookings,calendar,mail,reviews,now=Date.now}){
  const ref=db.doc('serviceMaintenance/worker'),owner=randomUUID();
  const acquired=await db.runTransaction(async tx=>{const old=(await tx.get(ref)).data();
    if(old?.expiresAt>now())return false;
    tx.set(ref,{owner,expiresAt:now()+180000});return true;});
  if(!acquired)return {busy:true};
  const failed=[];
  const step=async(name,fn)=>{try{await fn();}catch{failed.push(name);}};
  try{
    await step('rentals',async()=>{
      for(const id of await store.expiredRentalIds(now()))await rentals.expire(id);
      for(const id of await store.expiredExtensionIds(now()))await rentals.expireExtension(id);
      for(const id of await store.activeRentalIds())await rentals.audit(id);
    });
    await step('bookings',async()=>{
      for(const id of await store.pendingFittingIds())await bookings.expirePayment(id);
      for(const id of await store.pendingBookingIds())try{await bookings.recheck(id);}catch{/* Individual unavailable requests stay unchanged. */}
    });
    if(mail)await step('mail',async()=>{const rows=await db.collection('appointmentMail').where('state','==','Queued').limit(10).get();for(const d of rows.docs)await mail.send(d.id);});
    if(calendar)await step('calendar',async()=>{const rows=await db.collection('calendarConnections').where('connected','==',true).get();for(const d of rows.docs)await calendar.sync(d.id);});
    await step('reviewCleanup',()=>reviews.cleanup());
    return {busy:false,failed};
  }finally{
    await db.runTransaction(async tx=>{const current=(await tx.get(ref)).data();if(current?.owner===owner)tx.set(ref,{owner:null,expiresAt:0,finishedAt:now(),failed});});
  }
}

export function scheduledHandler({handler,run,audience,email,verify,now=Date.now}){
  const client=new OAuth2Client();
  const identity=verify??(async token=>(await client.verifyIdToken({idToken:token,audience})).getPayload());
  return async(req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(url.pathname!=='/internal/maintenance')return handler(req,res);
    res.setHeader('Cache-Control','no-store');
    if(req.method!=='POST'||url.search||!audience||!email){res.writeHead(404);return res.end();}
    const token=/^Bearer (\S+)$/.exec(req.headers.authorization??'')?.[1];
    try{
      if(!token)throw Error();
      const p=await identity(token);
      if(p?.email!==email||p.email_verified!==true||p.aud!==audience||
        !['https://accounts.google.com','accounts.google.com'].includes(p.iss)||p.exp*1000<=now())throw Error();
    }catch{res.writeHead(401);return res.end();}
    try{const result=await run();res.writeHead(result.failed?.length?503:200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));}
    catch{res.writeHead(503);res.end();}
  };
}
