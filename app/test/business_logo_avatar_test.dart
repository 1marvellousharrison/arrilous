import 'package:dee_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A business logo is optional: with one chosen the tile paints the image, and
/// without one it falls back to the first letter of the name.
void main() {
  // A real 1x1 PNG, so the image path exercises the engine's decoder.
  const onePixelPng =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';

  Widget wrap(String? logoUrl, {String name = 'ada provisions'}) => MaterialApp(
        home: Scaffold(body: BusinessLogoAvatar(logoUrl: logoUrl, name: name)),
      );

  testWidgets('falls back to the capitalised first letter when there is no logo',
      (tester) async {
    await tester.pumpWidget(wrap(null));

    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('paints the logo image when one is set', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(onePixelPng));
      // Let the bytes decode in real time; the fake clock alone never resolves.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  test('decode is null for a missing or malformed data URL', () {
    expect(BusinessLogoAvatar.decode(null), isNull);
    expect(BusinessLogoAvatar.decode('not-a-data-url'), isNull);
    expect(BusinessLogoAvatar.decode(onePixelPng), isNotNull);
  });
}
