import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/data/nigeria.dart';
import '../../core/state/logistics_repository.dart';
import '../../core/state/wallet_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/phone.dart';
import '../../core/utils/text.dart';
import '../../widgets/common.dart';
import '../../widgets/nigeria_fields.dart';
import '../../widgets/phone_field.dart';
import '../wallet/wallet_screen.dart';
import 'delivery_request_detail_screen.dart';
import 'delivery_requests_list_screen.dart';

/// When `hour:minute` next arrives relative to `now`: today while it is still
/// ahead of the clock, the same time tomorrow once it has passed.
///
/// A closing time must always be in the future — the server refuses an expired
/// one and the whole working day (and the night beyond it) has to be reachable,
/// not just the hours left today.
DateTime nextWorkUntil(DateTime now, int hour, [int minute = 0]) {
  final today = DateTime(now.year, now.month, now.day);
  final candidate = DateTime(today.year, today.month, today.day, hour, minute);
  return candidate.isAfter(now) ? candidate : candidate.add(const Duration(days: 1));
}

/// Spec 42 and 43 — the two internal dashboards.
///
/// An organization sees fleet, riders, coverage and pricing; a rider sees their
/// own availability, modes and deliveries. Nothing here is a placeholder: every
/// number and row comes from the API payload the repository already loaded.
class LogisticsWorkspaceScreen extends StatefulWidget {
  const LogisticsWorkspaceScreen({
    required this.user,
    required this.logistics,
    this.wallet,
    this.onOpenSettings,
    super.key,
  });

  final AuthUser user;
  final LogisticsRepository logistics;
  final WalletRepository? wallet;
  final VoidCallback? onOpenSettings;

  @override
  State<LogisticsWorkspaceScreen> createState() => _LogisticsWorkspaceScreenState();
}

class _LogisticsWorkspaceScreenState extends State<LogisticsWorkspaceScreen> {
  bool get _isRider => widget.user.role == 'rider';

