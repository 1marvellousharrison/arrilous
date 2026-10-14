import 'package:flutter/material.dart';

import '../../core/state/logistics_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import 'delivery_request_detail_screen.dart';

/// Every status a delivery request can hold, so a "show all" page is not
/// filtered down to a subset the summary never explains.
const Set<String> allDeliveryRequestStatuses = {
  'requested',
  'quoted',
  'accepted',
  'assigned',
  'picked_up',
  'in_transit',
  'delivered',
  'failed',
  'declined',
  'cancelled',
};

/// Spec 28 — the dedicated page behind a summary count.
///
/// The workspace grid says how many requests are new, active, done or failed;
/// tapping it opens this list, and a row opens the full breakdown of that one
/// delivery.
class DeliveryRequestsListScreen extends StatelessWidget {
  const DeliveryRequestsListScreen({
    required this.title,
    required this.statuses,
    required this.logistics,
    required this.role,
    super.key,
  });

  final String title;
  final Set<String> statuses;
  final LogisticsRepository logistics;
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = logistics.requests
        .where((request) => statuses.contains(request['status'] as String? ?? ''))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: logistics.load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (rows.isEmpty)
              const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Nothing here yet',
                message: 'Deliveries move into this section as their status changes.',
              ),
            for (final request in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DeliveryRequestDetailScreen(
                        logistics: logistics,
                        requestId: request['id'] as String,
                        role: role,
                      ),
                    ),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(request['transactionNumber'] as String? ?? 'Delivery request',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: AppSpacing.xs),
                        Text('${request['pickupCity'] ?? 'Pickup'} to ${request['destinationCity'] ?? 'Destination'}',
                            style: theme.textTheme.bodySmall),
                        if ((request['riderName'] as String? ?? '').isNotEmpty)
                          Text('Rider: ${request['riderName']}', style: theme.textTheme.bodySmall),
                        if (request['acceptedPriceKobo'] != null || request['publishedPriceKobo'] != null)
                          Text(
                            'Fee ${formatKobo((request['acceptedPriceKobo'] ?? request['publishedPriceKobo']) as num?)}',
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
