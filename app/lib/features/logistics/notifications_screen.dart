import 'package:flutter/material.dart';

import '../../core/state/app_notifications_repository.dart';
import '../../core/state/logistics_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import 'delivery_request_detail_screen.dart';

/// Spec 27 — the full notification history on its own page.
///
/// Two streams share this page: order alerts raised by the app itself (sales,
/// payments, stock, drafts) and delivery-request activity from the logistics
/// partner. They are merged into one chronological history and sectioned by
/// day, or by month when the window is wide enough that days would be noise.
/// Nothing is sampled away: the range chips only choose how far back to look.
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

/// How far back the inbox looks. The list itself is complete; these chips are
/// a lens over the same history, not separate server queries.
enum _InboxRange { today, week, month, year, all }

extension on _InboxRange {
  String get label => switch (this) {
        _InboxRange.today => 'Today',
        _InboxRange.week => '7 days',
        _InboxRange.month => '30 days',
        _InboxRange.year => 'This year',
        _InboxRange.all => 'All',
      };

  /// Number of days back from today, or null for "everything".
  int? get days => switch (this) {
        _InboxRange.today => 0,
        _InboxRange.week => 6,
        _InboxRange.month => 29,
        _InboxRange.year => 364,
        _InboxRange.all => null,
      };

  bool get groupsByMonth =>
      this == _InboxRange.year || this == _InboxRange.all;
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  _InboxRange _range = _InboxRange.all;

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

  bool _inRange(DateTime? value) {
    final days = _range.days;
    if (days == null) return true;
    if (value == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    return !day.isBefore(today.subtract(Duration(days: days)));
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
              message:
                  'Sales, stock, order alerts and delivery activity will be listed here.',
            );
          }

          final entries = _entries(alerts, notifications);
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
                _rangeChips(theme),
                const SizedBox(height: AppSpacing.md),
                if (app != null && app.lowStockCount > 0) ...[
                  _lowStockCard(app),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: EmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'Nothing in this period',
                      message:
                          'There is no notification in the selected window. Try a wider range.',
                      action: TextButton(
                        onPressed: () =>
                            setState(() => _range = _InboxRange.all),
                        child: const Text('Show all history'),
                      ),
                    ),
                  )
                else
                  ..._sectioned(theme, app, logistics, entries),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Merges both streams, keeps the selected window, newest first.
  List<_InboxEntry> _entries(
    List<AppNotification> alerts,
    List<Map<String, dynamic>> logistics,
  ) {
    final entries = <_InboxEntry>[];
    for (final alert in alerts) {
      final at = DateTime.tryParse(alert.createdAt)?.toLocal();
      if (!_inRange(at)) continue;
      entries.add(_InboxEntry.app(alert, at));
    }
    for (final notification in logistics) {
      final at = DateTime.tryParse(
        notification['createdAt'] as String? ?? '',
      )?.toLocal();
      if (!_inRange(at)) continue;
      entries.add(_InboxEntry.delivery(notification, at));
    }
    entries.sort((a, b) {
      final ad = a.at;
      final bd = b.at;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return entries;
  }

  List<Widget> _sectioned(
    ThemeData theme,
    AppNotificationsRepository? app,
    LogisticsRepository logistics,
    List<_InboxEntry> entries,
  ) {
    final children = <Widget>[];
    String? section;
    for (final entry in entries) {
      final label = _sectionLabel(entry.at);
      if (label != section) {
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: AppSpacing.sm));
        }
        children.add(_sectionTitle(theme, label));
        section = label;
      }
      children.add(
        entry.alert != null
            ? _appAlertCard(entry.alert!)
            : _notificationCard(logistics, entry.delivery!),
      );
    }
    return children;
  }

  Widget _rangeChips(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final range in _InboxRange.values) ...[
            ChoiceChip(
              label: Text(range.label),
              selected: _range == range,
              onSelected: (_) => setState(() => _range = range),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            if (range != _InboxRange.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  /// Wider windows group by month; shorter ones by day, where the time of day
  /// is still useful.
  String _sectionLabel(DateTime? value) {
    if (value == null) return 'Earlier';
    if (_range.groupsByMonth) {
      return '${_months[value.month - 1]} ${value.year}';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return '${_weekdays[value.weekday - 1]} ${value.day} '
        '${_months[value.month - 1]}';
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
    } else if (productId != null) {
      widget.onOpenProduct?.call(productId);
    }
  }

  Widget _appAlertCard(AppNotification notification) {
    final theme = Theme.of(context);
    final app = widget.appNotifications;
    final unread = notification.isUnread;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: app == null ? null : () => _openAlert(app, notification),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notification.isError
                  ? Icons.error_outline
                  : notification.severity == 'warning'
                      ? Icons.warning_amber_outlined
                      : notification.type == 'sale_recorded'
                          ? Icons.point_of_sale_outlined
                          : notification.type == 'sale_status'
                              ? Icons.payments_outlined
                              : notification.type == 'restock'
                                  ? Icons.inventory_2_outlined
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(notification.message, style: theme.textTheme.bodySmall),
                  if (notification.actorName != null ||
                      notification.createdAt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          if (notification.actorName != null) ...[
                            Icon(
                              Icons.person_outline,
                              size: 12,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                'by ${notification.actorName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                          Text(
                            _timeLabel(notification.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
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

  Widget _notificationCard(
    LogisticsRepository logistics,
    Map<String, dynamic> notification,
  ) {
    final theme = Theme.of(context);
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    notification['body'] as String? ?? '',
                    style: theme.textTheme.bodySmall,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      _timeLabel(notification['createdAt'] as String? ?? ''),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
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

  String _timeLabel(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '';
    final hh = parsed.hour.toString().padLeft(2, '0');
    final mm = parsed.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// One row in the merged history: either an app alert or a delivery update.
class _InboxEntry {
  _InboxEntry.app(this.alert, this.at) : delivery = null;
  _InboxEntry.delivery(this.delivery, this.at) : alert = null;

  final AppNotification? alert;
  final Map<String, dynamic>? delivery;
  final DateTime? at;
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
