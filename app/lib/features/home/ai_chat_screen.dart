import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/state/ai_repository.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/state/customer_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/phone.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_field.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    required this.ai,
    required this.catalog,
    required this.customers,
    required this.onViewTransaction,
    super.key,
  });

  final AiRepository ai;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final ValueChanged<String> onViewTransaction;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _picker = ImagePicker();
  final _search = TextEditingController();
  bool _uploading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.ai.loadAll();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickAndImport() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      // Phone screenshots are often 4-8 MB; shrinking them keeps the upload
      // quick without losing the text the model has to read.
      imageQuality: 75,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (xfile == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xfile.readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final res = await widget.ai.importImage(imageDataUrl: dataUrl, source: 'screenshot');
      final raw = res?['import'];
      final importId = raw is Map<String, dynamic> ? raw['id'] as String? : null;
      if (importId == null) {
        _snack('The screenshot could not be queued. Please try again.');
        return;
      }

      // The upload request now only queues the image. Show it in the chat
      // immediately, then wait for the server to finish reading it.
      await widget.ai.loadAll();
      if (!mounted) return;
      final status = raw is Map<String, dynamic> ? raw['status'] as String? : null;
      if (status == 'processing') {
        final done = await widget.ai.waitForImport(importId);
        if (!mounted) return;
        await widget.ai.loadAll();
        if (done == null) {
          _snack('Still reading your screenshot. Open the draft in the chat when it is ready.');
          return;
        }
      }

      if (!mounted) return;
      // The review screen opens straight away: the owner confirms, they do
      // not have to hunt for the draft in the chat.
      await _openComplete(importId);
      await widget.ai.loadAll();
    } on ApiException catch (e) {
      _snack(e.message);
    } on NetworkException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not import that image. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  OrderImport? _importFor(AiMessage message) =>
      widget.ai.imports.where((imp) => imp.id == message.orderImportId).firstOrNull;

  /// Everything searchable about a chat entry: the message text, the customer
  /// and the products the draft was read into.
  String _haystack(AiMessage message) {
    final import = _importFor(message);
    final parts = <String>[
      message.content,
      if (import != null) ...[
        import.customerName ?? '',
        import.customerPhone ?? '',
        import.deliveryAddress ?? '',
        import.transactionNumber ?? '',
        import.status,
        ...import.items.map((item) => item['name']?.toString() ?? ''),
      ],
    ];
    return parts.join(' ').toLowerCase();
  }

  Future<void> _deleteDraft(String importId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text(
          'The uploaded image and everything read from it will be removed. '
          'Orders that have already become sales cannot be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.ai.deleteImport(importId);
      _snack('Draft deleted.');
    } on ApiException catch (e) {
      _snack(e.message);
    } on NetworkException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ai,
      builder: (context, _) {
        final messages = widget.ai.messages;
        final query = _query.trim().toLowerCase();
        final filtered = query.isEmpty
            ? messages
            : messages.where((message) => _haystack(message).contains(query)).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('AI / Chats'),
            actions: [
              IconButton(
                tooltip: 'Import from screenshot or photo',
                onPressed: _uploading ? null : _pickAndImport,
                icon: _uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
              ),
            ],
          ),
          body: Column(
            children: [
              _searchBar(),
              if (_uploading) const _ReadingBanner(),
              Expanded(child: _body(messages, filtered, query)),
            ],
          ),
        );
      },
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: TextField(
        controller: _search,
        onChanged: (value) => setState(() => _query = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search customer, phone, item or order no.',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _body(List<AiMessage> messages, List<AiMessage> filtered, String query) {
    if (widget.ai.loading && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (query.isNotEmpty) {
      if (filtered.isEmpty) {
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            EmptyState(
              icon: Icons.search_off,
              title: 'No matches',
              message: 'Nothing in your chats matches “$query”.',
            ),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '${filtered.length} result${filtered.length == 1 ? '' : 's'} for “$query”',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          for (final message in filtered.reversed)
            _MessageTile(
              message: message,
              onReview: _openComplete,
              orderImport: _importFor(message),
              onViewTransaction: widget.onViewTransaction,
              onDelete: _deleteDraft,
            ),
        ],
      );
    }

    if (messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.ai.loadAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (widget.ai.error != null) ...[
              ErrorBanner(message: widget.ai.error!, onRetry: widget.ai.loadAll),
              const SizedBox(height: AppSpacing.lg),
            ],
            const _EmptyChat(),
          ],
        ),
      );
    }

    // `reverse: true` starts the list at its bottom, so opening the tab always
    // lands on the newest conversation instead of the oldest one.
    return RefreshIndicator(
      onRefresh: widget.ai.loadAll,
      child: ListView.builder(
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final message = messages[messages.length - 1 - i];
          return _MessageTile(
            message: message,
            onReview: _openComplete,
            orderImport: _importFor(message),
            onViewTransaction: widget.onViewTransaction,
            onDelete: _deleteDraft,
          );
        },
      ),
    );
  }

  Future<void> _openComplete(String importId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CompleteImportScreen(
          ai: widget.ai,
          catalog: widget.catalog,
          customers: widget.customers,
          importId: importId,
          onViewTransaction: widget.onViewTransaction,
        ),
      ),
    );
  }
}

