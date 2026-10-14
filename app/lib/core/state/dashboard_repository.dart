import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/auth_repository.dart';
import '../state/transaction_repository.dart';

/// Spec 41 — the logistics strip on the business dashboard.
///
/// `nearbyProviders` and `nearbyRiders` cover this business's pickup city, so a
/// number is only ever shown when the business has a location to measure from.
class LogisticsSummary {
  const LogisticsSummary({
    required this.pendingRequests,
    required this.activeDeliveries,
    required this.deliveryFailures,
    required this.nearbyProviders,
    required this.nearbyRiders,
  });

  factory LogisticsSummary.fromJson(Map<String, dynamic> json) => LogisticsSummary(
        pendingRequests: (json['pendingRequests'] as num?)?.toInt() ?? 0,
        activeDeliveries: (json['activeDeliveries'] as num?)?.toInt() ?? 0,
        deliveryFailures: (json['deliveryFailures'] as num?)?.toInt() ?? 0,
        nearbyProviders: (json['nearbyProviders'] as num?)?.toInt() ?? 0,
        nearbyRiders: (json['nearbyRiders'] as num?)?.toInt() ?? 0,
      );

  final int pendingRequests;
  final int activeDeliveries;
  final int deliveryFailures;
  final int nearbyProviders;
  final int nearbyRiders;

  bool get isEmpty =>
      pendingRequests == 0 &&
      activeDeliveries == 0 &&
      deliveryFailures == 0 &&
      nearbyProviders == 0 &&
      nearbyRiders == 0;
}

/// The Phase 12 dashboard figures, straight from the database.
///
/// Every number here is an aggregate the API computed. The dashboard never
/// derives a total by summing a list it happens to have loaded, because a list
/// is paginated and summing a page would quietly under-report.
class DashboardSummary {
  const DashboardSummary({
    required this.transactionCount,
    required this.grossSalesKobo,
    required this.collectedKobo,
    required this.outstandingKobo,
    required this.pendingOrder,
    required this.pendingPayment,
    required this.awaitingDelivery,
    required this.inTransit,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.activeProducts,
    required this.customerCount,
    required this.logistics,
    required this.recent,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final totals = (json['totals'] as Map<String, dynamic>?) ?? const {};
    final counts = (json['counts'] as Map<String, dynamic>?) ?? const {};
    final catalog = (json['catalog'] as Map<String, dynamic>?) ?? const {};
    final recent = (json['recent'] as List?) ?? const [];

    return DashboardSummary(
      transactionCount: (totals['transactionCount'] as num?)?.toInt() ?? 0,
      grossSalesKobo: (totals['grossSalesKobo'] as num?)?.toInt() ?? 0,
      collectedKobo: (totals['collectedKobo'] as num?)?.toInt() ?? 0,
      outstandingKobo: (totals['outstandingKobo'] as num?)?.toInt() ?? 0,
      pendingOrder: (counts['pendingOrder'] as num?)?.toInt() ?? 0,
      pendingPayment: (counts['pendingPayment'] as num?)?.toInt() ?? 0,
      awaitingDelivery: (counts['awaitingDelivery'] as num?)?.toInt() ?? 0,
      inTransit: (counts['inTransit'] as num?)?.toInt() ?? 0,
      completed: (counts['completed'] as num?)?.toInt() ?? 0,
      failed: (counts['failed'] as num?)?.toInt() ?? 0,
      cancelled: (counts['cancelled'] as num?)?.toInt() ?? 0,
      activeProducts: (catalog['activeProducts'] as num?)?.toInt() ?? 0,
      customerCount: (catalog['customers'] as num?)?.toInt() ?? 0,
      logistics: LogisticsSummary.fromJson(
        (json['logistics'] as Map<String, dynamic>?) ?? const {},
      ),
      recent: recent
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList(growable: false),
    );
  }

  final int transactionCount;
  final int grossSalesKobo;
  final int collectedKobo;
  final int outstandingKobo;
  final int pendingOrder;
  final int pendingPayment;
  final int awaitingDelivery;
  final int inTransit;
  final int completed;
  final int failed;
  final int cancelled;

  /// Counts the API aggregates, so the business card is right without waiting on
  /// the paginated product and customer lists.
  final int activeProducts;
  final int customerCount;

  /// Spec 41 — delivery workload and nearby supply, computed by the API against
  /// this business's own pickup city.
  final LogisticsSummary logistics;

  final List<Transaction> recent;

  bool get isEmpty => transactionCount == 0 && cancelled == 0;

  /// True when something needs the owner's attention rather than just existing.
  bool get needsAttention => failed > 0 || outstandingKobo > 0;
}

/// Phase 12 dashboard state.
class DashboardRepository extends ChangeNotifier {
  DashboardRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  DashboardSummary? _summary;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  DashboardSummary? get summary => _summary;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.get('/dashboard/summary', token: _token);
      _summary = DashboardSummary.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (error) {
      _error = error.message;
    } on NetworkException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  String get _token {
    final session = _auth.session;
    if (session == null) {
      throw ApiException(401, 'unauthorized', 'You need to sign in to continue.');
    }
    return session.accessToken;
  }

  void reset() {
    _summary = null;
    _loading = false;
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}