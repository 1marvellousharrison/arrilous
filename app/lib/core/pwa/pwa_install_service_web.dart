import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

@JS('window.bizinessDeferredInstallPrompt')
external JSObject? get _savedInstallPrompt;

@JS('window.navigator.standalone')
external JSAny? get _iosStandalone;

@JS()
extension type _BeforeInstallPromptEvent._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prompt();
  external JSPromise<_PromptChoice> get userChoice;
}

@JS()
extension type _PromptChoice._(JSObject _) implements JSObject {
  external JSString get outcome;
}

/// Browser install support shared by the startup nudge and Profile > Settings.
/// Dismissal is intentionally not persisted; an installed app is persisted.
class PwaInstallService extends ChangeNotifier {
  PwaInstallService._();

  static final PwaInstallService instance = PwaInstallService._();
  static const _installedKey = 'biziness_pwa_installed';

  Object? _deferredPrompt;
  bool _initialized = false;
  bool _installed = false;
  bool get isInstalled => _installed || _isStandalone;
  bool get canPrompt => _deferredPrompt != null;
  bool get isIos => web.window.navigator.userAgent.toLowerCase().contains('iphone') ||
      web.window.navigator.userAgent.toLowerCase().contains('ipad');

  bool get _isStandalone {
    final displayMode = web.window.matchMedia('(display-mode: standalone)').matches;
    final iosStandalone = _iosStandalone.dartify() == true;
    return displayMode || iosStandalone;
  }

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    try {
      _installed = web.window.localStorage.getItem(_installedKey) == 'true' || _isStandalone;
      if (_isStandalone) web.window.localStorage.setItem(_installedKey, 'true');
    } catch (_) {
      _installed = _isStandalone;
    }

    // The bootstrap listener runs before Flutter starts, so recover an install
    // event that fired while the Dart app was loading.
    _deferredPrompt = _savedInstallPrompt;
    web.window.addEventListener('bizinessinstallprompt', ((web.Event _) {
      _deferredPrompt = _savedInstallPrompt;
      notifyListeners();
    }).toJS);
    web.window.addEventListener('appinstalled', ((web.Event _) {
      _markInstalled();
    }).toJS);
  }

  Future<bool> promptInstall() async {
    final promptEvent = _deferredPrompt;
    if (promptEvent == null || isInstalled) return false;

    try {
      final event = promptEvent as _BeforeInstallPromptEvent;
      event.prompt();
      final choice = await event.userChoice.toDart;
      final outcome = choice.outcome.toDart;
      _deferredPrompt = null;
      notifyListeners();
      if (outcome == 'accepted') {
        // Browser confirmation can arrive slightly after userChoice resolves.
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _markInstalled() {
    _installed = true;
    _deferredPrompt = null;
    try {
      web.window.localStorage.setItem(_installedKey, 'true');
    } catch (_) {
      // Standalone mode still suppresses the prompt if storage is unavailable.
    }
    notifyListeners();
  }

}
