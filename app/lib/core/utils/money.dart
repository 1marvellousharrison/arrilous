/// Money helpers for the client.
///
/// The server stores and returns integer kobo and never accepts floats. The
/// client follows the same rule so a value shown on screen and the value sent
/// over the wire cannot disagree.
///
/// The unit contract is the one implemented in `server/src/lib/money.js`:
///  * a JSON **number** in a `_kobo` field is already kobo,
///  * a **string** is what a human typed, in naira ("15000" or "15,000.50").
library;

const int koboPerNaira = 100;

/// Renders kobo as a human amount: 1500000 -> "₦15,000.00".
String formatKobo(num? kobo) {
  final int value = (kobo ?? 0).round();
  final bool negative = value < 0;
  final int abs = value.abs();
  final int major = abs ~/ koboPerNaira;
  final int minor = abs % koboPerNaira;

  final String digits = major.toString();
  final StringBuffer grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }

  return '${negative ? '-' : ''}₦$grouped.${minor.toString().padLeft(2, '0')}';
}

/// Parses a human-typed naira amount ("15000", "15,000.50", "₦250.5") to kobo.
///
/// Returns null when the text is not a valid amount, which is the same
/// strictness the server applies: no third decimal place, no stray characters.
int? parseNairaToKobo(String input) {
  final String cleaned = input
      .replaceAll(RegExp(r'[,\s ₦]'), '')
      .replaceAll('₦', '');
  if (!RegExp(r'^-?\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;

  final bool negative = cleaned.startsWith('-');
  final List<String> parts = cleaned.replaceFirst('-', '').split('.');
  final String whole = parts[0];
  final String fraction = parts.length > 1 ? parts[1] : '';
  final String padded = '${fraction}00'.substring(0, 2);

  final int kobo = int.parse(whole) * koboPerNaira + int.parse(padded);
  return negative ? -kobo : kobo;
}
