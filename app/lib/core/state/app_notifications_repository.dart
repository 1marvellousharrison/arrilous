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

  void updateToken(String? token) {
    _token = token;
  }

  Future<void> load() async {
    if (_token == null) return;
    try {
      final data = await _api.get('/notifications', token: _token) as Map<String, dynamic>;
      notifications = (data['notifications'] as List<dynamic>? ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      unreadCount = data['unreadCount'] as int? ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    if (_token == null) return;
    try {
      await _api.patch('/notifications//read', token: _token);
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
}

class AppNotification {
  AppNotification({required this.id, required this.type, required this.title, required this.message, required this.severity, this.orderImportId, this.transactionId, this.readAt, required this.createdAt});

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      severity: json['severity'] as String? ?? 'info',
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
  final String? orderImportId;
  final String? transactionId;
  final String? readAt;
  final String createdAt;
  bool get isUnread => readAt == null;
}
