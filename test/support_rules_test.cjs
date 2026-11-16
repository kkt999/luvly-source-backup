const assert = require('node:assert/strict');
const ah=process.env.FIREBASE_AUTH_EMULATOR_HOST, dh=process.env.FIRESTORE_EMULATOR_HOST;
for(const h of [ah,dh]) assert.match(h||'',/^(localhost|127\.0\.0\.1):\d+$/);
const prefix='projects/demo-luvly/databases/(default)/documents/';
const base=`http://${dh}/v1/${prefix.slice(0,-1)}`;
const enc=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k,typeof v==='number'?{integerValue:String(v)}:typeof v==='boolean'?{booleanValue:v}:{stringValue:v}]));
async function req(url,token,body,method='POST') {const r=await fetch(url,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json()};}
async function user(n){return (await req(`http://${ah}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`,null,{email:`support-${n}@example.com`,password:'Support1!test',returnSecureToken:true})).data;}
const write=(path,data,times,create=false)=>({update:{name:prefix+path,fields:enc(data)},...(create?{currentDocument:{exists:false}}:{updateMask:{fieldPaths:Object.keys(data)}}),updateTransforms:times.map(fieldPath=>({fieldPath,setToServerValue:'REQUEST_TIME'}))});
const commit=(u,writes)=>req(`${base}:commit`,u.idToken,{writes});
let n=0;function check(r,status,label){assert.equal(r.status,status,`${label}: ${JSON.stringify(r.data)}`);console.log('PASS '+label);n++;}
(async()=>{
 const a=await user('a'),b=await user('b'),s=await user('staff');
 for(const u of [a,b])await req(`${base}/brides/${u.localId}`,'owner',{fields:enc({name:'Jane'})},'PATCH');
 await req(`${base}/staff/${s.localId}`,'owner',{fields:enc({name:'John',active:true,role:'staff'})},'PATCH');
 const ticket={uid:a.localId,name:'Jane',subject:'Fitting question',category:'Appointments',status:'Open',revision:1,lastMessageId:'m1',updatedBy:a.localId};
 const msg=(u,id,body='Hello',role='bride')=>write(`supportTickets/a/messages/${id}`,{body,senderId:u.localId,senderName:role==='staff'?'John':'Jane',senderRole:role},['sentAt'],true);
 const update=(u,id,revision,status)=>write('supportTickets/a',{lastMessageId:id,revision,status,updatedBy:u.localId},['updatedAt']);
 check(await commit(a,[write('supportTickets/a',ticket,['createdAt','updatedAt'],true)]),403,'ticket requires first message');
 check(await commit(a,[write('supportTickets/a',ticket,['createdAt','updatedAt'],true),msg(a,'m1')]),200,'atomic ticket creation');
 for(const [u,status,label] of [[a,200,'owner'],[b,403,'other bride'],[s,200,'staff']])check(await req(`${base}/supportTickets/a`,u.idToken,null,'GET'),status,label+' ticket read');
 check(await req(`${base}/supportTickets/a/messages/m1`,b.idToken,null,'GET'),403,'other bride message denied');
 check(await req(`${base}/supportTickets/a`,null,null,'GET'),403,'anonymous denied');
 check(await commit(a,[update(a,'m2',2,'In Progress'),msg(a,'m2','Hello','staff')]),403,'role spoof denied');
 check(await commit(s,[update(s,'m2',2,'In Progress'),msg(s,'m2','We can help','staff')]),200,'staff replies');
 check(await commit(a,[update(a,'m3',3,'Open'),msg(a,'m3','   ')]),403,'blank denied');
 check(await commit(a,[update(a,'m3',3,'Open'),msg(a,'m3','a'.repeat(2001))]),403,'oversized denied');
 check(await commit(b,[update(b,'m3',3,'Open'),msg(b,'m3')]),403,'cross-account reply denied');
 check(await commit(a,[update(a,'m3',3,'Open'),msg(a,'m3','Thank you')]),200,'bride replies');
 check(await commit(a,[write('supportTickets/a/messages/m1',{body:'Changed'},[])]),403,'history immutable');
 check(await commit(a,[update(a,'m3',3,'Closed')]),403,'stale close denied');
 check(await commit(a,[update(a,'m3',4,'Closed')]),200,'owner closes');
 check(await commit(s,[update(s,'m4',5,'In Progress'),msg(s,'m4','Late reply','staff')]),403,'closed ticket reply denied');
 check(await req(`${base}/brides/${a.localId}`,s.idToken,null,'GET'),403,'private profile remains private');
 await req(`${base}/staff/${s.localId}`,'owner',{fields:enc({name:'John',active:false,role:'staff'})},'PATCH');
 check(await req(`${base}/supportTickets/a`,s.idToken,null,'GET'),403,'revoked staff denied');
 console.log(`${n} support security checks passed`);
})().catch(e=>{console.error(e);process.exitCode=1;});
