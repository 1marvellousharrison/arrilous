import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/state/customer_repository.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';

/// Phase 9 — `+ New Transaction`.
///
/// The screen composes a sale but never decides its price: a line that picks a
/// catalog product sends only the product id, and the server reads the name and
/// price back from the catalog. That is what stops a stale or edited price on
/// this screen from becoming the price of record.
class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({
    required this.transactions,
    required this.catalog,
    required this.customers,
    super.key,
    this.onCreated,
  });

  final TransactionRepository transactions;
  final CatalogRepository catalog;
  final CustomerRepository customers;

  /// Called with the saved transaction so the caller can open its detail screen.
  final ValueChanged<Transaction>? onCreated;

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  final List<DraftItem> _items = [];
  final _formKey = GlobalKey<FormState>();

  Customer? _customer;
  bool _deliveryRequired = false;
  bool _submitting = false;
  String? _formError;
  final Map<String, String> _fieldErrors = {};

  late final TextEditingController _discount =
      TextEditingController(text: '0');
  late final TextEditingController _deliveryFee =
      TextEditingController(text: '0');
  late final TextEditingController _deliveryAddress = TextEditingController();
  late final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The product picker searches the catalog, so make sure there is something
    // to search before the owner opens it.
    if (!widget.catalog.loaded) widget.catalog.load();
    if (!widget.customers.loaded) widget.customers.load();
  }

  @override
  void dispose() {
    for (final controller in [_discount, _deliveryFee, _deliveryAddress, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _subtotalKobo =>
      _items.fold(0, (sum, item) => sum + item.subtotalKobo);

  int get _discountKobo => parseNairaToKobo(_discount.text) ?? 0;

  int get _deliveryFeeKobo => parseNairaToKobo(_deliveryFee.text) ?? 0;

  int get _totalKobo => _subtotalKobo + _deliveryFeeKobo - _discountKobo;

  /// Problems the owner can see before spending the owner's or server's time.
  List<String> get _problems {
    final problems = <String>[];
    if (_items.isEmpty) problems.add('Add at least one product.');
    for (final item in _items) {
      if (item.quantity <= 0) {
        problems.add('Quantity for ${item.name} must be at least 1.');
      }
    }
    if (_discount.text.trim().isNotEmpty &&
        parseNairaToKobo(_discount.text) == null) {
      problems.add('The discount is not a valid amount.');
    }
    if (_deliveryFee.text.trim().isNotEmpty &&
        parseNairaToKobo(_deliveryFee.text) == null) {
      problems.add('The delivery fee is not a valid amount.');
    }
    if (_discountKobo > _subtotalKobo && _items.isNotEmpty) {
      problems.add('The discount cannot be more than the items total.');
    }
    if (_deliveryRequired && _deliveryAddress.text.trim().isEmpty) {
      problems.add('Add the address this order should be delivered to.');
    }
    return problems;
  }

  bool get _canSubmit => _problems.isEmpty && !_submitting;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New transaction')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              120,
            ),
            children: [
              if (_formError != null) ...[
                ErrorBanner(message: _formError!),
                const SizedBox(height: AppSpacing.lg),
              ],
              _sectionLabel('Customer'),
              const SizedBox(height: AppSpacing.sm),
              _customerPicker(),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Products'),
              const SizedBox(height: AppSpacing.sm),
              ..._itemEditors(),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _addProduct,
                icon: const Icon(Icons.add),
                label: const Text('Add product'),
              ),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Charges'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _discount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Discount',
                              prefixText: '₦',
                              errorText: _fieldErrors['discount_kobo'],
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextFormField(
                            controller: _deliveryFee,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Delivery fee',
                              prefixText: '₦',
                              errorText: _fieldErrors['delivery_fee_kobo'],
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _totalRow('Subtotal', formatKobo(_subtotalKobo)),
                    if (_discountKobo != 0)
                      _totalRow('Discount', '-${formatKobo(_discountKobo)}'),
                    if (_deliveryFeeKobo != 0)
                      _totalRow('Delivery fee', formatKobo(_deliveryFeeKobo)),
                    const Divider(height: AppSpacing.xl),
                    _totalRow('Total', formatKobo(_totalKobo), emphasise: true),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Delivery'),
              const SizedBox(height: AppSpacing.sm),
              AppCard(
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Needs delivery'),
                      subtitle: const Text('Turn this on to track the delivery status'),
                      value: _deliveryRequired,
                      onChanged: (value) => setState(() => _deliveryRequired = value),
                    ),
                    if (_deliveryRequired) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _deliveryAddress,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Delivery address',
                          hintText: '10 Adeola Odeku St, Victoria Island',
                          errorText: _fieldErrors['delivery_address'],
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _sectionLabel('Notes'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Paid by transfer, will confirm in the morning',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _submitBar(),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _customerPicker() {
    return AppCard(
      onTap: _pickCustomer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              _customer?.name ?? 'Walk-in customer (no account)',
              style: TextStyle(
                fontWeight: _customer == null ? FontWeight.w400 : FontWeight.w600,
                color: _customer == null
                    ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)
                    : null,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }

  List<Widget> _itemEditors() {
    if (_items.isEmpty) {
      return [
        AppCard(
          child: Text(
            'No products yet. Add one from your catalog, or type a one-off line.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ];
    }

    return [
      for (final item in _items) _itemCard(item),
    ];
  }

  Widget _itemCard(DraftItem item) {
    final index = _items.indexOf(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
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
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.productId == null
                            ? 'One-off line — price is yours to set'
                            : '${formatKobo(item.unitPriceKobo)} each, from your catalog',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => _items.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: 'Quantity',
                    value: item.quantity,
                    min: 1,
                    onChanged: (value) => setState(() => item.quantity = value),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  formatKobo(item.subtotalKobo),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool emphasise = false}) {
    final style = TextStyle(
      fontSize: emphasise ? 17 : 14,
      fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500,
      color: emphasise ? Theme.of(context).colorScheme.primary : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  Widget _submitBar() {
    final problems = _problems;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Surfacing the reason inline is kinder than disabling the button and
          // leaving the owner to guess.
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                problems.first,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(
                    _items.isEmpty
                        ? 'Record sale'
                        : 'Record sale • ${formatKobo(_totalKobo)}',
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomer() async {
    final selected = await showModalBottomSheet<Customer?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CustomerPickerSheet(customers: widget.customers),
    );
    if (!mounted) return;
    setState(() => _customer = selected);
  }

  Future<void> _addProduct() async {
    final draft = await showModalBottomSheet<DraftItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddItemSheet(catalog: widget.catalog),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _items.add(draft);
      _formError = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      final created = await widget.transactions.create(
        items: _items,
        customerId: _customer?.id,
        discountKobo: _discountKobo,
        deliveryFeeKobo: _deliveryFeeKobo,
        deliveryRequired: _deliveryRequired,
        deliveryAddress: _deliveryAddress.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${created.transactionNumber} recorded.')),
      );
      if (widget.onCreated != null) {
        widget.onCreated!(created);
      } else {
        Navigator.of(context).pop();
      }
    } on ApiException catch (error) {
      _applyError(error);
    } on NetworkException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _applyError(ApiException error) {
    if (!mounted) return;
    setState(() {
      _fieldErrors
        ..clear()
        ..addEntries(
          (error.details ?? const <FieldError>[]).map(
            (detail) => MapEntry(detail.field, detail.message),
          ),
        );
      _formError =
          error.details == null || error.details!.isEmpty ? error.message : null;
    });
  }
}

/// Small +/- counter used for quantities.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Pick an existing customer, or leave it as a walk-in.
class _CustomerPickerSheet extends StatelessWidget {
  const _CustomerPickerSheet({required this.customers});

  final CustomerRepository customers;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedBuilder(
        animation: customers,
        builder: (context, _) {
          final list = customers.customers;
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (context, controller) => Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Who is this for?',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(
                          icon: Icons.person_outline,
                          title: 'No customers yet',
                          message: 'You can add customers from the Customers tab.',
                        )
                      : ListView.builder(
                          controller: controller,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final customer = list[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                child: Text(
                                  customer.initials,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(customer.name),
                              subtitle: customer.phone == null
                                  ? null
                                  : Text(customer.phone!),
                              onTap: () => Navigator.of(context).pop(customer),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Phase 9 — add one line: from the catalog, or as a one-off with a typed price.
class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet({required this.catalog});

  final CatalogRepository catalog;

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  bool _adHoc = false;
  final _name = TextEditingController();
  final _price = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AnimatedBuilder(
          animation: widget.catalog,
          builder: (context, _) {
            final products = widget.catalog.activeProducts;
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              builder: (context, controller) => Column(
                children: [
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('From catalog')),
                        ButtonSegment(value: true, label: Text('One-off')),
                      ],
                      selected: {_adHoc},
                      onSelectionChanged: (selection) =>
                          setState(() => _adHoc = selection.first),
                    ),
                  ),
                  if (_adHoc)
                    _adHocForm()
                  else
                    Expanded(
                      child: products.isEmpty
                          ? const EmptyState(
                              icon: Icons.inventory_2_outlined,
                              title: 'No active products',
                              message:
                                  'Add products to your catalog, or record this sale as a one-off line.',
                            )
                          : ListView.builder(
                              controller: controller,
                              itemCount: products.length,
                              itemBuilder: (context, index) {
                                final product = products[index];
                                return ListTile(
                                  title: Text(product.name),
                                  subtitle: Text(
                                    product.isOutOfStock
                                        ? 'Out of stock'
                                        : '${formatKobo(product.priceKobo)} • ${product.stockQuantity} in stock',
                                  ),
                                  trailing: const Icon(Icons.add_circle_outline),
                                  // Out-of-stock lines are shown but not
                                  // selectable: the server would refuse them
                                  // anyway, and an owner may still be taking a
                                  // deposit against restock.
                                  onTap: product.isOutOfStock
                                      ? null
                                      : () => Navigator.of(context).pop(
                                            DraftItem(
                                              name: product.name,
                                              productId: product.id,
                                              unitPriceKobo: product.priceKobo,
                                              quantity: 1,
                                            ),
                                          ),
                                );
                              },
                            ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _adHocForm() {
    final priceKobo = parseNairaToKobo(_price.text) ?? 0;
    final valid = _name.text.trim().isNotEmpty && priceKobo >= 0;

    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A one-off line is not in your catalog, so its name and price are '
              'yours to set. Useful for a single repair or a market-day special.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Item name',
                hintText: 'Singe pair',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Unit price',
                prefixText: '₦',
                errorText: _price.text.trim().isNotEmpty && parseNairaToKobo(_price.text) == null
                    ? 'Enter an amount like 4500 or 4500.50'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Line total: ${formatKobo(priceKobo * _quantity)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.of(context).pop(
                        DraftItem(
                          name: _name.text.trim(),
                          quantity: _quantity,
                          unitPriceKobo: priceKobo,
                        ),
                      )
                  : null,
              child: const Text('Add line'),
            ),
          ],
        ),
      ),
    );
  }
}