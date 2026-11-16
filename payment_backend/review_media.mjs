import {Worker} from 'node:worker_threads';
import {HttpError} from './payment_service.mjs';
export const reviewVideoLimit=20*1024*1024,reviewPhotoLimit=220*1024;

export function jpegInfo(b){
  if(b.length<20||b.length>reviewPhotoLimit||b.readUInt16BE(0)!==0xffd8||b.readUInt16BE(b.length-2)!==0xffd9)return null;
  let offset=2,dimensions;
  while(offset+4<b.length){
    if(b[offset++]!==0xff)return null;
    while(b[offset]===0xff)offset++;
    const marker=b[offset++];
    if(![0xe0,0xdb,0xc0,0xc4,0xdd,0xda].includes(marker)||offset+2>b.length)return null;
    const size=b.readUInt16BE(offset);if(size<2||offset+size>b.length-2)return null;
    if(marker===0xc0){
      if(dimensions||size!==17||b[offset+2]!==8||b[offset+7]!==3)return null;
      const height=b.readUInt16BE(offset+3),width=b.readUInt16BE(offset+5);
      if(Math.min(width,height)<64||Math.max(width,height)>1200)return null;
      dimensions={mime:'image/jpeg',width,height};
    }
    if(marker===0xda)return dimensions&&offset+size<b.length-2?dimensions:null;
    offset+=size;
  }
  return null;
}
export async function inspectReviewMedia(bytes,mime){
  if(mime==='image/jpeg'){const info=jpegInfo(bytes);if(info)return info;}
  else if(mime==='video/mp4'&&bytes.length<=reviewVideoLimit&&bytes.length>=100){
    const value=await new Promise(resolve=>{
      const worker=new Worker(new URL('./review_video_worker.mjs',import.meta.url),{workerData:bytes,execArgv:[],resourceLimits:{maxOldGenerationSizeMb:128}});
      let done=false;const finish=result=>{if(done)return;done=true;clearTimeout(timer);void worker.terminate();resolve(result);};
      const timer=setTimeout(()=>finish(null),5000);
      worker.once('message',finish);worker.once('error',()=>finish(null));worker.once('exit',()=>finish(null));
    });
    if(value)return value;
  }
  throw new HttpError(400,'INVALID_REVIEW_MEDIA');
}

export class ReviewMediaBucket {
  constructor(bucket){this.bucket=bucket;}
  async put(path,bytes,mime,hash){
    try{await this.bucket.file(path).save(bytes,{resumable:false,validation:'crc32c',preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:mime,cacheControl:'private, max-age=0, no-store',metadata:{sha256:hash}}});}
    catch(e){if(e.code!==412)throw new HttpError(503,'REVIEW_MEDIA_UNAVAILABLE');const[m]=await this.bucket.file(path).getMetadata();if(m.metadata?.sha256!==hash)throw new HttpError(409,'REQUEST_CONFLICT');}
  }
  async url(path){
    try{const[url]=await this.bucket.file(path).getSignedUrl({version:'v4',action:'read',expires:Date.now()+15*60*1000});return url;}
    catch{throw new HttpError(503,'REVIEW_MEDIA_UNAVAILABLE');}
  }
  async remove(path){await this.bucket.file(path).delete({ignoreNotFound:true});}
}
