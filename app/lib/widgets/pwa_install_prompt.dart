import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/pwa/pwa_install_service.dart';
import '../core/theme/app_theme.dart';

/// Compact web-only install nudge, mounted only on the Home tab. Dismissal is
/// remembered in memory until reload; installation is remembered per device.
class PwaInstallPrompt extends StatefulWidget {
  const PwaInstallPrompt({required this.child, super.key});

  final Widget child;

  @override
  State<PwaInstallPrompt> createState() => _PwaInstallPromptState();
}

class _PwaInstallPromptState extends State<PwaInstallPrompt> {
  final _install = PwaInstallService.instance;
  Timer? _showTimer;

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
        final show = !_install.dismissedThisLoad && !_install.isInstalled && _showTimer?.isActive == false;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (show)
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.sm,
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _InstallCard(
                        onDismiss: _install.dismissForThisLoad,
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
      elevation: 5,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
        child: Row(
          children: [
            Icon(Icons.install_mobile_outlined, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Install Biziness', style: theme.textTheme.labelLarge),
                  Text(
                    'Add to your device for quick access',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onInstall,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(48, 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: const Text('Install'),
            ),
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
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
