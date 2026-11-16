import test from 'node:test';
import assert from 'node:assert/strict';
import {passwordError, symbols} from '../auth_site/password-policy.mjs';
import {resetRequest, resetError, otherActionUrl} from '../auth_site/reset-api.mjs';

test('password policy requires all categories, bounds and matching confirmation', () => {
  for (const weak of ['12345678', 'abcdefgh', 'ABCDEFGH', 'Abcdef12', 'abcdef1!', 'ABCDEF1!', 'Abcdefg!', 'Ab1!', 'Aa1!'+'x'.repeat(125)]) {
    assert.ok(passwordError(weak, weak));
  }
  assert.equal(passwordError('Unique1!password', 'Unique1!password'), null);
  assert.equal(passwordError('Aa1!'+'x'.repeat(124), 'Aa1!'+'x'.repeat(124)), null);
  assert.equal(passwordError('Unique1!password', 'different'), 'Passwords do not match.');
  for (const symbol of symbols) assert.equal(passwordError('Abcdefg1'+symbol, 'Abcdefg1'+symbol), null);
});
test('verification sends code without password and confirmation sends both only to Firebase', async () => {
  let calls = [];
  const fake = async (url, options) => {
    calls.push({url, options});
    return {ok:true, json:async()=>({email:'synthetic@example.com', requestType:'PASSWORD_RESET'})};
  };
  assert.equal(await resetRequest('synthetic-code', undefined, fake), 'synthetic@example.com');
  assert.deepEqual(JSON.parse(calls[0].options.body), {oobCode:'synthetic-code'});
  await resetRequest('synthetic-code', 'Unique1!password', fake);
  assert.deepEqual(JSON.parse(calls[1].options.body), {oobCode:'synthetic-code', newPassword:'Unique1!password'});
  assert.equal(new URL(calls[1].url).hostname, 'identitytoolkit.googleapis.com');
  assert.equal(calls[1].options.referrerPolicy, 'no-referrer');
});
test('invalid codes and unexpected successful action types are rejected', async () => {
  await assert.rejects(resetRequest('invalid', undefined, async()=>({ok:false,json:async()=>({error:{message:'INVALID_OOB_CODE'}})})), {code:'INVALID_OOB_CODE'});
  await assert.rejects(resetRequest('invalid', undefined, async()=>({ok:true,json:async()=>({email:'synthetic@example.com',requestType:'VERIFY_EMAIL'})})), {code:'INVALID_OOB_CODE'});
  assert.match(resetError({code:'EXPIRED_OOB_CODE'}), /expired/);
  assert.match(resetError({code:'PASSWORD_DOES_NOT_MEET_REQUIREMENTS'}), /requirements/);
  assert.match(resetError(new Error('SECRET BACKEND ERROR')), /internet/);
});
test('other actions use fixed project handler and ignore untrusted redirects and API keys', () => {
  assert.equal(otherActionUrl(new URLSearchParams('mode=unknown&oobCode=test')), null);
  assert.equal(otherActionUrl(new URLSearchParams('mode=resetPassword&oobCode=test')), null);
  const url = new URL(otherActionUrl(new URLSearchParams('mode=verifyEmail&oobCode=test&continueUrl=https://evil.example&apiKey=evil')));
  assert.equal(url.origin, 'https://luvly-44c77.firebaseapp.com');
  assert.equal(url.pathname, '/__/auth/action');
  assert.equal(url.searchParams.has('continueUrl'), false);
  assert.notEqual(url.searchParams.get('apiKey'), 'evil');
});
