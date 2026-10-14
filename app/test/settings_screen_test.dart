import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/theme_controller.dart';
import 'package:dee_app/core/theme/app_theme.dart';
import 'package:dee_app/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// The Appearance card carries the colour switch. It has to move the theme the
/// owner actually sees, and letting go of "follow system" has to leave them on
/// a concrete shade rather than stuck on the system.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const base = 'http://localhost:4000/api/v1';

  AuthRepository buildAuth() {
    final client = MockClient(
      (_) async => http.Response(
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    return AuthRepository(
      ApiClient(baseUrl: base, client: client),
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
  }

  Future<void> pumpSettings(WidgetTester tester, ThemeController theme) async {
    final auth = buildAuth();
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (context, _) => MaterialApp(
          themeMode: theme.mode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          home: SettingsScreen(theme: theme, auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the dark switch pins an explicit dark theme', (tester) async {
    final theme = ThemeController();
    await theme.load();
    await pumpSettings(tester, theme);

    // The dark switch is first; the follow-system switch is second.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(theme.mode, ThemeMode.dark);
    expect(theme.isFollowingSystem, isFalse);
  });

  testWidgets('letting go of follow-system keeps the phone shade as an explicit choice', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final theme = ThemeController();
    await theme.load();
    await pumpSettings(tester, theme);

    // Follow the system first.
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(theme.isFollowingSystem, isTrue);

    // Turning it off must not stay on system — it pins the shade the phone is
    // showing (dark), so the switch visibly moves.
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(theme.isFollowingSystem, isFalse);
    expect(theme.mode, ThemeMode.dark);
  });
}
