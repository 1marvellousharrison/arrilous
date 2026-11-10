import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/state/business_repository.dart';
import '../../core/state/dashboard_repository.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/status.dart';

/// The staff member's own home.
///
/// It is deliberately not the owner's dashboard with a few cards removed: a
/// staff member is here to sell and to move deliveries, so the page leads with
/// their own money for today, their quick actions, what needs chasing, and the
/// sales they personally recorded. Business-wide catalog and customer counts
/// stay, because the catalog is theirs to read; the wallet, the shop report and
/// staff management do not.
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({
    required this.dashboard,
    required this.business,
    required this.user,
    required this.onOpenTransaction,
    required this.onNewSale,
    required this.onSeeAllTransactions,
    required this.onAddCustomer,
    required this.onOpenProducts,
    required this.onOpenProfile,
    required this.onGoToLogistics,
    super.key,
  });

  final DashboardRepository dashboard;
  final BusinessRepository business;
  final AuthUser user;
  final ValueChanged<Transaction> onOpenTransaction;

  /// Opens the same choice the owner gets: manual, screenshot or AI. A staff
  /// member sells the same way the owner does.
  final VoidCallback onNewSale;
  final VoidCallback onSeeAllTransactions;
  final VoidCallback onAddCustomer;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenProfile;
  final VoidCallback onGoToLogistics;

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

