// Emulator-only security acceptance tests. Never uses the real project.
const assert=require('node:assert/strict');
const ah=process.env.FIREBASE_AUTH_EMULATOR_HOST, dh=process.env.FIRESTORE_EMULATOR_HOST;
assert.match(ah||'',/^(localhost|127\.0\.0\.1):\d+$/);
assert.match(dh||'',/^(localhost|127\.0\.0\.1):\d+$/);
const base=`http://${dh}/v1/projects/demo-luvly/databases/(default)/documents`;
const prefix='projects/demo-luvly/databases/(default)/documents/';
const encode=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k,v instanceof Date?{timestampValue:v.toISOString()}:typeof v==='number'?{integerValue:String(v)}:typeof v==='boolean'?{booleanValue:v}:{stringValue:v}]));
async function req(url,token,body,method='POST') {
 const r=await fetch(url,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});
 return {status:r.status,data:await r.json()};
}
async function user(name) {return (await req(`http://${ah}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`,null,{email:`booking-${name}@example.com`,password:'Booking1!test',returnSecureToken:true})).data;}
const write=(path,data,create=false)=>({update:{name:prefix+path,fields:encode(data)},...(create?{currentDocument:{exists:false}}:{updateMask:{fieldPaths:Object.keys(data)}}),updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'},...(create?[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}]:[])]});
const commit=(u,writes)=>req(`${base}:commit`,u.idToken,{writes});
const listVisits=(u,assignedTo)=>req(`${base}:runQuery`,u.idToken,{structuredQuery:{
 from:[{collectionId:'appointments'}],
 ...(assignedTo?{where:{fieldFilter:{field:{fieldPath:'assignedStaffId'},op:'EQUAL',value:{stringValue:assignedTo}}}}:{}),
}});
let n=0;
function check(r,status,label) {assert.equal(r.status,status,`${label}: ${JSON.stringify(r.data)}`);console.log('PASS '+label);n++;}
(async()=>{
 const [a,b,s,desk,manager]=await Promise.all(['bride','other','staff','desk','manager'].map(user));
 for(const u of [a,b]) await req(`${base}/brides/${u.localId}`,'owner',{fields:encode({name:'Jane',phone:'0123456789'})},'PATCH');
 for (const [u,role] of [[s,'staff'],[desk,'staff'],[manager,'manager']]) {
   check(await req(`${base}/staff/${u.localId}`,'owner',{fields:encode({name:'Employee',active:true,role})},'PATCH'),200,'seed '+role+' fixture');
 }
 check(await req(`${base}/staffScheduling/${desk.localId}`,'owner',{fields:encode({jobRole:'FrontDesk'})},'PATCH'),200,'seed front desk scheduling role');
 check(await req(`${base}/staffScheduling/${s.localId}`,'owner',{fields:encode({jobRole:'MakeupArtist'})},'PATCH'),200,'seed specialist scheduling role');
 const date=new Date();date.setUTCDate(date.getUTCDate()+2);date.setUTCHours(2,0,0,0);
 const slot=String(date.getTime());
 const data=u=>({uid:u.localId,name:'Jane',phone:'0123456789',type:'Dress Trial',startAt:date,slotKey:slot,notes:'',dressId:'',dressName:'',status:'Requested',response:'',revision:1,updatedBy:u.localId});
 check(await commit(a,[write('appointments/a',data(a),true)]),403,'booking creation must use validated backend');
 check(await commit(b,[write('appointments/b',data(b),true)]),403,'direct second request denied');
 // Trusted emulator-only fixtures model backend-owned bookings.
 for(const [id,u]of [['a',a],['b',b]])await req(`${base}/appointments/${id}`,'owner',{fields:encode({...data(u),...(id==='a'?{assignedStaffId:s.localId}:{}),createdAt:new Date(),updatedAt:new Date()})},'PATCH');
 check(await req(`${base}/appointments/a`,a.idToken,null,'GET'),200,'owner reads request');
 check(await req(`${base}/appointments/a`,b.idToken,null,'GET'),403,'other bride cannot read');
 check(await req(`${base}/appointments/a`,null,null,'GET'),403,'anonymous cannot read');
 check(await req(`${base}/appointments/a`,s.idToken,null,'GET'),200,'specialist reads assigned visit');
 check(await req(`${base}/appointments/b`,s.idToken,null,'GET'),403,'specialist cannot read unassigned visit');
 check(await req(`${base}/appointments/b`,desk.idToken,null,'GET'),200,'front desk reads unassigned visit');
 check(await req(`${base}/appointments/b`,manager.idToken,null,'GET'),200,'manager reads unassigned visit');
 check(await listVisits(s),403,'specialist cannot query all visits');
 check(await listVisits(s,desk.localId),403,'specialist cannot query another staff member');
 const own=await listVisits(s,s.localId);
 check(own,200,'specialist can query their assigned visits');
 assert.deepEqual(own.data.map(item=>item.document?.name?.split('/').at(-1)),['a']);
 check(await listVisits(desk),200,'front desk can query all visits');
 check(await listVisits(manager),200,'manager can query all visits');
 check(await req(`${base}/staffScheduling/${s.localId}`,s.idToken,null,'GET'),200,'staff can verify their own work role');
 check(await req(`${base}/staffScheduling/${desk.localId}`,s.idToken,null,'GET'),403,'staff cannot read another scheduling profile');
 check(await req(`${base}/staffScheduling/${s.localId}`,s.idToken,{fields:encode({jobRole:'FrontDesk'})},'PATCH'),403,'staff cannot grant themselves front desk access');
 await req(`${base}/appointments/a?updateMask.fieldPaths=assignedStaffId`,'owner',{fields:encode({assignedStaffId:desk.localId})},'PATCH');
 check(await req(`${base}/appointments/a`,s.idToken,null,'GET'),403,'reassigned appointment is no longer visible');
 await req(`${base}/staffScheduling/${desk.localId}`,'owner',{fields:encode({jobRole:'Consultant'})},'PATCH');
 check(await listVisits(desk),403,'changing a work role removes all-appointments access');
 const reassigned=await listVisits(desk,desk.localId);
 check(reassigned,200,'new assignee can query their visit');
 assert.deepEqual(reassigned.data.map(item=>item.document?.name?.split('/').at(-1)),['a']);
 check(await commit(a,[write('appointments/b',{status:'Cancelled',revision:2,updatedBy:a.localId})]),403,'cross-account cancellation denied');
 check(await commit(a,[write('appointments/bad',{...data(a),status:'Confirmed'},true)]),403,'bride cannot self-confirm');
 check(await commit(a,[write('appointments/bad',{...data(a),phone:'0199999999'},true)]),403,'spoofed contact denied');
 check(await commit(a,[write('appointments/bad',{...data(a),slotKey:'another-slot'},true)]),403,'spoofed slot key denied');
 check(await commit(a,[write('appointments/bad',{...data(a),startAt:new Date(0)},true)]),403,'past request denied');
 check(await commit(s,[write('appointments/a',{status:'Confirmed',revision:2,updatedBy:s.localId})]),403,'confirmation requires atomic reservation');
 const slotWrite=id=>({update:{name:prefix+'appointmentSlots/'+slot,fields:encode({appointmentId:id,uid:id==='a'?a.localId:b.localId,startAt:date})}});
 check(await commit(s,[write('appointments/a',{status:'Confirmed',revision:2,updatedBy:s.localId}),slotWrite('a')]),403,'manual confirm plus reservation cannot bypass backend');
 check(await commit(s,[write('appointments/b',{status:'Confirmed',revision:2,updatedBy:s.localId}),slotWrite('b')]),403,'double booking denied');
 check(await commit(s,[write('appointments/a',{status:'Completed',revision:3,updatedBy:s.localId})]),403,'future appointment cannot be completed');
 check(await commit(a,[write('appointments/a',{status:'Cancelled',revision:3,updatedBy:a.localId})]),403,'cancellation must release reservation');
 check(await commit(a,[write('appointments/a',{status:'Cancelled',revision:3,updatedBy:a.localId}),{delete:prefix+'appointmentSlots/'+slot}]),403,'cancellation must use backend to release all schedule records');
 check(await commit(s,[write('appointments/b',{status:'Confirmed',revision:2,updatedBy:s.localId}),slotWrite('b')]),403,'direct staff writes remain denied');
 check(await commit(s,[write('appointments/a',{status:'Confirmed',revision:4,updatedBy:s.localId})]),403,'cancelled request cannot be reopened');
 check(await commit(s,[write('appointments/b',{notes:'Changed private request',revision:3,updatedBy:s.localId})]),403,'staff cannot rewrite bride request');
 await req(`${base}/staff/${s.localId}`,'owner',{fields:encode({name:'Staff',active:false,role:'staff'})},'PATCH');
 check(await listVisits(s,s.localId),403,'revoked staff cannot read assigned appointments');
 for(const collection of ['appointmentAvailability','appointmentMail']) {
   check(await req(`${base}/${collection}/private`,a.idToken,{fields:encode({value:'forged'})},'PATCH'),403,'clients cannot write '+collection);
   check(await req(`${base}/${collection}/private`,a.idToken,null,'GET'),403,'clients cannot read '+collection);
 }
 console.log(`${n} appointment rules checks passed.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
