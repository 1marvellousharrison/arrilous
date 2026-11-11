import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Copies text to the browser clipboard.
///
/// Browsers are inconsistent here: the async Clipboard API can be blocked by
/// permissions, insecure contexts, iframes and some installed-PWA shells, and a
/// rejection does not always surface as a Dart exception through Flutter. So we
/// try the synchronous selection path inside the tap first, then the modern API,
/// then Flutter's own channel. Returning `false` lets the UI show a manual
/// fallback instead of a false "copied" message.
class AppClipboard {
  static Future<bool> copy(String text) async {
    // This runs synchronously inside the caller's tap, which is exactly where
    // browsers still allow execCommand('copy').
    if (_copyWithSelection(text)) return true;

    try {
      await web.window.navigator.clipboard.writeText(text).toDart;
      return true;
    } catch (_) {
      // Permission denied, or the API is unavailable in this context.
    }

    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _copyWithSelection(String text) {
    web.HTMLTextAreaElement? area;
    try {
      area = web.HTMLTextAreaElement()
        ..value = text
        ..readOnly = true;
      area.style.position = 'fixed';
      area.style.top = '-1000px';
      area.style.left = '-1000px';
      area.style.opacity = '0';
      web.document.body?.append(area);
      area.focus();
      area.select();
      return web.document.execCommand('copy');
    } catch (_) {
      return false;
    } finally {
      area?.remove();
    }
  }
}
