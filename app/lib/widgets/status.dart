import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/state/transaction_repository.dart';

/// Turns a raw status value into a word an owner would use.
String prettyStatus(String status) {
  if (status.isEmpty) return status;
  return status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
}

/// Colours for a value on any of the four axes.
///
/// "Failed" is red on every axis and "delivered"/"paid"/"completed" are the good
/// news states; the rest are read as neutral or in-progress. Keyed by value
/// rather than by axis so one glance is enough to judge a row.
Color statusColor(String status) => switch (status) {
      'paid' || 'delivered' || 'completed' || 'confirmed' => AppColors.success,
      'failed' || 'cancelled' => AppColors.danger,
      'pending' || 'payment_pending' || 'accepted' || 'picked_up' =>
        AppColors.warning,
      'in_transit' => AppColors.info,
      'unpaid' => AppColors.danger,
      'refunded' => AppColors.info,
      _ => AppColors.lightTextMuted,
    };

/// One axis as a labelled pill, e.g. "Payment • Paid".
class AxisPill extends StatelessWidget {
  const AxisPill({required this.axis, required this.value, super.key, this.compact = false});

  final TransactionAxis axis;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(value);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Text(
              axis.label,
              style: TextStyle(
                color: color.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            prettyStatus(value),
            style: TextStyle(color: color, fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The four statuses of a transaction, laid out compactly.
///
/// Order and payment always show because they are the two an owner checks
/// first. Delivery and completion only appear when they carry meaning, so a
/// walk-in sale is not buried under four near-identical pills.
class StatusRow extends StatelessWidget {
  const StatusRow({required this.transaction, super.key, this.compact = false});

  final Transaction transaction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        AxisPill(axis: TransactionAxis.order, value: transaction.orderStatus, compact: compact),
        AxisPill(axis: TransactionAxis.payment, value: transaction.paymentStatus, compact: compact),
        if (transaction.deliveryRequired)
          AxisPill(
            axis: TransactionAxis.delivery,
            value: transaction.deliveryStatus,
            compact: compact,
          ),
        if (transaction.isCompleted)
          AxisPill(
            axis: TransactionAxis.completion,
            value: transaction.completionStatus,
            compact: compact,
          ),
      ],
    );
  }
}