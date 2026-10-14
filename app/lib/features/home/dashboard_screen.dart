import 'package:flutter/material.dart';

import '../../core/state/business_repository.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/state/customer_repository.dart';
import '../../core/state/dashboard_repository.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/status.dart';

/// Phase 12 — Home.
///
/// Every figure comes from `GET /dashboard/summary`, which aggregates the
/// database server-side. Nothing on this screen is a placeholder, and nothing is
/// summed from a paginated list.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.dashboard,
    required this.business,
    required this.transactions,
    required this.catalog,
    required this.customers,
    required this.onOpenTransaction,
    required this.onManualEntry,
    required this.onSeeAllTransactions,
    required this.onAddProduct,
    required this.onAddCustomer,
    super.key,
  });

  final DashboardRepository dashboard;
  final BusinessRepository business;
  final TransactionRepository transactions;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final ValueChanged<Transaction> onOpenTransaction;

  /// Spec 6 — manual entry is the only method that runs, so the available
  /// option opens it directly instead of re-showing the choice sheet.
  final VoidCallback onManualEntry;
  final VoidCallback onSeeAllTransactions;
  final VoidCallback onAddProduct;
  final VoidCallback onAddCustomer;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.dashboard.loaded) widget.dashboard.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.dashboard,
      builder: (context, _) {
        final repository = widget.dashboard;
        final summary = repository.summary;
    final products = summary?.activeProducts ?? 0;
    final customers = summary?.customerCount ?? 0;

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
              _moneyBlock(summary),
              const SizedBox(height: AppSpacing.lg),
              _stateCounts(summary),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Logistics'),
              const SizedBox(height: AppSpacing.sm),
              _logisticsBlock(summary?.logistics),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Recent activity'),
              const SizedBox(height: AppSpacing.sm),
              _recent(repository, summary),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('New transaction'),
              const SizedBox(height: AppSpacing.sm),
              _entryOptions(),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Quick actions'),
              const SizedBox(height: AppSpacing.sm),
              _quickActions(),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Your business'),
              const SizedBox(height: AppSpacing.sm),
              _businessCard(products, customers),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  /// Spec 41 — delivery workload and the nearby supply that could take it.
  Widget _logisticsBlock(LogisticsSummary? logistics) {
    final theme = Theme.of(context);
    if (logistics == null) {
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

    if (logistics.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No delivery activity yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Set your business location to see the providers and riders '
              'that cover your pickup city.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    final tiles = <Widget>[
      _StateTile(
        label: 'Pending requests',
        value: logistics.pendingRequests,
        color: AppColors.warning,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Active deliveries',
        value: logistics.activeDeliveries,
        color: AppColors.info,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Nearby providers',
        value: logistics.nearbyProviders,
        color: theme.colorScheme.primary,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Nearby riders',
        value: logistics.nearbyRiders,
        color: theme.colorScheme.primary,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Delivery failures',
        value: logistics.deliveryFailures,
        color: AppColors.danger,
        onTap: () => widget.onSeeAllTransactions(),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.5,
      children: tiles,
    );
  }

  /// Spec 6 — three entry methods over one engine. Only manual entry runs today;
  /// the other two are visible, inert, and clearly labelled.
  Widget _entryOptions() {
    return Column(
      children: [
        _EntryOption(
          icon: Icons.edit_note,
          label: 'Manual Entry',
          state: 'Available',
          available: true,
          onTap: widget.onManualEntry,
        ),
        const SizedBox(height: AppSpacing.sm),
        _EntryOption(
          icon: Icons.chat_bubble_outline,
          label: 'WhatsApp AI',
          state: 'Coming soon',
          available: false,
          onTap: _comingSoon,
        ),
        const SizedBox(height: AppSpacing.sm),
        _EntryOption(
          icon: Icons.photo_camera_outlined,
          label: 'Screenshot / Photo',
          state: 'Coming soon',
          available: false,
          onTap: _comingSoon,
        ),
      ],
    );
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This method is coming soon. Use Manual Entry for now.'),
      ),
    );
  }

  /// The headline money figures: what was sold, what came in, what is still owed.
  Widget _moneyBlock(DashboardSummary? summary) {
    final theme = Theme.of(context);
    if (summary == null) {
      return const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 28, width: 180),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 14),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total sales',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatKobo(summary.grossSalesKobo),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'across ${summary.transactionCount} '
            '${summary.transactionCount == 1 ? 'transaction' : 'transactions'}',
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
                  value: formatKobo(summary.collectedKobo),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MiniStat(
                  label: 'Outstanding',
                  value: formatKobo(summary.outstandingKobo),
                  color: summary.outstandingKobo > 0
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

  /// The per-state counts, tappable so a number leads somewhere useful.
  Widget _stateCounts(DashboardSummary? summary) {
    if (summary == null) {
      return Row(
        children: const [
          Expanded(child: SkeletonBox(height: 74)),
          SizedBox(width: AppSpacing.md),
          Expanded(child: SkeletonBox(height: 74)),
        ],
      );
    }

    final tiles = <Widget>[
      _StateTile(
        label: 'Pending payment',
        value: summary.pendingPayment,
        color: AppColors.danger,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Awaiting delivery',
        value: summary.awaitingDelivery,
        color: AppColors.warning,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'In transit',
        value: summary.inTransit,
        color: AppColors.info,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Completed',
        value: summary.completed,
        color: AppColors.success,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Failed',
        value: summary.failed,
        color: AppColors.danger,
        onTap: () => widget.onSeeAllTransactions(),
      ),
      _StateTile(
        label: 'Pending order',
        value: summary.pendingOrder,
        color: AppColors.warning,
        onTap: () => widget.onSeeAllTransactions(),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.5,
      children: tiles,
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

    if (repository.error != null && summary == null) {
      return AppCard(
        child: Column(
          children: [
            Text(repository.error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: repository.load,
              child: const Text('Retry'),
            ),
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
              'No sales recorded yet.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: widget.onManualEntry,
              icon: const Icon(Icons.add),
              label: const Text('Record your first sale'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // A short preview so the page stays scannable; the full list lives
        // behind the button below.
        for (final transaction in recent.take(7))
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
                  Text(
                    formatKobo(transaction.totalKobo),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton(
          onPressed: widget.onSeeAllTransactions,
          child: const Text('See all transactions'),
        ),
      ],
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.point_of_sale_outlined,
            label: 'New sale',
            primary: true,
            onTap: widget.onManualEntry,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _ActionButton(
            icon: Icons.person_add_alt,
            label: 'Add customer',
            onTap: widget.onAddCustomer,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _ActionButton(
            icon: Icons.add_box_outlined,
            label: 'Add product',
            onTap: widget.onAddProduct,
          ),
        ),
      ],
    );
  }

  Widget _businessCard(int products, int customers) {
    final theme = Theme.of(context);
    final profile = widget.business.business;
    final location = profile?.location;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  (profile?.displayName ?? '').isEmpty
                      ? 'Your business'
                      : profile!.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (profile?.businessCategory != null)
            _DetailRow(label: 'Category', value: profile!.businessCategory!),
          if (profile?.phone != null)
            _DetailRow(label: 'Phone', value: profile!.phone!),
          _DetailRow(
            label: 'Location',
            value: location?.oneLine ?? 'Not set yet',
          ),
          if (location?.latitude != null && location?.longitude != null)
            _DetailRow(
              label: 'Coordinates',
              value:
                  '${location!.latitude!.toStringAsFixed(4)}, ${location.longitude!.toStringAsFixed(4)}',
            ),
          _DetailRow(
            label: 'Catalog',
            value: '$products products • $customers customers',
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});

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
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A state with nothing in it is not worth a tap, so it does not pretend to
    // be a link.
    final active = value > 0;
    return AppCard(
      onTap: active ? onTap : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: active ? color : theme.colorScheme.onSurface.withValues(alpha: 0.4),
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

/// One row of the three transaction entry options (spec 6). An unavailable
/// method stays visible with a clear label instead of disappearing, so the
/// owner can see what is coming without a dead button that looks broken.
class _EntryOption extends StatelessWidget {
  const _EntryOption({
    required this.icon,
    required this.label,
    required this.state,
    required this.available,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String state;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: available
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: available
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: available ? AppColors.success : AppColors.info,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (available)
            Icon(Icons.chevron_right, color: theme.colorScheme.primary)
          else
            Icon(
              Icons.lock_outline,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}