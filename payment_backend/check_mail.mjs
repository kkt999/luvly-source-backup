// Safe setup diagnostic: never print credentials, recipient addresses or SMTP responses.
import {gmailMail} from './appointment_mail.mjs';
import {readFileSync} from 'node:fs';
import {loadEnvFile} from 'node:process';
import {initializeApp,cert} from 'firebase-admin/app';
import {getFirestore} from 'firebase-admin/firestore';
let db,mail;
try {
  const config=JSON.parse(readFileSync('secrets/mail-config.json','utf8'));
  console.log(JSON.stringify({configuration:{enabled:config.enabled===true,
    emailValid:/^[A-Za-z0-9._%+-]+@gmail\.com$/i.test(config.email ?? ''),
    appPasswordPresent:typeof config.appPassword==='string' && config.appPassword.trim().length>0,
    appPasswordFormatValid:/^[a-zA-Z]{16}$/.test(String(config.appPassword ?? '').replace(/\s/g,''))}}));
  mail=gmailMail(null,'secrets/mail-config.json');
  if(!mail){console.log('MAIL_DISABLED_OR_MISSING');process.exitCode=1;}
  else {
    if(!process.argv.includes('--queue-only')) {
      await mail.transport.verify();
      console.log('GMAIL_SMTP_AUTHENTICATION_OK');
    }
    loadEnvFile('.env');
    const c=JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS,'utf8'));
    if(c.project_id!=='luvly-44c77')throw Error('WRONG_PROJECT');
    db=getFirestore(initializeApp({credential:cert(c)}));
    const counts={};
    for(const state of ['Queued','Sending','Sent','ReviewRequired','Superseded']){
      counts[state]=(await db.collection('appointmentMail').where('state','==',state).count().get()).data().count;
    }
    console.log(JSON.stringify({appointmentMail:counts}));
  }
}catch(e){
  const known=['MAIL_CONFIG_INVALID','WRONG_PROJECT','EAUTH','ECONNECTION','ETIMEDOUT','ESOCKET','EDNS'];
  console.log('MAIL_CHECK_FAILED:'+ (known.includes(e.code)?e.code:known.includes(e.message)?e.message:'CONFIG_OR_SERVICE_UNAVAILABLE'));
  process.exitCode=1;
}finally{mail?.transport.close();if(db)await db.terminate();}
