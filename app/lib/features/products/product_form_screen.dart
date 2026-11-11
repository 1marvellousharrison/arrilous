import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/services/digital_file_service.dart';
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
    this.digitalFileService,
  });

  final CatalogRepository catalog;
  final Product? product;

  /// Viewing only — a staff member can read a product but not edit or add one.
  final bool readOnly;

  /// The device picker behind the photo tile. Isolated so tests can choose an
  /// image without a real gallery, the same way the setup flow does.
  final LogoService? logoService;

  /// The device picker behind a digital product's file. Tests supply a fake so
  /// the upload path can be exercised without a real file dialog.
  final DigitalFileService? digitalFileService;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.product?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.product?.description ?? '',
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.product?.category ?? '',
  );
  late final TextEditingController _sku = TextEditingController(
    text: widget.product?.sku ?? '',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.product == null
        ? ''
        : _koboToNairaText(widget.product!.priceKobo),
  );
  late final TextEditingController _stock = TextEditingController(
    text: widget.product == null
        ? ''
        : widget.product!.stockQuantity.toString(),
  );
  late final TextEditingController _digitalUrl = TextEditingController(
    text: widget.product?.digitalUrl ?? '',
  );
  late final TextEditingController _digitalInstructions = TextEditingController(
    text: widget.product?.digitalInstructions ?? '',
  );

  /// 'physical' or 'digital'. New products default to a shelf item.
  late String _kind = widget.product?.isDigital == true
      ? 'digital'
      : 'physical';

  bool _submitting = false;
  String? _formError;
  final Map<String, String> _fieldErrors = {};

  /// The product photo, if any — stored as a data URL so it can be previewed
  /// inside the form and sent straight to the server.
  String? _imageUrl;
  Uint8List? _imageBytes;
  bool _pickingImage = false;

  /// A file chosen in this session, and whether an existing upload should be
  /// removed when saving. A new pick always wins over the clear flag.
  PickedDigitalFile? _pickedFile;
  bool _clearDigitalFile = false;
  bool _pickingFile = false;

  late final LogoService _imageService =
      widget.logoService ?? const DeviceLogoService();
  late final DigitalFileService _fileService =
      widget.digitalFileService ?? const DeviceDigitalFileService();

  bool get _isEditing => widget.product != null;
  bool get _isDigital => _kind == 'digital';
  bool get _hasExistingFile =>
      !_clearDigitalFile && (widget.product?.hasDigitalFile ?? false);

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
      _digitalUrl,
      _digitalInstructions,
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
    return minor == 0
        ? '$sign$major'
        : '$sign$major.${minor.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseNairaToKobo(_price.text);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.readOnly
              ? 'Product'
              : (_isEditing ? 'Edit product' : 'New product'),
        ),
      ),
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
                validator: (value) => (value == null || value.trim().length < 2)
                    ? 'Enter a product name.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'physical',
                    label: Text('Physical'),
                    icon: Icon(Icons.inventory_2_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: 'digital',
                    label: Text('Digital'),
                    icon: Icon(Icons.cloud_download_outlined, size: 18),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: widget.readOnly
                    ? null
                    : (selection) => setState(() => _kind = selection.first),
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
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a price.';
                  }
                  if (parseNairaToKobo(value) == null) {
                    return 'Use at most two decimal places.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_isDigital)
                ..._digitalFields(theme)
              else
                TextFormField(
                  controller: _stock,
                  enabled: !widget.readOnly,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Stock quantity',
                    hintText: '0',
                    errorText: _fieldErrors['stock_quantity'],
                    helperText: _isEditing
                        ? 'Adding new stock? Use + on the product list instead of editing this number.'
                        : null,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a stock quantity.';
                    }
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

  List<Widget> _digitalFields(ThemeData theme) {
    final String? existingName = _clearDigitalFile
        ? null
        : widget.product?.digitalFileName;
    return [
      Row(
        children: [
          Icon(
            Icons.cloud_download_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Digital delivery',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'The buyer receives this after payment, by email and on a private '
        'download page. Digital products never run out of stock.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        controller: _digitalUrl,
        enabled: !widget.readOnly,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Download link (optional)',
          hintText: 'https://drive.google.com/...',
          errorText: _fieldErrors['digital_url'],
          helperText: 'Buyers open this from their delivery page.',
        ),
        validator: (value) {
          if (!_isDigital) return null;
          final String url = value?.trim() ?? '';
          final bool hasFile = _pickedFile != null || _hasExistingFile;
          if (url.isEmpty && !hasFile) {
            return 'Add a download link or upload a file.';
          }
          if (url.isNotEmpty && !RegExp(r'^https?://').hasMatch(url)) {
            return 'Enter a link starting with http:// or https://';
          }
          return null;
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        controller: _digitalInstructions,
        enabled: !widget.readOnly,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Instructions for the buyer (optional)',
          hintText: 'Unzip the file and open start.html',
          alignLabelWithHint: true,
          errorText: _fieldErrors['digital_instructions'],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('Product file', style: theme.textTheme.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      if (_pickedFile != null)
        _fileTile(
          theme,
          name: _pickedFile!.name,
          detail: formatFileSize(_pickedFile!.sizeBytes),
          onRemove: widget.readOnly
              ? null
              : () => setState(() => _pickedFile = null),
        )
      else if (existingName != null)
        _fileTile(
          theme,
          name: existingName,
          detail: 'Uploaded file',
          onRemove: widget.readOnly
              ? null
              : () => setState(() => _clearDigitalFile = true),
        )
      else
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: (widget.readOnly || _pickingFile) ? null : _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_pickingFile ? 'Choosing…' : 'Upload file'),
          ),
        ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'PDF, ZIP, image, audio or video, up to 6 MB. You can set both a link '
        'and a file.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    ];
  }

  Widget _fileTile(
    ThemeData theme, {
    required String name,
    required String detail,
    required VoidCallback? onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove file',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 20),
            ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    setState(() => _pickingFile = true);
    try {
      final file = await _fileService.pick();
      if (!mounted || file == null) return;
      if (file.sizeBytes > kDigitalFileMaxBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That file is larger than 6 MB.')),
        );
        return;
      }
      setState(() {
        _pickedFile = file;
        _clearDigitalFile = false;
      });
    } on Object {
      // A platform without a file picker simply leaves the upload empty; the
      // product can still be saved with a link instead.
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
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
        stockQuantity: int.tryParse(_stock.text.trim()) ?? 0,
        description: _description.text.trim(),
        category: _category.text.trim(),
        sku: _sku.text.trim(),
        imageUrl: _imageUrl,
        kind: _kind,
        digitalUrl: _digitalUrl.text.trim(),
        digitalInstructions: _digitalInstructions.text.trim(),
        digitalFile: _pickedFile,
        clearDigitalFile: _clearDigitalFile,
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
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.field),
          ),
          child: hasPhoto
              ? Image.memory(
                  _imageBytes!,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        color: theme.colorScheme.primary,
                      ),
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
