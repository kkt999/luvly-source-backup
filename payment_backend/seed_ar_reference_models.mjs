// Explicit administrator import. AR metadata belongs outside rentable dresses.
// Default is read-only preparation. --apply creates missing records atomically.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore,FieldValue} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';

const base=dirname(fileURLToPath(import.meta.url)),root=resolve(base,'..');
const catalogue=JSON.parse(readFileSync(resolve(root,'design/dresses/ar_reference_catalogue.json'),'utf8'));
const expected=['francine-reference','princess-wedding','elegant-local-review'];
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
if(catalogue.length!==3||expected.some(id=>catalogue.filter(x=>x.modelId===id).length!==1))throw Error('Unexpected catalogue');
const photos=new Map();
for(const model of catalogue){
  if(!/^assets\/images\/[a-z_]+\.jpg$/.test(model.thumbnailAsset)||
     !['Sheath','Ball Gown','A-Line'].includes(model.category)||
     !['PublicReference','AndroidDebugOnly'].includes(model.visibility)||
     ['priceCents','sizes','quantity','stock'].some(k=>k in model))throw Error('Invalid display metadata');
  if(model.modelId==='elegant-local-review'&&model.visibility!=='AndroidDebugOnly')throw Error('Local review flag required');
  const bytes=readFileSync(resolve(root,model.thumbnailAsset));
  if(bytes.length>200*1024||bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)throw Error('Invalid reference thumbnail');
  photos.set(model.modelId,{bytes,hash:digest(bytes)});
}
loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(key),projectId:'luvly-44c77'});
try{
  const db=getFirestore(app),collection=db.collection('arDressModels');
  const before=await collection.get();
  const products=await db.collection('dresses').get();
  const pending=catalogue.filter(m=>!before.docs.some(d=>d.id===m.modelId||d.data().modelId===m.modelId));
  for(const doc of before.docs){
    if(expected.includes(doc.id)&&(doc.data().kind!=='ARReference'||
       !(doc.data().rentalEnabled===false || (doc.data().rentalEnabled===true && typeof doc.data().catalogueDressId==='string'))))
      throw Error('Existing record needs manual review; nothing overwritten');
  }
  console.log(JSON.stringify({mode:process.argv.includes('--apply')?'apply':'prepare',
    existingRentableCatalogueRecords:products.size,existingArRecords:before.size,
    add:pending.map(m=>({id:m.modelId,name:m.name,visibility:m.visibility})),
    collection:'arDressModels',rentalEnabled:false}));
  if(process.argv.includes('--apply')){
    const backupDir=resolve(base,'secrets/catalogue-backups');mkdirSync(backupDir,{recursive:true});
    const stamp=Date.now();
    writeFileSync(resolve(backupDir,`ar-reference-${stamp}.json`),JSON.stringify({
      project:'luvly-44c77',collection:'arDressModels',createdAt:new Date().toISOString(),
      existing:before.docs.map(d=>({id:d.id,data:d.data()})),
      existingProductIds:products.docs.map(d=>d.id),createOnly:pending.map(m=>m.modelId),
    },null,2));
    const bucket=getStorage(app).bucket('luvly-44c77.firebasestorage.app');
    const records=[];
    for(const model of pending){
      const photo=photos.get(model.modelId);
      const objectPath=`ar-reference-thumbnails/${model.modelId}-${photo.hash.slice(0,16)}.jpg`;
      const file=bucket.file(objectPath);const[exists]=await file.exists();
      if(!exists)await file.save(photo.bytes,{resumable:false,validation:'crc32c',
        preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:'image/jpeg',
          cacheControl:'public,max-age=31536000,immutable',metadata:{sha256:photo.hash,
            firebaseStorageDownloadTokens:randomUUID(),purpose:'Public reference model thumbnail; no customer media'}}});
      const[meta]=await file.getMetadata();
      if(meta.metadata?.sha256!==photo.hash)throw Error('Thumbnail mismatch');
      const token=meta.metadata?.firebaseStorageDownloadTokens;
      if(!/^[a-f0-9-]{36}$/.test(token??''))throw Error('Invalid thumbnail link');
      const thumbnailUrl=`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(objectPath)}?alt=media&token=${token}`;
      records.push({...model,thumbnailUrl,thumbnailSha256:photo.hash,
        schemaVersion:1,kind:'ARReference',rentalEnabled:false,published:true,
        createdBy:'admin-ar-reference-import',createdAt:FieldValue.serverTimestamp(),
        updatedBy:'admin-ar-reference-import',updatedAt:FieldValue.serverTimestamp()});
    }
    const batch=db.batch();
    for(const model of records)batch.create(collection.doc(model.modelId),model);
    if(records.length)await batch.commit();
    const after=await collection.get();
    for(const id of expected){
      const row=after.docs.find(d=>d.id===id||d.data().modelId===id)?.data();
      if(!row||!(row.rentalEnabled===false || (row.rentalEnabled===true && typeof row.catalogueDressId==='string'))||row.kind!=='ARReference'||
         ['priceCents','sizes','quantity','stock'].some(k=>k in row))throw Error('Reference verification failed');
    }
    const productsAfter=await db.collection('dresses').get();
    if(digest(JSON.stringify(products.docs.map(d=>[d.id,d.data()])))!==
       digest(JSON.stringify(productsAfter.docs.map(d=>[d.id,d.data()]))))
      throw Error('Product catalogue changed during import; inspect concurrent edits');
    console.log(JSON.stringify({verified:true,created:records.length,arReferenceRecords:after.size,
      rentableCatalogueRecords:productsAfter.size,productCatalogueUnchanged:true,
      backup:`secrets/catalogue-backups/ar-reference-${stamp}.json`}));
  }
}finally{await deleteApp(app);}
