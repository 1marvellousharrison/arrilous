import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/state/customer_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';

/// Phase 4 — customer list with search.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({required this.customers, super.key});

  final CustomerRepository customers;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.customers,
      builder: (context, _) {
        final customers = widget.customers;

        return Scaffold(
          appBar: AppBar(title: const Text('Customers')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openForm(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add customer'),
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
                    hintText: 'Search name, phone or email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: customers.search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              customers.setSearch('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              Expanded(child: _body(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final customers = widget.customers;

    if (customers.loading && !customers.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (customers.error != null && customers.customers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [ErrorBanner(message: customers.error!, onRetry: customers.load)],
      );
    }
    if (customers.customers.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: customers.search.isEmpty ? 'No customers yet' : 'No matches',
        message: customers.search.isEmpty
            ? 'Save the people you sell to so you can attach them to a transaction later.'
            : 'No customer matches "${customers.search}".',
        action: customers.search.isEmpty
            ? null
            : OutlinedButton(
                onPressed: () {
                  _searchController.clear();
                  customers.setSearch('');
                },
                child: const Text('Clear search'),
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: customers.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          96,
        ),
        itemCount: customers.customers.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final customer = customers.customers[index];
          return _CustomerTile(
            customer: customer,
            onTap: () => _openDetail(context, customer),
          );
        },
      ),
    );
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      widget.customers.setSearch(value.trim());
    });
  }

  Future<void> _openForm(BuildContext context, [Customer? customer]) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerFormScreen(
          customers: widget.customers,
          customer: customer,
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, Customer customer) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerDetailScreen(
          customers: widget.customers,
          customerId: customer.id,
        ),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String? contact = customer.phone ?? customer.email;
    final bool hasSpending = customer.totalSpentKobo > 0;

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              customer.initials,
              style: TextStyle(
                fontWeight: FontWeight.w800,
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
                  customer.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (contact != null)
                  Text(
                    contact,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                if (hasSpending) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        formatKobo(customer.totalSpentKobo),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        ' • ${customer.transactionCount} '
                        '${customer.transactionCount == 1 ? "order" : "orders"}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
