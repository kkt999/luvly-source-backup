import 'malaysia_phone_metadata.dart';

class ContactValidationException implements Exception {
  const ContactValidationException(this.message);
  final String message;
}

String normalizeContactName(String value) =>
    value.trim().replaceAll(RegExp(r' +'), ' ');

String? validateName(String? value) {
  final name = normalizeContactName(value ?? '');
  if (name.isEmpty) return 'Enter your full name';
  if (name.length > 100) return 'Use up to 100 characters for your name';
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(name) ||
      !RegExp(r"^[\p{L}\p{M} .'’/@-]+$", unicode: true).hasMatch(name)) {
    return 'Use letters and normal name punctuation, without numbers or other symbols';
  }
  return null;
}

/// Accept local, national or MY international input. Never strip arbitrary
/// letters/other country codes and accidentally turn them into a valid number.
String? normalizeMalaysiaPhone(String value) {
  final raw = value.trim();
  if (raw.isEmpty ||
      raw.length > 40 ||
      !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(raw)) {
    return null;
  }
  var digits = raw.replaceAll(RegExp(r'[ ()-]'), '');
  if (digits.startsWith('+')) {
    if (!digits.startsWith('+60')) return null;
    digits = digits.substring(3);
  } else if (digits.startsWith('0060')) {
    digits = digits.substring(4);
  } else if (digits.startsWith('60')) {
    digits = digits.substring(2);
  }
  // Accept one national trunk zero, including the commonly pasted +60 (0)...
  if (digits.startsWith('0')) digits = digits.substring(1);
  if (!RegExp('^$malaysiaContactNationalPattern\$').hasMatch(digits)) {
    return null;
  }
  return '+60$digits';
}

String? validatePhone(String? value) =>
    normalizeMalaysiaPhone(value ?? '') != null
    ? null
    : 'Enter a valid Malaysian phone number, e.g. 012 345 6789';

/// Formats known Malaysian numbers and preserves other saved numbers.
String formatContactPhone(String value) =>
    normalizeMalaysiaPhone(value) ?? value.trim();

String malaysiaNationalInput(String value) {
  final normalized = normalizeMalaysiaPhone(value);
  return normalized == null ? value : normalized.substring(3);
}
