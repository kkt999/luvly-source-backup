/// Keep in sync with auth_site/password-policy.mjs and Firebase Auth policy.
const passwordSymbols = r'''^$*.[]{}()?-"!@#%&/\,><':;|_~`+=''';

Map<String, bool> passwordRequirements(String value) => {
  '8–128 characters': value.length >= 8 && value.length <= 128,
  'An uppercase letter (A–Z)': RegExp(r'[A-Z]').hasMatch(value),
  'A lowercase letter (a–z)': RegExp(r'[a-z]').hasMatch(value),
  'A number (0–9)': RegExp(r'[0-9]').hasMatch(value),
  'A symbol (for example ! @ # % &)': value
      .split('')
      .any(passwordSymbols.contains),
};

String? validateNewPassword(String? value) =>
    passwordRequirements(value ?? '').values.every((met) => met)
    ? null
    : 'Use 8–128 characters with uppercase, lowercase, a number and a symbol.';
