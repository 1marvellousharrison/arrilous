import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/state/ai_repository.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/state/customer_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../core/utils/money.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
    required this.ai,
    required this.catalog,
    required this.customers,
    super.key,
  });

  final AiRepository ai;
  final CatalogRepository catalog;
  final CustomerRepository customers;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _picker = ImagePicker();
  bool _uploading = false;
  String? _expandedImageId;

  @override
  void initState() {
    super.initState();
    widget.ai.loadChat();
    widget.ai.loadImports();
  }

  Future<void> _pickAndImport() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xfile == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xfile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$base64Image';
      final res = await widget.ai.importImage(imageDataUrl: dataUrl, source: 'screenshot');
      if (!mounted) return;
      if (res != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Details extracted. Check them and confirm.')),
        );
        final importId = (res['import'] as Map<String, dynamic>?)?['id'] as String?;
        if (importId != null) {
          await _openComplete(importId);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ai,
      builder: (context, _) {
        final messages = widget.ai.messages;
        return Scaffold(
          appBar: AppBar(
            title: const Text('AI / Chats'),
            actions: [
              IconButton(
                tooltip: 'Import from screenshot/photo',
                onPressed: _uploading ? null : _pickAndImport,
                icon: _uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_photo_alternate_outlined),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        children: const [
                          EmptyState(
                            icon: Icons.auto_awesome_outlined,
                            title: 'Import an order from a photo/screenshot',
                            message: 'Tap the image icon above to upload a screenshot or photo. The AI will extract details and create a draft. If customer/product details are missing, you will get notifications here and in Notifications.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[i];
                          final isUser = m.role == 'user';
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                              padding: const EdgeInsets.all(AppSpacing.md),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                              decoration: BoxDecoration(
                                color: isUser ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (m.messageType == 'image' && m.metadata?['image'] != null) {
                                        setState(() {
                                          final id = m.id;
                                          if (_expandedImageId == id) {
                                            _expandedImageId = null;
                                          } else {
                                            _expandedImageId = id;
                                          }
                                        });
                                      }
                                    },
                                    child: Text(m.content),
                                  ),
                                  if (_expandedImageId == m.id && m.messageType == 'image' && m.metadata?['image'] != null) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    GestureDetector(
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (dialogContext) => Dialog(
                                            insetPadding: EdgeInsets.zero,
                                            backgroundColor: Colors.black,
                                            child: Stack(
                                              children: [
                                                Center(
                                                  child: InteractiveViewer(
                                                    child: Image.memory(
                                                      base64Decode(m.metadata!['image'].toString().split(',').last),
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 40,
                                                  right: 16,
                                                  child: IconButton(
                                                    icon: const Icon(Icons.close, color: Colors.white, size: 32),
                                                    onPressed: () => Navigator.of(dialogContext).pop(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          base64Decode(m.metadata!['image'].toString().split(',').last),
                                          height: 200,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 200,
                                            color: Colors.grey.shade200,
                                            child: const Center(child: Icon(Icons.broken_image)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (m.messageType == 'order_draft' && m.orderImportId != null) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    FilledButton(
                                      onPressed: () => _openComplete(m.orderImportId!),
                                      child: Text(
                                        m.metadata?['incomplete'] == true
                                            ? 'Complete order details'
                                            : 'Review & confirm order',
                                      ),
                                    ),
                                  ],
                                ],
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
    );
  }

  Future<void> _openComplete(String importId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CompleteImportScreen(ai: widget.ai, catalog: widget.catalog, customers: widget.customers, importId: importId),
      ),
    );
  }
}

class CompleteImportScreen extends StatefulWidget {
  const CompleteImportScreen({required this.ai, required this.catalog, required this.customers, required this.importId, super.key});

  final AiRepository ai;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final String importId;

  @override
  State<CompleteImportScreen> createState() => _CompleteImportScreenState();
}

class _CompleteImportScreenState extends State<CompleteImportScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _fee = TextEditingController();
  final _discount = TextEditingController();
  bool _delivery = false;
  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    final imp = widget.ai.imports.where((e) => e.id == widget.importId).firstOrNull;
    if (imp != null) {
      _name.text = imp.customerName ?? '';
      _phone.text = imp.customerPhone ?? '';
      _address.text = imp.deliveryAddress ?? '';
      if (imp.deliveryFeeKobo != null) _fee.text = (imp.deliveryFeeKobo! / 100).toString();
      if (imp.discountKobo != null) _discount.text = (imp.discountKobo! / 100).toString();
      _delivery = imp.deliveryRequired;
      for (final it in imp.items) {
        _items.add(Map<String, dynamic>.from(it));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete import')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Required: Customer detail (name or phone)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Customer name')),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Customer phone')),
          const SizedBox(height: AppSpacing.lg),
          Text('Required: Product/amount', style: Theme.of(context).textTheme.titleSmall),
          ..._items.asMap().entries.map((entry) {
            final index = entry.key;
            final it = entry.value;
            final price = (it['unit_price_kobo'] ?? it['unitPriceKobo'] ?? 0) as int;
            final qty = (it['quantity'] ?? 1) as int;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(it['name']?.toString() ?? ''),
              subtitle: Text('$qty × ${formatKobo(price)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit line',
                    onPressed: () => _editItem(index),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove line',
                    onPressed: () => setState(() => _items.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          }),
          FilledButton.tonal(onPressed: _addItem, child: const Text('Add product/line')),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Subtotal ${formatKobo(_subtotalKobo())}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(value: _delivery, onChanged: (v) => setState(() => _delivery = v), title: const Text('Delivery required')),
          if (_delivery) ...[
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Delivery address (required)')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _fee, decoration: const InputDecoration(labelText: 'Delivery fee (naira, required)'), keyboardType: TextInputType.number),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _discount, decoration: const InputDecoration(labelText: 'Discount (naira, optional)'), keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _submit, child: const Text('Create order')),
        ],
      ),
    );
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

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(index == null ? 'Add line' : 'Edit line'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Item name')),
              TextField(controller: price, decoration: const InputDecoration(labelText: 'Unit price (naira)'), keyboardType: TextInputType.number),
              TextField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final p = double.tryParse(price.text.replaceAll(',', '')) ?? 0;
                final line = {
                  'name': name.text.trim(),
                  'quantity': int.tryParse(qty.text) ?? 1,
                  'unit_price_kobo': (p * 100).round(),
                };
                setState(() {
                  if (index == null) {
                    _items.add(line);
                  } else {
                    _items[index] = line;
                  }
                });
                Navigator.pop(context);
              },
              child: Text(index == null ? 'Add' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    try {
      double feeN = 0, discN = 0;
      if (_delivery) feeN = double.tryParse(_fee.text.replaceAll(',', '')) ?? 0;
      discN = double.tryParse(_discount.text.replaceAll(',', '')) ?? 0;
      await widget.ai.completeImport(widget.importId, {
        'customer_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'customer_phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'items': _items,
        'delivery_required': _delivery,
        'delivery_address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'delivery_fee_kobo': (_delivery ? (feeN * 100).round() : 0),
        'discount_kobo': (discN * 100).round(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order created from import')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
