// Malaysia contact-number metadata from Google libphonenumber (snapshot 2026-11-03).
// Copyright The Libphonenumber Authors. Licensed under Apache-2.0.
// Source: https://github.com/google/libphonenumber/blob/master/resources/PhoneNumberMetadata.xml
// Keep this number format aligned with lib/src/contact_validation.dart.
const malaysiaNationalPattern = /^(?:1(?:(?:1888[689]|4400|8(?:47|8[27])[0-4])\d{4}|9\d{7,8})|1(?:0(?:[23568]\d|4[0-6]|7[016-9]|9[0-8])|1(?:[1-5]\d\d|6(?:0[5-9]|[1-9]\d)|7(?:[0-4]\d|5[0-79]|6[02-4]|8[02-5]))|(?:[26]\d|[37][1-9]|4[235-9])\d|5(?:31|9\d\d)|8(?:1[23]|[236]\d|4[06]|5(?:46|[7-9])|7[016-9]|8[01]|9[0-8]))\d{5}|427[01]\d{4}|(?:3(?:2[0-36-9]|3[0-368]|4[0-278]|5[0-24-8]|6[0-467]|7[1246-9]|8\d|9[0-57])\d|4(?:2[0-689]|[3-79]\d|8[1-35689])|5(?:2[0-589]|[3468]\d|5[0-489]|7[1-9]|9[23])|6(?:2[2-9]|3[1357-9]|[46]\d|5[0-6]|7[0-35-9]|85|9[015-8])|7(?:[2579]\d|3[03-68]|4[0-8]|6[5-9]|8[0-35-9])|8(?:[24][2-8]|3[2-5]|5[2-7]|6[2-589]|7[2-578]|[89][2-9])|9(?:0[57]|13|[25-7]\d|[3489][0-8]))\d{5}|15(?:4(?:6[0-4]\d|8(?:0[125]|[17]\d|21|3[01]|4[01589]|5[014]|6[02]))|6(?:32[0-6]|78\d))\d{4})$/;

export function normalizeMalaysiaPhone(value) {
  if (typeof value !== 'string') return null;
  const raw = value.trim();
  if (!raw || raw.length > 40 || !/^\+?[0-9 ()-]+$/.test(raw)) return null;
  let digits = raw.replace(/[ ()-]/g, '');
  if (digits.startsWith('+')) {
    if (!digits.startsWith('+60')) return null;
    digits = digits.slice(3);
  } else if (digits.startsWith('0060')) {
    digits = digits.slice(4);
  } else if (digits.startsWith('60')) {
    digits = digits.slice(2);
  }
  if (digits.startsWith('0')) digits = digits.slice(1);
  return malaysiaNationalPattern.test(digits) ? '+60' + digits : null;
}

export function staffPhoneForSave(value, existing) {
  return normalizeMalaysiaPhone(value) ??
    (typeof existing === 'string' && typeof value === 'string' &&
      existing.trim() === value.trim() ? existing : null);
}

export function validContactName(value) {
  if (typeof value !== 'string') return false;
  const name = value.trim().replace(/ +/g, ' ');
  return name.length <= 100 && /\p{L}/u.test(name) &&
    /^[\p{L}\p{M} .'’/@-]+$/u.test(name);
}
