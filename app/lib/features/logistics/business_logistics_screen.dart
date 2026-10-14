import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/business_repository.dart';
import '../../core/state/logistics_repository.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/text.dart';
import '../../widgets/common.dart';
import 'delivery_request_detail_screen.dart';
import 'delivery_requests_list_screen.dart';
import 'notifications_screen.dart';

/// Business-facing delivery requests and provider matching (spec 14, 15, 44).
///
/// The flow is the eight steps the spec asks for: confirm pickup, confirm
/// destination, find active providers, filter by service area, filter by
/// vehicle/mode, show rates, choose or request a quote, then send the request.
/// Availability, coverage and suitability are decided by the API — this screen
/// only asks for the filters and renders what comes back.
class BusinessLogisticsScreen extends StatefulWidget {
  const BusinessLogisticsScreen({
    required this.business,
    required this.transactions,
    required this.logistics,
    super.key,
  });

  final BusinessRepository business;
  final TransactionRepository transactions;
  final LogisticsRepository logistics;

  @override
  State<BusinessLogisticsScreen> createState() => _BusinessLogisticsScreenState();
}

class _BusinessLogisticsScreenState extends State<BusinessLogisticsScreen> {
  late final TextEditingController _destination = TextEditingController(
    text: widget.business.business?.location?.city ?? '',
  );

  String _packageSize = 'any';
  String _preferredMode = 'any';

  static const Map<String, String> _packageSizes = {
    'any': 'Any size',
    'small': 'Small',
    'medium': 'Medium',
    'large': 'Large',
    'very_large': 'Very large',
  };

  static const Map<String, String> _modes = {
    'any': 'Any mode',
    'motorcycle': 'Motorcycle',
    'tricycle': 'Tricycle',
    'car': 'Car',
    'van': 'Van',
    'pickup': 'Pickup',
    'truck': 'Truck',
  };

