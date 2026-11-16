// Read-only live verification. Logs no account identifiers or review content.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
import {FirestoreStore} from './firestore_store.mjs';
import {CustomerReviews} from './customer_reviews.mjs';
import {productEditorial} from './product_editorial.mjs';
import {isDeepStrictEqual} from 'node:util';
const base=dirname(fileURLToPath(import.meta.url));loadEnvFile(resolve(base,'.env'));
const credentials=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credentials.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(credentials)});
try{
 const db=getFirestore(app),store=new FirestoreStore(db),service=new CustomerReviews({store});
 const customers=await db.collection('brides').limit(20).get();let uid;
 for(const customer of customers.docs){if(!(await db.doc(`staff/${customer.id}`).get()).exists){uid=customer.id;break;}}
 if(!uid)throw Error('No existing customer available for read-only permission verification');
 const aggregates=await service.ratings(uid);
 console.log(JSON.stringify({catalogueRatingProducts:aggregates.ratings.length,customerRatingCount:aggregates.ratings.reduce((n,r)=>n+r.count,0)}));
 for(const [id,wanted] of Object.entries(productEditorial)){
  const dress=(await db.doc(`dresses/${id}`).get()).data();
  if(dress.description!==wanted.description||!isDeepStrictEqual(dress.productDetails,wanted.productDetails))throw Error('Product metadata mismatch');
  const result=await service.list(uid,'all',id),eligible=await service.options(uid,id);
  console.log(JSON.stringify({product:id,metadataVerified:true,publishedReviewCount:result.summary.count,eligibleOwnRentals:eligible.rentals.length}));
 }
}finally{await deleteApp(app);}