  /// Spec 6 — the dashboard is split into four pages so nothing fights for
  /// space: Home is the dashboard (earnings, counts and new work), Active holds
  /// the availability controls, History carries the earnings ledger and Setup
  /// the fleet, riders, coverage and pricing.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.logistics.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.logistics,
      builder: (context, _) {
        final repository = widget.logistics;
        final profile = _isRider ? repository.rider : repository.organization;
        return Scaffold(
          appBar: AppBar(
            title: Text(_isRider ? 'Rider workspace' : 'Logistics workspace'),
            actions: [
              // Before the profile exists there is nothing to refresh, no status
              // to show and no wallet to open, so setup shows only settings.
              if (profile != null) ...[
                IconButton(tooltip: 'Refresh', onPressed: repository.load, icon: const Icon(Icons.refresh)),
                _statusIndicator(profile),
                if (widget.wallet != null)
                  IconButton(
                    tooltip: 'Wallet',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => WalletScreen(wallet: widget.wallet!)),
                    ),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                  ),
              ],
              if (widget.onOpenSettings != null)
                Padding(
                  // Keep the settings button off the screen edge.
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: IconButton(tooltip: 'Settings', onPressed: widget.onOpenSettings, icon: const Icon(Icons.settings_outlined)),
                ),
            ],
          ),
          body: profile == null
              ? _setup(repository)
              : switch (_tab) {
                  0 => _homeTab(repository),
                  1 => _activeTab(repository),
                  2 => _historyTab(repository),
                  _ => _setupTab(repository),
                },
          bottomNavigationBar: profile == null
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (index) => setState(() => _tab = index),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                    NavigationDestination(icon: Icon(Icons.radar_outlined), selectedIcon: Icon(Icons.radar), label: 'Active'),
                    NavigationDestination(icon: Icon(Icons.history), label: 'History'),
                    NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Setup'),
                  ],
                ),
        );
      },
    );
  }

  /// Spec 4/19 — a provider or rider cannot be matched at all without a
  /// location, so setup asks for one instead of creating an unfindable account.
  Widget _setup(LogisticsRepository repository) {
    // The setup form is its own stateful widget so its text, the picked
    // categories and the chosen state and town survive the dashboard around it
    // rebuilding whenever the repository notifies.
    return _LogisticsSetupForm(
      repository: repository,
      isRider: _isRider,
      defaultName: widget.user.fullName,
    );
  }

  Widget _scroll(LogisticsRepository repository, List<Widget> children) {
    return RefreshIndicator(
      onRefresh: repository.load,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (repository.error != null) ErrorBanner(message: repository.error!, onRetry: repository.load),
          ...children,
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  /// Home page — a dashboard that mirrors the business home: the money the
  /// deliveries have earned, the state counts and the work that needs attention
  /// right now. The availability card lives on the Active tab only.
  Widget _homeTab(LogisticsRepository repository) {
    final requests = repository.requests;
    final incoming = requests
        .where((request) => const {'requested', 'quoted'}.contains(request['status'] as String? ?? ''))
        .toList();
    final active = requests
        .where((request) => const {'accepted', 'assigned', 'picked_up', 'in_transit'}.contains(request['status'] as String? ?? ''))
        .toList();

    return _scroll(repository, [
      _earningsBlock(repository, requests),
      const SizedBox(height: AppSpacing.xl),
      _sectionLabel('Summary'),
      const SizedBox(height: AppSpacing.sm),
      _summaryGrid(_isRider
          ? [
              ('New', _countStatuses(requests, const {'requested', 'quoted'}), AppColors.warning,
                  () => _openList('New delivery requests', const {'requested', 'quoted'})),
              ('Assigned', _countStatuses(requests, const {'accepted', 'assigned', 'picked_up'}), AppColors.info,
                  () => _openList('Assigned deliveries', const {'accepted', 'assigned', 'picked_up'})),
              ('In transit', _countStatuses(requests, const {'in_transit'}), AppColors.info,
                  () => _openList('In transit', const {'in_transit'})),
              ('Completed', _countStatuses(requests, const {'delivered'}), AppColors.success,
                  () => _openList('Completed deliveries', const {'delivered'})),
            ]
          : [
              ('New', _countStatuses(requests, const {'requested', 'quoted'}), AppColors.warning,
                  () => _openList('New delivery requests', const {'requested', 'quoted'})),
              ('Active', _countStatuses(requests, const {'accepted', 'assigned', 'picked_up', 'in_transit'}), AppColors.info,
                  () => _openList('Active deliveries', const {'accepted', 'assigned', 'picked_up', 'in_transit'})),
              ('Completed', _countStatuses(requests, const {'delivered'}), AppColors.success,
                  () => _openList('Completed deliveries', const {'delivered'})),
              ('Failed', _countStatuses(requests, const {'failed'}), AppColors.danger,
                  () => _openList('Failed deliveries', const {'failed', 'declined'})),
            ]),
      const SizedBox(height: AppSpacing.xl),
      _sectionHeader(
        'New requests',
        action: incoming.isEmpty
            ? null
            : TextButton(
                onPressed: () => _openList('New delivery requests', const {'requested', 'quoted'}),
                child: const Text('See all'),
              ),
      ),
      const SizedBox(height: AppSpacing.xs),
      if (incoming.isEmpty)
        const EmptyState(
          icon: Icons.mark_chat_unread_outlined,
          title: 'No new requests',
          message: 'A delivery offered to you lands here so you can accept or decline it.',
        ),
      for (final request in incoming) _requestCard(repository, request, assignable: !_isRider),
      const SizedBox(height: AppSpacing.xl),
      _sectionLabel('Active delivery'),
      const SizedBox(height: AppSpacing.sm),
      if (active.isEmpty)
        const EmptyState(icon: Icons.inbox_outlined, title: 'No active delivery', message: 'An accepted assignment will show its pickup and destination here.'),
      for (final request in active) _requestCard(repository, request),
    ]);
  }

  /// The dashboard headline — the same ledger the History tab shows, led with
  /// the kobo total and backed by how many deliveries produced it. Mirrors the
  /// business home's money block so both account types open the same way.
  Widget _earningsBlock(LogisticsRepository repository, List<Map<String, dynamic>> requests) {
    final theme = Theme.of(context);
    final earnings = _isRider ? repository.riderEarnings : repository.organizationEarnings;
    final total = (earnings?['earningsKobo'] as num?)?.toInt() ?? 0;
    final completed = (earnings?['history'] as List<dynamic>? ?? const []).length;
    final activeJobs = _countStatuses(requests, const {'accepted', 'assigned', 'picked_up', 'in_transit'});
    final newJobs = _countStatuses(requests, const {'requested', 'quoted'});

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total earnings', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: AppSpacing.xs),
          Text(formatKobo(total), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
          const SizedBox(height: AppSpacing.xs),
          Text('across $completed completed ${completed == 1 ? 'delivery' : 'deliveries'}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Active jobs', value: '$activeJobs', color: AppColors.info)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _MiniStat(label: 'New offers', value: '$newJobs', color: AppColors.warning)),
            ],
          ),
        ],
      ),
    );
  }

  /// Active page — the status that answers "am I on duty right now?", the
  /// availability controls and the overtime extension for a shift that runs
  /// over its scheduled closing time.
  Widget _activeTab(LogisticsRepository repository) {
    final active = repository.requests
        .where((request) => const {'accepted', 'assigned', 'picked_up', 'in_transit'}.contains(request['status'] as String? ?? ''))
        .toList();

    return _scroll(repository, [
      _header(repository),
      const SizedBox(height: AppSpacing.xl),
      _sectionLabel('Availability extension'),
      const SizedBox(height: AppSpacing.sm),
      Text(
        _isRider
            ? 'Add or remove working time before your availability closes automatically, so a long delivery never gets cut off mid-route.'
            : 'Add or remove working time around your scheduled closing time, so the business never sees you suddenly go offline.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
      const SizedBox(height: AppSpacing.md),
      _extensionCard(repository),
      const SizedBox(height: AppSpacing.xl),
      _sectionLabel('On the road'),
      const SizedBox(height: AppSpacing.sm),
      if (active.isEmpty)
        const EmptyState(icon: Icons.inbox_outlined, title: 'No active delivery', message: 'Deliveries you are carrying appear here with their next step.'),
      for (final request in active) _requestCard(repository, request),
    ]);
  }

  /// History page — the ledger, exactly like the business dashboard: how much
  /// has been earned (kobo formatted as naira) and the deliveries behind it.
  Widget _historyTab(LogisticsRepository repository) {
    final earnings = _isRider ? repository.riderEarnings : repository.organizationEarnings;
    final total = (earnings?['earningsKobo'] as num?)?.toInt() ?? 0;
    final entries = (earnings?['history'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>().toList();

    return _scroll(repository, [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Total earnings', style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Text(formatKobo(total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.success)),
            const SizedBox(height: AppSpacing.xs),
            Text('Milestone payments are recorded here as deliveries complete.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      _sectionHeader('History'),
      const SizedBox(height: AppSpacing.xs),
      if (entries.isEmpty)
        const EmptyState(
          icon: Icons.history,
          title: 'No history yet',
          message: 'Every completed delivery and the money it earned is kept here.',
        ),
      for (final entry in entries) AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(entry['transactionNumber'] as String? ?? 'Delivery', style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(formatKobo((entry['amountKobo'] as num?)?.toInt() ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
            ]),
            const SizedBox(height: AppSpacing.xs),
            Text(capitalizeName(entry['businessName'] as String? ?? 'Business')),
            if ((entry['riderName'] as String? ?? '').isNotEmpty)
              Text('Rider: ${entry['riderName']}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            if ((entry['completedAt'] as String? ?? '').isNotEmpty)
              Text(_dateLabel(DateTime.parse(entry['completedAt'] as String)), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      _sectionLabel('Past deliveries'),
      const SizedBox(height: AppSpacing.sm),
      if (repository.requests.isEmpty)
        const EmptyState(icon: Icons.inbox_outlined, title: 'Nothing completed yet', message: 'Deliveries you finished or that came back are kept here.'),
      for (final request in _finished(repository)) _requestCard(repository, request),
    ]);
  }

  List<Map<String, dynamic>> _finished(LogisticsRepository repository) => repository.requests
      .where((request) =>
          const {'delivered', 'failed', 'declined', 'cancelled'}.contains(request['status'] as String? ?? ''))
      .toList();

  /// Setup page — fleet, riders, coverage and pricing for an organization;
  /// delivery modes and service areas for a rider. The workload, moved out of
  /// the home page so the dashboard stops being one long scroll.
  Widget _setupTab(LogisticsRepository repository) {
    if (_isRider) {
      final details = repository.riderDetails ?? const {};
      final modes = (details['modes'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
      final areas = (details['serviceAreas'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
      return _scroll(repository, [
        _sectionHeader('Delivery modes', action: TextButton.icon(onPressed: repository.loading ? null : () => _addMode(repository), icon: const Icon(Icons.add, size: 18), label: const Text('Add mode'))),
        const SizedBox(height: AppSpacing.xs),
        _modesCard(modes),
        const SizedBox(height: AppSpacing.xl),
        _sectionHeader('Service areas', action: TextButton.icon(onPressed: repository.loading ? null : () => _addServiceArea(repository), icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('Add area'))),
        const SizedBox(height: AppSpacing.xs),
        _areasCard(areas),
      ]);
    }

    final details = repository.organizationDetails ?? const {};
    final vehicles = (details['vehicles'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final areas = (details['serviceAreas'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final pricing = (details['pricing'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final roster = repository.myRiders;
    return _scroll(repository, [
      _sectionHeader('Fleet', action: TextButton.icon(onPressed: repository.loading ? null : () => _addVehicle(repository), icon: const Icon(Icons.add, size: 18), label: const Text('Add vehicle'))),
      const SizedBox(height: AppSpacing.xs),
      _fleetCard(vehicles),
      const SizedBox(height: AppSpacing.xl),
      _sectionHeader('Riders'),
      const SizedBox(height: AppSpacing.sm),
      _rosterCard(roster),
      const SizedBox(height: AppSpacing.xl),
      _sectionHeader(
        'Service areas & pricing',
        action: Wrap(spacing: AppSpacing.xs, children: [
          TextButton.icon(onPressed: repository.loading ? null : () => _addServiceArea(repository), icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('Area')),
          TextButton.icon(onPressed: repository.loading ? null : () => _addPrice(repository), icon: const Icon(Icons.add, size: 18), label: const Text('Price')),
        ]),
      ),
      const SizedBox(height: AppSpacing.xs),
      _coverageCard(areas, pricing),
    ]);
  }

  /// Spec 42 header / spec 43 header — identity, the availability switch and
  /// the automatic closing time the business promised.
  Widget _header(LogisticsRepository repository) {
    final theme = Theme.of(context);
    final profile = (_isRider ? repository.rider : repository.organization) ?? const {};
    final available = profile['isAvailable'] as bool? ?? false;
    final expiresAt = DateTime.tryParse(profile['availabilityExpiresAt'] as String? ?? '')?.toLocal();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_isRider ? Icons.pedal_bike : Icons.local_shipping, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isRider ? widget.user.fullName : (profile['name'] as String? ?? ''), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(available ? 'Active — accepting new requests' : 'Inactive — not accepting new requests',
                        style: theme.textTheme.bodySmall?.copyWith(color: available ? AppColors.success : AppColors.danger)),
                  ],
                ),
              ),
              Switch(value: available, onChanged: repository.loading ? null : (value) => _confirmAvailability(repository, value)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _detailRow('Automatic closing', _closingLabel(expiresAt, available)),
          if (available && expiresAt != null) _detailRow('Availability left', _countdown(expiresAt)),
        ],
      ),
    );
  }

  /// Spec 16 and 17 — going active (or inactive) is a decision, not a flick of
  /// the switch. The switch asks first; only an explicit "yes" reaches the API,
  /// and cancelling leaves the profile exactly as it was. Going active also asks
  /// the exact time of day the provider wants to work until.
  Future<void> _confirmAvailability(LogisticsRepository repository, bool next) async {
    DateTime? closesAt;
    if (next) {
      final chosen = await _askForCloseTime(
        title: 'Go active?',
        confirmLabel: 'Yes, go active',
      );
      if (chosen == null || !mounted) return;
      closesAt = chosen;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Go inactive?'),
          content: const Text(
            'You will be hidden from new matching straight away. Deliveries you already accepted are not affected.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, go inactive'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await repository.setAvailability(next, closesAt: closesAt);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _closingLabel(DateTime? expiresAt, bool available) {
    if (!available) return 'Not scheduled';
    if (expiresAt == null) return 'No automatic closing set';
    return '${_dateLabel(expiresAt)} at ${TimeOfDay.fromDateTime(expiresAt).format(context)}';
  }

  String _dateLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(value.year, value.month, value.day);
    if (that == today) return 'Today';
    if (that == today.add(const Duration(days: 1))) return 'Tomorrow';
    return '${value.day}/${value.month}/${value.year}';
  }

  String _countdown(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) return '$hours h $minutes min';
    return '$minutes min';
  }

  /// The on-duty lightning beside the settings button. Standby keeps a muted
  /// look; the moment the provider is live the lightning turns green and back
  /// again when the shift closes or the provider hops off.
  Widget _statusIndicator(Map<String, dynamic>? profile) {
    final available = profile?['isAvailable'] as bool? ?? false;
    return _AvailabilityIndicator(available: available);
  }

  Widget _sectionLabel(String text) => Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));

  /// Spec 28 — the count links to the list behind it, and a row links to the
  /// full breakdown of that delivery.
  void _openList(String title, Set<String> statuses) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryRequestsListScreen(
          title: title,
          statuses: statuses,
          logistics: widget.logistics,
          role: widget.user.role,
        ),
      ),
    );
  }

  void _openDetail(String requestId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryRequestDetailScreen(
          logistics: widget.logistics,
          requestId: requestId,
          role: widget.user.role,
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, {Widget? action}) => Row(
        children: [
          Expanded(child: _sectionLabel(text)),
          ?action,
        ],
      );

  int _countStatuses(List<Map<String, dynamic>> requests, Set<String> statuses) =>
      requests.where((request) => statuses.contains(request['status'] as String? ?? '')).length;

  Widget _summaryGrid(List<(String, int, Color, VoidCallback?)> entries) => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 2.2,
        children: [
          for (final (label, value, color, onTap) in entries)
            AppCard(
              onTap: onTap,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
                  Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
        ],
      );

  /// Spec 42 fleet — totals, availability, price and capacity per vehicle type.
  Widget _fleetCard(List<Map<String, dynamic>> vehicles) {
    if (vehicles.isEmpty) {
      return const EmptyState(icon: Icons.directions_car_outlined, title: 'No fleet yet', message: 'Add vehicles so businesses can match you to a delivery.');
    }
    final total = vehicles.fold<int>(0, (sum, vehicle) => sum + ((vehicle['totalQuantity'] as num?)?.toInt() ?? 0));
    final available = vehicles.fold<int>(0, (sum, vehicle) => sum + ((vehicle['availableQuantity'] as num?)?.toInt() ?? 0));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('$available of $total available', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (available == 0) const StatusPill(label: 'Fully booked', color: AppColors.warning),
          ]),
          const SizedBox(height: AppSpacing.sm),
          for (final vehicle in vehicles) ...[
            const Divider(height: AppSpacing.md),
            Row(children: [
              const Icon(Icons.directions_car_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('${vehicle['vehicleType'] ?? vehicle['vehicle_type'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${vehicle['availableQuantity'] ?? 0}/${vehicle['totalQuantity'] ?? 0}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            Text(
              '${vehicle['capacityCategory'] ?? vehicle['capacity_category'] ?? ''} • from ${formatKobo((vehicle['startingPriceKobo'] ?? vehicle['starting_price_kobo'] as num?) as num?)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ],
      ),
    );
  }

  /// Spec 42 riders — active vs inactive, with the jobs each one is carrying.
  Widget _rosterCard(List<Map<String, dynamic>> roster) {
    if (roster.isEmpty) {
      return const EmptyState(icon: Icons.people_outline, title: 'No riders yet', message: 'Attach rider accounts so they can pick up assignments.');
    }
    final active = roster.where((rider) => rider['isAvailable'] as bool? ?? false).length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$active active • ${roster.length - active} inactive', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          for (final rider in roster) ...[
            const Divider(height: AppSpacing.md),
            Row(children: [
              Icon(Icons.two_wheeler_outlined, size: 18, color: (rider['isAvailable'] as bool? ?? false) ? AppColors.success : AppColors.danger),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(rider['fullName'] as String? ?? 'Rider', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${rider['activeJobs'] ?? 0} jobs', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ],
        ],
      ),
    );
  }

  /// Spec 42 service areas and pricing — destinations with their published fee.
  Widget _coverageCard(List<Map<String, dynamic>> areas, List<Map<String, dynamic>> pricing) {
    if (areas.isEmpty) {
      return const EmptyState(icon: Icons.public, title: 'No service areas yet', message: 'Publish the destinations you cover so businesses can match you.');
    }
    final feesByDestination = <String, num>{};
    for (final row in pricing) {
      final destination = (row['destination'] as String?) ?? '';
      final price = (row['priceKobo'] ?? row['price_kobo'] as num?) as num?;
      if (destination.isEmpty || price == null) continue;
      feesByDestination[destination] = price;
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final area in areas) ...[
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(_areaLabel(area), style: const TextStyle(fontWeight: FontWeight.w700))),
              if (feesByDestination.containsKey(area['city']))
                Text(formatKobo(feesByDestination[area['city']]), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800))
              else
                Text('No fee published', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning)),
            ]),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  String _areaLabel(Map<String, dynamic> area) {
    final parts = <String>[if ((area['city'] as String? ?? '').isNotEmpty) area['city'] as String];
    if ((area['area'] as String? ?? '').isNotEmpty) parts.add(area['area'] as String);
    if ((area['state'] as String? ?? '').isNotEmpty) parts.add(area['state'] as String);
    return parts.join(', ');
  }

  /// Spec 43 delivery modes — primary mode first, with rate and capacity.
  Widget _modesCard(List<Map<String, dynamic>> modes) {
    if (modes.isEmpty) {
      return const EmptyState(icon: Icons.motorcycle_outlined, title: 'No delivery modes yet', message: 'Add the modes you ride and your rate for each.');
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mode in modes) ...[
            Row(children: [
              Icon(mode['isPrimary'] == true || mode['is_primary'] == true ? Icons.star_outline : Icons.motorcycle_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('${mode['mode'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${mode['capacityCategory'] ?? mode['capacity_category'] ?? ''}', style: Theme.of(context).textTheme.bodySmall),
            ]),
            Text('Rate ${formatKobo((mode['rateKobo'] ?? mode['rate_kobo'] as num?) as num?)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  /// Spec 43 — where a rider works, which is what puts them in front of a
  /// nearby business at all.
  Widget _areasCard(List<Map<String, dynamic>> areas) {
    if (areas.isEmpty) {
      return const EmptyState(icon: Icons.public, title: 'No service areas yet', message: 'Add the towns you cover so nearby businesses can match you.');
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, area) in areas.indexed) ...[
            if (index > 0) const Divider(height: AppSpacing.md),
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(_areaLabel(area), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ],
        ],
      ),
    );
  }

  /// Shared sheet for every "add" flow: fields on top, one action below, and
  /// the server's own message if it refuses.
  Future<void> _openForm({
    required String title,
    required List<Widget> children,
    required Future<String?> Function() onSubmit,
    String submitLabel = 'Save',
  }) async {
    bool busy = false;
    String? message;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
          ),
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpacing.md),
                ...children,
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(message!, style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setSheetState(() => busy = true);
                            final error = await onSubmit();
                            if (error == null) {
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            } else if (sheetContext.mounted) {
                              setSheetState(() {
                                busy = false;
                                message = error;
                              });
                            }
                          },
                    child: Text(submitLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _report(Object error) {
    if (error is ApiException) return error.message;
    if (error is NetworkException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  /// Spec 22 — add a vehicle type with its quantity, capacity and price.
  Future<void> _addVehicle(LogisticsRepository repository) async {
    String type = 'motorcycle';
    String capacity = 'small';
    final total = TextEditingController(text: '1');
    final price = TextEditingController();
    await _openForm(
      title: 'Add vehicle',
      children: [
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                isExpanded: true,
                items: [
                  for (final value in const ['motorcycle', 'tricycle', 'car', 'van', 'pickup', 'truck', 'other'])
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) => setState(() => type = value ?? 'motorcycle'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: capacity,
                decoration: const InputDecoration(labelText: 'Capacity'),
                items: [
                  for (final value in const ['small', 'medium', 'large', 'very_large'])
                    DropdownMenuItem(value: value, child: Text(value.replaceAll('_', ' '))),
                ],
                onChanged: (value) => setState(() => capacity = value ?? 'small'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: total, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'How many')),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Starting price (₦)', hintText: 'e.g. 2500')),
      ],
      onSubmit: () async {
        final quantity = int.tryParse(total.text.trim());
        final kobo = parseNairaToKobo(price.text.trim());
        if (quantity == null || quantity < 1) return 'Enter how many you have.';
        if (kobo == null) return 'Enter a valid starting price.';
        try {
          await repository.addVehicle(
            vehicleType: type,
            totalQuantity: quantity,
            availableQuantity: quantity,
            capacityCategory: capacity,
            startingPriceKobo: kobo,
          );
          return null;
        } catch (error) {
          return _report(error);
        }
      },
    );
  }

  /// Spec 19/20 — coverage and the published destination price.
  Future<void> _addServiceArea(LogisticsRepository repository) async {
    final area = TextEditingController();
    String? state;
    String? city;
    await _openForm(
      title: 'Add service area',
      children: [
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              NigerianStateDropdown(
                value: state,
                onChanged: (value) => setState(() {
                  state = value;
                  if (city != null && !citiesForState(value).contains(city)) {
                    city = null;
                  }
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              NigerianCityDropdown(
                state: state,
                value: city,
                onChanged: (value) => setState(() => city = value),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: area, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Area (optional)', hintText: 'e.g. Allen Avenue')),
            ],
          ),
        ),
      ],
      onSubmit: () async {
        if (city == null || city!.trim().isEmpty) {
          return 'Choose the city or town you cover.';
        }
        try {
          await repository.addServiceArea(
            city: city!.trim(),
            area: area.text.trim(),
            state: state?.trim() ?? '',
          );
          return null;
        } catch (error) {
          return _report(error);
        }
      },
    );
  }

  Future<void> _addPrice(LogisticsRepository repository) async {
    final destination = TextEditingController();
    final price = TextEditingController();
    await _openForm(
      title: 'Publish destination price',
      children: [
        TextField(controller: destination, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Destination city', hintText: 'e.g. Warri')),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price (₦)', hintText: 'e.g. 3500')),
      ],
      onSubmit: () async {
        if (destination.text.trim().isEmpty) return 'Enter the destination city.';
        final kobo = parseNairaToKobo(price.text.trim());
        if (kobo == null) return 'Enter a valid price.';
        try {
          await repository.addPricing(destination: destination.text.trim(), priceKobo: kobo);
          return null;
        } catch (error) {
          return _report(error);
        }
      },
    );
  }

  /// Spec 24 — the modes a rider offers, with the rate businesses see.
  Future<void> _addMode(LogisticsRepository repository) async {
    String mode = 'motorcycle';
    String capacity = 'small';
    bool primary = true;
    final rate = TextEditingController();
    await _openForm(
      title: 'Add delivery mode',
      children: [
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Mode'),
                isExpanded: true,
                items: [
                  for (final value in const ['motorcycle', 'car', 'bicycle', 'other'])
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) => setState(() => mode = value ?? 'motorcycle'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: capacity,
                decoration: const InputDecoration(labelText: 'Capacity'),
                items: [
                  for (final value in const ['small', 'medium', 'large', 'very_large'])
                    DropdownMenuItem(value: value, child: Text(value.replaceAll('_', ' '))),
                ],
                onChanged: (value) => setState(() => capacity = value ?? 'small'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Main mode'),
                value: primary,
                onChanged: (value) => setState(() => primary = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Your rate (₦)', hintText: 'e.g. 1500')),
      ],
      onSubmit: () async {
        final kobo = parseNairaToKobo(rate.text.trim());
        if (kobo == null) return 'Enter a valid rate.';
        try {
          await repository.addMode(mode: mode, capacityCategory: capacity, rateKobo: kobo, isPrimary: primary);
          return null;
        } catch (error) {
          return _report(error);
        }
      },
    );
  }

  /// Spec 17 v2 — today's shift. The card shows the day's planned hours and the
  /// closing time, lets the provider re-plan mid-shift (edit icon), and offers
  /// buttons to lengthen OR trim the shift. Trimming below what is left makes
  /// the server close the shift.
  Widget _extensionCard(LogisticsRepository repository) {
    final profile = _isRider ? repository.rider : repository.organization;
    final available = profile?['isAvailable'] as bool? ?? false;
    final plannedHours = (profile?['plannedHours'] as num?)?.toInt();
    final expiresAt = DateTime.tryParse(profile?['availabilityExpiresAt'] as String? ?? '')?.toLocal();
    final startedAt = DateTime.tryParse(profile?['availabilityStartedAt'] as String? ?? '')?.toLocal();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6));

    String? headline;
    String? startedLabel;
    if (available) {
      headline = expiresAt != null
          ? 'Work until ${TimeOfDay.fromDateTime(expiresAt).format(context)}'
          : (plannedHours != null ? '$plannedHours h shift' : 'On duty');
      final plan = plannedHours != null ? '$plannedHours h shift' : null;
      if (expiresAt != null) {
        final left = expiresAt.difference(DateTime.now());
        if (!left.isNegative) {
          startedLabel = left.inHours > 0
              ? '${left.inHours}h ${left.inMinutes.remainder(60)}min left'
              : '${left.inMinutes}min left';
        }
      }
      if (startedAt != null) {
        final started = 'Started at ${TimeOfDay.fromDateTime(startedAt).format(context)}';
        startedLabel = startedLabel == null ? started : '$startedLabel — $started';
      }
      if (startedLabel != null && plan != null) startedLabel = '$plan — $startedLabel';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.schedule, size: 20, color: available ? AppColors.info : Theme.of(context).colorScheme.outline),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                available ? headline ?? 'On duty' : 'Not on duty',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (available)
              IconButton(
                tooltip: 'Edit today\'s plan',
                visualDensity: VisualDensity.compact,
                onPressed: repository.loading ? null : () => _editPlan(repository),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
          ]),
          if (available && startedLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('$startedLabel — closes automatically.', style: muted),
          ] else if (!available) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Go active before planning or changing your closing time.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning)),
          ],
          if (available) ...[
            const Divider(height: AppSpacing.xl),
            Text('Add time', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(onPressed: repository.loading ? null : () => _adjust(repository, 30), child: const Text('+30 min')),
                OutlinedButton(onPressed: repository.loading ? null : () => _adjust(repository, 60), child: const Text('+1 hour')),
                OutlinedButton(onPressed: repository.loading ? null : () => _adjustCustom(repository, remove: false), child: const Text('Custom')),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Remove time', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(onPressed: repository.loading ? null : () => _adjust(repository, -30), child: const Text('-30 min')),
                OutlinedButton(onPressed: repository.loading ? null : () => _adjust(repository, -60), child: const Text('-1 hour')),
                OutlinedButton(onPressed: repository.loading ? null : () => _adjustCustom(repository, remove: true), child: const Text('Trim more')),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Removing more than the time you have left ends today\'s shift.', style: muted),
          ],
        ],
      ),
    );
  }

  Future<void> _adjust(LogisticsRepository repository, int minutes) async {
    try {
      await repository.adjustAvailability(minutes);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _adjustCustom(LogisticsRepository repository, {required bool remove}) async {
    final controller = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(remove ? 'Remove minutes' : 'Add minutes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Minutes', hintText: remove ? 'e.g. 45' : 'e.g. 45'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: Text(remove ? 'Remove' : 'Add'),
          ),
        ],
      ),
    );
    if (minutes == null || minutes < 1 || !mounted) return;
    await _adjust(repository, remove ? -minutes : minutes);
  }

  Future<void> _editPlan(LogisticsRepository repository) async {
    final profile = _isRider ? repository.rider : repository.organization;
    final current = DateTime.tryParse(profile?['availabilityExpiresAt'] as String? ?? '')?.toLocal();
    final chosen = await _askForCloseTime(
      title: 'Work until',
      confirmLabel: 'Update plan',
      current: current,
    );
    if (chosen == null || !mounted) return;
    try {
      await repository.setAvailability(true, closesAt: chosen);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// The work-until chooser used when going active and when re-planning
  /// mid-shift. Presets cover the whole clock, and any choice that is already
  /// behind "now" rolls to the same time tomorrow, so a provider can always go
  /// active — late at night included — and the closing time the server receives
  /// is always in the future.
  Future<DateTime?> _askForCloseTime({
    required String title,
    required String confirmLabel,
    DateTime? current,
  }) {
    final now = DateTime.now();
    final presets = List<int>.generate(24, (hour) => hour);

    late DateTime closing;
    if (current != null && current.isAfter(now)) {
      closing = current;
    } else {
      closing = nextWorkUntil(now, now.hour == 23 ? 0 : now.hour + 1);
    }
    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final past = !closing.isAfter(now);
          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title == 'Go active?'
                        ? 'You will be visible to businesses looking for delivery capacity until you stop, later today.'
                        : 'Your closing time follows the exact hour you pick. Change it and the shift moves to that time.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Work until', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                  for (final hour in presets)
                    Builder(
                      builder: (chipContext) {
                        final candidate = nextWorkUntil(now, hour);
                        return ChoiceChip(
                          label: Text(TimeOfDay(hour: hour, minute: 0).format(chipContext)),
                          selected: closing.isAtSameMomentAs(candidate),
                          onSelected: (_) => setState(() => closing = candidate),
                        );
                      },
                    ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay(hour: closing.hour, minute: closing.minute),
                      );
                      if (picked == null) return;
                      // An hour already gone today reads as tomorrow, exactly as
                      // the presets do, so the choice is never refused.
                      setState(() => closing = nextWorkUntil(now, picked.hour, picked.minute));
                    },
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Pick a different time…'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    past ? 'Please pick a time still ahead today.' : _centerLabel(closing),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: past ? AppColors.danger : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(null), child: const Text('Cancel')),
              FilledButton(
                onPressed: past ? null : () => Navigator.of(dialogContext).pop(closing),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    );
  }

  String _centerLabel(DateTime value) => 'Closes ${_closingLabel(value, true)}.';

  Widget _requestCard(LogisticsRepository repository, Map<String, dynamic> request, {bool assignable = false}) {
    final status = request['status'] as String? ?? 'requested';
    final incoming = status == 'requested' || status == 'quoted';
    final next = switch (status) {
      'requested' || 'quoted' => 'accepted',
      'accepted' || 'assigned' => 'picked_up',
      'picked_up' => 'in_transit',
      'in_transit' => 'delivered',
      _ => null,
    };
    final color = switch (status) {
      'failed' => AppColors.danger,
      'delivered' => AppColors.success,
      'declined' || 'cancelled' => AppColors.danger,
      _ => AppColors.info,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        onTap: () => _openDetail(request['id'] as String),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(request['transactionNumber'] as String? ?? 'Delivery request', style: const TextStyle(fontWeight: FontWeight.w800))),
            const Icon(Icons.chevron_right, size: 18),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text('${request['pickupCity'] ?? 'Pickup'} to ${request['destinationCity'] ?? 'Destination'}'),
          if ((request['riderName'] as String? ?? '').isNotEmpty) Text('Rider: ${request['riderName']}'),
          if (request['acceptedPriceKobo'] != null) Text('Accepted ${formatKobo((request['acceptedPriceKobo'] as num?)?.toInt())}'),
          if (request['failureReason'] != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${request['failureReason']}', style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: AppSpacing.sm),
          StatusPill(label: status.replaceAll('_', ' '), color: color),
          if (incoming) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: FilledButton(
                  onPressed: repository.loading ? null : () => repository.updateRequest(request['id'] as String, 'accepted'),
                  child: const Text('Accept delivery'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: repository.loading ? null : () => repository.updateRequest(request['id'] as String, 'declined'),
                  child: const Text('Decline'),
                ),
              ),
            ]),
          ] else if (next != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: repository.loading ? null : () => repository.updateRequest(request['id'] as String, next),
              child: Text(_nextLabel(next)),
            ),
          ],
          if (assignable && status == 'requested') ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: repository.loading ? null : () => _assign(repository, request),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Assign rider & vehicle'),
            ),
          ],
        ]),
      ),
    );
  }

  String _nextLabel(String next) => switch (next) {
        'accepted' => 'Accept delivery',
        'picked_up' => 'Mark picked up',
        'in_transit' => 'Start transit',
        'delivered' => 'Mark delivered',
        _ => next.replaceAll('_', ' '),
      };

  Future<void> _assign(LogisticsRepository repository, Map<String, dynamic> request) async {
    final roster = repository.myRiders.where((rider) => rider['isAvailable'] as bool? ?? false).toList();
    if (roster.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No available rider to assign.')));
      return;
    }
    final rider = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose a rider')),
            for (final entry in roster)
              ListTile(
                leading: const Icon(Icons.two_wheeler_outlined),
                title: Text(entry['fullName'] as String? ?? 'Rider'),
                subtitle: Text('${entry['activeJobs'] ?? 0} active jobs'),
                onTap: () => Navigator.pop(context, entry),
              ),
          ],
        ),
      ),
    );
    if (rider == null || !mounted) return;
    try {
      await repository.assign(request['id'] as String, riderId: rider['id'] as String?);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rider assigned.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Widget _detailRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)))),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// One of the two headline figures under the dashboard's money block.
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }
}

