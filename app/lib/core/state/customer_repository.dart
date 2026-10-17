import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/auth_repository.dart';

/// A customer record owned by a business.
///
/// This is deliberately NOT an account: it has no password, no role and no
/// session. Phones and emails here are contact details the owner typed.
class Customer {
  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    this.phone,
    this.email,
    this.notes,
    this.transactionCount = 0,
    this.totalSpentKobo = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        businessId: json['businessId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        notes: json['notes'] as String?,
        transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
        totalSpentKobo: (json['totalSpentKobo'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;
  final int transactionCount;
  final int totalSpentKobo;

  /// Up to two letters for the avatar, e.g. "Ada Nwosu" -> "AN".
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// A single past transaction, used on the customer detail screen.
class CustomerTransactionSummary {
  const CustomerTransactionSummary({
    required this.id,
    required this.transactionNumber,
    required this.totalKobo,
    required this.createdAt,
    required this.paymentStatus,
  });

  factory CustomerTransactionSummary.fromJson(Map<String, dynamic> json) =>
      CustomerTransactionSummary(
        id: json['id'] as String,
        transactionNumber: json['transactionNumber'] as String? ?? '',
        totalKobo: (json['totalKobo'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        paymentStatus: json['paymentStatus'] as String? ?? 'unpaid',
      );

  final String id;
  final String transactionNumber;
  final int totalKobo;
  final DateTime createdAt;
  final String paymentStatus;
}

/// Phase 4 customer state.
class CustomerRepository extends ChangeNotifier {
  CustomerRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  List<Customer> _customers = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String _search = '';

  List<Customer> get customers => _customers;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  String get search => _search;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    final query = _search.isEmpty
        ? ''
        : '?${Uri(queryParameters: {'search': _search}).query}';

    try {
      final data = await _api.get('/customers$query', token: _token);
      _customers = _objectList(data, 'customers').map(Customer.fromJson).toList();
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

  Future<void> setSearch(String value) async {
    if (_search == value) return;
    _search = value;
    await load();
  }

  /// Loads one customer with their spend summary and recent transactions.
  Future<({Customer customer, List<CustomerTransactionSummary> transactions})>
      detail(String id) async {
    final data = await _api.get('/customers/$id', token: _token) as Map<String, dynamic>;
    final customer = Customer.fromJson(data['customer'] as Map<String, dynamic>);
    final transactions = _objectList(data, 'transactions')
        .map(CustomerTransactionSummary.fromJson)
        .toList();
    return (customer: customer, transactions: transactions);
  }

  Future<Customer> save({
    String? id,
    required String name,
    required String phone,
    String? email,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'phone': _blankToNull(phone),
      'email': _blankToNull(email),
      'notes': _blankToNull(notes),
    };

    final data = id == null
        ? await _api.post('/customers', token: _token, body: body)
        : await _api.patch('/customers/$id', token: _token, body: body);

    await load();
    return Customer.fromJson((data as Map<String, dynamic>)['customer'] as Map<String, dynamic>);
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String get _token {
    final session = _auth.session;
    if (session == null) {
      throw ApiException(401, 'unauthorized', 'You need to sign in to continue.');
    }
    return session.accessToken;
  }

  void reset() {
    _customers = const [];
    _loading = false;
    _loaded = false;
    _error = null;
    _search = '';
    notifyListeners();
  }
}

/// Reads the object entries of a list field, ignoring anything that is not a JSON
/// object so a malformed response cannot throw inside a build.
List<Map<String, dynamic>> _objectList(dynamic data, String key) {
  if (data is! Map<String, dynamic>) return const [];
  final raw = data[key];
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().toList(growable: false);
}
