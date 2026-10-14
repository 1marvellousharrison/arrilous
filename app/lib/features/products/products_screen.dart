import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
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
  const ProductsScreen({required this.catalog, required this.businessName, super.key});

  final CatalogRepository catalog;
  final String businessName;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

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
          floatingActionButton: FloatingActionButton.extended(
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
              if (catalog.categories.isNotEmpty)
                _CategoryBar(
                  categories: catalog.categories,
                  selected: catalog.category,
                  onSelect: catalog.setCategory,
                ),
              Expanded(child: _body(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final catalog = widget.catalog;

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
    if (catalog.products.isEmpty) {
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
        itemCount: catalog.products.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final product = catalog.products[index];
          return _ProductTile(
            product: product,
            onTap: () => _openForm(context, product),
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
        ),
      ),
    );
  }

  Future<void> _toggleArchive(BuildContext context, Product product) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await widget.catalog.setArchived(product.id, product.active);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            product.active
                ? '"${product.name}" archived.'
                : '"${product.name}" restored.',
          ),
          action: product.active
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () => widget.catalog.setArchived(product.id, false),
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

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final category in categories)
            _Chip(
              label: category,
              selected: selected == category,
              onTap: () => onSelect(selected == category ? null : category),
            ),
        ],
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
    required this.onArchive,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      // An archived product stays visible in the list but is visibly out of play.
      opacity: product.active ? 1 : 0.55,
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                color: theme.colorScheme.primary,
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
    final (String label, Color color) = switch (product) {
      Product(isOutOfStock: true) => ('Out of stock', AppColors.danger),
      Product(isLowStock: true) => ('${product.stockQuantity} left', AppColors.warning),
      _ => ('${product.stockQuantity} in stock', theme.colorScheme.onSurface),
    };

    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
