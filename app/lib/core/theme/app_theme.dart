import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens for the whole app.
///
/// Palette decisions requested by the product owner:
///  * primary accent  -> orangered
///  * light canvas    -> #ddd
///  * dark canvas     -> a soft charcoal, deliberately NOT pure black
class AppColors {
  const AppColors._();

  static const Color orangeRed = Color(0xFFFF4500);
  static const Color orangeRedDark = Color(0xFFD93A00);
  static const Color orangeRedLight = Color(0xFFFF7A4D);

  // Light mode
  static const Color lightBackground = Color(0xFFDDDDDD);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF2F2F2);
  static const Color lightBorder = Color(0xFFCFCFCF);
  static const Color lightText = Color(0xFF1F1F1F);
  static const Color lightTextMuted = Color(0xFF5F6368);

  // Dark mode — soft charcoal, not black.
  static const Color darkBackground = Color(0xFF1E1E22);
  static const Color darkSurface = Color(0xFF2A2A30);
  static const Color darkSurfaceAlt = Color(0xFF34343C);
  static const Color darkBorder = Color(0xFF454550);
  static const Color darkText = Color(0xFFF2F2F5);
  static const Color darkTextMuted = Color(0xFFA9A9B4);

  // Status colours used by the status pills required by the spec.
  static const Color success = Color(0xFF17864A);
  static const Color warning = Color(0xFFB5730B);
  static const Color danger = Color(0xFFC62828);
  static const Color info = Color(0xFF1F6FEB);
}

class AppRadius {
  const AppRadius._();

  static const double card = 20;
  static const double field = 16;
  static const double pill = 999;
  static const double button = 16;
}

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Light theme: #ddd canvas with white cards.
ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.orangeRed,
    onPrimary: Colors.white,
    secondary: AppColors.orangeRedLight,
    onSecondary: Colors.white,
    error: AppColors.danger,
    onError: Colors.white,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightText,
  );

  return _base(scheme).copyWith(
    scaffoldBackgroundColor: AppColors.lightBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightBackground,
      foregroundColor: AppColors.lightText,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lightBorder,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      hintStyle: const TextStyle(color: AppColors.lightTextMuted),
      labelStyle: const TextStyle(color: AppColors.lightTextMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.orangeRed, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orangeRed,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.lightBorder,
        disabledForegroundColor: AppColors.lightTextMuted,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orangeRed,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.orangeRed),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.orangeRed),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.lightSurface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.orangeRed
            : AppColors.lightBorder;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.lightText,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
    ),
  );
}

/// Dark theme: soft charcoal (#1E1E22) — clearly dark, but never pure black.
ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.orangeRedLight,
    onPrimary: Color(0xFF23150F),
    secondary: AppColors.orangeRed,
    onSecondary: Colors.white,
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF231313),
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkText,
  );

  return _base(scheme).copyWith(
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      foregroundColor: AppColors.darkText,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceAlt,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      hintStyle: const TextStyle(color: AppColors.darkTextMuted),
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: AppColors.orangeRedLight, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orangeRed,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.darkSurfaceAlt,
        disabledForegroundColor: AppColors.darkTextMuted,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orangeRedLight,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.orangeRedLight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.orangeRedLight),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.white
            : AppColors.darkSurfaceAlt;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.orangeRed
            : AppColors.darkBorder;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkSurfaceAlt,
      contentTextStyle: const TextStyle(color: AppColors.darkText),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
    ),
  );
}

ThemeData _base(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
  );
}
