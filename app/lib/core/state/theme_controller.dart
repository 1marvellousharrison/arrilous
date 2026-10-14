import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the light/dark preference and pushes it into the widget tree.
///
/// The switch lives in Settings (see `features/settings/settings_screen.dart`).
class ThemeController extends ChangeNotifier {
  ThemeController([this._prefs]);

  static const _key = 'dee.theme.mode';

  SharedPreferences? _prefs;
  ThemeMode _mode = ThemeMode.light;
  bool _ready = false;

  ThemeMode get mode => _mode;
  bool get isDarkMode => _mode == ThemeMode.dark;

  /// True while the theme tracks the phone's appearance rather than a choice
  /// the owner made.
  bool get isFollowingSystem => _mode == ThemeMode.system;

  /// False until the persisted preference has been read from disk.
  bool get isReady => _ready;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final stored = _prefs?.getString(_key);
    _mode = switch (stored) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      // First launch: start on the light theme the brief specifies.
      _ => ThemeMode.light,
    };
    _ready = true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    _mode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(_key, enabled ? 'dark' : 'light');
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setString(_key, mode.name);
  }
}
