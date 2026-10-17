import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/customer_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_field.dart';

/// Create or edit a customer (Phase 4).
///
/// A phone number is required: it is the contact the business and any delivery
/// rider rely on to reach the customer, so a customer is never recorded without
/// one. The email stays optional, and the delivery address is captured on the
/// sale itself only when an order needs delivering.
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
      TextEditingController(text: formatNationalPhone(widget.customer?.phone ?? ''));
  late final TextEditingController _email =
      TextEditingController(text: widget.customer?.email ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.customer?.notes ?? '');

  bool _submitting = false;
  String? _formError;
  final Map<String, String> _fieldErrors = {};

  bool get _isEditing => widget.customer != null;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _email, _notes]) {
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
              NigerianPhoneField(
                controller: _phone,
                errorText: _fieldErrors['phone'],
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
        // The field holds the ten national digits; the API stores the full
        // '+234' international form.
        phone: toNigerianE164(_phone.text),
        email: _email.text.trim(),
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
