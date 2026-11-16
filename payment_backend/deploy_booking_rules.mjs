// Only close direct appointment writes; preserve deployed permissions elsewhere.
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {initializeApp,cert} from 'firebase-admin/app';
import {getSecurityRules} from 'firebase-admin/security-rules';
loadEnvFile('.env');
try {
 const c=JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS,'utf8'));
 if(c.project_id!=='luvly-44c77')throw Error('WRONG_PROJECT');
 const api=getSecurityRules(initializeApp({credential:cert(c)}));
 const norm=s=>s.replace(/\r\n/g,'\n').trim();
 const before=norm(readFileSync('logs/booking-before-revision3.rules','utf8')),after=norm(readFileSync('../firestore.rules','utf8'));
 const approved=before.replace('allow create: if request.auth != null && validAppointment(request.resource.data)','allow create: if false && request.auth != null && validAppointment(request.resource.data)')
   .replace('allow update: if request.auth != null && validAppointment(request.resource.data)','allow update: if false && request.auth != null && validAppointment(request.resource.data)')
   .replace('allow create: if staffAccess()\n        && request.resource.data.keys().hasAll','allow create: if false && staffAccess()\n        && request.resource.data.keys().hasAll')
   .replace('allow delete: if request.auth != null && (staffAccess() || resource.data.uid == request.auth.uid)','allow delete: if false && request.auth != null && (staffAccess() || resource.data.uid == request.auth.uid)');
 if(approved!==after)throw Error('UNRELATED_LOCAL_CHANGE');
 const remote=await api.getFirestoreRuleset();
 if(norm(remote.source[0].content)===after){console.log('Booking rules already deployed.');}
 else {
   if(norm(remote.source[0].content)!==before)throw Error('REMOTE_RULES_DIFFER');
   console.log('Verified narrow change: direct appointment writes close; authenticated reads preserved.');
   if(process.argv.includes('--publish')){
     if((await api.getFirestoreRuleset()).name!==remote.name)throw Error('RULES_CHANGED');
     await api.releaseFirestoreRulesetFromSource(after);
     if(norm((await api.getFirestoreRuleset()).source[0].content)!==after)throw Error('VERIFY_FAILED');
     console.log('Booking rules published and verified.');
   }
 }
}catch(e){console.error(/^[A-Z_]+$/.test(e.message)?e.message:'RULES_DEPLOY_FAILED');process.exitCode=1;}
