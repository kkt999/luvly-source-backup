// User-authorized FYP fixture provisioning, not a claim of real boutique stock.
// Dry run by default; one guarded transaction, create-only products and stock.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore,FieldValue} from 'firebase-admin/firestore';
import {variantId,rentalDates} from './rental_service.mjs';
import {demoMeasurements} from './demo_measurements.mjs';
import {stockStatus} from './rental_availability.mjs';

const base=dirname(fileURLToPath(import.meta.url)),root=resolve(base,'..');
const catalogue=JSON.parse(readFileSync(resolve(root,'design/dresses/ar_reference_catalogue.json'),'utf8'));
export const demoGowns=[
 {id:'demo-francine',modelId:'francine-reference',name:'Francine Gown',priceCents:49900,
  description:'An ivory sheath-style gown with a folded neckline, fitted silhouette and flared hem. FYP demonstration rental catalogue; imagery is a 3D render. Fit and alterations are confirmed at your fitting.'},
 {id:'demo-princess',modelId:'princess-wedding',name:'Princess Wedding Dress',priceCents:59900,
  description:'A white ball gown with layered lace, floral details and a sweeping train. FYP demonstration rental catalogue; imagery is a 3D render. Fit and alterations are confirmed at your fitting.'},
 {id:'demo-elegant',modelId:'elegant-local-review',name:'Elegant Bridal Gown',priceCents:54900,
  description:'A white A-line bridal gown with delicate tulle and a long train. FYP demonstration rental catalogue; imagery is a 3D render. Fit and alterations are confirmed at your fitting.'},
];
const sizes=['S','M','L','XL'];
function jpegSize(b){
 if(b.length>200*1024||b[0]!==255||b[1]!==216||b.at(-2)!==255||b.at(-1)!==217)throw Error('Invalid photo');
 let i=2;
 while(i<b.length){
  if(b[i++]!==255)throw Error('Invalid JPEG marker');
  while(b[i]===255)i++;
  const m=b[i++],n=b.readUInt16BE(i);
  if([0xc0,0xc1,0xc2].includes(m)){
   const height=b.readUInt16BE(i+3),width=b.readUInt16BE(i+5);
   if(width<1||height<1||width>1200||height>1200)throw Error('Invalid photo dimensions');
   return {width,height};
  }
  i+=n;
 }
 throw Error('JPEG dimensions missing');
}
const photos=new Map(demoGowns.map(g=>{
 const m=catalogue.find(m=>m.modelId===g.modelId);
 if(!m)throw Error('Unknown model');
 const bytes=readFileSync(resolve(root,m.thumbnailAsset));
 return [g.id,{data:bytes.toString('base64'),mime:'image/jpeg',...jpegSize(bytes)}];
}));
loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(key),projectId:key.project_id});
try{
 const db=getFirestore(app),marker=db.doc('catalogueImports/demo-gowns-20261030');
 const [products,packages,refs,staff]=await Promise.all(['dresses','servicePackages','arDressModels','staff'].map(c=>db.collection(c).get()));
 const actor=staff.docs.find(d=>d.data().active===true&&d.data().role==='manager')?.id;
 if(!actor)throw Error('Active manager required');
 const packageDocs=packages.docs.filter(d=>d.data().active===true&&d.data().includedGownCount>0);
 const targetPaths=demoGowns.flatMap(g=>[`dresses/${g.id}`,`dressPhotos/${g.id}`,...sizes.map(s=>`rentalVariants/${variantId(g.id,s)}`)]);
 const targets=await db.getAll(...targetPaths.map(p=>db.doc(p)),marker);
 const applied=targets.at(-1).exists;
 if(!applied&&targets.slice(0,-1).some(d=>d.exists))throw Error('Existing target requires review; nothing overwritten');
 for(const g of demoGowns){
  if(!refs.docs.some(d=>d.id===g.modelId))throw Error('AR metadata missing');
  if(products.docs.some(d=>d.id!==g.id&&d.data().arModelId===g.modelId))throw Error('Duplicate linked product');
 }
 console.log(JSON.stringify({mode:process.argv.includes('--apply')?'apply':'prepare',alreadyApplied:applied,
  gowns:demoGowns.map(g=>({id:g.id,name:g.name,priceCents:g.priceCents,sizes,quantityPerSize:1})),
  packageEligibility:packageDocs.map(d=>d.id),existingOrdersChanged:false}));
 if(process.argv.includes('--apply')&&!applied){
  const backupDir=resolve(base,'secrets/catalogue-backups');mkdirSync(backupDir,{recursive:true});
  const backup=resolve(backupDir,`demo-gowns-before-${Date.now()}.json`);
  writeFileSync(backup,JSON.stringify({project:key.project_id,createdAt:new Date().toISOString(),
   targetPaths,products:products.docs.map(d=>({id:d.id,data:d.data()})),
   packages:packages.docs.map(d=>({id:d.id,data:d.data()})),references:refs.docs.map(d=>({id:d.id,data:d.data()}))},null,2));
  await db.runTransaction(async tx=>{
   const current=await tx.getAll(...targetPaths.map(p=>db.doc(p)),marker,...packageDocs.map(d=>d.ref),...demoGowns.map(g=>db.doc(`arDressModels/${g.modelId}`)));
   if(current.slice(0,targetPaths.length+1).some(d=>d.exists))throw Error('Targets changed concurrently');
   const currentPackages=current.slice(targetPaths.length+1,targetPaths.length+1+packageDocs.length);
   for(let i=0;i<packageDocs.length;i++)if(currentPackages[i].data()?.revision!==packageDocs[i].data().revision)throw Error('Package changed concurrently');
   for(const g of demoGowns){
    const m=catalogue.find(m=>m.modelId===g.modelId);
    tx.create(db.doc(`dresses/${g.id}`),{name:g.name,category:m.category,description:g.description,colour:m.colour,
     sizes:sizes.join(', '),priceCents:g.priceCents,imageUrl:'',photoRevision:1,arModelId:g.modelId,
     availability:'Available',published:true,revision:1,createdBy:actor,updatedBy:actor,
     createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});
    tx.create(db.doc(`dressPhotos/${g.id}`),{...photos.get(g.id),revision:1,updatedBy:actor,updatedAt:FieldValue.serverTimestamp()});
    for(const size of sizes){
     const id=variantId(g.id,size);
     tx.create(db.doc(`rentalVariants/${id}`),{id,dressId:g.id,size,quantity:1,revision:1,allocations:{},updatedBy:actor,
      measurements:demoMeasurements(size),measurementSource:'demo-reference',
      measurementNote:'Illustrative FYP body ranges; not measured garments. Confirm actual fit with staff.'});
    }
    tx.update(db.doc(`arDressModels/${g.modelId}`),{rentalEnabled:true,catalogueDressId:g.id,updatedBy:actor,updatedAt:FieldValue.serverTimestamp()});
   }
   for(const p of currentPackages){
    const old=p.data();
    tx.update(p.ref,{eligibleDressIds:[...new Set([...(old.eligibleDressIds??[]),...demoGowns.map(g=>g.id)])],
     revision:old.revision+1,updatedBy:actor,updatedAt:Date.now()});
   }
   tx.create(marker,{kind:'FYPDemoCatalogue',productIds:demoGowns.map(g=>g.id),quantityPerSize:1,sizes,
    actorId:actor,createdAt:FieldValue.serverTimestamp(),backupPath:backup});
  });
  console.log('Applied guarded catalogue import; prior business records preserved.');
 }
 if(process.argv.includes('--apply')||applied){
  const documents=await db.getAll(...targetPaths.map(p=>db.doc(p)));
  if(documents.some(d=>!d.exists))throw Error('Incomplete import');
  for(const g of demoGowns){
   const product=documents.find(d=>d.ref.path===`dresses/${g.id}`).data();
   if(product.arModelId!==g.modelId||!product.published)throw Error('Invalid product link');
   for(const size of sizes){
    const v=documents.find(d=>d.ref.path===`rentalVariants/${variantId(g.id,size)}`).data();
    if(v.dressId!==g.id||v.size!==size||!Number.isInteger(v.quantity)||v.quantity<0)throw Error('Invalid stock');
   }
  }
  const now=Date.now(),day=new Date(now+8*3600000).toISOString().slice(0,10);
  const dates=rentalDates({pickupDate:day,eventDate:day,returnDate:day},now);
  const variants=documents.filter(d=>d.ref.path.startsWith('rentalVariants/'));
  const packageChecks=await Promise.all(packageDocs.map(async p=>{
   const latest=(await p.ref.get()).data();
   return {id:p.id,newGownsEligible:demoGowns.every(g=>latest.eligibleDressIds?.includes(g.id)),
    priceUnchanged:latest.basePriceCents===p.data().basePriceCents};
  }));
  if(packageChecks.some(p=>!p.newGownsEligible||!p.priceUnchanged))throw Error('Package eligibility verification failed');
  console.log(JSON.stringify({verified:true,rentableProducts:(await db.collection('dresses').get()).size,
   createdVariantRecords:variants.length,availableNow:variants.filter(d=>stockStatus(d.data(),dates,now)==='Available').length,
   packages:packageChecks}));
 }
}finally{await deleteApp(app);}
