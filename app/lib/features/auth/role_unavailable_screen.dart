import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../widgets/common.dart';

/// Shown to a signed-in account whose role has no workspace yet.
///
/// The Logistics Partner and Rider experiences are a later phase. Until they
/// exist, a non-business account must not be dropped into the business shell:
/// that shell's first request is `GET /business`, which the server refuses for
/// these roles, and the resulting error view is a dead end — no back route, no
/// sign-out. This screen replaces it and always offers a way back to sign-in.
class RoleUnavailableScreen extends StatelessWidget {
  const RoleUnavailableScreen({
    required this.user,
    required this.onSignOut,
    super.key,
  });

  final AuthUser user;

  /// Leaves the account and returns to the sign-in screen. Wired to both the
  /// app-bar back arrow and the primary button, because on the root route a
  /// "back" arrow has nowhere else to go.
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final isLogistics = user.role == 'logistics_partner';
    final roleName = isLogistics ? 'Logistics Partner' : 'Rider';

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: onSignOut),
        title: const Text('biziness'),
      ),
      body: SafeArea(
        child: EmptyState(
          icon: isLogistics
              ? Icons.local_shipping_outlined
              : Icons.pedal_bike_outlined,
          title: 'The $roleName workspace is coming',
          message: 'It arrives in a later phase. You are signed in as '
              '${user.email}. Sign out to continue with a business account.',
          action: FilledButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ),
      ),
    );
  }
}