class _ReadingBanner extends StatelessWidget {
  const _ReadingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Reading your screenshot… This can take a few seconds.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.auto_awesome_outlined,
      title: 'Turn a screenshot into an order',
      message: 'Upload a WhatsApp chat, receipt or photo. The details are read, '
          'matched to your catalog and customer list, then you confirm before '
          'anything is saved.',
    );
  }
}


class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.onReview,
    required this.orderImport,
    required this.onViewTransaction,
    required this.onDelete,
  });

  final AiMessage message;
  final ValueChanged<String> onReview;
  final OrderImport? orderImport;
  final ValueChanged<String> onViewTransaction;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';

    if (message.messageType == 'action') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                message.content,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    if (message.messageType == 'order_draft') {
      return _OrderDraftCard(
        message: message,
        onReview: onReview,
        orderImport: orderImport,
        onViewTransaction: onViewTransaction,
        onDelete: onDelete,
      );
    }

    if (message.messageType == 'image' && message.metadata?['image'] != null) {
      return Align(
        alignment: Alignment.centerRight,
        child: _ImageBubble(
          base64Image: message.metadata!['image'].toString(),
          processing: orderImport?.isProcessing ?? false,
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message.content, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}

class _OrderDraftCard extends StatelessWidget {
  const _OrderDraftCard({
    required this.message,
    required this.onReview,
    required this.orderImport,
    required this.onViewTransaction,
    required this.onDelete,
  });

  final AiMessage message;
  final ValueChanged<String> onReview;
  final OrderImport? orderImport;
  final ValueChanged<String> onViewTransaction;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final importId = message.orderImportId;
    final incomplete = message.metadata?['incomplete'] == true;
    final processing = orderImport?.isProcessing ?? false;
    final orderCreated = orderImport?.status == 'completed' || orderImport?.transactionId != null;
    final statusColor = orderCreated
        ? theme.colorScheme.primary
        : incomplete
            ? theme.colorScheme.error
            : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: statusColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                 child: Text(orderCreated ? 'Order' : 'Order draft', style: theme.textTheme.titleSmall),
                ),
                StatusPill(
                  label: orderCreated
                      ? 'Created'
                      : processing
                          ? 'Reading…'
                          : incomplete
                              ? 'Needs details'
                              : 'Ready',
                  color: statusColor,
                ),
                if (!orderCreated && importId != null)
                  IconButton(
                    tooltip: 'Delete draft',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => onDelete(importId),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (processing) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Reading the image. This draft opens when it is ready.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (orderCreated) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: statusColor),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      orderImport?.transactionNumber == null
                          ? 'Order created successfully'
                          : 'Order ${orderImport!.transactionNumber} created',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (orderImport?.transactionId != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onViewTransaction(orderImport!.transactionId!),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View sale'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
              ],
            ] else if (importId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => onReview(importId),
                  child: Text(incomplete ? 'Complete details' : 'Review & confirm'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.base64Image, this.processing = false});

  final String base64Image;
  final bool processing;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeCached(base64Image);
    if (bytes == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openImageViewer(context, bytes),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Image.memory(
                bytes,
                width: 220,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 220,
                  height: 150,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
              if (processing)
                Positioned(
                  left: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                        ),
                        SizedBox(width: 5),
                        Text('Reading…', style: TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              Container(
                margin: const EdgeInsets.all(AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out_map, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text('View', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen viewer: pinch to zoom, tap the dark area or the close button to
/// get out. The photo itself swallows taps so zooming never closes it.
Future<void> _openImageViewer(BuildContext context, Uint8List bytes) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: Stack(
            children: [
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: size.width,
                        maxHeight: size.height * 0.82,
                      ),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Uint8List? _decode(String dataUrl) {
  try {
    final comma = dataUrl.indexOf(',');
    return base64Decode(comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl);
  } catch (_) {
    return null;
  }
}

/// Decoding a multi-megabyte data URL on every rebuild is visible jank, so the
/// bytes are kept once per image.
final Map<int, Uint8List?> _decodedImageCache = {};

Uint8List? _decodeCached(String dataUrl) {
  final key = dataUrl.hashCode;
  if (_decodedImageCache.containsKey(key)) return _decodedImageCache[key];
  final bytes = _decode(dataUrl);
  if (_decodedImageCache.length > 20) _decodedImageCache.clear();
  _decodedImageCache[key] = bytes;
  return bytes;
}

class CompleteImportScreen extends StatefulWidget {
  const CompleteImportScreen({
    required this.ai,
    required this.catalog,
    required this.customers,
    required this.importId,
    required this.onViewTransaction,
    super.key,
  });

  final AiRepository ai;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final String importId;
  final ValueChanged<String> onViewTransaction;

  @override
  State<CompleteImportScreen> createState() => _CompleteImportScreenState();
}

class _CompleteImportScreenState extends State<CompleteImportScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _fee = TextEditingController();
  final _discount = TextEditingController();
  final List<Map<String, dynamic>> _items = [];

  bool _delivery = false;
  bool _loading = true;
  bool _saving = false;
  bool _incomplete = false;
  bool _alreadyCreated = false;
  String? _transactionId;
  String? _transactionNumber;
  List<String> _missingFields = const [];
  String? _error;
  Map<String, dynamic>? _matchedCustomer;
  String? _matchedBy;
  Timer? _lookupTimer;
  int _lookupSeq = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.catalog.loaded) widget.catalog.load();
    _name.addListener(_scheduleLookup);
    _phone.addListener(_scheduleLookup);
    _load();
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _fee.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    OrderImport? imp = widget.ai.imports.where((e) => e.id == widget.importId).firstOrNull;
    Map<String, dynamic>? customer;

    if (!widget.catalog.loaded || widget.catalog.error != null) {
      await widget.catalog.load();
    }

    try {
      final data = await widget.ai.importDetail(widget.importId);
      final raw = data['import'];
      if (raw is Map<String, dynamic>) imp = OrderImport.fromJson(raw);
      final rawCustomer = data['customer'];
      if (rawCustomer is Map<String, dynamic>) customer = rawCustomer;
    } catch (_) {
      // Offline: the copy already in memory is enough to review.
    }

    if (!mounted) return;

    if (imp != null) {
      _alreadyCreated = imp.status == 'completed' || imp.transactionId != null;
      _transactionId = imp.transactionId;
      _transactionNumber = imp.transactionNumber;
      _incomplete = !_alreadyCreated && imp.missingFields.isNotEmpty;
      _missingFields = imp.missingFields;
      _name.text = imp.customerName ?? '';
      // The review page uses the same +234 field as the rest of the app. A
      // malformed number read from the screenshot is cleared instead of being
      // shown as an over-long value; the owner can type it correctly.
      _phone.text = _formatStoredPhone(imp.customerPhone);
      _address.text = imp.deliveryAddress ?? '';
      if (imp.deliveryFeeKobo != null) _fee.text = (imp.deliveryFeeKobo! / 100).toString();
      if (imp.discountKobo != null && imp.discountKobo! > 0) {
        _discount.text = (imp.discountKobo! / 100).toString();
      }
      _delivery = imp.deliveryRequired;
      for (final it in imp.items) {
        _items.add(Map<String, dynamic>.from(it));
      }
    } else {
      _error = 'This draft could not be loaded. Go back and try again.';
    }

    setState(() => _loading = false);
    if (customer != null) {
      _applyMatchedCustomer(customer);
    } else {
      _scheduleLookup();
    }
  }

  void _scheduleLookup() {
    _lookupTimer?.cancel();
    if (mounted) {
      setState(_refreshMissingFields);
    }
    _lookupTimer = Timer(const Duration(milliseconds: 500), _lookupCustomer);
  }

  Future<void> _lookupCustomer() async {
    final seq = ++_lookupSeq;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty && phone.isEmpty) {
      if (_matchedCustomer != null && mounted) {
        setState(() {
          _matchedCustomer = null;
          _matchedBy = null;
        });
      }
      return;
    }

    try {
      final result = await widget.ai.matchCustomer(name: name, phone: phone);
      if (!mounted || seq != _lookupSeq) return;
      final customer = result['customer'] as Map<String, dynamic>?;
      if (customer == null) {
        setState(() {
          _matchedCustomer = null;
          _matchedBy = null;
        });
        return;
      }
      _applyMatchedCustomer(customer, matchedBy: result['matchedBy'] as String?);
    } catch (_) {
      // A lookup failure must never block the review screen.
    }
  }

  /// The ten national digits the +234 field displays, or blank when the saved
  /// value is not a complete Nigerian mobile number.
  String _formatStoredPhone(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty || !isValidNigerianPhone(value)) return '';
    return formatNationalPhone(value);
  }

  /// Fills only the blanks: what the owner typed always wins over the record.
  void _applyMatchedCustomer(Map<String, dynamic> customer, {String? matchedBy}) {
    final savedName = (customer['name'] as String? ?? '').trim();
    final savedPhone = (customer['phone'] as String? ?? '').trim();
    final savedAddress = (customer['address'] as String? ?? '').trim();

    setState(() {
      _matchedCustomer = customer;
      _matchedBy = matchedBy;
      if (_name.text.trim().isEmpty && savedName.isNotEmpty) _name.text = savedName;
      if (_phone.text.trim().isEmpty && savedPhone.isNotEmpty) {
        _phone.text = _formatStoredPhone(savedPhone);
      }
      if (_delivery && _address.text.trim().isEmpty && savedAddress.isNotEmpty) {
        _address.text = savedAddress;
      }
      _refreshMissingFields();
    });
  }

  int _subtotalKobo() {
    var total = 0;
    for (final it in _items) {
      final price = (it['unit_price_kobo'] ?? it['unitPriceKobo'] ?? 0) as int;
      final qty = (it['quantity'] ?? 1) as int;
      total += price * qty;
    }
    return total;
  }

  int _feeKobo() => _delivery ? (parseNairaToKobo(_fee.text) ?? 0) : 0;

  int _discountKobo() => parseNairaToKobo(_discount.text) ?? 0;

  int _totalKobo() => _subtotalKobo() + _feeKobo() - _discountKobo();

  void _refreshMissingFields() {
    final missing = <String>[];
    if (_name.text.trim().isEmpty && _phone.text.trim().isEmpty) {
      missing.add('customer_detail');
    }
    if (_items.isEmpty) missing.add('products');
    if (_delivery) {
      if (_feeKobo() <= 0) missing.add('delivery_fee');
      if (_address.text.trim().isEmpty) missing.add('delivery_address');
    }
    _missingFields = missing;
    _incomplete = missing.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_incomplete ? 'Complete order' : 'Review order')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _alreadyCreated
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
                        const SizedBox(height: AppSpacing.md),
                        Text('Sale created', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: AppSpacing.xs),
                        if (_transactionNumber != null) ...[
                          Text('Order ${_transactionNumber!}', style: theme.textTheme.titleMedium),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        Text(
                          'This order has already been created and added to your sales.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        if (_transactionId != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton.icon(
                            onPressed: () => widget.onViewTransaction(_transactionId!),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('View sale details'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_missingFields.isNotEmpty) ...[
                  _MissingBanner(fields: _missingFields.map(_missingLabel).toList()),
                  const SizedBox(height: AppSpacing.md),
                ],
                _CustomerSection(
                  name: _name,
                  phone: _phone,
                  matchedCustomer: _matchedCustomer,
                  matchedBy: _matchedBy,
                  onChanged: _scheduleLookup,
                ),
                const SizedBox(height: AppSpacing.md),
                _ItemsSection(
                  items: _items,
                  onAdd: _addItem,
                  onEdit: _editItem,
                  onRemove: (index) => setState(() {
                    _items.removeAt(index);
                    _refreshMissingFields();
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                _DeliverySection(
                  delivery: _delivery,
                  address: _address,
                  fee: _fee,
                  discount: _discount,
                  onDeliveryChanged: (value) => setState(() {
                    _delivery = value;
                    _refreshMissingFields();
                  }),
                  onChanged: () => setState(_refreshMissingFields),
                ),
              ],
            ),
      bottomNavigationBar: _loading || _alreadyCreated
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: theme.textTheme.bodyMedium),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              formatKobo(_totalKobo()),
                              maxLines: 1,
                              softWrap: false,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.point_of_sale_outlined),
                        label: Text(_saving ? 'Creating sale…' : 'Create sale'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _missingLabel(String field) {
    switch (field) {
      case 'customer_detail':
        return 'customer name or phone';
      case 'products':
        return 'products';
      case 'delivery_fee':
        return 'delivery fee';
      case 'delivery_address':
        return 'delivery address';
      default:
        return field;
    }
  }

  void _addItem() => _itemDialog();

  void _editItem(int index) => _itemDialog(index: index);

  void _itemDialog({int? index}) {
    final existing = index == null ? null : _items[index];
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final price = TextEditingController(
      text: existing == null
          ? ''
          : (((existing['unit_price_kobo'] ?? existing['unitPriceKobo'] ?? 0) as int) / 100)
              .toString(),
    );
    final qty = TextEditingController(text: (existing?['quantity'] ?? 1).toString());
    final catalogProducts = widget.catalog.activeProducts;
    final existingProductId = existing?['product_id']?.toString();
    String? selectedProductId =
        existingProductId == null || existingProductId.isEmpty ? null : existingProductId;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final selectedProduct = catalogProducts
                .where((p) => p.id == selectedProductId)
                .firstOrNull;

            void chooseProduct(String? id) {
              setDialogState(() {
                selectedProductId = id;
                final product = catalogProducts.where((p) => p.id == id).firstOrNull;
                if (product != null) {
                  // The catalog owns the name and the price once a product is
                  // picked, so the two can never disagree.
                  name.text = product.name;
                  price.text = (product.priceKobo / 100).toString();
                }
              });
            }

            return AlertDialog(
              title: Text(index == null ? 'Add item' : 'Edit item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String?>(
                      key: ValueKey<String?>(selectedProductId),
                      initialValue: selectedProductId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Catalog product'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Not in catalog (enter manually)'),
                        ),
                        ...catalogProducts.map(
                          (p) => DropdownMenuItem<String?>(
                            value: p.id,
                            child: Text(
                              '${p.name} · ${formatKobo(p.priceKobo)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: chooseProduct,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: name,
                      readOnly: selectedProduct != null,
                      decoration: const InputDecoration(labelText: 'Item name'),
                    ),
                    TextField(
                      controller: price,
                      readOnly: selectedProduct != null,
                      decoration: InputDecoration(
                        labelText: selectedProduct != null
                            ? 'Unit price (from catalog)'
                            : 'Unit price (naira)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: qty,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final p = selectedProduct != null
                        ? selectedProduct.priceKobo / 100
                        : (parseNairaToKobo(price.text) ?? 0) / 100;
                    final line = <String, dynamic>{
                      'name': name.text.trim(),
                      'quantity': int.tryParse(qty.text) ?? 1,
                      'unit_price_kobo': (p * 100).round(),
                      'product_id': selectedProductId,
                    };
                    setState(() {
                      if (index == null) {
                        _items.add(line);
                      } else {
                        _items[index] = line;
                      }
                      _refreshMissingFields();
                    });
                    Navigator.pop(dialogContext);
                  },
                  child: Text(index == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final address = _address.text.trim();
    final phoneE164 = phone.isEmpty ? null : toNigerianE164(phone);

    String? validation;
    if (phone.isNotEmpty && !isValidNigerianPhone(phone)) {
      validation = nigerianPhoneError;
    } else if (name.isEmpty && phone.isEmpty) {
      validation = 'Add the customer name or phone number.';
    } else if (_items.isEmpty) {
      validation = 'Add at least one item to the order.';
    } else if (_delivery && address.isEmpty) {
      validation = 'Add the delivery address, or switch delivery off.';
    } else if (_discountKobo() > _subtotalKobo()) {
      validation = 'The discount is more than the items total.';
    }

    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final result = await widget.ai.completeImport(widget.importId, {
        'customer_name': name.isEmpty ? null : name,
        'customer_phone': phoneE164,
        'items': _items,
        'delivery_required': _delivery,
        'delivery_address': address.isEmpty ? null : address,
        'delivery_fee_kobo': _feeKobo(),
        'discount_kobo': _discountKobo(),
      });
      if (widget.customers.loaded) widget.customers.load();
      navigator.pop();
      final number = result['transactionNumber'] as String?;
      messenger.showSnackBar(
        SnackBar(content: Text(number == null ? 'Order created.' : 'Order $number created.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.details?.isNotEmpty == true ? e.details!.first.message : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }
}

class _MissingBanner extends StatelessWidget {
  const _MissingBanner({required this.fields});

  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Still missing: ${fields.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSection extends StatelessWidget {
  const _CustomerSection({
    required this.name,
    required this.phone,
    required this.matchedCustomer,
    required this.matchedBy,
    required this.onChanged,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final Map<String, dynamic>? matchedCustomer;
  final String? matchedBy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matchedName = matchedCustomer?['name']?.toString();
    final matchedLabel = matchedBy == 'phone' ? 'phone number' : 'name';

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: name,
            onChanged: (_) => onChanged(),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          NigerianPhoneField(
            controller: phone,
            label: 'Phone',
            required: false,
            onChanged: (_) => onChanged(),
          ),
          if (matchedCustomer != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Existing customer${matchedName == null ? '' : ': $matchedName'}'
                    ' · matched by $matchedLabel',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({
    required this.items,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: theme.textTheme.titleSmall),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No items yet.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final price = (item['unit_price_kobo'] ?? item['unitPriceKobo'] ?? 0) as int;
            final qty = (item['quantity'] ?? 1) as int;
            final productId = item['product_id']?.toString();
            final matched = productId != null && productId.isNotEmpty;
            final needsPrice = !matched && price == 0;

            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    matched ? Icons.check_circle_outline : Icons.help_outline,
                    size: 18,
                    color: matched ? theme.colorScheme.primary : theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name']?.toString() ?? '', style: theme.textTheme.bodyMedium),
                        Text(
                          '$qty × ${formatKobo(price)}'
                          '${matched ? ' · from catalog' : needsPrice ? ' · set the price' : ' · not in catalog'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: needsPrice ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit item',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onEdit(index),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Remove item',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onRemove(index),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add item'),
          ),
        ],
      ),
    );
  }
}

class _DeliverySection extends StatelessWidget {
  const _DeliverySection({
    required this.delivery,
    required this.address,
    required this.fee,
    required this.discount,
    required this.onDeliveryChanged,
    required this.onChanged,
  });

  final bool delivery;
  final TextEditingController address;
  final TextEditingController fee;
  final TextEditingController discount;
  final ValueChanged<bool> onDeliveryChanged;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Delivery', style: theme.textTheme.titleSmall),
            subtitle: const Text('Add an address and rider fee'),
            value: delivery,
            onChanged: onDeliveryChanged,
          ),
          if (delivery) ...[
            TextField(
              controller: address,
              onChanged: (_) => onChanged(),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Delivery address', isDense: true),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: fee,
              onChanged: (_) => onChanged(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Delivery fee (naira)', isDense: true),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: discount,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Discount (naira, optional)',
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
