import 'dart:async';

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
    this.canAddProduct = true,
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

  /// A staff member can add customers but not products, so the quick action is
  /// hidden rather than offered and refused.
  final bool canAddProduct;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.dashboard.loaded) widget.dashboard.load();
    // The showcase slide borrows the catalog to feature a product from each
    // category, so it is loaded here too — a failure leaves the slide quiet
    // rather than blocking the dashboard.
    if (!widget.catalog.loaded) widget.catalog.load();
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
              // The shop's own showcase sits where New transaction used to, so
              // the business is front and centre before the entry options. Its
              // position was swapped with New transaction, which now closes the
              // page.
              _sectionLabel('Your business'),
              const SizedBox(height: AppSpacing.sm),
              _businessShowcase(products, customers),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Quick actions'),
              const SizedBox(height: AppSpacing.sm),
              _quickActions(),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('New transaction'),
              const SizedBox(height: AppSpacing.sm),
              _entryOptions(),
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
        if (widget.canAddProduct) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _ActionButton(
              icon: Icons.add_box_outlined,
              label: 'Add product',
              onTap: widget.onAddProduct,
            ),
          ),
        ],
      ],
    );
  }

  /// The auto-advancing showcase that replaced the plain business card. It
  /// reads the catalog itself so the featured products appear as soon as the
  /// catalog lands, without the dashboard having to reload.
  Widget _businessShowcase(int products, int customers) {
    final business = widget.business.business;
    return _BusinessShowcase(
      catalog: widget.catalog,
      businessName: business?.displayName ?? 'Your business',
      logoUrl: business?.logoUrl,
      category: business?.businessCategory,
      locationLine: business?.location?.oneLine ?? 'Location not set yet',
      catalogLine: '$products products • $customers customers',
    );
  }
}

/// Picks up to three products that belong to three different categories. When
/// the catalog is too thin to find three categories it backfills with whatever
/// else is active, so the slide is never empty.
List<Product> _featuredProducts(List<Product> active) {
  final byCategory = <String, List<Product>>{};
  for (final product in active) {
    final category = product.category?.trim() ?? '';
    final key = category.isEmpty ? ' Other' : category.toLowerCase();
    byCategory.putIfAbsent(key, () => <Product>[]).add(product);
  }

  final featured = <Product>[];
  for (final group in byCategory.values) {
    if (featured.length == 3) break;
    featured.add(group.first);
  }
  for (final product in active) {
    if (featured.length == 3) break;
    if (!featured.contains(product)) featured.add(product);
  }
  return featured;
}

/// The "Your business" slide: a slightly taller card than the old business
/// card, holding the logo, a textured ribbon carrying the shop's name, and up
/// to three featured products scattered — never in a neat row — across the
/// canvas. It advances itself so the showcase is alive without a tap.
class _BusinessShowcase extends StatefulWidget {
  const _BusinessShowcase({
    required this.catalog,
    required this.businessName,
    required this.logoUrl,
    required this.category,
    required this.locationLine,
    required this.catalogLine,
  });

  final CatalogRepository catalog;
  final String businessName;
  final String? logoUrl;
  final String? category;
  final String locationLine;
  final String catalogLine;

  @override
  State<_BusinessShowcase> createState() => _BusinessShowcaseState();
}

