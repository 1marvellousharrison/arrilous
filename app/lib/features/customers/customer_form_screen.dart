import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/customer_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Create or edit a customer (Phase 4).
///
/// Contact details are optional on purpose: a walk-in who only gives a name is
/// still worth recording, and a missing phone must not block the sale.
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({required this.customers, this.customer, super.key});

  final CustomerRepository customers;
  final Customer? customer;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.customer?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.customer?.phone ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.customer?.email ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.customer?.address ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.customer?.notes ?? '');

  bool _submitting = false;
  String? _formError;
  final Map<String, String> _fieldErrors = {};

  bool get _isEditing => widget.customer != null;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _email, _address, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit customer' : 'New customer')),
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
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Customer name',
                  hintText: 'Ada Nwosu',
                  errorText: _fieldErrors['name'],
                ),
                validator: (value) =>
                    (value == null || value.trim().length < 2) ? 'Enter a name.' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone (optional)',
                  hintText: '+2348012345678',
                  errorText: _fieldErrors['phone'],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email (optional)',
                  errorText: _fieldErrors['email'],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _address,
                maxLines: 2,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Prefers delivery on weekends',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
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
                    : Text(_isEditing ? 'Save changes' : 'Add customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _submitting = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await widget.customers.save(
        id: widget.customer?.id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        notes: _notes.text.trim(),
      );
      messenger.showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Customer updated.' : 'Customer added.')),
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
