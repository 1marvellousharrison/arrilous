import 'package:dee_app/core/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to light mode', () async {
    final controller = ThemeController();
    await controller.load();

    expect(controller.mode, ThemeMode.light);
    expect(controller.isDarkMode, isFalse);
    expect(controller.isReady, isTrue);
  });

  test('the settings switch flips to dark mode', () async {
    final controller = ThemeController();
    await controller.load();

    await controller.setDarkMode(true);

    expect(controller.isDarkMode, isTrue);
    expect(controller.mode, ThemeMode.dark);
  });

  test('the choice is persisted and restored on next launch', () async {
    final first = ThemeController();
    await first.load();
    await first.setDarkMode(true);

    final second = ThemeController();
    await second.load();

    expect(second.isDarkMode, isTrue);
  });

  test('choosing light mode persists too', () async {
    final first = ThemeController();
    await first.load();
    await first.setDarkMode(true);
    await first.setDarkMode(false);

    final second = ThemeController();
    await second.load();
    expect(second.isDarkMode, isFalse);
  });

  test('follow-system is a distinct third option', () async {
    final controller = ThemeController();
    await controller.load();

    await controller.setMode(ThemeMode.system);
    expect(controller.mode, ThemeMode.system);
    expect(controller.isDarkMode, isFalse, reason: 'not an explicit dark choice');

    final restored = ThemeController();
    await restored.load();
    expect(restored.mode, ThemeMode.system);
  });

  test('notifies listeners when the mode changes', () async {
    final controller = ThemeController();
    await controller.load();

    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.setDarkMode(true);
    await controller.setDarkMode(false);

    expect(notifications, 2);
  });
}