  @override
  void initState() {
    super.initState();
    widget.logistics.load();
    widget.transactions.load();
    widget.logistics.loadNotifications();
    // Spec 41 — active nearby providers and riders belong on the dashboard, so
    // the first search runs itself instead of waiting for a tap.
    if (_destination.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  void _search() => widget.logistics.findProviders(
        _destination.text,
        packageSize: _packageSize,
        preferredMode: _preferredMode,
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.logistics, widget.transactions]),
      builder: (context, _) {
        final logistics = widget.logistics;
        final newRequests = logistics.requests
            .where((request) => const {'requested', 'quoted'}.contains(request['status'] as String? ?? ''))
            .length;
        return RefreshIndicator(
          onRefresh: logistics.load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Logistics', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (newRequests > 0)
                    StatusPill(label: '$newRequests new', color: AppColors.warning, icon: Icons.notifications_active_outlined),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('Match active providers for a delivery destination and track every request.'),
              const SizedBox(height: AppSpacing.lg),
              _requestSummary(logistics),
              const SizedBox(height: AppSpacing.lg),
              _filters(),
              if (logistics.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                ErrorBanner(message: logistics.error!, onRetry: logistics.load),
              ],
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(child: Text('Active nearby providers', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  if (logistics.providers.isNotEmpty || logistics.riders.isNotEmpty)
                    Text('${logistics.providers.length} org • ${logistics.riders.length} rider', style: Theme.of(context).textTheme.bodySmall),
                  if (logistics.loading) const Padding(padding: EdgeInsets.only(left: AppSpacing.sm), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!logistics.loading && logistics.providers.isEmpty && logistics.riders.isEmpty)
                const EmptyState(icon: Icons.local_shipping_outlined, title: 'Find providers by destination', message: 'Enter the customer delivery city to see suitable active providers.'),
              for (final provider in logistics.providers) _providerCard(provider),
              for (final rider in logistics.riders) _riderCard(rider),
              const SizedBox(height: AppSpacing.xl),
              Text('Delivery requests', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              if (!logistics.loading && logistics.requests.isEmpty)
                const EmptyState(icon: Icons.inbox_outlined, title: 'No delivery requests yet', message: 'Choose a matched provider to request delivery.'),
              // The tab carries a sample so it stays scannable; the full
              // history lives behind More.
              for (final request in logistics.requests.take(3)) _requestCard(request),
              if (logistics.requests.length > 3) ...[
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: _openAllRequests,
                  child: const Text('More'),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text('Notifications', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              _notifications(logistics),
              if (logistics.notifications.length > 7) ...[
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: _openAllNotifications,
                  child: const Text('More'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Spec 14 — the delivery-request counts the owner's logistics dashboard owes
  /// at a glance: new work, work in progress, finished and failed.
  Widget _requestSummary(LogisticsRepository logistics) {
    final counts = <(String, int, Color)>[
      ('New', _count(logistics, const {'requested', 'quoted'}), AppColors.warning),
      ('Active', _count(logistics, const {'accepted', 'assigned', 'picked_up', 'in_transit'}), AppColors.info),
      ('Completed', _count(logistics, const {'delivered'}), AppColors.success),
      ('Failed', _count(logistics, const {'failed', 'declined'}), AppColors.danger),
    ];
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          for (final (index, entry) in counts.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.$2}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: entry.$3)),
                  Text(entry.$1, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _count(LogisticsRepository logistics, Set<String> statuses) => logistics.requests
      .where((request) => statuses.contains(request['status'] as String? ?? ''))
      .length;

  /// Steps 1–5 of the selection flow: pickup is read from the business profile,
  /// destination, size and mode are the owner's inputs.
  Widget _filters() {
    final pickup = widget.business.business?.location;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.storefront, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('Pickup: ${pickup?.oneLine ?? 'Set your business location first'}', style: Theme.of(context).textTheme.bodySmall)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _destination,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Customer delivery city',
              hintText: 'e.g. Warri',
              suffixIcon: IconButton(
                tooltip: 'Find providers',
                onPressed: logisticsBusy ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _packageSize,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Package size', isDense: true),
                items: [
                  for (final entry in _packageSizes.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _packageSize = value ?? 'any'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _preferredMode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Preferred mode', isDense: true),
                items: [
                  for (final entry in _modes.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() => _preferredMode = value ?? 'any'),
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: logisticsBusy ? null : _search, icon: const Icon(Icons.search), label: const Text('Find providers')),
          ),
        ],
      ),
    );
  }

  bool get logisticsBusy => widget.logistics.loading;

  /// Spec 14 — name, status, distance, service areas, published rates and the
  /// vehicles that are actually free right now.
  Widget _providerCard(Map<String, dynamic> provider) {
    final theme = Theme.of(context);
    final organization = provider['organization'] as Map<String, dynamic>? ?? const {};
    final vehicles = (provider['vehicles'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final pricing = (provider['pricing'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final areas = (provider['serviceAreas'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final distance = provider['distanceKm'] as num?;

    final prices = pricing.map((row) => (row['priceKobo'] ?? row['price_kobo'] as num?) as num?).whereType<num>().toList();
    final vehicleTypes = vehicles
        .map((vehicle) => (vehicle['vehicleType'] ?? vehicle['vehicle_type']) as String? ?? '')
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_shipping_outlined),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(organization['name'] as String? ?? 'Logistics provider', style: const TextStyle(fontWeight: FontWeight.w800))),
            StatusPill(
              label: organization['isAvailable'] as bool? ?? true ? 'Active' : 'Inactive',
              color: organization['isAvailable'] as bool? ?? true ? AppColors.success : AppColors.danger,
            ),
          ]),
          if (organization['isAvailable'] == true && _untilLabel(organization['availabilityExpiresAt'] as String?) != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Available until ${_untilLabel(organization['availabilityExpiresAt'] as String?)}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success)),
          ],
          if (distance != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${distance.toStringAsFixed(1)} km away', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
          if (areas.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Covers: ${areas.map(_areaLabel).join(', ')}', style: theme.textTheme.bodySmall),
          ],
          if (vehicleTypes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Available vehicles: ${vehicleTypes.join(', ')}', style: theme.textTheme.bodySmall),
          ],
          if (vehicles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final vehicle in vehicles)
              Text(
                '${vehicle['vehicleType'] ?? vehicle['vehicle_type'] ?? ''} — from ${formatKobo((vehicle['startingPriceKobo'] ?? vehicle['starting_price_kobo'] as num?) as num?)}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
          ],
          if (prices.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Published rate ${formatKobo(prices.reduce((a, b) => a < b ? a : b))} +',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
            Text('Final fee may vary with the order (spec 45).', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(onPressed: () => _requestFor(organizationId: organization['id'] as String?), icon: const Icon(Icons.send_outlined), label: const Text('Request delivery')),
        ]),
      ),
    );
  }

  /// Spec 14 — the rider card the owner sees when direct selection applies.
  Widget _riderCard(Map<String, dynamic> entry) {
    final theme = Theme.of(context);
    final rider = entry['rider'] as Map<String, dynamic>? ?? const {};
    final areas = (entry['serviceAreas'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final modes = (entry['modes'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final distance = entry['distanceKm'] as num?;
    final rates = modes.map((mode) => (mode['rateKobo'] ?? mode['rate_kobo'] as num?) as num?).whereType<num>().toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.two_wheeler_outlined),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(rider['fullName'] as String? ?? 'Rider', style: const TextStyle(fontWeight: FontWeight.w800))),
            StatusPill(
              label: rider['isAvailable'] as bool? ?? true ? 'Active' : 'Inactive',
              color: rider['isAvailable'] as bool? ?? true ? AppColors.success : AppColors.danger,
            ),
          ]),
          if (rider['isAvailable'] != true)
            Text('Not accepting new requests right now.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger))
          else if (_untilLabel(rider['availabilityExpiresAt'] as String?) != null)
            Text('Available until ${_untilLabel(rider['availabilityExpiresAt'] as String?)}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success)),
          if (distance != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${distance.toStringAsFixed(1)} km away', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
          if (areas.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Covers: ${areas.map(_areaLabel).join(', ')}', style: theme.textTheme.bodySmall),
          ],
          if (modes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('Modes: ${modes.map((mode) => mode['mode']).whereType<String>().join(', ')}', style: theme.textTheme.bodySmall),
          ],
          if (rates.isNotEmpty)
            Text('Published rate from ${formatKobo(rates.reduce((a, b) => a < b ? a : b))}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(onPressed: () => _requestFor(riderId: rider['id'] as String?), icon: const Icon(Icons.send_outlined), label: const Text('Request delivery')),
        ]),
      ),
    );
  }

  /// Spec 14/16 — "Active until 8:00 PM", the closing time the owner needs to
  /// judge whether the match will still be around.
  String? _untilLabel(String? iso) {
    final expiresAt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (expiresAt == null) return null;
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

  String _areaLabel(Map<String, dynamic> area) {
    final parts = <String>[
      if ((area['area'] as String? ?? '').isNotEmpty) area['area'] as String,
      if ((area['city'] as String? ?? '').isNotEmpty) area['city'] as String,
    ];
    return parts.join(', ');
  }

  /// Spec 28 — the request has to carry enough to accept or decline, and spec 27
  /// keeps new work visible rather than behind a bell icon.
  Widget _requestCard(Map<String, dynamic> request) {
    final status = request['status'] as String? ?? 'requested';
    final color = switch (status) {
      'delivered' => AppColors.success,
      'failed' || 'declined' || 'cancelled' => AppColors.danger,
      'requested' || 'quoted' => AppColors.warning,
      _ => AppColors.info,
    };
    final quote = request['acceptedPriceKobo'] ??
        request['quotedPriceKobo'] ??
        request['publishedPriceKobo'];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DeliveryRequestDetailScreen(
              logistics: widget.logistics,
              requestId: request['id'] as String,
              role: 'business',
            ),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(request['transactionNumber'] as String? ?? 'Delivery request', style: const TextStyle(fontWeight: FontWeight.w800))),
            StatusPill(label: status.replaceAll('_', ' '), color: color),
            const Icon(Icons.chevron_right, size: 18),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text('Business: ${capitalizeName(request['businessName'] as String? ?? '—')}'),
          Text('Pickup: ${request['pickupCity'] ?? 'Pickup'}'),
          Text('Destination: ${request['destinationCity'] ?? 'Destination'}'),
          if ((request['packageSize'] as String? ?? '').isNotEmpty) Text('Package: ${request['packageSize']}'),
          if ((request['preferredMode'] as String? ?? '').isNotEmpty) Text('Preferred mode: ${request['preferredMode']}'),
          if (quote != null)
            Text('Fee: ${formatKobo((quote as num?)?.toInt())}', style: const TextStyle(fontWeight: FontWeight.w700))
          else
            const Text('Fee: quote request pending', style: TextStyle(color: AppColors.warning)),
          if ((request['riderName'] as String? ?? '').isNotEmpty) Text('Rider: ${request['riderName']}'),
          if (request['failureReason'] != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${request['failureReason']}', style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
        ]),
      ),
    );
  }

  Widget _notifications(LogisticsRepository logistics) {
    if (logistics.notifications.isEmpty) {
      return const EmptyState(icon: Icons.notifications_none, title: 'No notifications yet', message: 'Delivery request activity will be listed here.');
    }
    return Column(
      children: [
        for (final notification in logistics.notifications.take(7))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              onTap: notification['readAt'] == null
                  ? () => logistics.markNotificationRead(notification['id'] as String)
                  : null,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  notification['readAt'] == null ? Icons.mark_email_unread_outlined : Icons.email_outlined,
                  size: 18,
                  color: notification['readAt'] == null ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(notification['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(notification['body'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  /// The full notification list behind the seven-item sample above.
  void _openAllNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(logistics: widget.logistics),
      ),
    );
  }

  /// The full request history behind the three-card sample above.
  void _openAllRequests() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryRequestsListScreen(
          title: 'Delivery requests',
          statuses: allDeliveryRequestStatuses,
          logistics: widget.logistics,
          role: 'business',
        ),
      ),
    );
  }

  Future<void> _requestFor({String? organizationId, String? riderId}) async {
    final candidates = widget.transactions.transactions
        .where((sale) => sale.deliveryRequired && sale.deliveryStatus == 'pending')
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a delivery-required transaction before requesting a provider.')));
      return;
    }
    final sale = await showModalBottomSheet<Transaction>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(children: [
          const ListTile(title: Text('Choose a transaction')),
          for (final item in candidates)
            ListTile(title: Text(item.transactionNumber), subtitle: Text(item.deliveryAddress ?? 'Delivery address'), onTap: () => Navigator.pop(context, item)),
        ]),
      ),
    );
    if (sale == null || !mounted) return;
    try {
      await widget.logistics.requestDelivery(
        transactionId: sale.id,
        organizationId: organizationId,
        riderId: riderId,
        packageSize: _packageSize == 'any' ? null : _packageSize,
        preferredMode: _preferredMode == 'any' ? null : _preferredMode,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery request sent.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
