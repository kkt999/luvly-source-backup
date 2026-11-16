import 'package:flutter/material.dart';
import 'contact_validation.dart';

class MalaysiaPhoneField extends StatefulWidget {
  const MalaysiaPhoneField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.label = 'Phone',
    this.onChanged,
    this.existingPhone,
    this.compact = false,
  });
  final TextEditingController controller;
  final bool enabled;
  final String label;
  final ValueChanged<String>? onChanged;
  final String? existingPhone;
  final bool compact;
  @override
  State<MalaysiaPhoneField> createState() => _MalaysiaPhoneFieldState();
}

class _MalaysiaPhoneFieldState extends State<MalaysiaPhoneField> {
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    focus.addListener(normalizeOnBlur);
  }

  void normalizeOnBlur() {
    if (focus.hasFocus) return;
    final original = widget.controller.text;
    final national = malaysiaNationalInput(original);
    if (national != original) {
      widget.controller.value = TextEditingValue(
        text: national,
        selection: TextSelection.collapsed(offset: national.length),
      );
    }
  }

  @override
  void dispose() {
    focus.removeListener(normalizeOnBlur);
    focus.dispose();
    super.dispose();
  }

  bool get hasLegacyPhone {
    final saved = widget.existingPhone;
    return saved != null &&
        saved.isNotEmpty &&
        normalizeMalaysiaPhone(saved) == null;
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    focusNode: focus,
    enabled: widget.enabled,
    keyboardType: TextInputType.phone,
    textInputAction: widget.compact ? TextInputAction.done : null,
    onChanged: widget.onChanged,
    autofillHints: const [AutofillHints.telephoneNumber],
    autocorrect: false,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIconConstraints: BoxConstraints(
        minWidth: 86,
        minHeight: widget.compact ? 48 : 52,
      ),
      prefixIcon: hasLegacyPhone
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Semantics(
                  label: 'Malaysia, country code plus sixty',
                  child: const Text(
                    'MY  +60',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
      helperText: hasLegacyPhone
          ? 'You can keep the saved number or enter a Malaysian number, e.g. 012 345 6789.'
          : widget.compact
          ? 'e.g. 12 345 6789'
          : 'Malaysia · e.g. 12 345 6789',
      helperMaxLines: 3,
      errorMaxLines: 6,
    ),
    validator: (value) =>
        hasLegacyPhone && value?.trim() == widget.existingPhone?.trim()
        ? null
        : validatePhone(value),
  );
}
