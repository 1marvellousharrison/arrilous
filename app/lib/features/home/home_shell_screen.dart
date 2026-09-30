import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Placeholder for the authenticated shell.
///
/// Phases 9-12 replace this with the real bottom navigation (Home |
/// Transactions | AI/Chats | Logistics | Profile). Until then it proves the
/// session handed over by the auth backend is live.
class HomeShellScreen extends StatelessWidget {
  const HomeShellScreen({
    required this.user,
    required this.onOpenSettings,
    super.key,
  });

  final AuthUser user;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hello,',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Text(
              user.fullName.isEmpty ? 'Welcome' : user.fullName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Signed in',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Row(label: 'User ID', value: user.id),
                _Row(label: 'Name', value: user.fullName),
                _Row(label: 'Email', value: user.email),
                _Row(label: 'Role', value: user.role),
                _Row(
                  label: 'Email verified',
                  value: user.emailVerified ? 'Yes' : 'Not yet',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const EmptyState(
            icon: Icons.construction_outlined,
            title: 'Dashboard arrives in Phase 12',
            message:
                'Authentication is live. Business setup, products, customers and '
                'transactions are being built in the phases that follow.',
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
