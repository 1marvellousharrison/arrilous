import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/state/analytics_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';

/// The owner's analysis page.
///
/// Every figure arrives in one shaped report from `/analytics/overview`; this
/// screen only draws it. The patterns are deliberately varied — a trend line,
/// a payment donut, ranked bars and day-of-week columns — because each answers a
/// different question about the same business.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({required this.repository, super.key});

  final AnalyticsRepository repository;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _repo.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final report = _repo.overview;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Business analysis'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _repo.loading ? null : () => _repo.load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: _body(report),
        );
      },
    );
  }

  Widget _body(AnalyticsOverview? report) {
    if (report == null && _repo.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (report == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_repo.error != null)
            ErrorBanner(message: _repo.error!, onRetry: _repo.load)
          else
            const EmptyState(
              icon: Icons.insights_outlined,
              title: 'No analysis yet',
              message: 'Record a sale and the report will start taking shape.',
            ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _repo.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _rangeBar(),
          const SizedBox(height: AppSpacing.md),
          _revenueHero(report),
          const SizedBox(height: AppSpacing.md),
          _statGrid(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Revenue trend'),
          const SizedBox(height: AppSpacing.sm),
          _trendCard(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Where the money is'),
          const SizedBox(height: AppSpacing.sm),
          _paymentCard(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('What sells'),
          const SizedBox(height: AppSpacing.sm),
          _productsCard(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('When the shop is busiest'),
          const SizedBox(height: AppSpacing.sm),
          _weekdayCard(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Customers'),
          const SizedBox(height: AppSpacing.sm),
          _customersCard(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Stock health'),
          const SizedBox(height: AppSpacing.sm),
          _stockCard(report),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle('Delivery'),
          const SizedBox(height: AppSpacing.sm),
          _deliveryCard(report),
        ],
      ),
    );
  }

  Widget _rangeBar() {
    return Row(
      children: [
        for (final days in const [7, 30, 90])
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(days == 7 ? '7 days' : '$days days'),
              selected: _repo.days == days,
              onSelected: (_) {
                if (_repo.days != days) _repo.load(days: days);
              },
            ),
          ),
        const Spacer(),
        if (_repo.loading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  Widget _revenueHero(AnalyticsOverview report) {
    final delta = _percentDelta(
      report.totals.revenueKobo,
      report.previous.revenueKobo,
    );
    final positive = (report.totals.revenueKobo - report.previous.revenueKobo) >= 0;
    return AppCard(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
      borderColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.30),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SALES',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (delta != null)
                _DeltaChip(
                  label: delta,
                  positive: positive,
                  caption: 'vs last ${report.days}d',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatKobo(report.totals.revenueKobo),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${report.totals.orders} ${report.totals.orders == 1 ? 'order' : 'orders'} in the last ${report.days} days',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
          ),
        ],
      ),
    );
  }

  Widget _statGrid(AnalyticsOverview report) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.receipt_long_outlined,
                label: 'Orders',
                value: '${report.totals.orders}',
                delta: _percentDelta(
                  report.totals.orders,
                  report.previous.orders,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                icon: Icons.shopping_bag_outlined,
                label: 'Average order',
                value: formatKobo(report.totals.averageOrderKobo),
                delta: _percentDelta(
                  report.totals.averageOrderKobo,
                  report.previous.averageOrderKobo,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Collected',
                value: formatKobo(report.totals.collectedKobo),
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatCard(
                icon: Icons.schedule_outlined,
                label: 'Outstanding',
                value: formatKobo(report.totals.outstandingKobo),
                color: AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _trendCard(AnalyticsOverview report) {
    final values = report.daily.map((day) => day.revenueKobo).toList();
    final max = values.fold<int>(0, math.max);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 170,
            child: CustomPaint(
              painter: _TrendPainter(
                values: values,
                color: Theme.of(context).colorScheme.primary,
                gridColor: Theme.of(context).dividerColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                _shortDate(report.daily.first.date),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                _shortDate(report.daily.last.date),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            max == 0
                ? 'No sales in this window yet.'
                : 'Best day: ${formatKobo(max)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.65),
                ),
          ),
        ],
      ),
    );
  }

  Widget _paymentCard(AnalyticsOverview report) {
    final slices = report.paymentMix
        .where((slice) => slice.count > 0)
        .map((slice) => _DonutSlice(
              label: slice.label,
              value: slice.count,
              color: _statusColor(context, slice.status),
            ))
        .toList();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: slices.isEmpty
          ? _quiet('No payments recorded in this window.')
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Donut(
                  slices: slices,
                  centerLabel: '${report.totals.orders}',
                  centerCaption: 'orders',
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final slice in slices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: _LegendRow(slice: slice),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _productsCard(AnalyticsOverview report) {
    if (report.topProducts.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _quiet('No product lines in this window.'),
      );
    }
    final max = report.topProducts
        .map((product) => product.revenueKobo)
        .fold<int>(0, math.max);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (final product in report.topProducts) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${product.quantity} sold',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : product.revenueKobo / max,
                      minHeight: 7,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.10),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatKobo(product.revenueKobo),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (product != report.topProducts.last)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }

  Widget _weekdayCard(AnalyticsOverview report) {
    final max = report.weekdays
        .map((day) => day.revenueKobo)
        .fold<int>(0, math.max);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in report.weekdays)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                widthFactor: 0.62,
                                heightFactor: max == 0
                                    ? 0
                                    : (day.revenueKobo / max).clamp(0.02, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(
                                          alpha: day.orders == 0 ? 0.18 : 0.85,
                                        ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            day.label,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            report.peakHour.orders == 0
                ? 'No busy hour recorded yet.'
                : 'Peak time: ${_hourLabel(report.peakHour.hour)} · ${report.peakHour.orders} ${report.peakHour.orders == 1 ? 'order' : 'orders'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _customersCard(AnalyticsOverview report) {
    final customers = report.customers;
    final slices = <_DonutSlice>[
      if (customers.newCustomers > 0)
        _DonutSlice(
          label: 'New',
          value: customers.newCustomers,
          color: Theme.of(context).colorScheme.primary,
        ),
      if (customers.returning > 0)
        _DonutSlice(
          label: 'Returning',
          value: customers.returning,
          color: AppColors.info,
        ),
    ];
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (slices.isEmpty)
                _quiet('No named customers bought in this window.')
              else
                _Donut(
                  slices: slices,
                  centerLabel: '${customers.buyers}',
                  centerCaption: 'buyers',
                  size: 108,
                ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MiniFact(
                      label: 'New customers',
                      value: '${customers.newCustomers}',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    _MiniFact(
                      label: 'Returning',
                      value: '${customers.returning}',
                      color: AppColors.info,
                    ),
                    _MiniFact(
                      label: 'Walk-in orders',
                      value: '${customers.walkInOrders}',
                      color: AppColors.lightTextMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (customers.top.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(height: 1),
            ),
            Text(
              'Top customers',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final customer in customers.top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '${customer.orders}×',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      formatKobo(customer.spentKobo),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _stockCard(AnalyticsOverview report) {
    final inventory = report.inventory;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniFact(
                  label: 'Active products',
                  value: '${inventory.activeProducts}',
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Expanded(
                child: _MiniFact(
                  label: 'Stock value',
                  value: formatKobo(inventory.inventoryValueKobo),
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _CountPill(
                label: '${inventory.lowStock} low stock',
                color: AppColors.warning,
                icon: Icons.warning_amber_rounded,
              ),
              _CountPill(
                label: '${inventory.outOfStock} out',
                color: AppColors.danger,
                icon: Icons.error_outline,
              ),
            ],
          ),
          if (inventory.products.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            for (final product in inventory.products.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(
                      product.isOutOfStock
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      size: 15,
                      color: product.isOutOfStock
                          ? AppColors.danger
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      product.isOutOfStock
                          ? 'Out'
                          : '${product.stockQuantity} left',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: product.isOutOfStock
                            ? AppColors.danger
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _deliveryCard(AnalyticsOverview report) {
    final logistics = report.logistics;
    final rate = logistics.successRate;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniFact(
                  label: 'Requests',
                  value: '${logistics.requests}',
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Expanded(
                child: _MiniFact(
                  label: 'Delivered',
                  value: '${logistics.delivered}',
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _MiniFact(
                  label: 'Failed',
                  value: '${logistics.failed}',
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: rate == null ? 0 : rate / 100,
                    minHeight: 8,
                    backgroundColor:
                        AppColors.success.withValues(alpha: 0.12),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.success),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                rate == null ? 'No finished jobs' : '$rate% success',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget _quiet(String message) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
    );
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'paid':
      case 'delivered':
      case 'confirmed':
      case 'completed':
        return AppColors.success;
      case 'failed':
      case 'cancelled':
        return AppColors.danger;
      case 'unpaid':
      case 'pending':
      case 'payment_pending':
        return AppColors.warning;
      case 'refunded':
        return AppColors.info;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _hourLabel(int hour) {
    final suffix = hour < 12 ? 'AM' : 'PM';
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display $suffix';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.delta,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? delta;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: tint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (delta != null)
                Text(
                  delta!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: delta!.startsWith('-')
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({
    required this.label,
    required this.positive,
    required this.caption,
  });

  final String label;
  final bool positive;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive ? Icons.trending_up : Icons.trending_down,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$label · $caption',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
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
        color: color.withValues(alpha: 0.11),
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

class _DonutSlice {
  const _DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.slices,
    required this.centerLabel,
    required this.centerCaption,
    this.size = 120,
  });

  final List<_DonutSlice> slices;
  final String centerLabel;
  final String centerCaption;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(slices: slices),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerLabel,
                style: TextStyle(
                  fontSize: size / 5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                centerCaption,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice});

  final _DonutSlice slice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: slice.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            slice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Text(
          '${slice.value}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.color,
    required this.gridColor,
  });

  final List<int> values;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    const left = 4.0;
    const right = 4.0;
    const top = 10.0;
    const bottom = 8.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
    }

    final max = values.fold<int>(0, math.max);
    if (max == 0) return;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? chart.center.dx
          : chart.left + chart.width * i / (values.length - 1);
      final y = chart.bottom - chart.height * (values[i] / max);
      points.add(Offset(x, y));
    }

    final area = Path()..moveTo(points.first.dx, chart.bottom);
    for (final point in points) {
      area.lineTo(point.dx, point.dy);
    }
    area
      ..lineTo(points.last.dx, chart.bottom)
      ..close();

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0.02)],
      ).createShader(chart);
    canvas.drawPath(area, fill);

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      points.last,
      3.6,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices});

  final List<_DonutSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;

    final rect = Offset.zero & size;
    final stroke = size.shortestSide * 0.16;
    final arcRect = rect.deflate(stroke / 2);
    var start = -math.pi / 2;

    for (final slice in slices) {
      final sweep = 2 * math.pi * slice.value / total;
      canvas.drawArc(
        arcRect,
        start,
        sweep,
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}

String? _percentDelta(int current, int previous) {
  if (previous == 0) return current == 0 ? null : 'new';
  final change = (current - previous) / previous * 100;
  final sign = change >= 0 ? '+' : '';
  return '$sign${change.toStringAsFixed(1)}%';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return '';
  return '${_months[date.month - 1]} ${date.day}';
}
