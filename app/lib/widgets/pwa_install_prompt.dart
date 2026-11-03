import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/pwa/pwa_install_service.dart';
import '../core/theme/app_theme.dart';

/// Optional web-only install nudge. Dismissal lives only in widget memory, so
/// it returns on the next page load. Installation itself is remembered by the
/// browser service and permanently suppresses the nudge on this device.
class PwaInstallPrompt extends StatefulWidget {
  const PwaInstallPrompt({required this.child, super.key});

  final Widget child;

  @override
  State<PwaInstallPrompt> createState() => _PwaInstallPromptState();
}

class _PwaInstallPromptState extends State<PwaInstallPrompt> {
  final _install = PwaInstallService.instance;
  Timer? _showTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    _install.initialize();
    _showTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return AnimatedBuilder(
      animation: _install,
      builder: (context, _) {
        final show = !_dismissed && !_install.isInstalled && _showTimer?.isActive == false;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (show)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: 88,
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _InstallCard(
                        onDismiss: () => setState(() => _dismissed = true),
                        onInstall: () async {
                          if (_install.canPrompt) {
                            final launched = await _install.promptInstall();
                            if (!context.mounted) return;
                            if (!launched && !_install.isInstalled) {
                              await showInstallInstructions(context, isIos: _install.isIos);
                            }
                          } else {
                            await showInstallInstructions(context, isIos: _install.isIos);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InstallCard extends StatelessWidget {
  const _InstallCard({required this.onDismiss, required this.onInstall});

  final VoidCallback onDismiss;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 10,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.install_mobile_outlined, color: theme.colorScheme.primary, size: 26),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Install Biziness', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Add it to your device for quick access.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onDismiss, child: const Text('Later')),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: onInstall,
              child: const Text('Install'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showInstallInstructions(BuildContext context, {required bool isIos}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Install Biziness'),
      content: Text(isIos
          ? 'In Safari, tap Share, then choose “Add to Home Screen”.'
          : 'Open your browser menu and choose “Install app” or “Add to Home screen”.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
      ],
    ),
  );
}