/// The app-bar availability indicator. It is a plain lightning bolt; tapping it
/// unrolls a pill to the left with the status word in the matching colour, so a
/// provider can read their own state at a glance. The pill holds for a few
/// seconds, then rolls back up and the neighbouring app-bar icons slide back to
/// where they were.
class _AvailabilityIndicator extends StatefulWidget {
  const _AvailabilityIndicator({required this.available});

  final bool available;

  @override
  State<_AvailabilityIndicator> createState() => _AvailabilityIndicatorState();
}

class _AvailabilityIndicatorState extends State<_AvailabilityIndicator> with SingleTickerProviderStateMixin {
  static const _hold = Duration(seconds: 3);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Tap reveals the word, tap again (or the hold expiring) rolls it back.
  void _reveal() {
    _holdTimer?.cancel();
    if (_controller.value == 1) {
      _controller.reverse();
      return;
    }
    _controller.forward();
    _holdTimer = Timer(_hold, () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.available ? AppColors.success : Theme.of(context).colorScheme.outline;
    final label = widget.available ? 'Active' : 'Not active';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _reveal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Icon(Icons.bolt, size: 18, color: color),
            ),
            ClipRect(
              child: SizeTransition(
                key: const ValueKey('status-pill-expand'),
                axis: Axis.horizontal,
                alignment: Alignment.centerLeft,
                sizeFactor: _curve,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0.4, 0), end: Offset.zero).animate(_curve),
                  child: FadeTransition(
                    opacity: _curve,
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11, height: 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spec 4/19 — a provider or rider cannot be matched at all without a phone,
/// a category and a location, so this is the one-time profile form shown before
/// the dashboard. It is a stateful widget so the typed details, the categories
/// picked and the chosen state and town are not lost when the dashboard around
/// it rebuilds.
class _LogisticsSetupForm extends StatefulWidget {
  const _LogisticsSetupForm({
    required this.repository,
    required this.isRider,
    required this.defaultName,
  });

  final LogisticsRepository repository;
  final bool isRider;
  final String defaultName;

  @override
  State<_LogisticsSetupForm> createState() => _LogisticsSetupFormState();
}

/// The categories a delivery partner or rider can offer. They may pick more
/// than one; the chosen set is joined into the single category string the API
/// stores.
const List<String> _logisticsCategories = [
  'Courier',
  'Bike messenger',
  'Food delivery',
  'Package delivery',
  'Grocery delivery',
  'Pharmacy delivery',
  'Document delivery',
  'E-commerce fulfilment',
  'Freight / haulage',
  'Moving / relocation',
  'Ride hailing',
  'Errand runner',
  'Cold chain',
  'Bulk logistics',
];

class _LogisticsSetupFormState extends State<_LogisticsSetupForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.isRider ? widget.defaultName : '');
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _area = TextEditingController();
  final Set<String> _categories = <String>{};
  String? _state;
  String? _city;

  @override
  void dispose() {
    for (final controller in [_name, _phone, _description, _area]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final missing = <String>[
      if (!widget.isRider && _name.text.trim().isEmpty) 'organization name',
      if (!isValidNigerianPhone(_phone.text)) 'phone number',
      if (_categories.isEmpty) 'category',
      if (_description.text.trim().length < 3) 'what you deliver',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add: ${missing.join(', ')}')),
      );
      return;
    }
    try {
      await widget.repository.createProfile(
        organizationName: widget.isRider ? null : _name.text.trim(),
        phone: toNigerianE164(_phone.text),
        category: _categories.join(', '),
        description: _description.text.trim(),
      );
      if (_city != null && _city!.trim().isNotEmpty) {
        await widget.repository.addServiceArea(
          city: _city!.trim(),
          area: _area.text.trim(),
          state: _state?.trim() ?? '',
          country: 'Nigeria',
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on NetworkException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Icon(
          widget.isRider ? Icons.pedal_bike_outlined : Icons.local_shipping_outlined,
          size: 52,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          widget.isRider ? 'Set up your rider profile' : 'Set up your organization',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          widget.isRider
              ? 'Create your profile, then tell us where you work so nearby businesses can find you.'
              : 'Create your organization, then add where you operate so nearby businesses can match you.',
          textAlign: TextAlign.center,
        ),
        if (!widget.isRider) ...[
          const SizedBox(height: AppSpacing.xl),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Organization name')),
        ],
        const SizedBox(height: AppSpacing.xl),
        NigerianPhoneField(controller: _phone),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Category — pick one or more',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in _logisticsCategories)
              FilterChip(
                label: Text(option),
                selected: _categories.contains(option),
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _categories.add(option);
                  } else {
                    _categories.remove(option);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _description,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'What do you deliver?',
            hintText: 'Tell businesses what you offer',
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        NigerianStateDropdown(
          value: _state,
          onChanged: (value) => setState(() {
            _state = value;
            if (_city != null && !citiesForState(value).contains(_city)) {
              _city = null;
            }
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        NigerianCityDropdown(
          state: _state,
          value: _city,
          onChanged: (value) => setState(() => _city = value),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _area,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Area (optional)', hintText: 'e.g. Allen Avenue'),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: widget.repository.loading ? null : _submit,
          icon: const Icon(Icons.add),
          label: Text(widget.isRider ? 'Create rider profile' : 'Create organization'),
        ),
      ],
    );
  }
}
