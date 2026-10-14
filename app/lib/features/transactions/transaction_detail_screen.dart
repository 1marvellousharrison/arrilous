import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/status.dart';

/// Phase 10 — one transaction in full, with its Phase 8 timeline.
///
/// The action row offers only the transitions that are legal from the current
/// state (see [TransactionRepository.availableTransitions]), so an owner is
/// never invited into a rejection. The server still enforces every rule.
class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({
    required this.transactions,
    required this.transactionId,
    super.key,
    this.showBackButton = true,
  });

  final TransactionRepository transactions;
  final String transactionId;

  /// False when this screen is pushed as the root of the shell tab.
  final bool showBackButton;

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    widget.transactions.loadDetail(widget.transactionId);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.transactions,
      builder: (context, _) {
        final repository = widget.transactions;
        final transaction = repository.detail;

        return Scaffold(
          appBar: AppBar(
            title: Text(transaction?.transactionNumber ?? 'Transaction'),
            automaticallyImplyLeading: widget.showBackButton,
            actions: [
              if (transaction != null)
                IconButton(
                  tooltip: 'Reload',
                  onPressed: repository.detailLoading
                      ? null
                      : () => repository.loadDetail(transaction.id),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          body: _body(repository, transaction),
          bottomNavigationBar:
              transaction == null ? null : _actionBar(repository, transaction),
        );
      },
    );
  }

  Widget _body(TransactionRepository repository, Transaction? transaction) {
    if (transaction == null) {
      if (repository.detailLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Transaction unavailable',
        message: repository.detailError ?? 'This transaction could not be loaded.',
        action: OutlinedButton(
          onPressed: () => repository.loadDetail(widget.transactionId),
          child: const Text('Retry'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => repository.loadDetail(transaction.id),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _header(transaction),
          const SizedBox(height: AppSpacing.lg),
          _statuses(transaction),
          const SizedBox(height: AppSpacing.lg),
          _items(transaction),
          const SizedBox(height: AppSpacing.lg),
          _charges(transaction),
          if (transaction.deliveryRequired && transaction.deliveryAddress != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _delivery(transaction),
          ],
          if (transaction.notes != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _notes(transaction),
          ],
          const SizedBox(height: AppSpacing.lg),
          _timeline(transaction),
          const SizedBox(height: AppSpacing.lg),
          _provenance(transaction),
        ],
      ),
    );
  }

  Widget _header(Transaction transaction) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            transaction.transactionNumber,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_formatDate(transaction.createdAt)} • ${prettyStatus(transaction.source)}',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatKobo(transaction.totalKobo),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (transaction.outstandingKobo > 0)
                StatusPill(
                  label: '${formatKobo(transaction.outstandingKobo)} outstanding',
                  color: AppColors.danger,
                  icon: Icons.error_outline,
                ),
            ],
          ),
          if (transaction.customerName != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.person_outline, size: 18, color: theme.colorScheme.onSurface),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  transaction.customerName!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statuses(Transaction transaction) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final axis in TransactionAxis.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(axis.label, style: const TextStyle(fontSize: 13)),
                  AxisPill(axis: axis, value: transaction.valueFor(axis)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _items(Transaction transaction) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final item in transaction.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${item.quantity}×',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name),
                        Text(
                          '${formatKobo(item.unitPriceKobo)} each'
                          '${item.isAdHoc ? ' • one-off line' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(formatKobo(item.subtotalKobo), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _charges(Transaction transaction) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Charges',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          _line('Subtotal', formatKobo(transaction.subtotalKobo)),
          if (transaction.discountKobo != 0)
            _line('Discount', '-${formatKobo(transaction.discountKobo)}'),
          if (transaction.deliveryFeeKobo != 0)
            _line('Delivery fee', formatKobo(transaction.deliveryFeeKobo)),
          const Divider(height: AppSpacing.xl),
          _line('Total', formatKobo(transaction.totalKobo), emphasise: true),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool emphasise = false}) {
    final style = TextStyle(
      fontSize: emphasise ? 16 : 14,
      fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500,
      color: emphasise ? Theme.of(context).colorScheme.primary : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  Widget _delivery(Transaction transaction) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_shipping_outlined, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deliver to',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(transaction.deliveryAddress!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notes(Transaction transaction) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(transaction.notes!),
        ],
      ),
    );
  }

  /// Phase 8 timeline, oldest first — the order things actually happened.
  Widget _timeline(Transaction transaction) {
    final theme = Theme.of(context);
    final history = transaction.history;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Timeline',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          if (history.isEmpty)
            Text(
              'No history recorded.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          else
            for (final entry in history)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: statusColor(entry.newValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 26,
                          color: theme.dividerColor,
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatTime(entry.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          if (entry.note != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '"${entry.note}"',
                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _provenance(Transaction transaction) {
    final theme = Theme.of(context);
    return Text(
      'Created ${_formatDateTime(transaction.createdAt)} • '
      'last updated ${_formatDateTime(transaction.updatedAt)}',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }

  /// Only the transitions the API would accept from here.
  Widget _actionBar(TransactionRepository repository, Transaction transaction) {
    final actions = <_StatusAction>[];
    for (final axis in TransactionAxis.values) {
      for (final value in repository.availableTransitions(transaction, axis)) {
        actions.add(_StatusAction(axis: axis, value: value));
      }
    }

    if (actions.isEmpty) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          MediaQuery.of(context).padding.bottom + AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              transaction.isCompleted ? Icons.check_circle : Icons.block,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              transaction.isCompleted
                  ? 'This transaction is complete.'
                  : 'No further status changes are available.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Move to',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final action in actions)
                ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: statusColor(action.value).withValues(alpha: 0.18),
                    child: Icon(
                      _iconFor(action.axis),
                      size: 14,
                      color: statusColor(action.value),
                    ),
                  ),
                  label: Text('${action.axis.label}: ${prettyStatus(action.value)}'),
                  onPressed: _acting
                      ? null
                      : () => _apply(repository, transaction, action),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(TransactionAxis axis) => switch (axis) {
        TransactionAxis.order => Icons.receipt_outlined,
        TransactionAxis.payment => Icons.payments_outlined,
        TransactionAxis.delivery => Icons.local_shipping_outlined,
        TransactionAxis.completion => Icons.task_alt,
      };

  Future<void> _apply(
    TransactionRepository repository,
    Transaction transaction,
    _StatusAction action,
  ) async {
    setState(() {
      _acting = true;
    });
    try {
      await repository.updateStatuses({action.axis.field: action.value});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${action.axis.label} moved to ${prettyStatus(action.value)}.',
          ),
        ),
      );
    } on ApiException catch (error) {
      _showError(error.message);
    } on NetworkException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.danger),
    );
  }
}

class _StatusAction {
  const _StatusAction({required this.axis, required this.value});

  final TransactionAxis axis;
  final String value;
}

String _formatDate(DateTime value) =>
    '${value.day}/${value.month}/${value.year}';

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _formatTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';