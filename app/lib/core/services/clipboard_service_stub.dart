import 'package:flutter/services.dart';

/// Copies text to the system clipboard.
///
/// Returns `false` instead of throwing when the platform refuses, so the UI can
/// offer the text for manual copying rather than claiming a copy that did not
/// happen.
class AppClipboard {
  static Future<bool> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }
}
