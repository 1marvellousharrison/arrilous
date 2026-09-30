import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/state/auth_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';

/// Phone/email code confirmation. The code is generated and validated by the
/// API; no SMS provider is wired up yet, so development builds display the
/// `dev_code` the server echoes back.
class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({
    required this.auth,
    required this.challenge,
    required this.onSignedIn,
    required this.onBack,
    super.key,
  });

  final AuthRepository auth;
  final OtpChallenge challenge;
  final ValueChanged<AuthUser> onSignedIn;
  final VoidCallback onBack;

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  String _code = '';
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    if (_code.length != 6 || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await widget.auth.verifyOtp(
        challengeId: widget.challenge.challengeId,
        code: _code,
      );
      if (!mounted) return;
      widget.onSignedIn(session.user);
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
    final channel = widget.challenge.channel == 'sms'
        ? 'SMS'
        : 'email';

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: _busy ? null : widget.onBack)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Icon(
                    channel == 'sms'
                        ? Icons.sms_outlined
                        : Icons.mark_email_read_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'We sent a 6-digit code to '
                      '${widget.challenge.destination} by $channel.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Verify your number',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enter the code to continue.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            OtpCodeInput(
              length: 6,
              hasError: _error != null,
              onChanged: (value) => setState(() => _code = value),
              onCompleted: (_) => _verify(),
            ),
            if (widget.challenge.devCode != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _DevCodeNotice(code: widget.challenge.devCode!),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy || _code.length != 6 ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Verify'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: _busy ? null : widget.onBack,
              child: const Text('Use a different account'),
            ),
          ],
        ),
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
              style: const TextStyle(fontSize: 13, color: AppColors.warning),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            color: AppColors.warning,
            tooltip: 'Copy code',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}
