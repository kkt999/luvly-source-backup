import 'package:flutter/material.dart';

/// A conservative, optional spelling hint, never an email provider allowlist.
/// Unknown domains are left alone; the address is changed only after a tap.
String? suggestEmailSpelling(String value) {
  final email = value.trim();
  if (email.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return null;
  }
  final at = email.indexOf('@');
  final domain = email.substring(at + 1).toLowerCase();
  const corrections = <String, String>{
    'gmail.con': 'gmail.com',
    'gmail.cmo': 'gmail.com',
    'gamil.com': 'gmail.com',
    'gmial.com': 'gmail.com',
    'gnail.com': 'gmail.com',
    'outlook.con': 'outlook.com',
    'outlook.cmo': 'outlook.com',
    'hotmail.con': 'hotmail.com',
    'hotmail.cmo': 'hotmail.com',
    'hotmial.com': 'hotmail.com',
    'yahoo.con': 'yahoo.com',
    'yahoo.cmo': 'yahoo.com',
    'icloud.con': 'icloud.com',
    'icloud.cmo': 'icloud.com',
  };
  final corrected = corrections[domain];
  return corrected == null ? null : '${email.substring(0, at)}@$corrected';
}

class EmailTypoSuggestion extends StatelessWidget {
  const EmailTypoSuggestion({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final suggestion = suggestEmailSpelling(value.text);
          if (suggestion == null) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
            textStyle: const TextStyle(fontFamily: 'LuvlySans', fontSize: 13),
                alignment: Alignment.centerLeft,
              ),
              onPressed: !enabled
                  ? null
                  : () {
                      controller.value = TextEditingValue(
                        text: suggestion,
                        selection: TextSelection.collapsed(
                          offset: suggestion.length,
                        ),
                      );
                    },
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Did you mean '),
                    TextSpan(
                      text: suggestion,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const TextSpan(text: '? Tap to use it.'),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
