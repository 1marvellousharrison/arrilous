import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/logistics_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/text.dart';
import '../../widgets/common.dart';

/// Spec 28 and 53 — the full breakdown of one delivery.
///
/// Everything needed to run the job without leaving the screen: where it is
/// picked up and who hands it over, where it goes and who receives it, who
/// carries it, what it pays, and how it got here. Names and phone numbers are
/// on the cards because the next step is almost always a phone call.
class DeliveryRequestDetailScreen extends StatefulWidget {
  const DeliveryRequestDetailScreen({
    required this.logistics,
    required this.requestId,
    required this.role,
    super.key,
  });

  final LogisticsRepository logistics;
  final String requestId;
  final String role;

  @override
  State<DeliveryRequestDetailScreen> createState() => _DeliveryRequestDetailScreenState();
}

class _DeliveryRequestDetailScreenState extends State<DeliveryRequestDetailScreen> {
  bool get _canAct => widget.role == 'rider' || widget.role == 'logistics_partner';

  @override
  void initState() {
    super.initState();
    // Next frame, not now: this state's build has not run yet and the
    // repository would otherwise notify listeners in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.logistics.loadRequestDetail(widget.requestId);
    });
  }

  Future<void> _act(String status) async {
    try {
      await widget.logistics.updateRequest(widget.requestId, status);
      await widget.logistics.loadRequestDetail(widget.requestId);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.logistics,
      builder: (context, _) {
        final repository = widget.logistics;
        final detail = repository.requestDetail;
        return Scaffold(
          appBar: AppBar(title: const Text('Delivery request')),
          body: repository.error != null && detail == null
              ? Center(child: ErrorBanner(message: repository.error!, onRetry: () => repository.loadRequestDetail(widget.requestId)))
              : detail == null
                  ? const Center(child: CircularProgressIndicator())
                  : _body(detail),
        );
      },
    );
  }

  Widget _body(Map<String, dynamic> detail) {
    final status = detail['status'] as String? ?? 'requested';
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(children: [
          Expanded(
            child: Text(detail['transactionNumber'] as String? ?? 'Delivery request',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          StatusPill(label: status.replaceAll('_', ' '), color: _statusColor(status)),
        ]),
        const SizedBox(height: AppSpacing.xl),
        _pickupCard(detail),
        const SizedBox(height: AppSpacing.md),
        _dropOffCard(detail),
        const SizedBox(height: AppSpacing.md),
        _carrierCard(detail),
        const SizedBox(height: AppSpacing.md),
        _orderCard(detail),
        const SizedBox(height: AppSpacing.md),
        _timelineCard(detail),
        if (_canAct) ...[
          const SizedBox(height: AppSpacing.xl),
          ..._actions(status),
        ],
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  /// Spec 28 — the pickup side: the business and the person handing over.
  /// Everything here is what the owner typed into business details — the name
  /// to ask for, the contact number to call, and the location down to the
  /// area — because the partner and the rider work from this card alone.
  Widget _pickupCard(Map<String, dynamic> detail) {
    final pickup = detail['pickup'] as Map<String, dynamic>? ?? const {};
    final business = detail['business'] as Map<String, dynamic>? ?? const {};
    String part(String key) => (pickup[key] as String? ?? '').trim();
    return _card(
      icon: Icons.storefront,
      title: 'Pickup — collection point',
      rows: [
        ('Business', capitalizeName(business['name'] as String? ?? detail['businessName'] as String? ?? '—')),
        if ((business['ownerName'] as String? ?? '').isNotEmpty) ('Contact', business['ownerName'] as String),
        if ((business['phone'] as String? ?? '').isNotEmpty) ('Phone', business['phone'] as String),
        if (part('address').isNotEmpty) ('Address', part('address')),
        if (part('area').isNotEmpty) ('Area', part('area')),
        if (part('city').isNotEmpty) ('City', part('city')),
        if (part('state').isNotEmpty) ('State', part('state')),
      ],
    );
  }

  /// Spec 28 — the drop-off side: the customer and their location.
  Widget _dropOffCard(Map<String, dynamic> detail) {
    final destination = detail['destination'] as Map<String, dynamic>? ?? const {};
    final customer = detail['customer'] as Map<String, dynamic>?;
    return _card(
      icon: Icons.location_on_outlined,
      title: 'Drop-off — customer location',
      rows: [
        if (customer != null) ...[
          ('Customer', customer['name'] as String? ?? '—'),
          if ((customer['phone'] as String? ?? '').isNotEmpty) ('Phone', customer['phone'] as String),
          if ((customer['email'] as String? ?? '').isNotEmpty) ('Email', customer['email'] as String),
        ] else
          ('Customer', 'Walk-in customer'),
        ('Address', [destination['address'], destination['city']].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ')),
        if (customer != null && (customer['address'] as String? ?? '').isNotEmpty && customer['address'] != destination['address'])
          ('Customer on file', customer['address'] as String),
      ],
    );
  }

  Widget _carrierCard(Map<String, dynamic> detail) {
    final rider = detail['rider'] as Map<String, dynamic>?;
    final organization = detail['organization'] as Map<String, dynamic>?;
    final rows = <(String, String)>[];
    if (organization != null) rows.add(('Logistics company', organization['name'] as String? ?? '—'));
    if (organization != null && (organization['phone'] as String? ?? '').isNotEmpty) rows.add(('Company phone', organization['phone'] as String));
    if (rider != null) {
      rows.add(('Rider', rider['name'] as String? ?? '—'));
      if ((rider['phone'] as String? ?? '').isNotEmpty) rows.add(('Rider phone', rider['phone'] as String));
    } else {
      rows.add(('Rider', 'Not assigned yet'));
    }
    return _card(icon: Icons.two_wheeler_outlined, title: 'Carried by', rows: rows);
  }

  Widget _orderCard(Map<String, dynamic> detail) {
    final totals = detail['totals'] as Map<String, dynamic>?;
    final rows = <(String, String)>[
      if ((detail['packageDescription'] as String? ?? '').isNotEmpty) ('Package', detail['packageDescription'] as String),
      if ((detail['packageSize'] as String? ?? '').isNotEmpty) ('Size', (detail['packageSize'] as String).replaceAll('_', ' ')),
      if ((detail['preferredMode'] as String? ?? '').isNotEmpty) ('Preferred mode', detail['preferredMode'] as String),
      if (detail['publishedPriceKobo'] != null) ('Published fee', formatKobo(detail['publishedPriceKobo'] as num)),
      if (detail['quotedPriceKobo'] != null) ('Quoted fee', formatKobo(detail['quotedPriceKobo'] as num)),
      if (detail['acceptedPriceKobo'] != null) ('Accepted fee', formatKobo(detail['acceptedPriceKobo'] as num)),
      if (totals != null) ('Order total', formatKobo(totals['totalKobo'] as num?)),
      if ((detail['failureReason'] as String? ?? '').isNotEmpty) ('Failure reason', detail['failureReason'] as String),
    ];
    return _card(icon: Icons.receipt_long_outlined, title: 'Order & payment', rows: rows);
  }

  Widget _timelineCard(Map<String, dynamic> detail) {
    final events = (detail['events'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timeline', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.sm),
          if (events.isEmpty) Text('No events yet.', style: theme.textTheme.bodySmall),
          for (final (index, entry) in events.indexed) ...[
            Row(children: [
              Icon(Icons.circle, size: 8, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(_eventLabel(entry['eventType'] as String? ?? ''), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md + 8),
              child: Text(
                '${entry['actorName'] ?? ''} · ${_timeLabel(entry['createdAt'] as String?)}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
            if (index != events.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(String status) {
    final next = switch (status) {
      'requested' || 'quoted' => [(label: 'Accept delivery', status: 'accepted'), (label: 'Decline', status: 'declined')],
      'accepted' || 'assigned' => [(label: 'Mark picked up', status: 'picked_up')],
      'picked_up' => [(label: 'Start transit', status: 'in_transit')],
      'in_transit' => [(label: 'Mark delivered', status: 'delivered'), (label: 'Report failed', status: 'failed')],
      _ => <({String label, String status})>[],
    };
    if (next.isEmpty) return const [];
    return [
      Row(children: [
        Expanded(
          child: FilledButton(
            onPressed: widget.logistics.loading ? null : () => _act(next.first.status),
            child: Text(next.first.label),
          ),
        ),
        if (next.length > 1) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: OutlinedButton(
              onPressed: widget.logistics.loading ? null : () => _act(next[1].status),
              child: Text(next[1].label),
            ),
          ),
        ],
      ]),
    ];
  }

  Widget _card({required IconData icon, required String title, required List<(String, String)> rows}) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, value) in rows) _row(label, value),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    final isPhone = label.toLowerCase().contains('phone');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)))),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: isPhone && value.isNotEmpty ? TextDecoration.underline : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _eventLabel(String type) => switch (type) {
        'requested' => 'Delivery requested',
        'quoted' => 'Quote sent',
        'quote_accepted' => 'Quote accepted',
        'assigned' => 'Rider assigned',
        'accepted' => 'Accepted',
        'picked_up' => 'Picked up',
        'in_transit' => 'In transit',
        'delivered' => 'Delivered',
        'failed' => 'Delivery failed',
        'declined' => 'Declined',
        'cancelled' => 'Cancelled',
        'otp_confirmed' => 'Customer confirmed with OTP',
        _ => type.replaceAll('_', ' '),
      };

  String _timeLabel(String? iso) {
    final value = DateTime.tryParse(iso ?? '');
    if (value == null) return '';
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hour:$minute';
  }

  Color _statusColor(String status) => switch (status) {
        'delivered' => AppColors.success,
        'failed' || 'declined' || 'cancelled' => AppColors.danger,
        'requested' || 'quoted' => AppColors.warning,
        _ => AppColors.info,
      };
}
