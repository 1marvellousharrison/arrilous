import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/app_notifications_repository.dart';
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

/// The shelf as the dashboard sees it: every active product at or below the
/// low-stock line, emptiest first.
class LowStockSummary {
  const LowStockSummary({
    required this.count,
    required this.outOfStock,
    required this.products,
  });

  factory LowStockSummary.fromJson(Map<String, dynamic> json) => LowStockSummary(
        count: (json['count'] as num?)?.toInt() ?? 0,
        outOfStock: (json['outOfStock'] as num?)?.toInt() ?? 0,
        products: (json['products'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LowStockProduct.fromJson)
            .toList(growable: false),
      );

  static const empty = LowStockSummary(count: 0, outOfStock: 0, products: []);

  final int count;
  final int outOfStock;
  final List<LowStockProduct> products;

  bool get hasIssues => count > 0;

  /// The line the owner reads first, e.g. "3 products need restocking".
  String get headline => count == 1
      ? '1 product needs restocking'
      : '$count products need restocking';

  String get productNames =>
      products.map((product) => product.name).where((name) => name.isNotEmpty).join(', ');
}

/// The signed-in staff member, as the dashboard needs them: who they are and
/// the permanent code the owner handed over.
class StaffSnapshot {
  const StaffSnapshot({
    required this.id,
    required this.fullName,
    required this.staffCode,
    required this.status,
    required this.salesCount,
    this.phone,
    this.activatedAt,
  });

  factory StaffSnapshot.fromJson(Map<String, dynamic> json) => StaffSnapshot(
        id: json['id'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        phone: json['phone'] as String?,
        staffCode: json['staffCode'] as String? ?? '',
        status: json['status'] as String? ?? '',
        activatedAt: json['activatedAt'] as String?,
        salesCount: (json['salesCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String fullName;
  final String? phone;
  final String staffCode;
  final String status;
  final String? activatedAt;
  final int salesCount;

  bool get isActive => status == 'active';
}

/// The money for one date range on the staff dashboard.
class SalesPeriodTotals {
  const SalesPeriodTotals({
    required this.transactionCount,
    required this.grossSalesKobo,
    required this.collectedKobo,
    required this.outstandingKobo,
  });

  factory SalesPeriodTotals.fromJson(Map<String, dynamic> json) => SalesPeriodTotals(
        transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
        grossSalesKobo: (json['grossSalesKobo'] as num?)?.toInt() ?? 0,
        collectedKobo: (json['collectedKobo'] as num?)?.toInt() ?? 0,
        outstandingKobo: (json['outstandingKobo'] as num?)?.toInt() ?? 0,
      );

  static const empty = SalesPeriodTotals(
    transactionCount: 0,
    grossSalesKobo: 0,
    collectedKobo: 0,
    outstandingKobo: 0,
  );

  final int transactionCount;
  final int grossSalesKobo;
  final int collectedKobo;
  final int outstandingKobo;
}

/// Today / last seven days / this month / all time, computed server-side in the
/// staff member's own timezone.
class SalesPeriods {
  const SalesPeriods({
    required this.today,
    required this.week,
    required this.month,
    required this.allTime,
  });

  factory SalesPeriods.fromJson(Map<String, dynamic> json) {
    SalesPeriodTotals read(String key) {
      final value = json[key];
      return value is Map<String, dynamic>
          ? SalesPeriodTotals.fromJson(value)
          : SalesPeriodTotals.empty;
    }

    return SalesPeriods(
      today: read('today'),
      week: read('week'),
      month: read('month'),
      allTime: read('allTime'),
    );
  }

  final SalesPeriodTotals today;
  final SalesPeriodTotals week;
  final SalesPeriodTotals month;
  final SalesPeriodTotals allTime;
}

/// One product a staff member sells most often.
class ProductLeader {
  const ProductLeader({
    required this.name,
    required this.quantity,
    required this.revenueKobo,
  });

  factory ProductLeader.fromJson(Map<String, dynamic> json) => ProductLeader(
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        revenueKobo: (json['revenueKobo'] as num?)?.toInt() ?? 0,
      );

  final String name;
  final int quantity;
  final int revenueKobo;
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
    this.lowStock = LowStockSummary.empty,
    this.staff,
    this.periods,
    this.topProducts = const [],
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final totals = (json['totals'] as Map<String, dynamic>?) ?? const {};
    final counts = (json['counts'] as Map<String, dynamic>?) ?? const {};
    final catalog = (json['catalog'] as Map<String, dynamic>?) ?? const {};
    final recent = (json['recent'] as List?) ?? const [];
    final staff = json['staff'];
    final periods = json['periods'];
    final topProducts = (json['topProducts'] as List?) ?? const [];

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
      lowStock: json['lowStock'] is Map<String, dynamic>
          ? LowStockSummary.fromJson(json['lowStock'] as Map<String, dynamic>)
          : LowStockSummary.empty,
      recent: recent
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList(growable: false),
      staff: staff is Map<String, dynamic> ? StaffSnapshot.fromJson(staff) : null,
      periods: periods is Map<String, dynamic> ? SalesPeriods.fromJson(periods) : null,
      topProducts: topProducts
          .whereType<Map<String, dynamic>>()
          .map(ProductLeader.fromJson)
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

  /// The shelf warning the owner and staff see on the first screen.
  final LowStockSummary lowStock;

  final List<Transaction> recent;

  /// Staff-only. Absent on the owner's summary, which is how the app tells the
  /// two dashboards apart without trusting the client role.
  final StaffSnapshot? staff;

  /// Today / last 7 days / this month for the home dashboard. The owner's
  /// windows cover the whole business; a staff member's cover their own sales.
  final SalesPeriods? periods;
  final List<ProductLeader> topProducts;

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
      // The server buckets "today" in the staff member's own day; send the
      // offset so a sale at 00:30 in Lagos is not filed under yesterday (UTC).
      final offset = DateTime.now().timeZoneOffset.inMinutes;
      final data = await _api.get(
        '/dashboard/summary?tz_offset_minutes=$offset',
        token: _token,
      );
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