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
    this.onGoToAiChat,
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
  final VoidCallback? onGoToAiChat;

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
          state: 'Available',
          available: true,
          onTap: () {
            if (widget.onGoToAiChat != null) {
              widget.onGoToAiChat!();
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('AI / Chats')),
                  body: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Go to the AI / Chats tab to import from screenshot/photo.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
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

/// One entry in the showcase reel. A slide is either the shop's name, its logo,
/// or a single product.
enum _ShowcaseKind { name, logo, product }

class _ShowcaseSlide {
  const _ShowcaseSlide.name()
      : kind = _ShowcaseKind.name,
        product = null;

  const _ShowcaseSlide.logo()
      : kind = _ShowcaseKind.logo,
        product = null;

  const _ShowcaseSlide.product(this.product) : kind = _ShowcaseKind.product;

  final _ShowcaseKind kind;
  final Product? product;
}

/// Lays out the reel: it opens on the shop's name, then walks every active
/// product — one per slide — dropping the logo in after every couple of
/// products so the products never run in a row. When the catalog is empty the
/// reel is just the name and the logo.
List<_ShowcaseSlide> _buildDeck(List<Product> products) {
  final deck = <_ShowcaseSlide>[const _ShowcaseSlide.name()];
  var sinceLogo = 0;
  for (final product in products) {
    deck.add(_ShowcaseSlide.product(product));
    sinceLogo += 1;
    if (sinceLogo >= 2) {
      deck.add(const _ShowcaseSlide.logo());
      sinceLogo = 0;
    }
  }
  if (sinceLogo != 0 || products.isEmpty) {
    deck.add(const _ShowcaseSlide.logo());
  }
  return deck;
}

/// The "Your business" slide: a slightly taller card that carries a self-running
/// reel — the shop's name on a textured ribbon, then each active product on its
/// own slide with its price and stock, with the logo cut in between so the
/// products never run in a row.
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
  static const _interval = Duration(seconds: 4);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  /// The reel currently on screen. Rebuilt on every frame from the catalog so
  /// it tracks products being added or hidden while the user watches.
  List<_ShowcaseSlide> _deck = const [];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients || _deck.length < 2) return;
      _controller.animateToPage(
        (_page + 1) % _deck.length,
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

  /// The reel is dressed for light mode whatever the app's theme is: it reads
  /// as a poster, so its surfaces and text must not flip when dark mode is on.
  static final ThemeData _reelTheme = buildLightTheme();

  @override
  Widget build(BuildContext context) {
    final theme = _reelTheme;
    return Theme(
      data: _reelTheme,
      child: AppCard(
        padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          // A touch taller than the old card, as asked.
          height: 224,
          child: AnimatedBuilder(
            animation: widget.catalog,
            builder: (context, _) {
              final deck = _buildDeck(widget.catalog.activeProducts);
              _deck = deck;
              if (_page >= deck.length) _page = 0;
              return Stack(
                children: [
                  Positioned.fill(child: _ShowcaseBackground(theme: theme)),
                  Positioned.fill(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: deck.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) => _slideFor(deck[index]),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 30,
                    child: _indicator(theme),
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
      ),
    );
  }

  Widget _slideFor(_ShowcaseSlide slide) {
    switch (slide.kind) {
      case _ShowcaseKind.name:
        return _NameSlide(
          name: widget.businessName,
          category: widget.category,
        );
      case _ShowcaseKind.logo:
        return _LogoSlide(
          name: widget.businessName,
          logoUrl: widget.logoUrl,
        );
      case _ShowcaseKind.product:
        return _ProductSlide(product: slide.product!);
    }
  }

  Widget _footer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 7),
      // Near-opaque so the shop's address and catalog count stay legible over
      // whatever slide is showing behind them.
      color: Colors.white.withValues(alpha: 0.92),
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

  Widget _indicator(ThemeData theme) {
    final total = _deck.length;
    if (total > 7) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            '${_page + 1} / $total',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
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

/// The opening slide: the shop's name on its textured ribbon, with the sector
/// it trades in tucked underneath.
class _NameSlide extends StatelessWidget {
  const _NameSlide({required this.name, required this.category});

  final String name;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sector = category?.trim() ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WELCOME TO',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _NameRibbon(name: name),
            if (sector.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                sector.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The shop's logo filling the whole slide — a full-bleed cover so the owner's
/// mark is the slide, not a stamp sitting on it. With no logo it falls back to
/// a warm wash carrying the name.
class _LogoSlide extends StatelessWidget {
  const _LogoSlide({required this.name, required this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(child: _logo(context));
  }

  Widget _logo(BuildContext context) {
    final theme = Theme.of(context);
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('data:')) {
        final bytes = BusinessLogoAvatar.decode(url);
        if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
        return _fallback(theme);
      }
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(theme),
      );
    }
    return _fallback(theme);
  }

  Widget _fallback(ThemeData theme) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.orangeRed, AppColors.orangeRedDark],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 60,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A product's own slide. The picture takes four-fifths of the slide and the
/// last fifth carries the name and — in heavy type — how much is left.
class _ProductSlide extends StatelessWidget {
  const _ProductSlide({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inStock = product.stockQuantity > 0;
    final accent = inStock ? theme.colorScheme.primary : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.field),
              child: _ProductArt(product: product),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  inStock ? '${product.stockQuantity}' : 'OUT',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: accent,
                  ),
                ),
                Text(
                  inStock ? 'left' : 'of stock',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The product's picture when it has one, otherwise a warm tile with its
/// initial — so the slide still reads as "this product" while photos are rare.
class _ProductArt extends StatelessWidget {
  const _ProductArt({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.orangeRed.withValues(alpha: 0.22),
            AppColors.orangeRed.withValues(alpha: 0.10),
          ],
        ),
      ),
      child: Text(
        _initial(product.name),
        style: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return SizedBox.expand(child: _image(fallback));
  }

  Widget _image(Widget fallback) {
    final url = product.imageUrl;
    if (url == null || url.isEmpty) return fallback;
    if (url.startsWith('data:')) {
      final bytes = BusinessLogoAvatar.decode(url);
      if (bytes == null) return fallback;
      return Image.memory(bytes, fit: BoxFit.cover);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
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
