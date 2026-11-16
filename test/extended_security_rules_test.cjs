// Local emulator only. These requests must never reach the live project.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const ah = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const dh = process.env.FIRESTORE_EMULATOR_HOST;
for (const host of [ah, dh]) assert.match(host || '', /^(localhost|127\.0\.0\.1):\d+$/);
const base = `http://${dh}/v1/projects/demo-luvly/databases/(default)/documents`;
const run = randomUUID();
let checks = 0;
async function request(path, token, method='GET', fields) {
  return fetch(`${base}/${path}`, {method, headers: {
    'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})
  }, ...(fields ? {body:JSON.stringify({fields})} : {})});
}
async function expectStatus(path,token,method,status,fields) {
  assert.equal((await request(path,token,method,fields)).status,status,`${method} ${path}`);
  checks++;
}
(async()=>{
  const actors=[];
  for (const role of ['bride','staff','manager','inactive']) {
    const r=await fetch(`http://${ah}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`,{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({email:`qa-${run}-${role}@example.com`,password:'Synthetic-test-123!',returnSecureToken:true})
    });
    assert.equal(r.status,200);
    const u=await r.json(); actors.push(u);
    if(role!=='bride') await expectStatus(`staff/${u.localId}`,'owner','PATCH',200,{
      active:{booleanValue:role!=='inactive'},role:{stringValue:role==='manager'?'manager':'staff'},name:{stringValue:'QA fixture'}
    });
  }
  const serverOnly=['tasks','staffScheduling','staffTimeOff','sandboxInvoices','rentals','packageSelections',
    'customerReviews','customerReviewUploads','customerReviewReports','customerReviewOperations','profilePhotos'];
  const paths=serverOnly.map(c=>`${c}/${run}`);
  paths.push(`inboxes/${actors[0].localId}/items/${run}`);
  for(const path of paths) {
    await expectStatus(path,'owner','PATCH',200,{uid:{stringValue:actors[0].localId},marker:{stringValue:'qa-only'}});
    // Even a manager client must use authenticated business APIs, not bypass
    // payment, ownership, moderation or scheduling invariants through Firestore.
    for(const token of [null,...actors.map(u=>u.idToken)]) {
      await expectStatus(path,token,'GET',403);
      await expectStatus(path,token,'PATCH',403,{marker:{stringValue:'forged'}});
      await expectStatus(path,token,'DELETE',403);
    }
  }
  const draft=`dresses/${run}`;
  await expectStatus(draft,'owner','PATCH',200,{published:{booleanValue:false}});
  await expectStatus(draft,actors[0].idToken,'GET',403);
  await expectStatus(draft,actors[1].idToken,'GET',200);
  await expectStatus(draft,actors[2].idToken,'GET',200);
  await expectStatus(draft,actors[3].idToken,'GET',403);
  await expectStatus(`staff/${actors[1].localId}`,actors[1].idToken,'PATCH',403,{role:{stringValue:'manager'}});
  console.log(`${checks} extended emulator checks passed (server-only records, role escalation and inactive staff).`);
})().catch(e=>{console.error(e.message);process.exitCode=1;});
