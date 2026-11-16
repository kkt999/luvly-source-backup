import {requirements, passwordError} from './password-policy.mjs';
import {resetRequest, resetError, otherActionUrl} from './reset-api.mjs';

const get = id => document.getElementById(id);
const form = get('reset-form'), status = get('status'), retry = get('retry');
const password = get('password'), confirmation = get('confirmation');
const error = get('error'), submit = get('submit');
const params = new URLSearchParams(location.search);
let code = params.get('oobCode');
let verified = false, busy = false;

// Keep the code in memory only. No analytics, storage, third-party assets or
// referrers. Reloading requires reopening the original email link.
history.replaceState(null, '', location.pathname);
const fallback = otherActionUrl(params);
if (fallback) location.replace(fallback);

function updateRequirements() {
  get('requirements').replaceChildren(...requirements(password.value).map(([label, met]) => {
    const item = document.createElement('li');
    item.textContent = `${met ? '✓' : '○'} ${label}`;
    item.className = met ? 'met' : '';
    item.setAttribute('aria-label', `${met ? 'Met' : 'Not met'}: ${label}`);
    return item;
  }));
}
password.addEventListener('input', () => {
  updateRequirements();
  error.textContent = '';
});
confirmation.addEventListener('input', () => { error.textContent = ''; });
for (const [input, button] of [[password, get('show-password')], [confirmation, get('show-confirmation')]]) {
  button.addEventListener('click', () => {
    const show = input.type === 'password';
    input.type = show ? 'text' : 'password';
    button.textContent = show ? 'Hide' : 'Show';
    button.setAttribute('aria-pressed', String(show));
    button.setAttribute('aria-label', `${show ? 'Hide' : 'Show'} ${input === password ? 'new password' : 'confirmation password'}`);
  });
}
async function verify() {
  if (busy || fallback) return;
  if (params.get('mode') !== 'resetPassword' || !code) {
    status.textContent = 'Open the password-reset link from your Luvly email. To get a new link, choose “Forgot password?” in the app.';
    return;
  }
  busy = true;
  retry.hidden = true;
  status.textContent = 'Checking your secure email link…';
  try {
    const email = await resetRequest(code);
    verified = true;
    status.textContent = 'Choose a new password to keep your account safe.';
    get('account').textContent = `For ${email}`;
    form.hidden = false;
    updateRequirements();
  } catch (e) {
    status.textContent = resetError(e);
    retry.hidden = ['INVALID_OOB_CODE', 'EXPIRED_OOB_CODE', 'USER_DISABLED', 'EMAIL_NOT_FOUND'].includes(e.code);
  } finally { busy = false; }
}
retry.addEventListener('click', verify);
form.addEventListener('submit', async event => {
  event.preventDefault();
  if (busy || !verified) return;
  const validation = passwordError(password.value, confirmation.value);
  error.textContent = validation ?? '';
  if (validation) { (password.value !== confirmation.value ? confirmation : password).focus(); return; }
  busy = true;
  for (const control of form.elements) control.disabled = true;
  submit.textContent = 'Saving…';
  try {
    await resetRequest(code, password.value);
    code = null;
    verified = false;
    form.reset();
    form.hidden = true;
    get('account').textContent = '';
    status.textContent = 'Your password has been updated. You can now return to Luvly and sign in with your new password.';
  } catch (e) {
    error.textContent = resetError(e);
    if (['INVALID_OOB_CODE', 'EXPIRED_OOB_CODE', 'USER_DISABLED', 'EMAIL_NOT_FOUND'].includes(e.code)) {
      verified = false;
      form.reset();
      form.hidden = true;
      status.textContent = resetError(e);
    }
  } finally {
    busy = false;
    for (const control of form.elements) control.disabled = false;
    submit.textContent = 'Save new password';
  }
});
await verify();
