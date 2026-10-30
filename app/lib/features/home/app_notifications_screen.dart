import 'package:flutter/material.dart';

import '../../core/state/app_notifications_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

class AppNotificationsScreen extends StatefulWidget {
  const AppNotificationsScreen({required this.notifications, super.key});

  final AppNotificationsRepository notifications;

  @override
  State<AppNotificationsScreen> createState() => _AppNotificationsScreenState();
}

class _AppNotificationsScreenState extends State<AppNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifications.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.notifications,
      builder: (context, _) {
        final items = widget.notifications.notifications;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (items.any((e) => e.isUnread))
                TextButton(onPressed: () => widget.notifications.markAllRead(), child: const Text('Mark all read')),
            ],
          ),
          body: items.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: const [
                    EmptyState(
                      icon: Icons.notifications_none,
                      title: 'No notifications',
                      message: 'You will see alerts about incomplete imports and important updates here.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final n = items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: Icon(n.severity == 'warning' ? Icons.warning_amber_outlined : Icons.notifications_outlined),
                        title: Text(n.title),
                        subtitle: Text(n.message),
                        trailing: n.isUnread ? const Icon(Icons.circle, size: 10, color: Colors.orange) : null,
                        onTap: () {
                          if (n.isUnread) widget.notifications.markRead(n.id);
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
