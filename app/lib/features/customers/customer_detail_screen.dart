import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/customer_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import 'customer_form_screen.dart';

/// One customer's contact details, spend summary and recent orders (Phase 4).
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    required this.customers,
    required this.customerId,
    super.key,
  });

  final CustomerRepository customers;
  final String customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer? _customer;
  List<CustomerTransactionSummary> _transactions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.customers.detail(widget.customerId);
      if (!mounted) return;
      setState(() {
        _customer = result.customer;
        _transactions = result.transactions;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = _customer;

    return Scaffold(
      appBar: AppBar(
        title: Text(customer?.name ?? 'Customer'),
        actions: [
          if (customer != null)
            IconButton(
              tooltip: 'Edit',
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => CustomerFormScreen(
                      customers: widget.customers,
                      customer: customer,
                    ),
                  ),
                );
                _load();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context, theme),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SizedBox(height: AppSpacing.xl),
          ErrorBanner(message: _error!, onRetry: _load),
        ],
      );
    }

    final customer = _customer;
    if (customer == null) {
      return const EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Customer not found',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              child: Text(
                customer.initials,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (customer.phone != null)
                    Text(customer.phone!, style: theme.textTheme.bodyMedium),
                  if (customer.email != null)
                    Text(customer.email!, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Total spent',
                value: formatKobo(customer.totalSpentKobo),
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                label: 'Orders',
                value: '${customer.transactionCount}',
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        if (customer.address != null || customer.notes != null) ...[
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.address != null) ...[
                  _DetailRow(
                    icon: Icons.place_outlined,
                    label: 'Address',
                    value: customer.address!,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (customer.notes != null)
                  _DetailRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Notes',
                    value: customer.notes!,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Recent orders',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_transactions.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            message: 'Transactions recorded for this customer will appear here.',
          )
        else
          for (final transaction in _transactions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.transactionNumber,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _formatDate(transaction.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: _paymentLabel(transaction.paymentStatus),
                      color: _paymentColor(context, transaction.paymentStatus),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      formatKobo(transaction.totalKobo),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  static String _paymentLabel(String status) => switch (status) {
        'paid' => 'Paid',
        'payment_pending' => 'Pending',
        'unpaid' => 'Unpaid',
        'failed' => 'Failed',
        'refunded' => 'Refunded',
        _ => status,
      };

  static Color _paymentColor(BuildContext context, String status) =>
      switch (status) {
        'paid' => AppColors.success,
        'payment_pending' => AppColors.warning,
        'failed' => AppColors.danger,
        'refunded' => AppColors.info,
        _ => AppColors.lightTextMuted,
      };
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