/// The four windows on the staff member's own sales.
enum _StaffRange { today, week, month, allTime }

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  _StaffRange _range = _StaffRange.today;

  @override
  void initState() {
    super.initState();
    if (!widget.dashboard.loaded) widget.dashboard.load();
  }

  SalesPeriodTotals _totals(DashboardSummary? summary) {
    final periods = summary?.periods;
    if (periods == null) return SalesPeriodTotals.empty;
    return switch (_range) {
      _StaffRange.today => periods.today,
      _StaffRange.week => periods.week,
      _StaffRange.month => periods.month,
      _StaffRange.allTime => periods.allTime,
    };
  }

  String get _rangeLabel => switch (_range) {
        _StaffRange.today => 'Today',
        _StaffRange.week => 'Last 7 days',
        _StaffRange.month => 'This month',
        _StaffRange.allTime => 'All time',
      };

  void _copyCode(String code) {
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.dashboard,
      builder: (context, _) {
        final repository = widget.dashboard;
        final summary = repository.summary;

        return RefreshIndicator(
          onRefresh: repository.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              _greeting(summary),
              if (summary?.lowStock.hasIssues == true) ...[
                const SizedBox(height: AppSpacing.md),
                _lowStockAlert(summary!.lowStock),
              ],
              if ((summary?.staff?.staffCode ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _codeCard(summary!.staff!),
              ],
              const SizedBox(height: AppSpacing.lg),
              _moneyCard(summary),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Quick actions'),
              const SizedBox(height: AppSpacing.sm),
              _quickActions(),
              if (_hasAttention(summary)) ...[
                const SizedBox(height: AppSpacing.xl),
                _sectionLabel('Needs attention'),
                const SizedBox(height: AppSpacing.sm),
                _attention(summary!),
              ],
              const SizedBox(height: AppSpacing.xl),
              _sectionRow(
                'Recent sales',
                action: 'See all',
                onAction: widget.onSeeAllTransactions,
              ),
              const SizedBox(height: AppSpacing.sm),
              _recent(repository, summary),
              if ((summary?.topProducts ?? const []).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                _sectionLabel('Your top products'),
                const SizedBox(height: AppSpacing.sm),
                _topProducts(summary!.topProducts),
              ],
              const SizedBox(height: AppSpacing.xl),
              _sectionRow(
                'Delivery desk',
                action: 'Open',
                onAction: widget.onGoToLogistics,
              ),
              const SizedBox(height: AppSpacing.sm),
              _deliveryDesk(summary),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Your shop'),
              const SizedBox(height: AppSpacing.sm),
              _shopCard(summary),
            ],
          ),
        );
      },
    );
  }

  bool _hasAttention(DashboardSummary? summary) {
    if (summary == null) return false;
    return summary.pendingPayment > 0 ||
        summary.awaitingDelivery > 0 ||
        summary.inTransit > 0;
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _sectionRow(String text, {required String action, required VoidCallback onAction}) {
    return Row(
      children: [
        Expanded(child: _sectionLabel(text)),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          child: Text(action),
        ),
      ],
    );
  }

  /// Staff see the shelf warning too: they are the ones at the counter when a
  /// customer asks for the last one. It is bigger than a tile and names the
  /// products so the message is actionable without opening the catalog first.
  Widget _lowStockAlert(LowStockSummary lowStock) {
    final theme = Theme.of(context);
    final out = lowStock.outOfStock;
    return AppCard(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderColor: AppColors.danger.withValues(alpha: 0.50),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: widget.onOpenProducts,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  out > 0 ? 'STOCK ALERT' : 'LOW STOCK',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lowStock.headline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (out > 0)
                  Text(
                    '$out already out of stock',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                if (lowStock.productNames.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    lowStock.productNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onOpenProducts,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      foregroundColor: AppColors.danger,
                    ),
                    child: const Text('Check products'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A compact welcome that names the person, not the shop: the business name
  /// is already in the app bar and again on the shop card below.
  Widget _greeting(DashboardSummary? summary) {
    final theme = Theme.of(context);
    final name = (summary?.staff?.fullName ?? widget.user.fullName).trim();
    final first = name.isEmpty ? 'there' : name.split(RegExp(r'\s+')).first;
    final initial = first.isEmpty ? '?' : first.substring(0, 1).toUpperCase();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Text(
            initial,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The permanent code, still copyable here so a staff member can hand it to
  /// the owner or sign in on another device without hunting through settings.
  Widget _codeCard(StaffSnapshot staff) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.badge_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY STAFF CODE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                Text(
                  staff.staffCode,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy code',
            onPressed: () => _copyCode(staff.staffCode),
            icon: const Icon(Icons.copy, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: (staff.isActive ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              staff.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: staff.isActive ? AppColors.success : AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The staff member's own money, with the range switch right above the
  /// figure it changes.
  Widget _moneyCard(DashboardSummary? summary) {
    final theme = Theme.of(context);
    final totals = _totals(summary);
    final loading = widget.dashboard.loading && summary == null;

    if (loading) {
      return const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 26, width: 160),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 14),
          ],
        ),
      );
    }

    if (summary == null && widget.dashboard.error != null) {
      return AppCard(
        child: Column(
          children: [
            Text(widget.dashboard.error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: widget.dashboard.load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final range in _StaffRange.values)
                ChoiceChip(
                  label: Text(
                    switch (range) {
                      _StaffRange.today => 'Today',
                      _StaffRange.week => '7 days',
                      _StaffRange.month => 'Month',
                      _StaffRange.allTime => 'All',
                    },
                  ),
                  selected: _range == range,
                  onSelected: (_) => setState(() => _range = range),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _rangeLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatKobo(totals.grossSalesKobo),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${totals.transactionCount} '
            '${totals.transactionCount == 1 ? 'sale' : 'sales'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Collected',
                  value: formatKobo(totals.collectedKobo),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MiniStat(
                  label: 'Outstanding',
                  value: formatKobo(totals.outstandingKobo),
                  color: totals.outstandingKobo > 0
                      ? AppColors.danger
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onOpenProducts,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text(
                  'Products',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onAddCustomer,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text(
                  'Add customer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: widget.onNewSale,
          icon: const Icon(Icons.point_of_sale_outlined, size: 18),
          label: const Text('New sale'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
        ),
      ],
    );
  }

  Widget _attention(DashboardSummary summary) {
    final tiles = <Widget>[
      if (summary.pendingPayment > 0)
        _AttentionTile(
          icon: Icons.payments_outlined,
          label: 'Awaiting payment',
          value: summary.pendingPayment,
          color: AppColors.danger,
          onTap: widget.onSeeAllTransactions,
        ),
      if (summary.awaitingDelivery > 0)
        _AttentionTile(
          icon: Icons.inventory_outlined,
          label: 'To deliver',
          value: summary.awaitingDelivery,
          color: AppColors.warning,
          onTap: widget.onGoToLogistics,
        ),
      if (summary.inTransit > 0)
        _AttentionTile(
          icon: Icons.local_shipping_outlined,
          label: 'On the road',
          value: summary.inTransit,
          color: AppColors.info,
          onTap: widget.onGoToLogistics,
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  Widget _recent(DashboardRepository repository, DashboardSummary? summary) {
    if (repository.loading && summary == null) {
      return const AppCard(
        child: Column(
          children: [
            SkeletonBox(height: 18),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 18),
          ],
        ),
      );
    }

    final recent = summary?.recent ?? const [];
    if (recent.isEmpty) {
      return AppCard(
        child: Column(
          children: [
            Text(
              'No sales yet.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: widget.onNewSale,
              icon: const Icon(Icons.add),
              label: const Text('Record your first sale'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final transaction in recent.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppCard(
              onTap: () => widget.onOpenTransaction(transaction),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction.transactionNumber,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        StatusRow(transaction: transaction, compact: true),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    formatKobo(transaction.totalKobo),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _topProducts(List<ProductLeader> products) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      products[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${products[i].quantity} sold',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    formatKobo(products[i].revenueKobo),
                    style: theme.textTheme.bodySmall?.copyWith(
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

  Widget _deliveryDesk(DashboardSummary? summary) {
    final logistics = summary?.logistics;
    final theme = Theme.of(context);
    return AppCard(
      onTap: widget.onGoToLogistics,
      child: Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Pending requests',
              value: '${logistics?.pendingRequests ?? 0}',
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MiniStat(
              label: 'Active deliveries',
              value: '${logistics?.activeDeliveries ?? 0}',
              color: AppColors.info,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _MiniStat(
              label: 'Failed',
              value: '${logistics?.deliveryFailures ?? 0}',
              color: (logistics?.deliveryFailures ?? 0) > 0
                  ? AppColors.danger
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shopCard(DashboardSummary? summary) {
    final theme = Theme.of(context);
    final business = widget.business.business;
    final name = business?.displayName ?? 'Your shop';
    final location = business?.location?.oneLine ?? 'Location not set yet';
    return AppCard(
      onTap: widget.onOpenProfile,
      child: Row(
        children: [
          BusinessLogoAvatar(
            logoUrl: business?.logoUrl,
            name: name,
            size: 42,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${summary?.activeProducts ?? 0} products • '
                  '${summary?.customerCount ?? 0} customers',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
