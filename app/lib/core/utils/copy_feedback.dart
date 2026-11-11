import 'package:flutter/material.dart';

import '../services/clipboard_service.dart';

/// Copies [text] and reports honestly whether it actually made it to the
/// clipboard.
///
/// A snackbar is only shown when the platform confirmed the copy. When the
/// browser or device refuses (blocked permissions, insecure context, embedded
/// PWA shell), a dialog shows the text preselected so it can still be copied by
/// hand. This is what callers should use instead of `Clipboard.setData`, which
/// fails silently in those environments and would otherwise produce a false
/// "copied" message.
Future<void> copyWithFeedback(
  BuildContext context,
  String text, {
  String successMessage = 'Copied.',
  String fallbackTitle = 'Copy manually',
  String fallbackHelp =
      'This device blocked access to the clipboard. The text is selected '
      'below, so you can copy it with Ctrl+C, \u2318C, or your device\'s copy '
      'menu.',
}) async {
  final copied = await AppClipboard.copy(text);
  if (!context.mounted) return;
  if (copied) {
    _showCopied(context, successMessage);
    return;
  }

  final retried = await showDialog<bool>(
    context: context,
    builder: (_) => _CopyFallbackDialog(
      text: text,
      title: fallbackTitle,
      help: fallbackHelp,
    ),
  );
  if (retried == true && context.mounted) {
    _showCopied(context, successMessage);
  }
}

void _showCopied(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class _CopyFallbackDialog extends StatefulWidget {
  const _CopyFallbackDialog({
    required this.text,
    required this.title,
    required this.help,
  });

  final String text;
  final String title;
  final String help;

  @override
  State<_CopyFallbackDialog> createState() => _CopyFallbackDialogState();
}

class _CopyFallbackDialogState extends State<_CopyFallbackDialog> {
  late final TextEditingController _controller;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.text.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final copied = await AppClipboard.copy(widget.text);
    if (!mounted) return;
    setState(() => _retrying = false);
    if (copied) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.help, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            readOnly: true,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _retrying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _retrying ? null : _retry,
          child: Text(_retrying ? 'Copying...' : 'Try again'),
        ),
      ],
    );
  }
}
