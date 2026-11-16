// Explicit administrator tool, never exposed by the HTTP backend.
// Publishes only the attributed static Princess reference model, not user media.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getStorage} from 'firebase-admin/storage';

const directory=dirname(fileURLToPath(import.meta.url));
const root=resolve(directory,'..');
const manifest=JSON.parse(readFileSync(resolve(root,'design/dresses/princess_room.json'),'utf8'));
const bytes=readFileSync(resolve(root,'design/dresses/princess_room.glb'));
const hash=createHash('sha256').update(bytes).digest('hex');
if(hash!==manifest.sha256||bytes.length!==manifest.bytes||bytes.length>10_000_000||
   manifest.modelId!=='princess-wedding'||manifest.hasDepthProxy||manifest.hasMorphTargets)
  throw Error('Static model validation failed');
const bucketName='luvly-44c77.firebasestorage.app';
const objectPath=`ar-models/princess-room-${hash.slice(0,16)}.glb`;
console.log(JSON.stringify({objectPath,bytes:bytes.length,sha256:hash,publish:process.argv.includes('--publish')}));
if(!process.argv.includes('--publish'))process.exit(0);
loadEnvFile(resolve(directory,'.env'));
const credential=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credential.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(credential),projectId:'luvly-44c77'});
try {
  const bucket=getStorage(app).bucket(bucketName);
  const file=bucket.file(objectPath);
  const [exists]=await file.exists();
  if(!exists)await file.save(bytes,{resumable:false,validation:'crc32c',
    preconditionOpts:{ifGenerationMatch:0},metadata:{
      contentType:'model/gltf-binary',cacheControl:'public, max-age=31536000, immutable',
      metadata:{sha256:hash,firebaseStorageDownloadTokens:randomUUID(),
        attribution:'Princess Wedding Dress by Messrs, CC BY 4.0; adapted by Luvly',
        purpose:'Static public AR reference model; no user media'},
    }});
  const [metadata]=await file.getMetadata();
  if(metadata.metadata?.sha256!==hash||Number(metadata.size)!==bytes.length)throw Error('Remote object mismatch');
  const token=metadata.metadata?.firebaseStorageDownloadTokens;
  if(!/^[0-9a-f-]{36}$/.test(token??''))throw Error('Unexpected model token');
  const url=`https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
  const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(45000)});
  if(!response.ok)throw Error('Public model download unavailable');
  const downloaded=Buffer.from(await response.arrayBuffer());
  if(createHash('sha256').update(downloaded).digest('hex')!==hash)throw Error('Download integrity failed');
  writeFileSync(resolve(root,'android/app/src/main/kotlin/com/luvly/luvly_app/ar/RoomModelDownload.kt'),
    `package com.luvly.luvly_app.ar\n\n// Public static reference asset; not a credential or a customer-media URL.\n`+
    `internal object RoomModelDownload {\n    const val URL = ${JSON.stringify(url)}\n}\n`);
  console.log('PASS static model published and anonymous HTTPS download SHA-256 verified. No IAM, rules or business records changed.');
}finally{await deleteApp(app);}
