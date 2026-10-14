import 'package:flutter/material.dart';

import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/status.dart';

/// Phase 11 — the transaction history screen.
///
/// Search, date range, status filters and source filters. Every filter is
/// applied by the API rather than in memory, so the list stays correct when a
/// business has thousands of sales and the visible page is only the first few.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    required this.transactions,
    required this.onOpen,
    required this.onCreate,
    super.key,
  });

  final TransactionRepository transactions;
  final ValueChanged<Transaction> onOpen;
  final VoidCallback onCreate;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!widget.transactions.loaded) widget.transactions.load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          AnimatedBuilder(
            animation: widget.transactions,
            builder: (context, _) => IconButton(
              tooltip: 'Filters',
              onPressed: _openFilters,
              icon: Badge(
                isLabelVisible: widget.transactions.activeFilterCount > 0,
                label: Text('${widget.transactions.activeFilterCount}'),
                child: const Icon(Icons.tune),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onCreate,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: AnimatedBuilder(
        animation: widget.transactions,
        builder: (context, _) {
          final repository = widget.transactions;
          final list = repository.transactions;

          return Column(
            children: [
              _searchBar(repository),
              if (repository.hasFilters) _activeFilterChips(repository),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: repository.load,
                  child: _list(repository, list),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchBar(TransactionRepository repository) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search number or notes',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: repository.search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    repository.setSearch('');
                  },
                ),
        ),
        onChanged: repository.setSearch,
      ),
    );
  }

  Widget _activeFilterChips(TransactionRepository repository) {
    final chips = <Widget>[];
    void add(String label, VoidCallback onRemove) {
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: onRemove,
          deleteIcon: const Icon(Icons.close, size: 16),
        ),
      );
    }

    if (repository.orderStatus != null) {
      add(
        'Order: ${prettyStatus(repository.orderStatus!)}',
        () => repository.setFilter(field: 'order'),
      );
    }
    if (repository.paymentStatus != null) {
      add(
        'Payment: ${prettyStatus(repository.paymentStatus!)}',
        () => repository.setFilter(field: 'payment'),
      );
    }
    if (repository.deliveryStatus != null) {
      add(
        'Delivery: ${prettyStatus(repository.deliveryStatus!)}',
        () => repository.setFilter(field: 'delivery'),
      );
    }
    if (repository.completionStatus != null) {
      add(
        'Completion: ${prettyStatus(repository.completionStatus!)}',
        () => repository.setFilter(field: 'completion'),
      );
    }
    if (repository.source != null) {
      add(
        'Source: ${prettyStatus(repository.source!)}',
        () => repository.setFilter(field: 'source'),
      );
    }
    if (repository.from != null || repository.to != null) {
      final from = repository.from;
      final to = repository.to;
      add(
        'Dates: ${_shortDate(from)} → ${_shortDate(to)}',
        () => repository.setDateRange(),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: chips.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == chips.length) {
            return TextButton(
              onPressed: repository.clearFilters,
              child: const Text('Clear all'),
            );
          }
          return chips[index];
        },
      ),
    );
  }

  Widget _list(TransactionRepository repository, List<Transaction> list) {
    if (list.isEmpty) {
      if (repository.loading) {
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            SkeletonBox(height: 78),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 78),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 78),
          ],
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: repository.hasFilters
                ? const EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'No matching transactions',
                    message: 'Try widening or clearing the filters.',
                  )
                : EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    message: 'Record your first sale to see it here.',
                    action: FilledButton.icon(
                      onPressed: widget.onCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('New transaction'),
                    ),
                  ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 96),
      itemCount: list.length + (repository.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        if (index == list.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: OutlinedButton(
              onPressed: repository.loading ? null : repository.loadMore,
              child: repository.loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Text('Load more'),
            ),
          );
        }
        return _TransactionCard(
          transaction: list[index],
          onTap: () => widget.onOpen(list[index]),
        );
      },
    );
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(transactions: widget.transactions),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction, required this.onTap});

  final Transaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.customerName ?? 'Walk-in customer',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transaction.transactionNumber} • ${_shortDate(transaction.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatKobo(transaction.totalKobo),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          StatusRow(transaction: transaction, compact: true),
        ],
      ),
    );
  }
}

/// The Phase 11 filter sheet: status, source and date range.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.transactions});

  final TransactionRepository transactions;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  @override
  Widget build(BuildContext context) {
    final repository = widget.transactions;
    return SafeArea(
      child: AnimatedBuilder(
        animation: repository,
        builder: (context, _) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Filter transactions',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Order'),
                _chips(
                  selected: repository.orderStatus,
                  values: axisValues['order']!,
                  onSelected: (value) =>
                      repository.setFilter(field: 'order', value: value),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Payment'),
                _chips(
                  selected: repository.paymentStatus,
                  values: axisValues['payment']!,
                  onSelected: (value) =>
                      repository.setFilter(field: 'payment', value: value),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Delivery'),
                _chips(
                  selected: repository.deliveryStatus,
                  values: axisValues['delivery']!,
                  onSelected: (value) =>
                      repository.setFilter(field: 'delivery', value: value),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Completion'),
                _chips(
                  selected: repository.completionStatus,
                  values: axisValues['completion']!,
                  onSelected: (value) =>
                      repository.setFilter(field: 'completion', value: value),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Source'),
                _chips(
                  selected: repository.source,
                  values: const ['manual', 'whatsapp'],
                  onSelected: (value) => repository.setFilter(field: 'source', value: value),
                ),
                const SizedBox(height: AppSpacing.lg),
                _label('Date range'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickFrom(repository),
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(
                          repository.from == null ? 'From' : _shortDate(repository.from),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTo(repository),
                        icon: const Icon(Icons.event_available, size: 18),
                        label: Text(
                          repository.to == null ? 'To' : _shortDate(repository.to),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );

  Widget _chips({
    required String? selected,
    required List<String> values,
    required ValueChanged<String?> onSelected,
  }) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(prettyStatus(value)),
            selected: selected == value,
            onSelected: (isSelected) => onSelected(isSelected ? value : null),
          ),
      ],
    );
  }

  Future<void> _pickFrom(TransactionRepository repository) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: repository.from ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    await repository.setDateRange(from: picked, to: repository.to);
  }

  Future<void> _pickTo(TransactionRepository repository) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: repository.to ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    // The owner means "up to and including that day", so extend to the last
    // millisecond of it rather than excluding everything created that evening.
    final endOfDay = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
    await repository.setDateRange(from: repository.from, to: endOfDay);
  }
}

String _shortDate(DateTime? value) =>
    value == null ? '—' : '${value.day}/${value.month}/${value.year}';