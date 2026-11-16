// Read-only rollout diagnostics. Never print customer IDs, amounts or secrets.
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
let app;
try{
 loadEnvFile('.env');const credential=JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS,'utf8'));
 if(credential.project_id!=='luvly-44c77')throw Error();
 app=initializeApp({credential:cert(credential)});const db=getFirestore(app);
 const creating=await db.collection('sandboxInvoices').where('state','==','Creating').get();
 const recent=creating.docs.filter(d=>d.data().updatedAt>Date.now()-5*60000).length;
 console.log(JSON.stringify({recentBillCreations:recent,rolloutSafe:recent===0,
  fittingInvoices:(await db.collection('sandboxInvoices').where('purpose','==','FittingFee').count().get()).data().count,
  policyRentals:(await db.collection('rentals').where('policyVersion','==',1).count().get()).data().count}));
 if(recent)process.exitCode=2;
 await db.terminate();
}catch{console.log('BILLING_READINESS_UNAVAILABLE');process.exitCode=1;}
finally{if(app)await deleteApp(app);}
