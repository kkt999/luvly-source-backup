// Read-only setup check: no account provisioning, Firestore writes, or emails.
import {loadEnvFile} from 'node:process';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initializeApp,cert,deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';
import {gmailMail} from './appointment_mail.mjs';
const directory=dirname(fileURLToPath(import.meta.url));let app;
try {
  loadEnvFile(resolve(directory,'.env'));
  const credential=JSON.parse(readFileSync(resolve(directory,process.env.GOOGLE_APPLICATION_CREDENTIALS),'utf8'));
  if(credential.project_id!=='luvly-44c77')throw Error();
  app=initializeApp({credential:cert(credential),projectId:'luvly-44c77'});
  const db=getFirestore(app),staff=await db.collection('staff').where('active','==',true).select('role').limit(101).get();
  const manager=staff.docs.find(d=>d.data().role==='manager');if(!manager)throw Error();
  await getAuth(app).getUser(manager.id);
  const mail=gmailMail(db,resolve(directory,'secrets/mail-config.json'));
  if(!mail)throw Error();await mail.transport.verify();mail.transport.close();
  console.log(JSON.stringify({adminAuthRead:'verified',mailConfiguration:'present',smtpConnection:'verified',accountsChanged:0,emailsSent:0}));
}catch{
  console.error('Staff account setup check did not complete. Review local Admin Auth permissions and mail configuration; no account or email was changed.');
  process.exitCode=1;
}finally{if(app)await deleteApp(app);}
