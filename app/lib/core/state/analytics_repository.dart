import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'auth_repository.dart';

/// The owner's business analysis, fetched as one shaped report.
///
/// The server owns every aggregate so the app never sums a paginated list and
/// calls it a total. The window is the owner's own week, month or quarter.
class AnalyticsRepository extends ChangeNotifier {
  AnalyticsRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  AnalyticsOverview? overview;
  int days = 30;
  bool loading = false;
  bool loaded = false;
  String? error;

  Future<void> load({int? days}) async {
    if (days != null) this.days = days;
    loading = true;
    error = null;
    notifyListeners();

    final offset = DateTime.now().timeZoneOffset.inMinutes;
    final query = Uri(queryParameters: {
      'days': '${this.days}',
      'tz_offset_minutes': '$offset',
    }).query;

    try {
      final data = await _api.get('/analytics/overview?$query', token: _token);
      overview = AnalyticsOverview.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      error = e.message;
    } on NetworkException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      loaded = true;
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
    overview = null;
    days = 30;
    loading = false;
    loaded = false;
    error = null;
    notifyListeners();
  }
}

class AnalyticsOverview {
  const AnalyticsOverview({
    required this.days,
    required this.totals,
    required this.previous,
    required this.daily,
    required this.weekdays,
    required this.peakHour,
    required this.topProducts,
    required this.paymentMix,
    required this.orderMix,
    required this.deliveryMix,
    required this.customers,
    required this.inventory,
    required this.logistics,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    final range = _map(json['range']);
    final peak = _map(json['peakHour']);
    return AnalyticsOverview(
      days: _int(range['days']),
      totals: AnalyticsTotals.fromJson(_map(json['totals'])),
      previous: AnalyticsTotals.fromJson(_map(json['previous'])),
      daily: _maps(json['daily']).map(AnalyticsDay.fromJson).toList(),
      weekdays: _maps(json['weekdays']).map(AnalyticsWeekday.fromJson).toList(),
      peakHour: AnalyticsHour(
        hour: _int(peak['hour']),
        revenueKobo: _int(peak['revenueKobo']),
        orders: _int(peak['orders']),
      ),
      topProducts:
          _maps(json['topProducts']).map(AnalyticsProduct.fromJson).toList(),
      paymentMix: _maps(json['paymentMix']).map(AnalyticsSlice.fromJson).toList(),
      orderMix: _maps(json['orderMix']).map(AnalyticsSlice.fromJson).toList(),
      deliveryMix:
          _maps(json['deliveryMix']).map(AnalyticsSlice.fromJson).toList(),
      customers:
          AnalyticsCustomers.fromJson(_map(json['customers'])),
      inventory:
          AnalyticsInventory.fromJson(_map(json['inventory'])),
      logistics:
          AnalyticsLogistics.fromJson(_map(json['logistics'])),
    );
  }

  final int days;
  final AnalyticsTotals totals;
  final AnalyticsTotals previous;
  final List<AnalyticsDay> daily;
  final List<AnalyticsWeekday> weekdays;
  final AnalyticsHour peakHour;
  final List<AnalyticsProduct> topProducts;
  final List<AnalyticsSlice> paymentMix;
  final List<AnalyticsSlice> orderMix;
  final List<AnalyticsSlice> deliveryMix;
  final AnalyticsCustomers customers;
  final AnalyticsInventory inventory;
  final AnalyticsLogistics logistics;

  bool get hasSales => totals.orders > 0;
}

class AnalyticsTotals {
  const AnalyticsTotals({
    required this.revenueKobo,
    required this.orders,
    required this.averageOrderKobo,
    required this.collectedKobo,
    required this.outstandingKobo,
  });

  factory AnalyticsTotals.fromJson(Map<String, dynamic> json) => AnalyticsTotals(
        revenueKobo: _int(json['revenueKobo']),
        orders: _int(json['orders']),
        averageOrderKobo: _int(json['averageOrderKobo']),
        collectedKobo: _int(json['collectedKobo']),
        outstandingKobo: _int(json['outstandingKobo']),
      );

  final int revenueKobo;
  final int orders;
  final int averageOrderKobo;
  final int collectedKobo;
  final int outstandingKobo;
}

class AnalyticsDay {
  const AnalyticsDay({
    required this.date,
    required this.revenueKobo,
    required this.orders,
  });

  factory AnalyticsDay.fromJson(Map<String, dynamic> json) => AnalyticsDay(
        date: json['date'] as String? ?? '',
        revenueKobo: _int(json['revenueKobo']),
        orders: _int(json['orders']),
      );

  final String date;
  final int revenueKobo;
  final int orders;
}

class AnalyticsWeekday {
  const AnalyticsWeekday({
    required this.weekday,
    required this.label,
    required this.revenueKobo,
    required this.orders,
  });

  factory AnalyticsWeekday.fromJson(Map<String, dynamic> json) =>
      AnalyticsWeekday(
        weekday: _int(json['weekday']),
        label: json['label'] as String? ?? '',
        revenueKobo: _int(json['revenueKobo']),
        orders: _int(json['orders']),
      );

