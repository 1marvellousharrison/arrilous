import 'package:flutter/material.dart';

import '../../core/state/logistics_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import 'delivery_request_detail_screen.dart';

/// Spec 27 — the full notification history on its own page.
///
/// The profile tab carries the latest seven as a preview; this page lists
/// everything the API returns (up to 100) with nothing sampled away, and a
/// tap marks an unread item as read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({required this.logistics, super.key});

  final LogisticsRepository logistics;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.logistics.loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListenableBuilder(
        listenable: widget.logistics,
        builder: (context, _) {
          final logistics = widget.logistics;
          final notifications = logistics.notifications;
          if (notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              message: 'Delivery request activity will be listed here.',
            );
          }
          return RefreshIndicator(
            onRefresh: logistics.loadNotifications,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (logistics.unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      '${logistics.unreadCount} unread',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                for (final notification in notifications)
                  _notificationCard(logistics, notification),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _notificationCard(LogisticsRepository logistics, Map<String, dynamic> notification) {
    final theme = Theme.of(context);
    final unread = notification['readAt'] == null;
    final requestId = notification['deliveryRequestId'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: unread
            ? () => logistics.markNotificationRead(notification['id'] as String)
            : requestId != null
                ? () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DeliveryRequestDetailScreen(
                          logistics: logistics,
                          requestId: requestId,
                          role: 'business',
                        ),
                      ),
                    )
                : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              unread ? Icons.mark_email_unread_outlined : Icons.email_outlined,
              size: 18,
              color: unread
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification['title'] as String? ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(notification['body'] as String? ?? '', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
