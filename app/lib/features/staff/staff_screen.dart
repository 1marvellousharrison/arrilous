import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/state/staff_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../widgets/common.dart';
import '../../widgets/phone_field.dart';
import 'staff_detail_screen.dart';

/// Owner-side staff management (docs/staff-accounts.md).
///
/// The owner adds a staff member, which issues a permanent code; the staff then
/// activates it and signs in. The owner never sees, sets or resets a password.
class StaffScreen extends StatefulWidget {
  const StaffScreen({required this.staff, super.key});

  final StaffRepository staff;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.staff.loaded) widget.staff.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addStaff(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add staff'),
      ),
      body: ListenableBuilder(
        listenable: widget.staff,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final staff = widget.staff;

    if (staff.loading && !staff.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (staff.error != null && staff.staff.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          ErrorBanner(message: staff.error!, onRetry: staff.load),
        ],
      );
    }
    if (staff.staff.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        title: 'No staff yet',
        message: 'Add a staff member and hand them their code to sign in.',
        action: FilledButton.icon(
          onPressed: () => _addStaff(context),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add staff'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: staff.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          96,
        ),
        itemCount: staff.staff.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final member = staff.staff[index];
          return _StaffTile(
            member: member,
            onTap: () => _openDetail(context, member),
          );
        },
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, StaffMember member) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StaffDetailScreen(staff: widget.staff, member: member),
      ),
    );
  }

  Future<void> _addStaff(BuildContext context) async {
    final created = await showDialog<StaffMember>(
      context: context,
      builder: (_) => _AddStaffDialog(staff: widget.staff),
    );
    if (created == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _StaffCodeDialog(member: created),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.member, required this.onTap});

  final StaffMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = member.fullName.trim().isEmpty ? 'Staff member' : member.fullName;

    return Opacity(
      opacity: member.isDisabled ? 0.55 : 1,
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              child: Text(
                _initials(name),
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        member.staffCode,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Flexible(
                        child: Text(
                          member.salesCount == 1
                              ? '1 sale'
                              : '${member.salesCount} sales',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusPill(label: member.statusLabel, color: _statusColor(member)),
          ],
        ),
      ),
    );
  }
}

/// The add form. On success it pops with the created member so the caller can
/// show the issued code.
class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog({required this.staff});

  final StaffRepository staff;

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  bool _submitting = false;
  String? _formError;
  String? _nameError;
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _nameError = null;
      _phoneError = null;
    });

    try {
      final phone = _phone.text.trim();
      final created = await widget.staff.create(
        fullName: _name.text.trim(),
        phone: phone.isEmpty ? null : toNigerianE164(phone),
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _nameError = error.fieldError('full_name');
        _phoneError = error.fieldError('phone');
        _formError = (_nameError == null && _phoneError == null) ? error.message : null;
      });
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We\'ll give them a code to sign in with. They set their own password.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_formError != null) ...[
                ErrorBanner(message: _formError!),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  errorText: _nameError,
                ),
                validator: (value) => (value == null || value.trim().length < 2)
                    ? 'Enter their name.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              NigerianPhoneField(
                controller: _phone,
                label: 'Phone (optional)',
                required: false,
                errorText: _phoneError,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

/// Shows the freshly issued code, with a copy button, so the owner can hand it
/// over exactly as the staff must type it.
class _StaffCodeDialog extends StatelessWidget {
  const _StaffCodeDialog({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = member.fullName.trim().isEmpty ? 'Staff member' : member.fullName;

    return AlertDialog(
      title: const Text('Staff code issued'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Give this code to $name. They activate it from the login screen, '
            'then sign in with it and a password they choose.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              children: [
                Text(
                  member.staffCode,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Permanent — they keep it for every sign-in.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: member.staffCode));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code copied.')),
            );
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

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
