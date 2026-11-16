// Local emulator only, no live user records. Verifies owner profile writes.
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const ah=process.env.FIREBASE_AUTH_EMULATOR_HOST,dh=process.env.FIRESTORE_EMULATOR_HOST;
for(const host of [ah,dh])assert.match(host||'',/^(localhost|127\.0\.0\.1):\d+$/);
const base=`http://${dh}/v1/projects/demo-luvly/databases/(default)/documents`;
const fields=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k,typeof v==='string'?{stringValue:v}:{integerValue:String(v)}]));
async function user(){const r=await fetch(`http://${ah}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`contact-${randomUUID()}@example.test`,password:'Synthetic-test-123!',returnSecureToken:true})});assert.equal(r.status,200);return r.json();}
(async()=>{
 let count=0;
 const a=await user(),b=await user();
 async function write(name,phone,expected,actor=a,extra={}){
   const p={uid:a.localId,email:a.email,name,phone,contact:'Email',notes:'',role:'bride',membership:'Standard',points:0,...extra};
   const r=await fetch(`${base}:commit`,{method:'POST',headers:{Authorization:`Bearer ${actor.idToken}`,'Content-Type':'application/json'},body:JSON.stringify({writes:[{update:{name:`projects/demo-luvly/databases/(default)/documents/brides/${a.localId}`,fields:fields(p)},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]})});
   assert.equal(r.status,expected,`${name}/${phone}: ${await r.text()}`);count++;
 }
 for(const name of ['**-+','1234','Jane123','Jane\nLim','Jane🙂','  Jane'])await write(name,'+60123456789',403);
 for(const phone of ['769898989646768','0123456789','+6512345678','+601012345678','+60abc123456','+6012345678'])await write('Jane Lim',phone,403);
 await write('Jane Lim','+60123456789',403,b);
 await write('Jane Lim','+60123456789',200);
 // Profile updates keep immutable creation fields. Admin fixture seeds legacy data
 // solely to verify existing records remain readable and can be corrected.
 const legacy={uid:a.localId,email:a.email,name:'Legacy Test',phone:'0123456789',contact:'Email',notes:'',role:'bride',membership:'Standard',points:0};
 assert.equal((await fetch(`${base}/brides/${a.localId}`,{method:'PATCH',headers:{Authorization:'Bearer owner','Content-Type':'application/json'},body:JSON.stringify({fields:fields(legacy)})})).status,200);
 assert.equal((await fetch(`${base}/brides/${a.localId}`,{headers:{Authorization:`Bearer ${a.idToken}`}})).status,200);count++;
 async function patch(name,phone,expected,extra={}) {
   const r=await fetch(`${base}:commit`,{method:'POST',headers:{Authorization:`Bearer ${a.idToken}`,'Content-Type':'application/json'},body:JSON.stringify({writes:[{update:{name:`projects/demo-luvly/databases/(default)/documents/brides/${a.localId}`,fields:fields({name,phone,...extra})},updateMask:{fieldPaths:['name','phone',...Object.keys(extra)]},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}]})});
   assert.equal(r.status,expected,await r.text());count++;
 }
 for(const name of ['张小明','李',"Anne-Marie O’Neil",'Ravi a/l Kumar','José','محمد علي','லட்சுமி'])await patch(name,'+60123456789',200);
 for(const phone of ['+601112345678','+60191234567','+601912345678','+60323856789'])await patch('Jane Lim',phone,200);
 await patch('Jane123','+60123456789',403);await patch('Jane Lim','123456789999999',403);
 await patch('Jane Lim','+60123456789',403,{role:'manager'});
 console.log(`${count} contact rule checks passed, including legacy read/correction and owner/role protection.`);
})().catch(e=>{console.error(e.message);process.exitCode=1;});
