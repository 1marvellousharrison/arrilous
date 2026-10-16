import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/business_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// The owner-confirmation gate before an existing business profile is changed.
///
/// It emails a one-time code to the owner and, once the code checks out, pops
/// with the short-lived edit token the editor's writes must carry. First-time
/// setup never passes through here. See docs/business-details-edit-otp.md.
class BusinessEditGate extends StatefulWidget {
  const BusinessEditGate({required this.business, super.key});

  final BusinessRepository business;

  @override
  State<BusinessEditGate> createState() => _BusinessEditGateState();
}

class _BusinessEditGateState extends State<BusinessEditGate> {
  BusinessEditChallenge? _challenge;
  String _code = '';
  bool _sending = false;
  bool _verifying = false;
  String? _error;
  Timer? _cooldownTimer;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
      _code = '';
    });
    try {
      final challenge = await widget.business.requestEditOtp();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _sending = false;
      });
      _startCooldown();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.message;
      });
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.message;
      });
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 45);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final challenge = _challenge;
    if (challenge == null || _code.length != 6 || _verifying) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final token = await widget.business.verifyEditOtp(
        challengeId: challenge.challengeId,
        code: _code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(token);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = error.message;
      });
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = _challenge;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: (_sending || _verifying)
              ? null
              : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              'Confirm it is you',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Changing your business details needs a quick check so nobody '
              'can change your shop from an unlocked phone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_sending && challenge == null)
              const Center(child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ))
            else if (challenge != null)
              ..._codeStep(theme, challenge)
            else
              FilledButton(
                onPressed: _send,
                child: const Text('Send the code'),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _codeStep(ThemeData theme, BusinessEditChallenge challenge) {
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
      OtpCodeInput(
        length: 6,
        hasError: _error != null,
        onChanged: (value) => setState(() => _code = value),
        onCompleted: (_) => _verify(),
      ),
      const SizedBox(height: AppSpacing.xl),
      FilledButton(
        onPressed: (_verifying || _code.length != 6) ? null : _verify,
        child: _verifying
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : const Text('Confirm'),
      ),
      const SizedBox(height: AppSpacing.md),
      Center(
        child: TextButton(
          onPressed: (_sending || _cooldown > 0) ? null : _send,
          child: Text(
            _cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code',
          ),
        ),
      ),
    ];
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
