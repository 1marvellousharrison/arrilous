import 'package:dee_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('palette', () {
    test('primary colour is orangered', () {
      expect(AppColors.orangeRed, const Color(0xFFFF4500));
      expect(buildLightTheme().colorScheme.primary, AppColors.orangeRed);
    });

    test('light canvas is #ddd', () {
      expect(AppColors.lightBackground, const Color(0xFFDDDDDD));
      expect(buildLightTheme().scaffoldBackgroundColor, AppColors.lightBackground);
    });

    test('dark canvas is dark but NOT pure black', () {
      expect(AppColors.darkBackground, isNot(const Color(0xFF000000)));

      final luminance = AppColors.darkBackground.computeLuminance();
      expect(luminance, greaterThan(0.0), reason: 'must not be pure black');
      expect(luminance, lessThan(0.1), reason: 'must still read as dark mode');

      expect(buildDarkTheme().scaffoldBackgroundColor, AppColors.darkBackground);
    });

    test('dark surfaces are lighter than the dark canvas', () {
      expect(
        AppColors.darkSurface.computeLuminance(),
        greaterThan(AppColors.darkBackground.computeLuminance()),
      );
      expect(
        AppColors.darkSurfaceAlt.computeLuminance(),
        greaterThan(AppColors.darkSurface.computeLuminance()),
      );
    });

    test('dark theme text has strong contrast against the dark canvas', () {
      final ratio = _contrast(AppColors.darkText, AppColors.darkBackground);
      expect(ratio, greaterThan(7.0), reason: 'WCAG AAA body text');
    });

    test('light theme text has strong contrast against #ddd', () {
      final ratio = _contrast(AppColors.lightText, AppColors.lightBackground);
      expect(ratio, greaterThan(7.0), reason: 'WCAG AAA body text');
    });

    test('orangered on white is readable as a button fill', () {
      final ratio = _contrast(Colors.white, AppColors.orangeRed);
      expect(ratio, greaterThan(3.0));
    });
  });

  group('theme wiring', () {
    test('both themes are Material 3', () {
      expect(buildLightTheme().useMaterial3, isTrue);
      expect(buildDarkTheme().useMaterial3, isTrue);
    });

    test('light theme reports light brightness, dark reports dark', () {
      expect(buildLightTheme().colorScheme.brightness, Brightness.light);
      expect(buildDarkTheme().colorScheme.brightness, Brightness.dark);
    });

    test('the dark toggle switch is rendered as an adaptive switch', () {
      expect(buildDarkTheme().switchTheme, isNotNull);
      expect(buildLightTheme().switchTheme, isNotNull);
    });

    test('cards use the large rounded radius from the spec', () {
      final shape =
          buildLightTheme().cardTheme.shape! as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, AppRadius.card);
    });

    test('input fields use the rounded field radius', () {
      final border = buildLightTheme().inputDecorationTheme.border!;
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border as OutlineInputBorder).borderRadius.topLeft.x,
        AppRadius.field,
      );
    });
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
