import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
const base=dirname(fileURLToPath(import.meta.url));
loadEnvFile(resolve(base,'.env'));
const key=JSON.parse(readFileSync(resolve(base,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(key.project_id!=='luvly-44c77')throw Error('Wrong project');
const app=initializeApp({credential:cert(key)});
try {
 const db=getFirestore(app);
 const [products,variants,packages,refs]=await Promise.all(['dresses','rentalVariants','servicePackages','arDressModels'].map(c=>db.collection(c).get()));
 console.log(JSON.stringify({products:products.docs.map(d=>({id:d.id,name:d.data().name,priceCents:d.data().priceCents,sizes:d.data().sizes,arModelId:d.data().arModelId,published:d.data().published,revision:d.data().revision})),variants:variants.docs.map(d=>({id:d.id,dressId:d.data().dressId,size:d.data().size,quantity:d.data().quantity})),packages:packages.docs.map(d=>({id:d.id,name:d.data().name,active:d.data().active,basePriceCents:d.data().basePriceCents,includedGownCount:d.data().includedGownCount,eligibleDressIds:d.data().eligibleDressIds,revision:d.data().revision})),references:refs.docs.map(d=>({id:d.id,rentalEnabled:d.data().rentalEnabled,thumbnail:!!d.data().thumbnailUrl}))},null,2));
} finally {await deleteApp(app);}
