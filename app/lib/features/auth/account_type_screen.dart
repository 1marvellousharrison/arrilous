import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Account type selection, screen 1 of sign-up (spec section 5).
class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({
    required this.onSelected,
    required this.onBack,
    super.key,
  });

  final ValueChanged<String> onSelected;
  final VoidCallback onBack;

  static const _options = [
    AccountTypeOption(
      role: 'business',
      title: 'Business',
      subtitle: 'Manage your sales, customers, payments and deliveries.',
      icon: Icons.storefront_outlined,
    ),
    AccountTypeOption(
      role: 'logistics_partner',
      title: 'Logistics Partner',
      subtitle: 'Manage deliveries for businesses on the platform.',
      icon: Icons.local_shipping_outlined,
    ),
    AccountTypeOption(
      role: 'rider',
      title: 'Rider',
      subtitle: 'Manage deliveries assigned to you.',
      icon: Icons.pedal_bike_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: onBack)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              'Create your account',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Choose how you will use the platform.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final option in _options) ...[
              _AccountTypeCard(
                option: option,
                onTap: () => onSelected(option.role),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class AccountTypeOption {
  const AccountTypeOption({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String role;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({required this.option, required this.onTap});

  final AccountTypeOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            child: Icon(option.icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}
