import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/services/logo_service.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';

/// Create or edit one product (Phase 3).
///
/// The price field is typed in naira because that is what a shopkeeper thinks in,
/// then converted to kobo before it is sent. The converted value is shown under
/// the field so the number stored is never a surprise. The owner can also attach
/// a photo, which is what the home showcase puts on the product's own slide.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    required this.catalog,
    this.product,
    super.key,
    this.readOnly = false,
    this.logoService,
  });

  final CatalogRepository catalog;
  final Product? product;

  /// Viewing only — a staff member can read a product but not edit or add one.
  final bool readOnly;

  /// The device picker behind the photo tile. Isolated so tests can choose an
  /// image without a real gallery, the same way the setup flow does.
  final LogoService? logoService;

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

  /// The product photo, if any — stored as a data URL so it can be previewed
  /// inside the form and sent straight to the server.
  String? _imageUrl;
  Uint8List? _imageBytes;
  bool _pickingImage = false;

  late final LogoService _imageService =
      widget.logoService ?? const DeviceLogoService();

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.product?.imageUrl;
    _imageBytes = BusinessLogoAvatar.decode(widget.product?.imageUrl);
  }

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Product photo',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _photoTile(theme),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'This shows on the product slide. You can leave it blank.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _description,
                      enabled: !widget.readOnly,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
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
        imageUrl: _imageUrl,
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

  Widget _photoTile(ThemeData theme) {
    final hasPhoto = _imageBytes != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        onTap: (widget.readOnly || _pickingImage) ? null : _pickImage,
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: hasPhoto
              ? Image.memory(_imageBytes!, width: 96, height: 96, fit: BoxFit.cover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined, color: theme.colorScheme.primary),
                      const SizedBox(height: 6),
                      Text(
                        _imageUrl == null ? 'Add photo' : 'Change',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final bytes = await _imageService.pick();
      if (!mounted) return;
      if (bytes == null) {
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageUrl = 'data:image/png;base64,${base64Encode(bytes)}';
      });
    } on Object {
      // The picker can throw on some platforms if the gallery is unavailable. If
      // it does, do not block saving — the product still posts without a photo.
    } finally {
      if (mounted) setState(() => _pickingImage = false);
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
