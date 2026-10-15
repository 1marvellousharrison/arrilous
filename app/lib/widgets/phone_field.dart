import 'package:flutter/material.dart';

import '../core/utils/phone.dart';

/// A Nigerian phone field with the '+234' code pinned in the prefix.
///
/// The field only ever holds the ten national digits, spaced 3-3-4 as they are
/// typed or pasted, exactly like the business details phone. Callers save the
/// value with [toNigerianE164] so the full international number reaches the API.
class NigerianPhoneField extends StatelessWidget {
  const NigerianPhoneField({
    required this.controller,
    this.label = 'Phone number',
    this.errorText,
    this.required = true,
    this.onChanged,
    this.autofocus = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;

  /// When false an empty field is valid; a non-empty one must still be a
  /// complete Nigerian number.
  final bool required;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      autofocus: autofocus,
      inputFormatters: [NigerianPhoneFormatter()],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '+234 ',
        hintText: '803 123 4567',
        errorText: errorText,
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) {
          return required ? 'Phone number is required.' : null;
        }
        if (!isValidNigerianPhone(text)) return nigerianPhoneError;
        return null;
      },
    );
  }
}
