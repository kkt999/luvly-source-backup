// Read-only diagnosis. Never log credentials or customer contact details.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
const dir=dirname(fileURLToPath(import.meta.url));loadEnvFile(resolve(dir,'.env'));
const credential=JSON.parse(readFileSync(resolve(dir,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
if(credential.project_id!=='luvly-44c77')throw Error('Wrong project');
const db=getFirestore(initializeApp({credential:cert(credential),projectId:credential.project_id}));
try {
  const selections=await db.collection('packageSelections').orderBy('createdAt','desc').limit(8).get();
  for(const doc of selections.docs){
    const s=doc.data();const appointments=[];
    for(const id of s.appointmentIds??[]){const b=(await db.doc(`appointments/${id}`).get()).data();appointments.push({id:id.slice(0,8),status:b?.status??'Missing',start:b?.startAt?.toDate?.().toISOString()??null,linkedToOwner:b?.uid===s.uid});}
    console.log(JSON.stringify({selection:doc.id.slice(0,8),package:s.name,createdAt:new Date(s.createdAt).toISOString(),rentalPlan:s.rentalPlan??null,appointments,rentalCreated:!!s.rentalId}));
  }
  const requested=await db.collection('appointments').where('status','==','Requested').get();
  console.log('Requested appointment count:',requested.size);
} finally {await db.terminate();}
