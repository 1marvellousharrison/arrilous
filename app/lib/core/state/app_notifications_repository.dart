import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

class AppNotificationsRepository extends ChangeNotifier {
  AppNotificationsRepository({required ApiClient api, required String? token})
      : _api = api,
        _token = token;

  final ApiClient _api;
  String? _token;

  List<AppNotification> notifications = const [];
  int unreadCount = 0;

  /// The server's breakdown of the inbox. `lowStock` is counted from the shelf
  /// itself rather than from unread rows, so the warning survives the owner
  /// clearing the bell: it only goes away when the product is restocked.
  int lowStockCount = 0;
  int outOfStockCount = 0;
  int errorCount = 0;
  int warningCount = 0;
  List<LowStockProduct> lowStockProducts = const [];

  void updateToken(String? token) {
    _token = token;
  }

  bool get hasLowStock => lowStockCount > 0;
  bool get hasErrors => errorCount > 0;

  Future<void> load() async {
    if (_token == null) return;
    try {
      final data = await _api.get('/notifications', token: _token) as Map<String, dynamic>;
      notifications = (data['notifications'] as List<dynamic>? ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      unreadCount = (data['unreadCount'] as num?)?.toInt() ?? 0;

      final counts = (data['counts'] as Map<String, dynamic>?) ?? const {};
      lowStockCount = (counts['lowStock'] as num?)?.toInt() ?? 0;
      outOfStockCount = (counts['outOfStock'] as num?)?.toInt() ?? 0;
      errorCount = (counts['errors'] as num?)?.toInt() ?? 0;
      warningCount = (counts['warnings'] as num?)?.toInt() ?? 0;

      final lowStock = (data['lowStock'] as Map<String, dynamic>?) ?? const {};
      lowStockProducts = (lowStock['products'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LowStockProduct.fromJson)
          .toList(growable: false);

      notifyListeners();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    if (_token == null) return;
    try {
      await _api.patch('/notifications/$id/read', token: _token);
      await load();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    if (_token == null) return;
    try {
      await _api.post('/notifications/read-all', token: _token);
      await load();
    } catch (_) {}
  }

  void reset() {
    notifications = const [];
    unreadCount = 0;
    lowStockCount = 0;
    outOfStockCount = 0;
    errorCount = 0;
    warningCount = 0;
    lowStockProducts = const [];
    notifyListeners();
  }
}

class AppNotification {
  AppNotification({required this.id, required this.type, required this.title, required this.message, required this.severity, this.productId, this.orderImportId, this.transactionId, this.readAt, required this.createdAt});

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      severity: json['severity'] as String? ?? 'info',
      productId: json['productId'] as String?,
      orderImportId: json['orderImportId'] as String?,
      transactionId: json['transactionId'] as String?,
      readAt: json['readAt'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  final String id;
  final String type;
  final String title;
  final String message;
  final String severity;
  final String? productId;
  final String? orderImportId;
  final String? transactionId;
  final String? readAt;
  final String createdAt;
  bool get isUnread => readAt == null;
  bool get isError => severity == 'error';
  bool get isWarning => severity == 'warning';
  bool get isLowStock => type == 'low_stock';
}

/// One product the server has flagged. The dashboard and the notification
/// screen share this shape so both can name the same products.
class LowStockProduct {
  const LowStockProduct({
    required this.id,
    required this.name,
    required this.stockQuantity,
    required this.severity,
  });

  factory LowStockProduct.fromJson(Map<String, dynamic> json) => LowStockProduct(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
        severity: json['severity'] as String? ?? 'warning',
      );

  final String id;
  final String name;
  final int stockQuantity;
  final String severity;

  bool get isOutOfStock => stockQuantity <= 0;
}
