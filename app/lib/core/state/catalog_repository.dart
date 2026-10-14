import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/auth_repository.dart';

/// A catalog product as the API returns it.
class Product {
  const Product({
    required this.id,
    required this.businessId,
    required this.name,
    required this.priceKobo,
    required this.stockQuantity,
    required this.active,
    this.description,
    this.category,
    this.sku,
    this.imageUrl,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        businessId: json['businessId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        // Money is an integer count of kobo; nothing here is ever a double.
        priceKobo: (json['priceKobo'] as num?)?.toInt() ?? 0,
        stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 0,
        active: json['active'] as bool? ?? true,
        description: json['description'] as String?,
        category: json['category'] as String?,
        sku: json['sku'] as String?,
        imageUrl: json['imageUrl'] as String?,
      );

  final String id;
  final String businessId;
  final String name;
  final int priceKobo;
  final int stockQuantity;
  final bool active;
  final String? description;
  final String? category;
  final String? sku;
  final String? imageUrl;

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= 5;
}

/// Phase 3 catalog state: products, category chips and search.
class CatalogRepository extends ChangeNotifier {
  CatalogRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  List<Product> _products = const [];
  List<String> _categories = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  String _search = '';
  String? _category;
  bool _includeArchived = false;

  List<Product> get products => _products;
  List<String> get categories => _categories;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  String get search => _search;
  String? get category => _category;
  bool get includeArchived => _includeArchived;

  List<Product> get activeProducts =>
      _products.where((product) => product.active).toList();

  /// Re-reads the catalog from the server. Search and category are applied by the
  /// API so that paging stays correct as the catalog grows.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    final params = <String, String>{
      if (_search.isNotEmpty) 'search': _search,
      'category': ?_category,
      if (_includeArchived) 'include_archived': 'true',
    };
    final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';

    try {
      final data = await _api.get('/products$query', token: _token);
      _products = _objectList(data, 'products')
          .map(Product.fromJson)
          .toList(growable: false);
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

  Future<void> loadCategories() async {
    try {
      final data = await _api.get('/products/categories', token: _token);
      _categories = _stringList(data, 'categories');
      notifyListeners();
    } on Object {
      // Category chips are a filter convenience; the list still works without
      // them, so a failure here is not worth surfacing.
    }
  }

  Future<void> setSearch(String value) async {
    if (_search == value) return;
    _search = value;
    await load();
  }

  Future<void> setCategory(String? value) async {
    if (_category == value) return;
    _category = value;
    await load();
  }

  Future<void> setIncludeArchived(bool value) async {
    if (_includeArchived == value) return;
    _includeArchived = value;
    await load();
  }

  /// A blank optional field is sent as null so the server stores null rather
  /// than an empty string.
  Future<Product> save({
    String? id,
    required String name,
    required int priceKobo,
    required int stockQuantity,
    String? description,
    String? category,
    String? sku,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      // An integer kobo value: the server reads a JSON number as kobo already.
      'price_kobo': priceKobo,
      'stock_quantity': stockQuantity,
      'description': _blankToNull(description),
      'category': _blankToNull(category),
      'sku': _blankToNull(sku),
    };

    final data = id == null
        ? await _api.post('/products', token: _token, body: body)
        : await _api.patch('/products/$id', token: _token, body: body);

    await load();
    await loadCategories();
    return Product.fromJson(
      (data as Map<String, dynamic>)['product'] as Map<String, dynamic>,
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    await _api.post(
      '/products/$id/${archived ? 'archive' : 'restore'}',
      token: _token,
    );
    await load();
  }

  /// Hard delete. The API refuses while the product appears in any transaction,
  /// so the UI offers archive for products that are in use.
  Future<void> delete(String id) async {
    await _api.delete('/products/$id', token: _token);
    await load();
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
    _products = const [];
    _categories = const [];
    _loading = false;
    _loaded = false;
    _error = null;
    _search = '';
    _category = null;
    _includeArchived = false;
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

/// Reads a list of plain strings, e.g. the distinct product categories.
List<String> _stringList(dynamic data, String key) {
  if (data is! Map<String, dynamic>) return const [];
  final raw = data[key];
  if (raw is! List) return const [];
  return raw.whereType<String>().toList(growable: false);
}
