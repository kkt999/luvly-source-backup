import {createHash} from 'node:crypto';
import {HttpError} from './payment_service.mjs';

const check=(ok,code,status=400)=>{if(!ok)throw new HttpError(status,code);};
const keys=(v,allowed)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).every(k=>allowed.includes(k));
export const maxProfilePhotoBytes=64*1024;

// Accept the small, metadata-free baseline JPEG produced by this app, not an
// arbitrary URL, SVG, original file, EXIF/GPS payload or client-selected owner.
export function validProfilePhoto(p){
  if(!keys(p,['data','mime','width','height'])||p.mime!=='image/jpeg'||!Number.isInteger(p.width)||p.width<64||p.width>512||p.height!==p.width||typeof p.data!=='string'||p.data.length>87384||!/^[A-Za-z0-9+/]+={0,2}$/.test(p.data))return false;
  const bytes=Buffer.from(p.data,'base64');
  if(bytes.length<20||bytes.length>maxProfilePhotoBytes||bytes.toString('base64')!==p.data||bytes.readUInt16BE(0)!==0xffd8||bytes.readUInt16BE(bytes.length-2)!==0xffd9)return false;
  let offset=2,dimensions=false;
  while(offset+4<bytes.length){
    if(bytes[offset++]!==0xff)return false;
    while(bytes[offset]===0xff)offset++;
    const marker=bytes[offset++];
    if(![0xe0,0xdb,0xc0,0xc4,0xdd,0xda].includes(marker)||offset+2>bytes.length)return false;
    const length=bytes.readUInt16BE(offset);
    if(length<2||offset+length>bytes.length-2)return false;
    if(marker===0xc0){
      if(dimensions||length!==17||bytes[offset+2]!==8||bytes[offset+7]!==3||bytes.readUInt16BE(offset+3)!==p.height||bytes.readUInt16BE(offset+5)!==p.width)return false;
      dimensions=true;
    }
    if(marker===0xda)return dimensions&&length>=6&&offset+length<bytes.length-2;
    offset+=length;
  }
  return false;
}

export class ProfilePhotosService {
  constructor({store,access,now=Date.now}){Object.assign(this,{store,access,now});}
  public(uid,row){return {uid,revision:row?.revision??0,photo:row?.photo??null};}
  async get(uid){return this.store.atomic(async tx=>{await this.access(tx,uid);const row=await tx.get(`profilePhotos/${uid}`);check(!row?.photo||validProfilePhoto(row.photo),'PROFILE_PHOTO_UNAVAILABLE',503);return this.public(uid,row);});}
  async save(uid,input){
    check(keys(input,['requestId','revision','photo'])&&typeof input.requestId==='string'&&/^[A-Za-z0-9_-]{1,150}$/.test(input.requestId)&&Number.isInteger(input.revision)&&input.revision>=0&&(input.photo===null||validProfilePhoto(input.photo)),'INVALID_PROFILE_PHOTO');
    const fingerprint=createHash('sha256').update(JSON.stringify({revision:input.revision,photo:input.photo})).digest('hex');
    return this.store.atomic(async tx=>{
      await this.access(tx,uid);const path=`profilePhotos/${uid}`,old=await tx.get(path);
      if(old?.requestId===input.requestId){check(old.fingerprint===fingerprint,'REQUEST_CONFLICT',409);return this.public(uid,old);}
      check((old?.revision??0)===input.revision,'PROFILE_PHOTO_CHANGED',409);
      const row={photo:input.photo,revision:input.revision+1,requestId:input.requestId,fingerprint,updatedAt:this.now()};
      // Retain the removal revision, preventing stale uploads from resurrecting
      // a deleted picture (no delete/recreate revision reset).
      tx.set(path,row);return this.public(uid,row);
    });
  }
}
