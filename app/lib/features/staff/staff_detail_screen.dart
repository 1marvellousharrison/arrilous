import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/staff_repository.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/copy_feedback.dart';
import '../../core/utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/status.dart';

/// One staff member: their code, status, and the sales they have recorded.
///
/// The owner can disable or re-enable them here. Disabling ends any live
/// session on the server as well as blocking the next sign-in.
class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({
    required this.staff,
    required this.member,
    super.key,
  });

  final StaffRepository staff;
  final StaffMember member;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  late StaffMember _member = widget.member;
  List<Transaction> _sales = const [];
  List<StaffActivity> _activity = const [];
  bool _loading = true;
  bool _toggling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.staff.detail(_member.id),
        widget.staff.sales(_member.id),
        widget.staff.activity(_member.id),
      ]);
      if (!mounted) return;
      setState(() {
        _member = results[0] as StaffMember;
        _sales = results[1] as List<Transaction>;
        _activity = results[2] as List<StaffActivity>;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStatus() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _toggling = true);
    try {
      final updated = await widget.staff.setStatus(
        _member.id,
        _member.isDisabled ? 'active' : 'disabled',
      );
      if (!mounted) return;
      setState(() => _member = updated);
      final message = updated.isDisabled
          ? '${updated.fullName} is now disabled.'
          : updated.isInvited
              ? '${updated.fullName}\'s code can be activated again.'
              : '${updated.fullName} can sign in again.';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _copyCode() async {
    await copyWithFeedback(
      context,
      _member.staffCode,
      successMessage: 'Code copied.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _member.fullName.trim().isEmpty ? 'Staff member' : _member.fullName;

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    _initials(name),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StatusPill(
                        label: _member.statusLabel,
                        color: _statusColor(_member),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff code',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _member.staffCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      // The code stays copyable after activation, so the owner
                      // can hand it over again without remembering it.
                      TextButton.icon(
                        onPressed: _copyCode,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'They sign in with this code and their own password.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Sales recorded',
                    value: '${_member.salesCount}',
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _StatCard(
                    label: _member.isInvited ? 'Not activated' : 'Activated',
                    value: _member.activatedAt == null
                        ? '—'
                        : _shortDate(_member.activatedAt!),
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _toggling ? null : _toggleStatus,
              icon: Icon(
                _member.isDisabled ? Icons.play_circle_outline : Icons.block,
                size: 18,
              ),
              label: Text(
                _member.isDisabled
                    ? (_member.activatedAt == null ? 'Restore code' : 'Enable staff')
                    : 'Disable staff',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    _member.isDisabled ? AppColors.success : AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Staff activity',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loading)
              const SizedBox.shrink()
            else if (_activity.isEmpty)
              Text(
                'No activity recorded yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            else
              for (final event in _activity.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          event.isError
                              ? Icons.error_outline
                              : event.isWarning
                                  ? Icons.warning_amber_outlined
                                  : event.type == 'sale_recorded'
                                      ? Icons.point_of_sale_outlined
                                      : event.type == 'restock'
                                          ? Icons.inventory_2_outlined
                                          : Icons.notifications_outlined,
                          size: 18,
                          color: event.isError
                              ? AppColors.danger
                              : event.isWarning
                                  ? AppColors.warning
                                  : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(event.message, style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        if (event.createdAt != null)
                          Text(
                            _shortDate(event.createdAt!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Sales by $name',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ))
            else if (_error != null)
              ErrorBanner(message: _error!, onRetry: _load)
            else if (_sales.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No sales yet',
                message: 'Sales this staff member records will appear here.',
              )
            else
              for (final transaction in _sales)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    transaction.customerName ?? 'Walk-in customer',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${transaction.transactionNumber} • '
                                    '${_shortDate(transaction.createdAt)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatKobo(transaction.totalKobo),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        StatusRow(transaction: transaction, compact: true),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

String _shortDate(DateTime value) => '${value.day}/${value.month}/${value.year}';

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

Color _statusColor(StaffMember member) => switch (member.status) {
      'active' => AppColors.success,
      'invited' => AppColors.warning,
      'disabled' => AppColors.lightTextMuted,
      _ => AppColors.lightTextMuted,
    };
