// Keep in sync with lib/src/password_policy.dart and Firebase Auth policy.
export const symbols = "^$*.[]{}()?-\"!@#%&/\\,><':;|_~`+=";
export function requirements(value) {
  return [
    ['8–128 characters', value.length >= 8 && value.length <= 128],
    ['An uppercase letter (A–Z)', /[A-Z]/.test(value)],
    ['A lowercase letter (a–z)', /[a-z]/.test(value)],
    ['A number (0–9)', /[0-9]/.test(value)],
    ['A symbol (for example ! @ # % &)', [...value].some(c => symbols.includes(c))],
  ];
}
export function passwordError(value, confirmation) {
  if (!requirements(value).every(([, met]) => met)) {
    return 'Please meet all five password requirements.';
  }
  if (value !== confirmation) return 'Passwords do not match.';
  return null;
}
