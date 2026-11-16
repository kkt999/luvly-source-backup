// Emulator only: this test must never use the live Firebase project.
const assert = require('node:assert/strict');
const auth = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestore = process.env.FIRESTORE_EMULATOR_HOST;
assert.match(auth || '', /^(localhost|127\.0\.0\.1):\d+$/);
assert.match(firestore || '', /^(localhost|127\.0\.0\.1):\d+$/);
const base = `http://${firestore}/v1/projects/demo-luvly/databases/(default)/documents`;
async function request(path, token, method = 'GET', body) {
  return fetch(`${base}/${path}`, {method, headers: {
    'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {}),
  }, ...(body ? {body: JSON.stringify(body)} : {})});
}
(async () => {
  const fields = {baseUrl: {stringValue: 'https://fixture.trycloudflare.com'}};
  assert.equal((await request('runtimeConfig/backend', 'owner', 'PATCH', {fields})).status, 200);
  assert.equal((await request('runtimeConfig/private', 'owner', 'PATCH', {fields})).status, 200);
  assert.equal((await request('runtimeConfig/backend')).status, 403);
  for (const role of ['bride', 'staff', 'manager']) {
    const user = await (await fetch(`http://${auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({email: `runtime-${role}@example.com`, password: 'Fixture1!secure', returnSecureToken: true}),
    })).json();
    assert.ok(user.idToken);
    if (role !== 'bride') await request(`staff/${user.localId}`, 'owner', 'PATCH', {fields: {
      active: {booleanValue: true}, role: {stringValue: role},
    }});
    assert.equal((await request('runtimeConfig/backend', user.idToken)).status, 200, `${role} can get endpoint`);
    assert.equal((await request('runtimeConfig', user.idToken)).status, 403, `${role} cannot list config`);
    assert.equal((await request('runtimeConfig/private', user.idToken)).status, 403, `${role} cannot read other config`);
    assert.equal((await request('runtimeConfig/backend', user.idToken, 'PATCH', {fields})).status, 403, `${role} cannot redirect tokens`);
    assert.equal((await request('runtimeConfig/backend', user.idToken, 'DELETE')).status, 403, `${role} cannot delete config`);
    assert.equal((await request('runtimeConfig/new', user.idToken, 'PATCH', {fields})).status, 403);
    console.log(`PASS ${role}: get only; list/other documents/write/delete denied`);
  }
  console.log('PASS anonymous denied; authenticated endpoint discovery security verified.');
})().catch(() => { console.error('Runtime-config rules acceptance failed'); process.exitCode = 1; });
