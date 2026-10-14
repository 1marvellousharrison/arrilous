import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/auth_repository.dart';
import '../../core/state/theme_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Settings screen (spec section 37).
///
/// The Appearance card holds the light/dark toggle switch. Dark mode uses a
/// soft charcoal canvas rather than pure black.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.theme,
    required this.auth,
    super.key,
    this.user,
  });

  final ThemeController theme;
  final AuthRepository auth;
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final current = user ?? auth.session?.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _SectionLabel('Appearance'),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    // The switch shows what the owner actually sees, so while
                    // the theme follows the phone it reads dark or light with
                    // the phone rather than sitting permanently off.
                    final effectiveDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: effectiveDark,
                      // An explicit tap always pins a concrete mode, which is
                      // also what turns following-the-system off.
                      onChanged: theme.setDarkMode,
                      secondary: Icon(
                        effectiveDark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text(
                        'Dark mode',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        theme.isFollowingSystem
                            ? 'Following your phone’s appearance'
                            : effectiveDark
                                ? 'Using the dark charcoal theme'
                                : 'Using the light theme',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  },
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  leading: const Icon(Icons.brightness_auto_outlined),
                  title: const Text('Follow system setting'),
                  subtitle: const Text(
                    'Match your phone’s light/dark appearance',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: Switch.adaptive(
                    value: theme.isFollowingSystem,
                    // Turning it off keeps whatever the phone is showing right
                    // now as an explicit choice, instead of sticking on system.
                    onChanged: (enabled) => enabled
                        ? theme.setMode(ThemeMode.system)
                        : theme.setDarkMode(
                            Theme.of(context).brightness == Brightness.dark,
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SectionLabel('Account'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Signed in as'),
                  subtitle: Text(
                    current == null
                        ? 'Not signed in'
                        : '${current.fullName}\n${current.email}',
                  ),
                  isThreeLine: current != null,
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Account type'),
                  trailing: StatusPill(
                    label: _roleLabel(current?.role),
                    color: AppColors.info,
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _comingSoon(context, 'Change password'),
                ),
                Divider(color: Theme.of(context).dividerColor, height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text(
                    'Sign out',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  onTap: () async {
                    await auth.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SectionLabel('Coming in later phases'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final entry in const [
                  (Icons.chat_bubble_outline, 'WhatsApp & AI settings'),
                  (Icons.account_balance_outlined, 'Payments'),
                  (Icons.local_shipping_outlined, 'Logistics preferences'),
                  (Icons.notifications_none, 'Notifications'),
                  (Icons.group_outlined, 'Team & permissions'),
                ]) ...[
                  ListTile(
                    leading: Icon(entry.$1),
                    title: Text(entry.$2),
                    trailing: const Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: AppColors.lightTextMuted,
                    ),
                    onTap: () => _comingSoon(context, entry.$2),
                  ),
                  if (entry.$2 != 'Team & permissions')
                    Divider(color: Theme.of(context).dividerColor, height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature arrives in a later phase.')),
    );
  }

  String _roleLabel(String? role) => switch (role) {
        'logistics_partner' => 'Logistics',
        'rider' => 'Rider',
        'business' => 'Business',
        _ => 'Unknown',
      };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
        top: AppSpacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
