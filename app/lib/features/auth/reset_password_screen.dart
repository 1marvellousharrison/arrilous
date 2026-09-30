import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/auth_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Password recovery: request a reset code, then set a new password.
///
/// Pops with `true` when the password was changed so the caller can tell the
/// user to sign in again; changing a password revokes every active session.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({required this.auth, super.key, this.initialIdentifier = ''});

  final AuthRepository auth;
  final String initialIdentifier;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _identifierKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  OtpChallenge? _challenge;
  bool _onCodeStep = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _fieldError;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _identifier.text = widget.initialIdentifier;
  }

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _fieldError = null;
      _notice = null;
    });
    if (!_identifierKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final identifier = _identifier.text.trim();
    try {
      final challenge = await widget.auth.requestPasswordReset(identifier: identifier);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (challenge == null) {
          _notice =
              'If an account exists for $identifier, a 6-digit reset code has '
              'been sent. Check your inbox, then try again.';
          return;
        }
        _challenge = challenge;
        _onCodeStep = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _fieldError = error.fieldError('identifier');
      });
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _fieldError = null;
    });
    final challenge = _challenge;
    if (challenge == null) return;
    if (!_passwordKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await widget.auth.resetPassword(
        challengeId: challenge.challengeId,
        code: _code.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _fieldError = error.fieldError('code') ?? error.fieldError('new_password');
      });
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  void _backToIdentifier() {
    setState(() {
      _onCodeStep = false;
      _challenge = null;
      _code.clear();
      _error = null;
      _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: _busy
              ? null
              : () {
                  if (_onCodeStep) {
                    _backToIdentifier();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              _onCodeStep ? 'Create a new password' : 'Reset your password',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _onCodeStep
                  ? 'Enter the code we sent and choose a new password.'
                  : 'Enter the email or phone number on your account.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_notice != null) ...[
              _NoticeCard(message: _notice!),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Back to sign in'),
              ),
            ] else if (_onCodeStep)
              ..._buildCodeStep(theme)
            else
              ..._buildIdentifierStep(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIdentifierStep() {
    return [
      Form(
        key: _identifierKey,
        child: TextFormField(
          controller: _identifier,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          onFieldSubmitted: (_) => _requestCode(),
          decoration: InputDecoration(
            labelText: 'Phone number or email',
            hintText: 'you@business.com',
            prefixIcon: const Icon(Icons.alternate_email),
            errorText: _fieldError,
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return 'Enter your email or phone number.';
            final email = text.contains('@');
            final phone = RegExp(r'^\+?[0-9\s-]{7,}$').hasMatch(text);
            if (!email && !phone) {
              return 'Enter a valid email address or phone number.';
            }
            return null;
          },
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      FilledButton(
        onPressed: _busy ? null : _requestCode,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : const Text('Send reset code'),
      ),
      const SizedBox(height: AppSpacing.md),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Back to sign in'),
      ),
    ];
  }

  List<Widget> _buildCodeStep(ThemeData theme) {
    final challenge = _challenge!;
    return [
      Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'We sent a 6-digit code to ${challenge.destination}.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      if (challenge.devCode != null) ...[
        _DevCodeNotice(code: challenge.devCode!),
        const SizedBox(height: AppSpacing.lg),
      ],
      Form(
        key: _passwordKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OtpCodeInput(
              length: 6,
              hasError: _fieldError != null && _code.text.isEmpty,
              onCompleted: (_) {},
              onChanged: (value) {
                setState(() {
                  _code.text = value;
                  _fieldError = null;
                });
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                errorText: _fieldError,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                ),
              ),
              validator: (value) => (value ?? '').length < 8
                  ? 'Password must be at least 8 characters.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
              ),
              validator: (value) =>
                  value != _password.text ? 'The two passwords do not match.' : null,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      FilledButton(
        onPressed: _busy || _code.text.length != 6 ? null : _submit,
        child: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : const Text('Reset password'),
      ),
      const SizedBox(height: AppSpacing.md),
      TextButton(
        onPressed: _busy ? null : _backToIdentifier,
        child: const Text('Use a different account'),
      ),
    ];
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DevCodeNotice extends StatelessWidget {
  const _DevCodeNotice({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_mode, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Development mode — your code is $code',
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
