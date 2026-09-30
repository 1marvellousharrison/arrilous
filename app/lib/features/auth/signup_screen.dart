import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/auth_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import 'account_type_screen.dart';

/// Sign-up form, screen 2 of sign-up (after the account type is chosen).
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    required this.auth,
    required this.onSignedIn,
    required this.onBack,
    super.key,
    this.initialRole = 'business',
  });

  final AuthRepository auth;
  final ValueChanged<AuthUser> onSignedIn;
  final VoidCallback onBack;
  final String initialRole;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  late final String _role = widget.initialRole;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  final Map<String, String?> _fieldErrors = {};

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _fieldErrors.clear();
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final session = await widget.auth.signUp(
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        phone: _phone.text.trim(),
        role: _role,
      );
      if (!mounted) return;
      widget.onSignedIn(session.user);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        for (final detail in error.details ?? const <FieldError>[]) {
          _fieldErrors[detail.field] = detail.message;
        }
      });
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _err(String field) => _fieldErrors[field];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusiness = _role == 'business';

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: _busy ? null : widget.onBack)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            children: [
              Text(
                isBusiness ? 'Set up your business account' : 'Create your account',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isBusiness
                    ? 'You can add the rest of your business details in the next step.'
                    : 'You are signing up as ${_roleLabel(_role)}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_error != null) ...[
                ErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _fullName,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: const Icon(Icons.person_outline),
                  errorText: _err('full_name'),
                ),
                validator: (value) =>
                    (value ?? '').trim().length < 2 ? 'Enter your full name.' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.alternate_email),
                  errorText: _err('email'),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Email is required.';
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(text)) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phone,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Phone number (optional)',
                  hintText: '+2348031234567',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  errorText: _err('phone'),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  if (!RegExp(r'^\+?[0-9\s-]{7,}$').hasMatch(text)) {
                    return 'Enter a valid phone number.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: _err('password'),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                  ),
                ),
                validator: (value) => (value ?? '').length < 8
                    ? 'Password must be at least 8 characters.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create account'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: _busy ? null : widget.onBack,
                child: const Text('Use a different account type'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleLabel(String role) => switch (role) {
    'logistics_partner' => 'a Logistics Partner',
    'rider' => 'a Rider',
    _ => 'a Business owner',
  };
}

/// Entry point that shows the account-type picker first.
class SignUpFlow extends StatelessWidget {
  const SignUpFlow({
    required this.auth,
    required this.onSignedIn,
    required this.onBack,
    super.key,
  });

  final AuthRepository auth;
  final ValueChanged<AuthUser> onSignedIn;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AccountTypeScreen(
      onBack: onBack,
      onSelected: (role) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SignUpScreen(
              auth: auth,
              initialRole: role,
              onBack: () => Navigator.of(context).pop(),
              onSignedIn: (user) {
                Navigator.of(context).popUntil((route) => route.isFirst);
                onSignedIn(user);
              },
            ),
          ),
        );
      },
    );
  }
}
