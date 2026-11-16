// Public Firebase configuration, not an administrative credential.
export const apiKey = 'AIzaSyDOFfVdLMQu_eKMpcoeqmSof5o4aBQM2Y8';
const endpoint = `https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${apiKey}`;

export async function resetRequest(code, newPassword, fetcher = globalThis.fetch) {
  const response = await fetcher(endpoint, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    credentials: 'omit',
    cache: 'no-store',
    referrerPolicy: 'no-referrer',
    signal: AbortSignal.timeout(20000),
    body: JSON.stringify({oobCode: code, ...(newPassword === undefined ? {} : {newPassword})}),
  });
  const data = await response.json();
  if (!response.ok) {
    // Never display arbitrary backend text or log codes/passwords.
    const error = new Error('Reset request failed');
    error.code = (data.error?.message ?? '').split(' : ')[0];
    throw error;
  }
  if (data.requestType !== 'PASSWORD_RESET' || typeof data.email !== 'string') {
    const error = new Error('Invalid reset response');
    error.code = 'INVALID_OOB_CODE';
    throw error;
  }
  return data.email;
}

export function resetError(error) {
  switch (error.code) {
    case 'INVALID_OOB_CODE': case 'EXPIRED_OOB_CODE':
      return 'This link is invalid, expired or already used. Return to Luvly and request a new reset email.';
    case 'WEAK_PASSWORD': case 'PASSWORD_DOES_NOT_MEET_REQUIREMENTS':
      return 'Choose a password that meets all the requirements below.';
    case 'USER_DISABLED': case 'EMAIL_NOT_FOUND':
      return 'This reset is unavailable. Return to Luvly or contact the project owner.';
    case 'TOO_MANY_ATTEMPTS_TRY_LATER':
      return 'Too many attempts. Please wait before trying again.';
    default:
      return 'Unable to connect. Check your internet connection and try again.';
  }
}

// Other email actions still use Firebase's built-in handler. Never follow an
// arbitrary continueUrl, apiKey or redirect supplied in an incoming URL.
export function otherActionUrl(params) {
  if (!['verifyEmail', 'recoverEmail', 'verifyAndChangeEmail', 'revertSecondFactorAddition'].includes(params.get('mode'))) return null;
  if (!params.get('oobCode')) return null;
  const url = new URL('https://luvly-44c77.firebaseapp.com/__/auth/action');
  url.searchParams.set('mode', params.get('mode'));
  url.searchParams.set('oobCode', params.get('oobCode'));
  url.searchParams.set('apiKey', apiKey);
  return url.href;
}
