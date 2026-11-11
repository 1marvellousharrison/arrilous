import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_notifications_repository.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import 'product_form_screen.dart';

/// Phase 3 — the product catalog list.
///
/// Search, category filtering and the archived toggle all run through the API
/// rather than filtering a list already in memory, so the catalog stays correct
/// once it outgrows one screen.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({
    required this.catalog,
    required this.businessName,
    super.key,
    this.readOnly = false,
    this.lowStockProducts = const [],
    this.initialLowStockOnly = false,
  });

  final CatalogRepository catalog;
  final String businessName;

  /// The server's low-stock list, so the warning still names every product even
  /// when the catalog on screen is filtered. Falls back to the loaded rows when
  /// the caller has not fetched the summary.
  final List<LowStockProduct> lowStockProducts;

  /// A staff member may read the catalog but never change it: no add button, no
  /// archive, and the detail opens for viewing only.
  final bool readOnly;

  /// A notification that points at the shelf opens the list already filtered to
  /// the products that need attention, instead of dropping the owner at the top
  /// of a long catalog.
  final bool initialLowStockOnly;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late bool _lowStockOnly = widget.initialLowStockOnly;

  @override
  void initState() {
    super.initState();
    // Products as well as categories: NavigationBar does not fire
    // onDestinationSelected for the tab the shell opens on, so without this the
    // first screen an owner sees would be an empty product list.
    if (!widget.catalog.loaded) widget.catalog.load();
    widget.catalog.loadCategories();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.catalog,
      builder: (context, _) {
        final catalog = widget.catalog;
        final warning = _warningProducts(catalog);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Products'),
            actions: [
              IconButton(
                tooltip: catalog.includeArchived
                    ? 'Hide archived products'
                    : 'Show archived products',
                onPressed: () => catalog.setIncludeArchived(!catalog.includeArchived),
                icon: Icon(
                  catalog.includeArchived
                      ? Icons.inventory_2
                      : Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          floatingActionButton: widget.readOnly
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add product'),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search products or SKU',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: catalog.search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              catalog.setSearch('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              if (warning.isNotEmpty)
                _LowStockBanner(
                  products: warning,
                  onTap: () => setState(() => _lowStockOnly = true),
                ),
              if (catalog.categories.isNotEmpty || warning.isNotEmpty)
                _CategoryBar(
                  categories: catalog.categories,
                  selected: catalog.category,
                  onSelect: catalog.setCategory,
                  lowStockCount: warning.length,
                  lowStockOnly: _lowStockOnly,
                  onToggleLowStock: () =>
                      setState(() => _lowStockOnly = !_lowStockOnly),
                ),
              Expanded(child: _body(context)),
            ],
          ),
        );
      },
    );
  }

  List<LowStockProduct> _warningProducts(CatalogRepository catalog) {
    // While the catalog is unfiltered it is the freshest view: saving a product
    // reloads it, so a restocked item disappears from the warning immediately.
    final unfiltered = catalog.loaded &&
        catalog.search.isEmpty &&
        catalog.category == null &&
        !catalog.includeArchived;
    if (unfiltered) {
      return catalog.lowStockProducts
          .map((product) => LowStockProduct(
                id: product.id,
                name: product.name,
                stockQuantity: product.stockQuantity,
                severity: product.isOutOfStock ? 'error' : 'warning',
              ))
          .toList(growable: false);
    }
    if (widget.lowStockProducts.isNotEmpty) return widget.lowStockProducts;
    return catalog.lowStockProducts
        .map((product) => LowStockProduct(
              id: product.id,
              name: product.name,
              stockQuantity: product.stockQuantity,
              severity: product.isOutOfStock ? 'error' : 'warning',
            ))
        .toList(growable: false);
  }

  Widget _body(BuildContext context) {
    final catalog = widget.catalog;
    final products = _lowStockOnly
        ? catalog.activeProducts
            .where((product) => product.isLowStock || product.isOutOfStock)
            .toList(growable: false)
        : catalog.products;

    if (catalog.loading && !catalog.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.error != null && catalog.products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          ErrorBanner(message: catalog.error!, onRetry: catalog.load),
        ],
      );
    }
    if (products.isEmpty) {
      if (_lowStockOnly) {
        return EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'No low-stock products',
          message: 'Every product on the shelf is above the warning line.',
          action: OutlinedButton(
            onPressed: () => setState(() => _lowStockOnly = false),
            child: const Text('Show all products'),
          ),
        );
      }
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: catalog.search.isEmpty
            ? 'No products yet'
            : 'No products match "${catalog.search}"',
        message: catalog.search.isEmpty
            ? 'Add what you sell so you can record sales quickly.'
            : 'Try a different search term or clear the filter.',
        action: catalog.search.isEmpty
            ? null
            : OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  catalog.setSearch('');
                },
                child: const Text('Clear search'),
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: catalog.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          96,
        ),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final product = products[index];
          return _ProductTile(
            product: product,
            readOnly: widget.readOnly,
            onTap: () => _openForm(context, product),
            onRestock: () => _restock(context, product),
            onArchive: () => _toggleArchive(context, product),
          );
        },
      ),
    );
  }

  /// Debounced so typing does not fire a request per keystroke.
  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      widget.catalog.setSearch(value.trim());
    });
  }

  Future<void> _openForm(BuildContext context, [Product? product]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(
          catalog: widget.catalog,
          product: product,
          readOnly: widget.readOnly,
        ),
      ),
    );
  }

  /// Restocking is an addition, not an edit: the owner types how many arrived
  /// and the server adds it to the shelf. That avoids remembering or retyping
  /// the old count, and makes the common case a two-field action.
  Future<void> _restock(BuildContext context, Product product) async {
    final controller = TextEditingController(text: '1');
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add stock to ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Currently ${product.stockQuantity} in stock. Enter how many you are adding now.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Items to add',
                hintText: '10',
              ),
              onSubmitted: (value) {
                final parsed = int.tryParse(value.trim());
                if (parsed != null && parsed > 0) Navigator.pop(dialogContext, parsed);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Add stock'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (quantity == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await widget.catalog.restock(product.id, quantity);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Added $quantity. ${updated.name} now has ${updated.stockQuantity} in stock.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _toggleArchive(BuildContext context, Product product) async {
    final messenger = ScaffoldMessenger.of(context);
    // A previous undo bar must not sit on top of this one. The action snackbar
    // is explicitly timed and closable: an undo that never leaves is worse than
    // no undo at all.
    messenger.hideCurrentSnackBar();

    try {
      await widget.catalog.setArchived(product.id, product.active);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            product.active
                ? '"${product.name}" archived.'
                : '"${product.name}" restored.',
          ),
          duration: const Duration(seconds: 5),
          showCloseIcon: true,
          action: product.active
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    messenger.hideCurrentSnackBar();
                    await widget.catalog.setArchived(product.id, false);
                  },
                )
              : null,
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// The catalog's own warning: a red card that names the products before the
/// owner scrolls past them. Tapping it filters the list to just those rows.
class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.products, required this.onTap});

  final List<LowStockProduct> products;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final out = products.where((product) => product.isOutOfStock).length;
    final names = products
        .take(4)
        .map((product) =>
            '${product.name} (${product.isOutOfStock ? 'out' : '${product.stockQuantity} left'})')
        .join(' • ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: AppCard(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderColor: AppColors.danger.withValues(alpha: 0.50),
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 24,
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
                    products.length == 1
                        ? '1 product needs restocking'
                        : '${products.length} products need restocking',
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
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      names,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Tap to show only these',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.lowStockCount,
    required this.lowStockOnly,
    required this.onToggleLowStock,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final int lowStockCount;
  final bool lowStockOnly;
  final VoidCallback onToggleLowStock;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          if (lowStockCount > 0)
            _AlertChip(
              label: 'Low stock ($lowStockCount)',
              selected: lowStockOnly,
              onTap: onToggleLowStock,
            ),
          _Chip(
            label: 'All',
            selected: selected == null && !lowStockOnly,
            onTap: () {
              if (lowStockOnly) onToggleLowStock();
              onSelect(null);
            },
          ),
          for (final category in categories)
            _Chip(
              label: category,
              selected: selected == category && !lowStockOnly,
              onTap: () {
                if (lowStockOnly) onToggleLowStock();
                onSelect(selected == category ? null : category);
              },
            ),
        ],
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.danger
                : AppColors.danger.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.danger),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: selected ? Colors.white : AppColors.danger,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : theme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.onTap,
    required this.onRestock,
    required this.onArchive,
    this.readOnly = false,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onRestock;
  final VoidCallback onArchive;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warning = product.active &&
        (product.isLowStock || product.isOutOfStock);

    return Opacity(
      // An archived product stays visible in the list but is visibly out of play.
      opacity: product.active ? 1 : 0.55,
      child: AppCard(
        onTap: onTap,
        color: warning ? AppColors.danger.withValues(alpha: 0.05) : null,
        borderColor: warning
            ? AppColors.danger.withValues(alpha: 0.40)
            : null,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: warning
                    ? AppColors.danger.withValues(alpha: 0.12)
                    : theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Icon(
                warning
                    ? Icons.warning_amber_rounded
                    : product.isDigital
                        ? Icons.cloud_download_outlined
                        : Icons.inventory_2_outlined,
                color: warning ? AppColors.danger : theme.colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!product.active) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const StatusPill(
                          label: 'Archived',
                          color: AppColors.lightTextMuted,
                        ),
                      ],
                      if (product.isDigital) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const StatusPill(
                          label: 'Digital',
                          color: AppColors.info,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (product.category != null) product.category!,
                      if (product.sku != null) 'SKU ${product.sku}',
                    ].join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        formatKobo(product.priceKobo),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _StockLabel(product: product),
                    ],
                  ),
                ],
              ),
            ),
            if (!readOnly && product.active && !product.isDigital)
              IconButton(
                tooltip: 'Add stock',
                onPressed: onRestock,
                icon: const Icon(Icons.add_box_outlined, size: 20),
              ),
            if (!readOnly)
              IconButton(
                tooltip: product.active ? 'Archive' : 'Restore',
                onPressed: onArchive,
                icon: Icon(
                  product.active ? Icons.archive_outlined : Icons.unarchive_outlined,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StockLabel extends StatelessWidget {
  const _StockLabel({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color color) = product.isDigital
        ? ('Unlimited · digital', AppColors.info)
        : switch (product) {
            Product(isOutOfStock: true) => ('Out of stock', AppColors.danger),
            Product(isLowStock: true) => ('${product.stockQuantity} left', AppColors.warning),
            _ => ('${product.stockQuantity} in stock', theme.colorScheme.onSurface),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (product.isDigital) ...[
            Icon(Icons.cloud_download_outlined, size: 13, color: color),
            const SizedBox(width: 3),
          ] else if (product.isOutOfStock || product.isLowStock) ...[
            Icon(
              product.isOutOfStock
                  ? Icons.error_outline
                  : Icons.warning_amber_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