class _BusinessShowcaseState extends State<_BusinessShowcase> {
  /// Enough pages to feel like a reel without being restless, and a pace slow
  /// enough to read a product before it moves.
  static const _pages = 3;
  static const _interval = Duration(seconds: 5);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_page + 1) % _pages,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          // A touch taller than the old card, as asked.
          height: 224,
          child: AnimatedBuilder(
            animation: widget.catalog,
            builder: (context, _) {
              final featured = _featuredProducts(widget.catalog.activeProducts);
              return Stack(
                children: [
                  Positioned.fill(child: _ShowcaseBackground(theme: theme)),
                  Positioned.fill(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) => _ShowcasePage(
                        index: index,
                        businessName: widget.businessName,
                        logoUrl: widget.logoUrl,
                        products: featured,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 30,
                    child: _dots(theme),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _footer(theme),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 7),
      color: Colors.white.withValues(alpha: 0.62),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.locationLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            widget.catalogLine,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _pages; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _page ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == _page
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }
}

/// One page of the showcase. The products are laid out at fixed but scattered
/// spots and rotated per page, so they read as accents dotted around the name
/// rather than a sequential 1-2-3 list.
class _ShowcasePage extends StatelessWidget {
  const _ShowcasePage({
    required this.index,
    required this.businessName,
    required this.logoUrl,
    required this.products,
  });

  final int index;
  final String businessName;
  final String? logoUrl;
  final List<Product> products;

  /// Scatter spots (alignment) per product slot, shifted one along each page so
  /// no two pages look alike and the order never matches the row order.
  static const _spots = <List<Alignment>>[
    [Alignment(0.80, -0.72), Alignment(-0.82, -0.18), Alignment(0.60, 0.58)],
    [Alignment(-0.80, -0.58), Alignment(0.74, -0.22), Alignment(-0.46, 0.62)],
    [Alignment(0.70, -0.62), Alignment(-0.70, 0.12), Alignment(0.52, 0.68)],
  ];

  @override
  Widget build(BuildContext context) {
    final spots = _spots[index % _spots.length];
    final showProducts = products.take(3).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: BusinessLogoAvatar(
              logoUrl: logoUrl,
              name: businessName,
              size: 46,
              radius: BorderRadius.circular(AppRadius.field),
            ),
          ),
          Align(
            alignment: const Alignment(-0.05, 0.02),
            child: _NameRibbon(name: businessName),
          ),
          for (var slot = 0; slot < showProducts.length; slot++)
            Align(
              // Rotating the slot by the page keeps the products interleaved.
              alignment: spots[(slot + index) % spots.length],
              child: _ProductChip(product: showProducts[slot]),
            ),
        ],
      ),
    );
  }
}

/// The shop's name on a textured, angled ribbon — the "designed" moment of the
/// slide. A faint diagonal pattern sits behind the letters and a warm shadow
/// lifts the ribbon off the canvas.
class _NameRibbon extends StatelessWidget {
  const _NameRibbon({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.04,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.orangeRedLight,
              AppColors.orangeRed,
              AppColors.orangeRedDark,
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.orangeRed.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DiagonalPatternPainter(
                  Colors.white.withValues(alpha: 0.16),
                  gap: 10,
                ),
              ),
            ),
            Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                fontSize: 20,
                letterSpacing: 1.4,
                shadows: [
                  Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small product card dotted around the slide: name, category and price.
class _ProductChip extends StatelessWidget {
  const _ProductChip({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = product.category?.trim();
    return Container(
      width: 118,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.orangeRed.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (category != null && category.isNotEmpty)
            Text(
              category.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.15),
          ),
          const SizedBox(height: 6),
          Text(
            formatKobo(product.priceKobo),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slide canvas: a soft warm gradient with two colour orbs and a faint
/// diagonal pattern, so the ribbon and chips have something to sit on.
class _ShowcaseBackground extends StatelessWidget {
  const _ShowcaseBackground({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF1EA), Color(0xFFFFE0D1)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: _Orb(color: AppColors.orangeRedLight.withValues(alpha: 0.28), size: 150),
          ),
          Positioned(
            left: -40,
            bottom: -60,
            child: _Orb(color: AppColors.info.withValues(alpha: 0.12), size: 140),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _DiagonalPatternPainter(
                AppColors.orangeRed.withValues(alpha: 0.05),
                gap: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Paints repeating diagonal stripes — the "background texture" echoed on both
/// the canvas and the name ribbon.
class _DiagonalPatternPainter extends CustomPainter {
  const _DiagonalPatternPainter(this.color, {this.gap = 12});

  final Color color;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    // A 45° pattern: walk the diagonal range and draw across each stripe.
    for (double x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DiagonalPatternPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.gap != gap;
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