  final int weekday;
  final String label;
  final int revenueKobo;
  final int orders;
}

class AnalyticsHour {
  const AnalyticsHour({
    required this.hour,
    required this.revenueKobo,
    required this.orders,
  });

  final int hour;
  final int revenueKobo;
  final int orders;
}

class AnalyticsProduct {
  const AnalyticsProduct({
    required this.name,
    required this.quantity,
    required this.revenueKobo,
  });

  factory AnalyticsProduct.fromJson(Map<String, dynamic> json) =>
      AnalyticsProduct(
        name: json['name'] as String? ?? '',
        quantity: _int(json['quantity']),
        revenueKobo: _int(json['revenueKobo']),
      );

  final String name;
  final int quantity;
  final int revenueKobo;
}

class AnalyticsSlice {
  const AnalyticsSlice({
    required this.status,
    required this.count,
    required this.amountKobo,
  });

  factory AnalyticsSlice.fromJson(Map<String, dynamic> json) => AnalyticsSlice(
        status: json['status'] as String? ?? '',
        count: _int(json['count']),
        amountKobo: _int(json['amountKobo']),
      );

  final String status;
  final int count;
  final int amountKobo;

  String get label {
    switch (status) {
      case 'payment_pending':
        return 'Payment pending';
      case 'not_required':
        return 'No delivery';
      case 'picked_up':
        return 'Picked up';
      case 'in_transit':
        return 'In transit';
      default:
        return status.isEmpty
            ? 'Unknown'
            : '${status[0].toUpperCase()}${status.substring(1)}';
    }
  }
}

class AnalyticsCustomers {
  const AnalyticsCustomers({
    required this.buyers,
    required this.newCustomers,
    required this.returning,
    required this.walkInOrders,
    required this.top,
  });

  factory AnalyticsCustomers.fromJson(Map<String, dynamic> json) =>
      AnalyticsCustomers(
        buyers: _int(json['buyers']),
        newCustomers: _int(json['newCustomers']),
        returning: _int(json['returning']),
        walkInOrders: _int(json['walkInOrders']),
        top: _maps(json['top']).map(AnalyticsCustomer.fromJson).toList(),
      );

  final int buyers;
  final int newCustomers;
  final int returning;
  final int walkInOrders;
  final List<AnalyticsCustomer> top;
}

class AnalyticsCustomer {
  const AnalyticsCustomer({
    required this.name,
    required this.orders,
    required this.spentKobo,
  });

  factory AnalyticsCustomer.fromJson(Map<String, dynamic> json) =>
      AnalyticsCustomer(
        name: json['name'] as String? ?? '',
        orders: _int(json['orders']),
        spentKobo: _int(json['spentKobo']),
      );

  final String name;
  final int orders;
  final int spentKobo;
}

class AnalyticsInventory {
  const AnalyticsInventory({
    required this.activeProducts,
    required this.inventoryValueKobo,
    required this.lowStock,
    required this.outOfStock,
    required this.products,
  });

  factory AnalyticsInventory.fromJson(Map<String, dynamic> json) =>
      AnalyticsInventory(
        activeProducts: _int(json['activeProducts']),
        inventoryValueKobo: _int(json['inventoryValueKobo']),
        lowStock: _int(json['lowStock']),
        outOfStock: _int(json['outOfStock']),
        products: _maps(json['products'])
            .map(AnalyticsStockProduct.fromJson)
            .toList(),
      );

  final int activeProducts;
  final int inventoryValueKobo;
  final int lowStock;
  final int outOfStock;
  final List<AnalyticsStockProduct> products;
}

class AnalyticsStockProduct {
  const AnalyticsStockProduct({
    required this.name,
    required this.stockQuantity,
    required this.severity,
  });

  factory AnalyticsStockProduct.fromJson(Map<String, dynamic> json) =>
      AnalyticsStockProduct(
        name: json['name'] as String? ?? '',
        stockQuantity: _int(json['stockQuantity']),
        severity: json['severity'] as String? ?? 'warning',
      );

  final String name;
  final int stockQuantity;
  final String severity;

  bool get isOutOfStock => stockQuantity <= 0;
}

class AnalyticsLogistics {
  const AnalyticsLogistics({
    required this.requests,
    required this.delivered,
    required this.failed,
    required this.successRate,
  });

  factory AnalyticsLogistics.fromJson(Map<String, dynamic> json) =>
      AnalyticsLogistics(
        requests: _int(json['requests']),
        delivered: _int(json['delivered']),
        failed: _int(json['failed']),
        successRate:
            json['successRate'] is num ? (json['successRate'] as num).round() : null,
      );

  final int requests;
  final int delivered;
  final int failed;
  final int? successRate;
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map<String, dynamic>>().toList(growable: false)
    : const [];

int _int(dynamic value) {
  if (value is num) return value.round();
  return int.tryParse('${value ?? ''}') ?? 0;
}
