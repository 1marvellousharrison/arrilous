import 'package:flutter/services.dart';

/// The ten national digits a Nigerian mobile number holds behind the '+234'
/// code the phone field shows. Pasting a whole number folds down to exactly
/// those digits: '+234 803 1234 567' and '0803 123 4567' both become
/// '8031234567'. A leading '234' country code or a leading '0' trunk code is
/// stripped when the number is longer than the ten national digits.
String nationalPhoneDigits(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 10 && digits.startsWith('234')) digits = digits.substring(3);
  if (digits.length > 10 && digits.startsWith('0')) digits = digits.substring(1);
  return digits;
}

/// A Nigerian mobile number starts 7, 8 or 9 and carries no more digits after
/// those ten.
final RegExp nigerianNationalPhone = RegExp(r'^[789]\d{9}$');

/// The ten national digits grouped the way the field presents them, three then
/// three then four: '+234 803 123 4567' reads as '803 123 4567'.
String formatNationalPhone(String raw) {
  var digits = nationalPhoneDigits(raw);
  if (digits.length > 10) digits = digits.substring(0, 10);
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i == 3 || i == 6) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Keeps a phone field on the strict '+234 *** *** ****' shape: the '+234'
/// code lives in the field's prefix and the field itself only ever holds the
/// ten national digits, spaced 3-3-4 as they are typed.
class NigerianPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatNationalPhone(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// The E.164 form the API stores and expects: '+234' plus the ten national
/// digits, with no spaces or punctuation.
String toNigerianE164(String raw) => '+234${nationalPhoneDigits(raw)}';

/// True when the field holds ten valid national digits (7, 8 or 9 first).
bool isValidNigerianPhone(String raw) =>
    nigerianNationalPhone.hasMatch(nationalPhoneDigits(raw));

/// The message a phone field shows when the ten digits are not complete.
const String nigerianPhoneError =
    'Type the 10 digits after +234, e.g. 803 123 4567.';
