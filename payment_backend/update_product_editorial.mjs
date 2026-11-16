// Explicit, bounded editorial updates and factual review indexing. No prices,
// quantities, payments, review text, ratings or moderation state are changed.
import {loadEnvFile} from 'node:process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore,FieldValue} from 'firebase-admin/firestore';
import {productEditorial} from './product_editorial.mjs';
import {reviewGownIds} from './customer_reviews.mjs';
import {isDeepStrictEqual} from 'node:util';
const base=dirname(fileURLToPath(import.meta.url));loadEnvFile(resolve(base,'.env'));
const credentials=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credentials.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(credentials)});
try{
 const db=getFirestore(app),refs=Object.keys(productEditorial).map(id=>db.doc(`dresses/${id}`));
 const dresses=await db.getAll(...refs),reviews=await db.collection('customerReviews').limit(1001).get();
 if(reviews.size>1000)throw Error('Review migration limit exceeded');
 for(const d of dresses)if(!d.exists||d.data().name!==productEditorial[d.id].name||!Number.isInteger(d.data().revision))throw Error('Unexpected product record');
 const links=[];
 for(const review of reviews.docs){
  const r=review.data();if(typeof r.rentalId!=='string'||!/^[A-Za-z0-9_-]{1,150}$/.test(r.rentalId))continue;
  const rental=await db.doc(`rentals/${r.rentalId}`).get();
  if(!rental.exists||rental.data().uid!==r.uid)continue;
  const ids=reviewGownIds(rental.data());
  if(JSON.stringify(ids)!==JSON.stringify(r.gownIds??[]))links.push({review,rental,ids});
 }
 console.log(JSON.stringify({products:dresses.map(d=>({id:d.id,name:d.data().name,revision:d.data().revision})),reviewsScanned:reviews.size,reviewIndexesToUpdate:links.length,changes:'Descriptions, bounded product details and actual-rental gown IDs only'}));
 if(process.argv.includes('--apply')){
  const folder=resolve(base,'secrets/catalogue-backups');mkdirSync(folder,{recursive:true});
  writeFileSync(resolve(folder,`product-editorial-before-${Date.now()}.json`),JSON.stringify({dresses:dresses.map(d=>({id:d.id,data:d.data()})),reviews:links.map(l=>({id:l.review.id,data:l.review.data(),rentalId:l.rental.id,gowns:l.rental.data().gowns}))},null,2));
  await db.runTransaction(async tx=>{
   const current=await tx.getAll(...refs);
   const currentLinks=links.length?await tx.getAll(...links.flatMap(l=>[l.review.ref,l.rental.ref])):[];
   current.forEach((d,i)=>{if(!d.updateTime.isEqual(dresses[i].updateTime))throw Error('Product changed concurrently');});
   links.forEach((l,i)=>{if(!currentLinks[i*2].updateTime.isEqual(l.review.updateTime)||!currentLinks[i*2+1].updateTime.isEqual(l.rental.updateTime))throw Error('Review or rental changed concurrently');});
   for(const d of current){const item=productEditorial[d.id];tx.update(d.ref,{description:item.description,productDetails:item.productDetails,revision:d.data().revision+1,updatedBy:'catalogue-editorial-2106',updatedAt:FieldValue.serverTimestamp()});}
   for(const l of links)tx.update(l.review.ref,{gownIds:l.ids});
  });
  const after=await db.getAll(...refs);
  for(let i=0;i<after.length;i++){
   const d=after[i].data(),old=dresses[i].data(),wanted=productEditorial[after[i].id];
   if(d.description!==wanted.description||!isDeepStrictEqual(d.productDetails,wanted.productDetails)||d.priceCents!==old.priceCents||d.sizes!==old.sizes||d.photoRevision!==old.photoRevision)throw Error('Editorial verification failed');
  }
  for(const l of links){const r=(await l.review.ref.get()).data();if(JSON.stringify(r.gownIds)!==JSON.stringify(l.ids)||r.stars!==l.review.data().stars||r.text!==l.review.data().text||r.revision!==l.review.data().revision)throw Error('Review index verification failed');}
  console.log('Product information and factual review indexes saved and verified.');
 }
}finally{await deleteApp(app);}
