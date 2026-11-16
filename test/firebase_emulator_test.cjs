// Local emulators only. Never creates users or documents in the real project.
const assert = require('node:assert/strict');
const project = 'demo-luvly';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const dbHost = process.env.FIRESTORE_EMULATOR_HOST;
assert.match(authHost || '', /^(127\.0\.0\.1|localhost):\d+$/);
assert.match(dbHost || '', /^(127\.0\.0\.1|localhost):\d+$/);
const auth = `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:`;
const base = `http://${dbHost}/v1/projects/${project}/databases/(default)/documents`;
async function request(url, body, token, method = 'POST') {
  const r = await fetch(url, {method, headers: {'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})}, ...(body ? {body:JSON.stringify(body)} : {})});
  return {status:r.status, data:await r.json()};
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([k,v]) => [k,
  typeof v === 'number' ? {integerValue:String(v)} : typeof v === 'boolean' ? {booleanValue:v} : {stringValue:v}]));
let checks = 0;
function check(actual, expected, label) { assert.equal(actual, expected, label); checks++; console.log(`PASS ${label}`); }
async function create(user, changes = {}, uid = user.localId) {
  return request(`${base}:commit`, {writes:[{
    update:{name:`projects/${project}/databases/(default)/documents/brides/${uid}`, fields:fields({
      uid, email:user.email, name:'Jane Lim', phone:'+60123456789', contact:'Email', notes:'',
      role:'bride', membership:'Standard', points:0, ...changes})},
    currentDocument:{exists:false},
    updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'},{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]
  }]}, user.idToken);
}
async function update(user, uid, changes) {
  return request(`${base}:commit`, {writes:[{
    update:{name:`projects/${project}/databases/(default)/documents/brides/${uid}`,fields:fields(changes)},
    updateMask:{fieldPaths:Object.keys(changes)},
    currentDocument:{exists:true}, updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]
  }]},user.idToken);
}
(async () => {
  const a = (await request(`${auth}signUp?key=test`, {email:'jane@example.com',password:'test-password-123',returnSecureToken:true})).data;
  const b = (await request(`${auth}signUp?key=test`, {email:'other@example.com',password:'test-password-456',returnSecureToken:true})).data;
  assert.ok(a.idToken && b.idToken);
  check((await request(`${auth}signInWithPassword?key=test`, {email:a.email,password:'wrong-password',returnSecureToken:true})).status,400,'wrong password rejected');
  check((await request(`${auth}signInWithPassword?key=test`, {email:a.email,password:'test-password-123',returnSecureToken:true})).status,200,'correct password accepted');
  check((await request(`${auth}signUp?key=test`, {email:a.email,password:'test-password-123',returnSecureToken:true})).status,400,'duplicate signup rejected');
  check((await request(`${auth}sendOobCode?key=test`, {email:a.email,requestType:'PASSWORD_RESET'})).status,200,'password reset request accepted');
  // Exercise the exact reset adapter shipped by the custom page, using ONLY the emulator.
  const {resetRequest} = await import('../auth_site/reset-api.mjs');
  const codes = (await request(`http://${authHost}/emulator/v1/projects/${project}/oobCodes`,null,null,'GET')).data.oobCodes;
  const code = codes.find(c => c.email === a.email && c.requestType === 'PASSWORD_RESET').oobCode;
  const localFetch = (_url, options) => fetch(`${auth}resetPassword?key=test`, options);
  check(await resetRequest(code,undefined,localFetch), a.email, 'custom page verifies reset email code');
  check(await resetRequest(code,'Unique1!newpassword',localFetch), a.email, 'custom page confirms a new password');
  await assert.rejects(resetRequest(code,'Other2!newpassword',localFetch), {code:'INVALID_OOB_CODE'});
  checks++; console.log('PASS reset code cannot be reused');
  await assert.rejects(resetRequest('invalid-code',undefined,localFetch), {code:'INVALID_OOB_CODE'});
  checks++; console.log('PASS invalid reset code rejected');
  check((await request(`${auth}signInWithPassword?key=test`, {email:a.email,password:'test-password-123',returnSecureToken:true})).status,400,'old password rejected after reset');
  const refreshed = await request(`${auth}signInWithPassword?key=test`, {email:a.email,password:'Unique1!newpassword',returnSecureToken:true});
  check(refreshed.status,200,'new password accepted after reset');
  a.idToken = refreshed.data.idToken;
  check((await create(a)).status,200,'owner can create Standard zero-point profile');
  check((await request(`${base}/brides/${a.localId}`,null,a.idToken,'GET')).status,200,'owner can read profile');
  check((await request(`${base}/brides/${a.localId}`,null,null,'GET')).status,403,'anonymous read denied');
  check((await request(`${base}/brides/${a.localId}`,null,b.idToken,'GET')).status,403,'other account read denied');
  check((await request(`${base}/brides`,null,a.idToken,'GET')).status,403,'profile listing denied');
  check((await update(a,a.localId,{name:'Jane Updated'})).status,200,'owner can update contact details');
  check((await update(b,a.localId,{name:'Attacker'})).status,403,'other account update denied');
  check((await update(a,a.localId,{role:'manager'})).status,403,'self-promotion denied');
  check((await update(a,a.localId,{points:10000})).status,403,'loyalty points tampering denied');
  check((await update(a,a.localId,{membership:'Gold'})).status,403,'membership tampering denied');
  check((await update(a,a.localId,{email:'changed@example.com'})).status,403,'profile email tampering denied');
  check((await update(a,a.localId,{password:'must-not-store'})).status,403,'unexpected secret field denied');
  check((await update(a,a.localId,{notes:'x'.repeat(1001)})).status,403,'oversized notes denied');
  check((await create(b,{role:'manager'})).status,403,'privileged role at signup denied');
  check((await create(b,{points:100})).status,403,'nonzero signup points denied');
  check((await create(b,{email:a.email})).status,403,'spoofed email denied');
  check((await create(b)).status,200,'second account gets its own profile');
  check((await request(`${base}/brides/${a.localId}`,null,a.idToken,'DELETE')).status,403,'profile deletion denied');
  check((await request(`${base}/staff/secret`,null,a.idToken,'GET')).status,403,'other collections remain denied');
  const access = {fields: fields({name:'Test Manager',role:'manager',active:true})};
  check((await request(`${base}/staff/${a.localId}`,access,a.idToken,'PATCH')).status,403,'customer cannot create staff access');
  // Emulator-only administrator token. Never used against production.
  check((await request(`${base}/staff/${b.localId}`,access,'owner','PATCH')).status,200,'trusted administrator provisions staff fixture');
  check((await request(`${base}/staff/${b.localId}`,null,b.idToken,'GET')).status,200,'staff can read own assigned role');
  check((await request(`${base}/staff/${b.localId}`,null,a.idToken,'GET')).status,403,'customer cannot read another staff record');
  check((await request(`${base}/staff`,null,b.idToken,'GET')).status,403,'manager cannot list staff without future dedicated rules');
  check((await request(`${base}/staff/${b.localId}`,null,null,'GET')).status,403,'anonymous staff lookup denied');
  check((await request(`${base}/staff/${b.localId}`,access,b.idToken,'PATCH')).status,403,'assigned manager cannot rewrite own access');
  check((await request(`${base}/staff/${a.localId}`,access,b.idToken,'PATCH')).status,403,'client manager cannot provision another account');
  check((await request(`${base}/staff/${b.localId}`,null,b.idToken,'DELETE')).status,403,'staff access deletion denied');
  check((await request(`${base}/brides/${a.localId}`,null,b.idToken,'GET')).status,403,'manager role does not broaden bride profile access');
  check((await request(`${base}/staff/${b.localId}`,{fields:fields({name:'Test Manager',role:'manager',active:false})},'owner','PATCH')).status,200,'trusted administrator can revoke access');
  const revoked = await request(`${base}/staff/${b.localId}`,null,b.idToken,'GET');
  check(revoked.data.fields.active.booleanValue,false,'account can observe its revoked access');
  check((await request(`${base}/staff/${b.localId}`,access,b.idToken,'PATCH')).status,403,'revoked account cannot reactivate itself');
  // Catalogue rules: same queries and revision checks used by the Flutter app.
  const staff = (await request(`${auth}signUp?key=test`, {email:'staff@example.com',password:'test-password-789',returnSecureToken:true})).data;
  await request(`${base}/staff/${b.localId}`,access,'owner','PATCH');
  await request(`${base}/staff/${staff.localId}`,{fields:fields({name:'Staff',role:'staff',active:true})},'owner','PATCH');
  async function dressWrite(user, id, data, creating = true) {
    return request(`${base}:commit`, {writes:[{
      update:{name:`projects/${project}/databases/(default)/documents/dresses/${id}`,fields:fields(data)},
      ...(creating ? {currentDocument:{exists:false}} : {currentDocument:{exists:true},updateMask:{fieldPaths:Object.keys(data)}}),
      updateTransforms:[...(creating ? [{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}] : []), {fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]
    }]}, user?.idToken);
  }
  const dress = {name:'Test Gown',category:'A-Line',description:'A lace dress with a full length skirt.',colour:'Ivory',sizes:'S, M',priceCents:125050,
    imageUrl:'https://example.com/dress.jpg',availability:'Available',published:true,revision:1,createdBy:b.localId,updatedBy:b.localId};
  check((await dressWrite(b,'public',dress)).status,200,'manager creates published dress');
  check((await dressWrite(b,'draft',{...dress,published:false,imageUrl:''})).status,200,'manager creates photo-free draft');
  check((await request(`${base}/dresses/missing`,null,b.idToken,'GET')).status,404,'manager may read missing ID for creation transaction');
  check((await request(`${base}/dresses/public`,null,a.idToken,'GET')).status,200,'bride reads published dress');
  check((await request(`${base}/dresses/public`,null,null,'GET')).status,403,'anonymous catalogue read denied');
  check((await request(`${base}/dresses/draft`,null,a.idToken,'GET')).status,403,'bride cannot read draft');
  check((await request(`${base}/dresses/draft`,null,staff.idToken,'GET')).status,200,'active staff can read draft inventory');
  const allQuery = {structuredQuery:{from:[{collectionId:'dresses'}]}};
  const publicQuery = {structuredQuery:{...allQuery.structuredQuery,where:{fieldFilter:{field:{fieldPath:'published'},op:'EQUAL',value:{booleanValue:true}}}}};
  check((await request(`${base}:runQuery`,publicQuery,a.idToken)).status,200,'bride published-only query succeeds');
  check((await request(`${base}:runQuery`,allQuery,a.idToken)).status,403,'bride cannot list private inventory');
  check((await request(`${base}:runQuery`,allQuery,staff.idToken)).status,200,'staff lists inventory');
  check((await request(`${base}:runQuery`,allQuery,b.idToken)).status,200,'manager lists inventory');
  check((await dressWrite(a,'forged',{...dress,createdBy:a.localId,updatedBy:a.localId})).status,403,'bride cannot create dresses');
  check((await dressWrite(staff,'staff-created',{...dress,createdBy:staff.localId,updatedBy:staff.localId})).status,403,'staff cannot create dresses');
  for (const [label, mutation] of Object.entries({negativePrice:{priceCents:-1},wrongType:{priceCents:'100'},missingPhoto:{imageUrl:''},insecurePhoto:{imageUrl:'http://example.com/a.jpg'},invalidStyle:{category:'Made up'},extraField:{role:'manager'},oversizedName:{name:'x'.repeat(101)},spoofedCreator:{createdBy:a.localId},badRevision:{revision:9}})) {
    check((await dressWrite(b,`invalid-${label}`,{...dress,...mutation})).status,403,`invalid dress rejected: ${label}`);
  }
  const edit = {name:'Updated Gown',revision:2,updatedBy:b.localId};
  for (const [label, mutation] of Object.entries({zeroPrice:{priceCents:0},unknownColour:{colour:'sdsdsds'},unknownSizes:{sizes:'sdsd'},duplicateSizes:{sizes:'S, S'},mixedTailoredSizes:{sizes:'S, Made to measure'},shortDescription:{description:'ewqeqwe'},whitespaceName:{name:'   '},numericName:{name:'12345'},controlName:{name:'Dress\u0000Name'},paddedDescription:{description:' A lace gown with a long flowing skirt. '}})) {
    check((await dressWrite(b,`validation-${label}`,{...dress,...mutation})).status,403,`structured validation: ${label}`);
  }
  check((await dressWrite(b,'tailored',{...dress,sizes:'Made to measure',name:'象牙白婚纱'})).status,200,'tailored sizing and Chinese dress name accepted');
  check((await dressWrite(b,'public',edit,false)).status,200,'manager updates dress with next revision');
  check((await dressWrite(b,'public',edit,false)).status,403,'stale revision rejected');
  check((await dressWrite(b,'public',{createdBy:a.localId,revision:3,updatedBy:b.localId},false)).status,403,'creator cannot be overwritten');
  check((await dressWrite(staff,'public',{name:'Staff edit',revision:3,updatedBy:staff.localId},false)).status,403,'staff cannot edit');
  check((await dressWrite(a,'public',{name:'Bride edit',revision:3,updatedBy:a.localId},false)).status,403,'bride cannot edit');
  check((await request(`${base}/dresses/public`,null,b.idToken,'DELETE')).status,403,'manager cannot hard-delete dresses');
  check((await dressWrite(b,'public',{published:false,revision:3,updatedBy:b.localId},false)).status,200,'manager unpublishes dress');
  check((await request(`${base}/dresses/public`,null,a.idToken,'GET')).status,403,'unpublished dress no longer readable by bride');
  // Synthetic photo envelopes test rules. Real decoding/encoding is covered by
  // dress_photo_test.dart; Firestore rules cannot validate JPEG pixel contents.
  const photo = {data:'/9j/2Q==',mime:'image/jpeg',width:200,height:300,revision:1,updatedBy:b.localId};
  const docName = (path) => `projects/${project}/databases/(default)/documents/${path}`;
  function photoWrite(id, p) {
    return {update:{name:docName(`dressPhotos/${id}`),fields:fields(p)},
      updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]};
  }
  async function withPhoto(user,id,data,p,creating=true) {
    const writes = [{update:{name:docName(`dresses/${id}`),fields:fields(data)},
      ...(creating ? {currentDocument:{exists:false}} : {currentDocument:{exists:true},updateMask:{fieldPaths:Object.keys(data)}}),
      updateTransforms:[...(creating ? [{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}] : []),{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]},
      p === null ? {delete:docName(`dressPhotos/${id}`)} : photoWrite(id,p)];
    return request(`${base}:commit`,{writes},user?.idToken);
  }
  const uploadedDress = {...dress,imageUrl:'',photoRevision:1,published:false};
  check((await withPhoto(b,'photo-draft',uploadedDress,photo)).status,200,'manager atomically saves draft and photo');
  check((await request(`${base}/dressPhotos/photo-draft`,null,b.idToken,'GET')).status,200,'manager reads draft photo');
  check((await request(`${base}/dressPhotos/photo-draft`,null,staff.idToken,'GET')).status,200,'staff reads draft photo');
  check((await request(`${base}/dressPhotos/photo-draft`,null,a.idToken,'GET')).status,403,'bride cannot read draft photo');
  check((await request(`${base}/dressPhotos/photo-draft`,null,null,'GET')).status,403,'anonymous photo read denied');
  check((await request(`${base}/dressPhotos`,null,b.idToken,'GET')).status,403,'bulk photo listing denied even for manager');
  check((await request(`${base}:commit`,{writes:[photoWrite('orphan',photo)]},b.idToken)).status,403,'orphan photo denied');
  check((await dressWrite(b,'missing-photo',uploadedDress)).status,403,'parent without required photo denied');
  check((await request(`${base}:commit`,{writes:[photoWrite('photo-draft',photo)]},b.idToken)).status,403,'photo mutation without parent update denied');
  check((await request(`${base}/dressPhotos/photo-draft`,null,b.idToken,'DELETE')).status,403,'photo deletion without clearing parent denied');
  for (const [label,mutation] of Object.entries({oversizedData:{data:'/9j/'+'A'.repeat(273068)},wrongMime:{mime:'image/png'},badData:{data:'<script>'},badWidth:{width:1201},badHeight:{height:0},wrongRevision:{revision:2},spoofedActor:{updatedBy:a.localId},extraField:{secret:'x'}})) {
    check((await withPhoto(b,`photo-invalid-${label}`,uploadedDress,{...photo,...mutation})).status,403,`invalid photo rejected: ${label}`);
  }
  check((await request(`${base}/dresses/photo-invalid-wrongMime`,null,b.idToken,'GET')).status,404,'failed photo transaction leaves no parent');
  check((await withPhoto(staff,'staff-photo',{...uploadedDress,createdBy:staff.localId,updatedBy:staff.localId},{...photo,updatedBy:staff.localId})).status,403,'staff cannot upload photo');
  check((await withPhoto(a,'bride-photo',{...uploadedDress,createdBy:a.localId,updatedBy:a.localId},{...photo,updatedBy:a.localId})).status,403,'bride cannot upload catalogue photo');
  check((await dressWrite(b,'photo-draft',{published:true,revision:2,updatedBy:b.localId},false)).status,200,'publish existing uploaded photo without reupload');
  check((await request(`${base}/dressPhotos/photo-draft`,null,a.idToken,'GET')).status,200,'bride reads published photo');
  check((await withPhoto(b,'photo-draft',{photoRevision:3,revision:3,updatedBy:b.localId},{...photo,revision:3},false)).status,200,'manager replaces photo atomically');
  check((await withPhoto(b,'photo-draft',{photoRevision:3,revision:3,updatedBy:b.localId},{...photo,revision:3},false)).status,403,'stale photo replacement denied');
  check((await dressWrite(b,'photo-draft',{photoRevision:0,published:false,revision:4,updatedBy:b.localId},false)).status,403,'clearing reference without deleting photo denied');
  check((await withPhoto(b,'photo-draft',{photoRevision:0,revision:4,updatedBy:b.localId},null,false)).status,403,'cannot remove sole photo from published dress');
  check((await dressWrite(b,'photo-draft',{published:false,revision:4,updatedBy:b.localId},false)).status,200,'unpublish uploaded photo');
  check((await request(`${base}/dressPhotos/photo-draft`,null,a.idToken,'GET')).status,403,'unpublishing revokes bride photo access');
  check((await withPhoto(b,'photo-draft',{photoRevision:0,revision:5,updatedBy:b.localId},null,false)).status,200,'remove draft photo and clear reference atomically');
  check((await request(`${base}/dressPhotos/photo-draft`,null,b.idToken,'GET')).status,404,'removed photo no longer stored');
  check((await dressWrite(b,'ar-linked',{...dress,arModelId:'princess-wedding'})).status,200,'manager links a prepared Princess model');
  check((await request(`${base}/dresses/ar-linked`,null,a.idToken,'GET')).data.fields.arModelId.stringValue,'princess-wedding','bride reads the exact prepared model ID');
  check((await dressWrite(b,'ar-linked',{arModelId:'francine-reference',revision:2,updatedBy:b.localId},false)).status,200,'manager can change to other prepared model');
  for (const value of ['unrecognised-model','https://example.com/model.glb','../princess_wedding.glb',42]) {
    check((await dressWrite(b,'invalid-ar',{...dress,arModelId:value})).status,403,'unknown or wrong-type AR model rejected');
  }
  check((await dressWrite(staff,'ar-linked',{arModelId:'princess-wedding',revision:3,updatedBy:staff.localId},false)).status,403,'staff cannot change AR link');
  check((await dressWrite(a,'ar-linked',{arModelId:'princess-wedding',revision:3,updatedBy:a.localId},false)).status,403,'bride cannot change AR link');
  check((await dressWrite(b,'ar-linked',{arModelId:'',revision:3,updatedBy:b.localId},false)).status,200,'manager can clear optional AR link');
  // The Flutter transaction deletes an optional link rather than retaining it.
  check((await request(`${base}:commit`,{writes:[{
    update:{name:docName('dresses/ar-linked'),fields:fields({revision:4,updatedBy:b.localId})},
    updateMask:{fieldPaths:['arModelId','revision','updatedBy']},
    updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]
  }]},b.idToken)).status,200,'optional AR link field can be deleted while updating dress');
  await request(`${base}/staff/${b.localId}`,{fields:fields({name:'Test Manager',role:'manager',active:false})},'owner','PATCH');
  check((await dressWrite(b,'ar-linked',{arModelId:'princess-wedding',revision:5,updatedBy:b.localId},false)).status,403,'revoked manager cannot change AR link');
  check((await withPhoto(b,'revoked-photo',uploadedDress,photo)).status,403,'revoked manager cannot upload photos');
  check((await dressWrite(b,'draft',{name:'Revoked edit',revision:2,updatedBy:b.localId},false)).status,403,'revoked manager cannot write inventory');
  check((await request(`${base}/dresses/draft`,null,b.idToken,'GET')).status,403,'revoked manager cannot read drafts');
  check((await request(`${base}/brides/${a.localId}`,null,staff.idToken,'GET')).status,403,'catalogue access does not expose bride profiles');
  console.log(`${checks} Firebase emulator checks passed.`);
})().catch(e => { console.error(e.message); process.exitCode = 1; });
