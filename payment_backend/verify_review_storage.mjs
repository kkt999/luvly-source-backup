// Scoped deployment verification. No customer, payment or review records written.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {randomBytes,createHash} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getStorage} from 'firebase-admin/storage';
import {getFirestore} from 'firebase-admin/firestore';
import {ReviewMediaBucket,inspectReviewMedia} from './review_media.mjs';
loadEnvFile('.env');
const credentials=JSON.parse(readFileSync(resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credentials.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(credentials),projectId:'luvly-44c77'});
let indexReady=false;
try{
  try{await getFirestore(app).collection('customerReviewUploads').where('reviewId','==','0'.repeat(32)).where('status','in',['Ready','Reserved','Failed','Deleting']).limit(1).get();indexReady=true;console.log('Review upload index: ready');}
  catch(e){console.log('Review upload index: error code '+e.code);}
  const bucket=getStorage(app).bucket('luvly-44c77.firebasestorage.app'),[metadata]=await bucket.getMetadata();
  console.log(JSON.stringify({bucketExists:true,location:metadata.location,corsRules:metadata.cors?.length??0}));
  const origins=['http://localhost:5000','http://127.0.0.1:5000'];
  const current=metadata.cors??[];
  if(!origins.every(o=>current.some(c=>c.origin?.includes(o)&&['GET','HEAD'].every(m=>c.method?.includes(m))))){
    await bucket.setCorsConfiguration([...current,{origin:origins,method:['GET','HEAD'],responseHeader:['Content-Type','Content-Length','Content-Range','Accept-Ranges'],maxAgeSeconds:3600}]);
    console.log('Added GET/HEAD CORS for the two local app origins; IAM and Storage rules unchanged');
  }
  const media=new ReviewMediaBucket(bucket),source=readFileSync(new URL('./profile_photos.test.mjs',import.meta.url),'utf8');
  const fixtures=[{mime:'image/jpeg',bytes:Buffer.from(/data:'([^']+)'/.exec(source)[1],'base64')},{mime:'video/mp4',bytes:readFileSync(new URL('../work/review-butterfly-test.mp4',import.meta.url))}];
  for(const fixture of fixtures){
    await inspectReviewMedia(fixture.bytes,fixture.mime);
    const path=`customer-reviews/${randomBytes(16).toString('hex')}/${randomBytes(16).toString('hex')}.${fixture.mime==='image/jpeg'?'jpg':'mp4'}`;
    let created=false;
    try{
      await media.put(path,fixture.bytes,fixture.mime,createHash('sha256').update(fixture.bytes).digest('hex'));created=true;
      const url=await media.url(path),r=await fetch(url,{headers:fixture.mime==='video/mp4'?{Range:'bytes=0-1023'}:{}});
      if(![200,206].includes(r.status))throw Error('Signed read failed '+r.status);await r.arrayBuffer();
      const anonymous=await fetch(`https://storage.googleapis.com/${bucket.name}/${path}`);await anonymous.arrayBuffer();
      if(anonymous.status!==403&&anonymous.status!==401)throw Error('Object not private');
      const cors=await fetch(url,{method:'HEAD',headers:{Origin:origins[0]}});
      if(cors.headers.get('access-control-allow-origin')!==origins[0])throw Error('Media CORS failed');
      console.log(JSON.stringify({type:fixture.mime,signedRead:r.status,anonymousRead:anonymous.status,cors:true}));
    }finally{if(created){await media.remove(path);console.log('Removed the exact synthetic verification object');}}
  }
  if(!indexReady)process.exitCode=1;
}catch(e){console.log('Storage verification failed: '+(typeof e.code==='number'?e.code:e.message?.replace(/https?:\/\/\S+/g,'[URL omitted]')));process.exitCode=1;}
finally{await deleteApp(app);}
