import 'package:flutter/foundation.dart';

/// No-op outside the browser. Keeping the same API lets native builds compile
/// without importing browser-only libraries.
class PwaInstallService extends ChangeNotifier {
  PwaInstallService._();

  static final PwaInstallService instance = PwaInstallService._();

  bool get isInstalled => false;
  bool get dismissedThisLoad => false;
  bool get canPrompt => false;
  bool get isIos => false;

  void initialize() {}
  void dismissForThisLoad() {}

  Future<bool> promptInstall() async => false;
}
