// Synthetic local emulator fixtures only. Never point this script at live data.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const dbHost = process.env.FIRESTORE_EMULATOR_HOST;
for (const host of [authHost, dbHost]) assert.match(host || '', /^(localhost|127\.0\.0\.1):\d+$/);
const root = 'projects/demo-luvly/databases/(default)/documents';
const base = `http://${dbHost}/v1/${root}`;
const fields = object => Object.fromEntries(Object.entries(object).map(([k,v]) => [k,
  typeof v === 'boolean' ? {booleanValue:v} : typeof v === 'number' ? {integerValue:String(v)} : {stringValue:v}]));
let checks = 0;
async function request(path, token, expected, method='GET', body) {
  const r = await fetch(base + path, {method, headers:{...(token ? {Authorization:`Bearer ${token}`} : {}), 'Content-Type':'application/json'}, body:body && JSON.stringify(body)});
  const text = await r.text();
  assert.equal(r.status, expected, `${method} ${path}: ${text}`); checks++;
  return text ? JSON.parse(text) : null;
}
async function user() {
  const r = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`, {
    method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email:`saved-${randomUUID()}@example.test`,password:'Synthetic-test-123!',returnSecureToken:true})});
  assert.equal(r.status,200); return r.json();
}
(async () => {
  const a=await user(), b=await user(), noProfile=await user();
  for (const u of [a,b]) await request(`/brides/${u.localId}`, 'owner', 200, 'PATCH', {fields:fields({name:'Synthetic Test'})});
  const id=`gown-${randomUUID()}`, privateId=`draft-${randomUUID()}`;
  for (const [key,published] of [[id,true],[privateId,false]]) await request(`/dresses/${key}`, 'owner', 200, 'PATCH', {fields:fields({published})});
  const savedPath=`/brides/${a.localId}/shortlist/${id}`;
  async function save(path, actor, expected, extra={}, timestamp=true, gown=id) {
    const update={name:root+path,fields:fields({dressId:gown,...extra})};
    if(!timestamp)update.fields.savedAt={timestampValue:'2020-01-01T00:00:00Z'};
    return request(':commit',actor,expected,'POST',{writes:[{update,
      ...(timestamp ? {updateTransforms:[{fieldPath:'savedAt',setToServerValue:'REQUEST_TIME'}]} : {})}]});
  }
  await request(savedPath,null,403);
  await request(savedPath,b.idToken,403);
  await save(savedPath,b.idToken,403);
  await save(`/brides/${noProfile.localId}/shortlist/${id}`,noProfile.idToken,403);
  await save(savedPath,a.idToken,403,{},false);
  await save(savedPath,a.idToken,403,{uid:b.localId});
  await save(savedPath,a.idToken,403,{name:'Forged gown',priceCents:1});
  await save(savedPath,a.idToken,403,{},true,privateId);
  await save(`/brides/${a.localId}/shortlist/${privateId}`,a.idToken,403,{},true,privateId);
  await save(`/brides/${a.localId}/shortlist/missing`,a.idToken,403,{},true,'missing');
  await save(savedPath,a.idToken,200);
  const saved=await request(savedPath,a.idToken,200);
  assert.equal(saved.fields.dressId.stringValue,id);
  assert.ok(saved.fields.savedAt.timestampValue);
  await save(savedPath,a.idToken,403); // Existing favourites cannot be overwritten.
  const query={structuredQuery:{from:[{collectionId:'shortlist'}]}};
  const rows=await request(`/brides/${a.localId}:runQuery`,a.idToken,200,'POST',query);
  assert.equal(rows.filter(r=>r.document).length,1);
  await request(`/brides/${a.localId}:runQuery`,b.idToken,403,'POST',query);
  await request(savedPath,b.idToken,403,'DELETE');
  // Unpublishing the gown does not trap a saved entry or reveal private gown data.
  await request(`/dresses/${id}`,'owner',200,'PATCH',{fields:fields({published:false})});
  await request(savedPath,a.idToken,200);
  await request(`/dresses/${id}`,a.idToken,403);
  await request(savedPath,a.idToken,200,'DELETE');
  await request(savedPath,a.idToken,404);
  await save(savedPath,a.idToken,403);
  console.log(`${checks} shortlist emulator checks passed (ownership, publication, fields, timestamps, list and removal).`);
})().catch(e=>{console.error(e.message);process.exitCode=1;});
