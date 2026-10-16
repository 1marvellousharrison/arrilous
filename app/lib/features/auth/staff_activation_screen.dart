import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/auth_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Staff activation (docs/staff-accounts.md).
///
/// A staff member the owner added holds a code like `ABC47-03`. Step one proves
/// the code is real and shows who it belongs to; step two sets the staff's own
/// password. No session is created here — the shell's login screen signs the
/// staff in with the code afterwards, so this screen closes with the code.
class StaffActivationScreen extends StatefulWidget {
  const StaffActivationScreen({required this.auth, super.key});

  final AuthRepository auth;

  @override
  State<StaffActivationScreen> createState() => _StaffActivationScreenState();
}

/// Matches the server's STAFF_CODE_PATTERN, case-insensitively.
final RegExp _staffCodePattern = RegExp(r'^[A-Za-z]{3}[0-9]{2}-[0-9]{2}$');

class _StaffActivationScreenState extends State<StaffActivationScreen> {
  final _codeFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  StaffClaim? _claim;
  String _submittedCode = '';
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _claimCode() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_codeFormKey.currentState!.validate()) return;

    final code = _code.text.trim().toUpperCase();
    setState(() => _busy = true);
    try {
      final claim = await widget.auth.claimStaffCode(code);
      if (!mounted) return;
      setState(() {
        _claim = claim;
        _submittedCode = code;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _activate() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await widget.auth.activateStaff(
        staffCode: _submittedCode,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(_submittedCode);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final claimed = _claim != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Activate staff account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    claimed ? 'Set your password' : 'Enter your staff code',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    claimed
                        ? 'Choose the password you will use to sign in. Your '
                            'login is the staff code below — keep it safe.'
                        : 'Your business owner gives you a code in the shape '
                            'ABC47-03. Enter it to get started.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (!claimed) _codeStep() else _passwordStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeStep() {
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _code,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _claimCode(),
            decoration: const InputDecoration(
              labelText: 'Staff code',
              hintText: 'ABC47-03',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Enter your staff code.';
              if (!_staffCodePattern.hasMatch(text)) {
                return 'Staff codes look like ABC47-03.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _claimCode,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _passwordStep() {
    final claim = _claim!;
    final theme = Theme.of(context);
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storefront_outlined,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        claim.businessName.isEmpty
                            ? 'Your business'
                            : claim.businessName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (claim.fullName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Welcome, ${claim.fullName}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _submittedCode,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: 'At least 8 characters',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
              ),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _confirm,
            enabled: !_busy,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _activate(),
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (value) =>
                value != _password.text ? 'Passwords do not match.' : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _activate,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Activate account'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _claim = null;
                      _error = null;
                    }),
            child: const Text('Use a different code'),
          ),
        ],
      ),
    );
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }
}
