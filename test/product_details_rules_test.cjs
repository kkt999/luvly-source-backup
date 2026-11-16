// Local synthetic data only. Never runs against the live project.
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const authHost=process.env.FIREBASE_AUTH_EMULATOR_HOST,dbHost=process.env.FIRESTORE_EMULATOR_HOST;
for(const host of [authHost,dbHost])assert.match(host||'',/^(localhost|127\.0\.0\.1):\d+$/);
const project='demo-luvly',base=`http://${dbHost}/v1/projects/${project}/databases/(default)/documents`;
const value=v=>typeof v==='string'?{stringValue:v}:typeof v==='number'?{integerValue:String(v)}:typeof v==='boolean'?{booleanValue:v}:{mapValue:{fields:fields(v)}};
const fields=o=>Object.fromEntries(Object.entries(o).map(([k,v])=>[k,value(v)]));
const req=async(url,token,body)=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
(async()=>{
 const actors=[];
 for(const role of ['manager','staff','bride','inactive']){
  const response=await req(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`,null,{email:`product-${randomUUID()}@example.test`,password:'Synthetic-test-123!',returnSecureToken:true});assert.equal(response.status,200);
  const user=await response.json();actors.push(user);
  if(role!=='bride')assert.equal((await fetch(`${base}/staff/${user.localId}`,{method:'PATCH',headers:{Authorization:'Bearer owner','Content-Type':'application/json'},body:JSON.stringify({fields:fields({active:role!=='inactive',role:role==='manager'?'manager':'staff'})})})).status,200);
 }
 const [manager,staff,bride,inactive]=actors;
 const write=async(user,details)=>req(`${base}:commit`,user.idToken,{writes:[{update:{name:`projects/${project}/databases/(default)/documents/dresses/${randomUUID()}`,fields:fields({name:'Synthetic Gown',category:'A-Line',description:'A synthetic gown for local security tests.',colour:'Ivory',sizes:'S, M',priceCents:54900,imageUrl:'https://example.test/gown.jpg',availability:'Available',published:true,revision:1,createdBy:user.localId,updatedBy:user.localId,...(details===undefined?{}:{productDetails:details})})},updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}],currentDocument:{exists:false}}]});
 let count=0;
 for(const details of [undefined,{}, {neckline:'Folded neckline',fabricAppearance:'Smooth finish',train:'Flared hem',features:'A clean silhouette.'}]){const r=await write(manager,details);assert.equal(r.status,200,await r.text());count++;}
 for(const details of [{supplier:'Unbounded field'},{neckline:'x'.repeat(161)},{features:'x'.repeat(601)},{neckline:2},{neckline:''}]){const r=await write(manager,details);assert.equal(r.status,403,await r.text());count++;}
 for(const user of [staff,bride,inactive]){const r=await write(user,{features:'A valid description.'});assert.equal(r.status,403,await r.text());count++;}
 console.log(`${count} product detail rule checks passed.`);
})().catch(e=>{console.error(e.message);process.exitCode=1;});
