import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

class AiRepository extends ChangeNotifier {
  AiRepository({required ApiClient api, required String? token})
      : _api = api,
        _token = token;

  final ApiClient _api;
  String? _token;

  List<AiMessage> messages = const [];
  List<OrderImport> imports = const [];

  void updateToken(String? token) {
    _token = token;
  }

  Future<void> loadChat() async {
    if (_token == null) return;
    try {
      final data = await _api.get('/ai/chat', token: _token) as Map<String, dynamic>;
      messages = (data['messages'] as List<dynamic>? ?? const [])
          .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadImports() async {
    if (_token == null) return;
    try {
      final data = await _api.get('/ai/imports', token: _token) as Map<String, dynamic>;
      imports = (data['imports'] as List<dynamic>? ?? const [])
          .map((e) => OrderImport.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> importImage({String? imageDataUrl, String? imageUrl, String source = 'screenshot'}) async {
    if (_token == null) return null;
    final data = await _api.post(
      '/ai/import',
      token: _token,
      body: {
        if (imageDataUrl != null) 'imageDataUrl': imageDataUrl,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'source': source,
      },
    ) as Map<String, dynamic>;
    await loadChat();
    await loadImports();
    return data;
  }

  Future<Map<String, dynamic>> completeImport(String importId, Map<String, dynamic> body) async {
    final data = await _api.post('/ai/imports/$importId/complete', token: _token, body: body) as Map<String, dynamic>;
    await loadImports();
    await loadChat();
    return data;
  }
}

class AiMessage {
  AiMessage({required this.id, required this.role, required this.messageType, required this.content, this.metadata, this.orderImportId, required this.createdAt});

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      messageType: json['messageType'] as String,
      content: json['content'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>?,
      orderImportId: json['orderImportId'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  final String id;
  final String role;
  final String messageType;
  final String content;
  final Map<String, dynamic>? metadata;
  final String? orderImportId;
  final String createdAt;
}

class OrderImport {
  OrderImport({required this.id, required this.status, required this.missingFields, this.customerName, this.customerPhone, required this.items, this.deliveryRequired = false, this.deliveryAddress, this.deliveryFeeKobo, this.discountKobo});

  factory OrderImport.fromJson(Map<String, dynamic> json) {
    return OrderImport(
      id: json['id'] as String,
      status: json['status'] as String,
      missingFields: (json['missingFields'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      customerName: json['customerName'] as String?,
      customerPhone: json['customerPhone'] as String?,
      items: (json['items'] as List<dynamic>? ?? const []).map((e) => e as Map<String, dynamic>).toList(),
      deliveryRequired: json['deliveryRequired'] == true,
      deliveryAddress: json['deliveryAddress'] as String?,
      deliveryFeeKobo: json['deliveryFeeKobo'] as int?,
      discountKobo: json['discountKobo'] as int?,
    );
  }

  final String id;
  final String status;
  final List<String> missingFields;
  final String? customerName;
  final String? customerPhone;
  final List<Map<String, dynamic>> items;
  final bool deliveryRequired;
  final String? deliveryAddress;
  final int? deliveryFeeKobo;
  final int? discountKobo;
}
