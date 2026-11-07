import 'package:flutter/material.dart';

import '../../core/state/app_notifications_repository.dart';
import '../../core/state/logistics_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import 'delivery_request_detail_screen.dart';

/// Spec 27 — the full notification history on its own page.
///
/// Two streams share this page: order alerts raised by the app itself (an
/// import that still needs details) and delivery-request activity from the
/// logistics partner. Each list is shown whole, with nothing sampled away, and
/// a tap marks an unread item as read.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    required this.logistics,
    this.appNotifications,
    this.onOpenProduct,
    this.onOpenTransaction,
    this.onOpenImport,
    this.onOpenDeliveryRequest,
    super.key,
  });

  final LogisticsRepository logistics;

  /// The app's own alerts. Optional so a logistics-only caller (for example a
  /// delivery partner view) can keep using the page unchanged.
  final AppNotificationsRepository? appNotifications;

  /// Where a tapped alert goes. The shell owns navigation, so this page stays a
  /// list and each alert can point at the screen that raised it.
  final void Function(String productId)? onOpenProduct;
  final void Function(String transactionId)? onOpenTransaction;
  final void Function(String importId)? onOpenImport;
  final void Function(String requestId)? onOpenDeliveryRequest;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening this page is reading the inbox: load it, then clear everything
    // routine in one go. Stock warnings and errors stay unread on purpose.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await widget.logistics.loadNotifications();
      await widget.appNotifications?.load();
      if (!mounted) return;
      await widget.appNotifications?.markAllRead();
      if (!mounted) return;
      await widget.logistics.markAllNotificationsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.appNotifications;
    final listenable = app == null
        ? widget.logistics
        : Listenable.merge([widget.logistics, app]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (app != null && app.notifications.any((n) => n.isUnread))
            TextButton(
              onPressed: app.markAllRead,
              child: const Text('Clear routine'),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final logistics = widget.logistics;
          final alerts = app?.notifications ?? const <AppNotification>[];
          final notifications = logistics.notifications;
          if (alerts.isEmpty && notifications.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'No notifications yet',
              message: 'Order alerts and delivery request activity will be listed here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              await logistics.loadNotifications();
              await app?.load();
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (app != null) ...[
                  _inboxSummary(theme, app),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (app != null && app.lowStockCount > 0) ...[
                  _sectionTitle(theme, 'Stock warnings'),
                  _lowStockCard(app),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (alerts.isNotEmpty) ...[
                  _sectionTitle(theme, 'Order alerts'),
                  for (final alert in alerts) _appAlertCard(app!, alert),
                  if (notifications.isNotEmpty)
                    const SizedBox(height: AppSpacing.md),
                ],
                if (notifications.isNotEmpty) ...[
                  _sectionTitle(theme, 'Delivery activity'),
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  /// The inbox at a glance: how many unread, how many need restocking, and how
  /// many are outright errors. The nav badge shows one number; this page shows
  /// what that number is made of.
  Widget _inboxSummary(ThemeData theme, AppNotificationsRepository app) {
    final items = <Widget>[
      if (app.unreadCount > 0)
        _CountChip(
          label: '${app.unreadCount} unread',
          color: theme.colorScheme.primary,
          icon: Icons.mark_email_unread_outlined,
        ),
      if (app.lowStockCount > 0)
        _CountChip(
          label: '${app.lowStockCount} low stock',
          color: AppColors.danger,
          icon: Icons.warning_amber_rounded,
        ),
      if (app.errorCount > 0)
        _CountChip(
          label: '${app.errorCount} errors',
          color: AppColors.danger,
          icon: Icons.error_outline,
        ),
      if (app.warningCount > 0)
        _CountChip(
          label: '${app.warningCount} warnings',
          color: AppColors.warning,
          icon: Icons.warning_amber_outlined,
        ),
    ];
    if (items.isEmpty) {
      return Text(
        'Everything is clear.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: items,
    );
  }

  Widget _lowStockCard(AppNotificationsRepository app) {
    final theme = Theme.of(context);
    final names = app.lowStockProducts
        .take(5)
        .map((product) =>
            '${product.name} (${product.isOutOfStock ? 'out' : '${product.stockQuantity} left'})')
        .join(' • ');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderColor: AppColors.danger.withValues(alpha: 0.45),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.lowStockCount == 1
                        ? '1 product needs restocking'
                        : '${app.lowStockCount} products need restocking',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (app.outOfStockCount > 0)
                    Text(
                      '${app.outOfStockCount} already out of stock',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (names.isNotEmpty)
                    Text(
                      names,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tap does both jobs: the alert is read, and the screen that raised it
  /// opens. A low-stock alert deliberately keeps its unread state until the
  /// shelf itself is fixed, even though the tap still takes the owner to the
  /// products that need attention.
  Future<void> _openAlert(
    AppNotificationsRepository app,
    AppNotification notification,
  ) async {
    if (!notification.isLowStock) {
      await app.markRead(notification.id);
    }
    if (!mounted) return;

    final productId = notification.productId;
    final transactionId = notification.transactionId;
    final importId = notification.orderImportId;
    if (notification.isLowStock && productId != null) {
      widget.onOpenProduct?.call(productId);
    } else if (importId != null) {
      widget.onOpenImport?.call(importId);
    } else if (transactionId != null) {
      widget.onOpenTransaction?.call(transactionId);
    }
  }

  Widget _appAlertCard(AppNotificationsRepository app, AppNotification notification) {
    final theme = Theme.of(context);
    final unread = notification.isUnread;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => _openAlert(app, notification),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notification.isError
                  ? Icons.error_outline
                  : notification.severity == 'warning'
                      ? Icons.warning_amber_outlined
                      : unread
                          ? Icons.mark_email_unread_outlined
                          : Icons.notifications_outlined,
              size: 18,
              color: notification.isError
                  ? AppColors.danger
                  : unread
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(notification.message, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDelivery(
    LogisticsRepository logistics,
    Map<String, dynamic> notification,
  ) async {
    if (notification['readAt'] == null) {
      await logistics.markNotificationRead(notification['id'] as String);
    }
    if (!mounted) return;
    final requestId = notification['deliveryRequestId'] as String?;
    if (requestId == null) return;
    if (widget.onOpenDeliveryRequest != null) {
      widget.onOpenDeliveryRequest!(requestId);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryRequestDetailScreen(
          logistics: logistics,
          requestId: requestId,
          role: 'business',
        ),
      ),
    );
  }

  Widget _notificationCard(LogisticsRepository logistics, Map<String, dynamic> notification) {    final theme = Theme.of(context);
    final unread = notification['readAt'] == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => _openDelivery(logistics, notification),
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

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
