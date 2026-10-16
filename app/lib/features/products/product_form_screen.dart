import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';

/// Create or edit one product (Phase 3).
///
/// The price field is typed in naira because that is what a shopkeeper thinks in,
/// then converted to kobo before it is sent. The converted value is shown under
/// the field so the number stored is never a surprise.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    required this.catalog,
    this.product,
    super.key,
    this.readOnly = false,
  });

  final CatalogRepository catalog;
  final Product? product;

  /// Viewing only — a staff member can read a product but not edit or add one.
  final bool readOnly;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(text: widget.product?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.product?.description ?? '');
  late final TextEditingController _category =
      TextEditingController(text: widget.product?.category ?? '');
  late final TextEditingController _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.product == null ? '' : _koboToNairaText(widget.product!.priceKobo),
  );
  late final TextEditingController _stock = TextEditingController(
    text: widget.product == null ? '' : widget.product!.stockQuantity.toString(),
  );

  bool _submitting = false;
  String? _formError;
  final Map<String, String> _fieldErrors = {};

  bool get _isEditing => widget.product != null;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _category,
      _sku,
      _price,
      _stock,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Renders stored kobo back into the editable naira string, e.g. 175025 ->
  /// "1750.25", so editing a price does not quietly rescale it.
  static String _koboToNairaText(int kobo) {
    final int abs = kobo.abs();
    final int major = abs ~/ koboPerNaira;
    final int minor = abs % koboPerNaira;
    final String sign = kobo < 0 ? '-' : '';
    return minor == 0 ? '$sign$major' : '$sign$major.${minor.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseNairaToKobo(_price.text);

    return Scaffold(
      appBar: AppBar(title: Text(widget.readOnly ? 'Product' : (_isEditing ? 'Edit product' : 'New product'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (_formError != null) ...[
                ErrorBanner(message: _formError!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _name,
                enabled: !widget.readOnly,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Product name',
                  hintText: 'Indomie 50 packs',
                  errorText: _fieldErrors['name'],
                ),
                validator: (value) =>
                    (value == null || value.trim().length < 2) ? 'Enter a product name.' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _description,
                enabled: !widget.readOnly,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _category,
                      enabled: !widget.readOnly,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: 'Category'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      controller: _sku,
                      enabled: !widget.readOnly,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'SKU',
                        errorText: _fieldErrors['sku'],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _price,
                enabled: !widget.readOnly,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Price',
                  prefixText: '₦ ',
                  hintText: '15000',
                  errorText: _fieldErrors['price_kobo'],
                  helperText: parsed == null
                      ? 'Enter an amount like 15000 or 15000.50'
                      : 'Stored as ${formatKobo(parsed)}',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Enter a price.';
                  if (parseNairaToKobo(value) == null) {
                    return 'Use at most two decimal places.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _stock,
                enabled: !widget.readOnly,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Stock quantity',
                  hintText: '0',
                  errorText: _fieldErrors['stock_quantity'],
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Enter a stock quantity.';
                  final int? quantity = int.tryParse(value.trim());
                  if (quantity == null) return 'Use a whole number.';
                  if (quantity < 0) return 'Stock cannot be negative.';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              if (!widget.readOnly) ...[
                FilledButton(
                  onPressed: _submitting ? null : _save,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add product'),
                ),
                if (_isEditing) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Archiving keeps this product in past transactions. Use the list to archive it.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final int? priceKobo = parseNairaToKobo(_price.text);
    if (priceKobo == null) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _submitting = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await widget.catalog.save(
        id: widget.product?.id,
        name: _name.text.trim(),
        priceKobo: priceKobo,
        stockQuantity: int.parse(_stock.text.trim()),
        description: _description.text.trim(),
        category: _category.text.trim(),
        sku: _sku.text.trim(),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Product updated.' : 'Product added.'),
        ),
      );
      navigator.pop();
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
      _formError = error.details == null || error.details!.isEmpty
          ? error.message
          : null;
    });
  }
}
