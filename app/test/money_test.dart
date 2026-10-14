import 'package:dee_app/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatKobo', () {
    test('renders kobo as naira with two decimals', () {
      expect(formatKobo(1500000), '₦15,000.00');
      expect(formatKobo(1500050), '₦15,000.50');
      expect(formatKobo(5), '₦0.05');
      expect(formatKobo(0), '₦0.00');
    });

    test('groups thousands', () {
      expect(formatKobo(250005000), '₦2,500,050.00');
      expect(formatKobo(100000000), '₦1,000,000.00');
    });

    test('renders negatives and null', () {
      expect(formatKobo(-1500050), '-₦15,000.50');
      expect(formatKobo(null), '₦0.00');
    });

    test('never leaks a decimal fraction of a kobo', () {
      // A kobo value is always an integer; formatting must not introduce a float.
      expect(formatKobo(1), '₦0.01');
      expect(formatKobo(99), '₦0.99');
      expect(formatKobo(100), '₦1.00');
    });
  });

  group('parseNairaToKobo', () {
    test('parses plain and grouped amounts', () {
      expect(parseNairaToKobo('15000'), 1500000);
      expect(parseNairaToKobo('15,000.50'), 1500050);
      expect(parseNairaToKobo(' 2500 '), 250000);
    });

    test('parses a single decimal digit by padding', () {
      expect(parseNairaToKobo('250.5'), 25050);
      expect(parseNairaToKobo('0.05'), 5);
    });

    test('parses a naira sign', () {
      expect(parseNairaToKobo('₦1500'), 150000);
    });

    test('parses negatives', () {
      expect(parseNairaToKobo('-1500'), -150000);
      expect(parseNairaToKobo('-1500.25'), -150025);
    });

    test('rejects more precision than a kobo can hold', () {
      // The server rejects this too, and silently rounding would make the price
      // shown on screen differ from the price stored.
      expect(parseNairaToKobo('100.005'), isNull);
      expect(parseNairaToKobo('100.999'), isNull);
    });

    test('rejects malformed input', () {
      expect(parseNairaToKobo(''), isNull);
      expect(parseNairaToKobo('abc'), isNull);
      expect(parseNairaToKobo('15kg'), isNull);
      expect(parseNairaToKobo('1.2.3'), isNull);
    });

    test('round-trips through formatKobo', () {
      for (final kobo in [1, 99, 100, 1500050, 250005000]) {
        final text = formatKobo(kobo);
        final parsed = parseNairaToKobo(text.replaceAll('₦', '').replaceAll(',', ''));
        expect(parsed, kobo);
      }
    });
  });
}
