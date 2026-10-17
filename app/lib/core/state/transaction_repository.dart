import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/auth_repository.dart';

/// The four independent status axes (Phase 7).
///
/// Kept as one class rather than four fields so a transaction can never be
/// described as "half paid, half delivered" — the axes are always read and
/// written together.
enum TransactionAxis {
  order('order', 'Order'),
  payment('payment', 'Payment'),
  delivery('delivery', 'Delivery'),
  completion('completion', 'Completion');

  const TransactionAxis(this.wire, this.label);

  /// The key the API uses, e.g. `orderStatus`.
  final String wire;
  final String label;

  String get field => '${wire}Status';
}

const Map<String, TransactionAxis> _axisByWire = {
  'order': TransactionAxis.order,
  'payment': TransactionAxis.payment,
  'delivery': TransactionAxis.delivery,
  'completion': TransactionAxis.completion,
};

TransactionAxis? axisForWire(String wire) => _axisByWire[wire];

/// The set of values an axis currently allows, and the ones reachable next.
///
/// This mirrors `server/src/lib/statuses.js`. The server is still the authority
/// and rejects anything illegal; duplicating the table here is what lets the UI
/// hide actions that cannot succeed, instead of showing them and surfacing an
/// error the owner caused no wrong turn to reach.
const Map<String, List<String>> axisValues = {
  'order': ['pending', 'confirmed', 'cancelled'],
  'payment': ['unpaid', 'payment_pending', 'paid', 'failed', 'refunded'],
  'delivery': [
    'not_required',
    'pending',
    'accepted',
    'picked_up',
    'in_transit',
    'delivered',
    'failed',
  ],
  'completion': ['open', 'completed'],
};

const Map<String, Map<String, List<String>>> axisTransitions = {
  'order': {
    'pending': ['confirmed', 'cancelled'],
    'confirmed': ['cancelled'],
    'cancelled': [],
  },
  'payment': {
    'unpaid': ['payment_pending', 'paid', 'failed'],
    'payment_pending': ['paid', 'failed'],
    'paid': ['refunded'],
    'failed': ['payment_pending', 'paid'],
    'refunded': [],
  },
  'delivery': {
    'not_required': ['pending'],
    'pending': ['accepted', 'failed'],
    'accepted': ['picked_up', 'failed'],
    'picked_up': ['in_transit', 'failed'],
    'in_transit': ['delivered', 'failed'],
    'delivered': [],
    'failed': ['pending'],
  },
  'completion': {
    'open': ['completed'],
    'completed': [],
  },
};

/// Statuses that mean "this order still has to reach the customer".
const Set<String> deliveryInFlight = {
  'pending',
  'accepted',
  'picked_up',
  'in_transit',
};

/// A line on a transaction, as stored. [unitPriceKobo] is the price captured at
/// the moment of sale, so editing a product later cannot rewrite history.
class TransactionItem {
  const TransactionItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPriceKobo,
    required this.subtotalKobo,
    this.productId,
    this.imageUrl,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) => TransactionItem(
        id: json['id'] as String? ?? '',
        productId: json['productId'] as String?,
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitPriceKobo: (json['unitPriceKobo'] as num?)?.toInt() ?? 0,
        subtotalKobo: (json['subtotalKobo'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String? productId;
  final String name;

  /// The product's picture as it was at the moment of sale, so a receipt keeps
  /// the mark that was sold even if the product is edited or archived.
  final String? imageUrl;
  final int quantity;
  final int unitPriceKobo;
  final int subtotalKobo;

  /// True for a one-off line the owner typed rather than picked from the catalog.
  bool get isAdHoc => productId == null;
}

/// One entry on the Phase 8 timeline.
class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.id,
    required this.statusType,
    required this.newValue,
    required this.createdAt,
    this.oldValue,
    this.note,
  });

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) => StatusHistoryEntry(
        id: json['id'] as String? ?? '',
        statusType: json['statusType'] as String? ?? 'order',
        oldValue: json['oldValue'] as String?,
        newValue: json['newValue'] as String? ?? '',
        note: json['note'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String id;
  final String statusType;
  final String? oldValue;
  final String newValue;
  final String? note;
  final DateTime createdAt;

  /// The creation entries carry no previous value; say so rather than showing
  /// a meaningless "null → pending".
  bool get isCreation => oldValue == null;

  String get label {
    // A staff note carries no status move, so it is labelled on its own rather
    // than dressed up as "Note set to ".
    if (statusType == 'note') return 'Note';
    final axis = axisForWire(statusType)?.label ?? statusType;
    if (isCreation) return '$axis set to ${_pretty(newValue)}';
    return '$axis: ${_pretty(oldValue!)} → ${_pretty(newValue)}';
  }
}

String _pretty(String status) {
  if (status.isEmpty) return status;
  final head = status[0].toUpperCase();
  return head + status.substring(1).replaceAll('_', ' ');
}

class Transaction {
  const Transaction({
    required this.id,
    required this.transactionNumber,
    required this.source,
    required this.subtotalKobo,
    required this.discountKobo,
    required this.deliveryFeeKobo,
    required this.totalKobo,
    required this.createdAt,
    required this.updatedAt,
    required this.orderStatus,
    required this.paymentStatus,
    required this.deliveryStatus,
    required this.completionStatus,
    required this.deliveryRequired,
    this.customerId,
    this.notes,
    this.deliveryAddress,
    this.items = const [],
    this.history = const [],
    this.customerName,
    this.customerPhone,
  });

  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    List<TransactionItem> items = const [],
    List<StatusHistoryEntry> history = const [],
    String? customerName,
    String? customerPhone,
  }) =>
      Transaction(
        id: json['id'] as String,
        transactionNumber: json['transactionNumber'] as String? ?? '',
        customerId: json['customerId'] as String?,
        source: json['source'] as String? ?? 'manual',
        subtotalKobo: (json['subtotalKobo'] as num?)?.toInt() ?? 0,
        discountKobo: (json['discountKobo'] as num?)?.toInt() ?? 0,
        deliveryFeeKobo: (json['deliveryFeeKobo'] as num?)?.toInt() ?? 0,
        totalKobo: (json['totalKobo'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String?,
        deliveryAddress: json['deliveryAddress'] as String?,
        deliveryRequired: json['deliveryRequired'] as bool? ?? false,
        orderStatus: json['orderStatus'] as String? ?? 'pending',
        paymentStatus: json['paymentStatus'] as String? ?? 'unpaid',
        deliveryStatus: json['deliveryStatus'] as String? ?? 'not_required',
        completionStatus: json['completionStatus'] as String? ?? 'open',
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        items: items,
        history: history,
        customerName: customerName,
        customerPhone: customerPhone,
      );

  final String id;
  final String transactionNumber;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String source;
  final int subtotalKobo;
  final int discountKobo;
  final int deliveryFeeKobo;
  final int totalKobo;
  final String? notes;
  final String? deliveryAddress;
  final bool deliveryRequired;
  final String orderStatus;
  final String paymentStatus;
  final String deliveryStatus;
  final String completionStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<TransactionItem> items;
  final List<StatusHistoryEntry> history;

  String valueFor(TransactionAxis axis) => switch (axis) {
        TransactionAxis.order => orderStatus,
        TransactionAxis.payment => paymentStatus,
        TransactionAxis.delivery => deliveryStatus,
        TransactionAxis.completion => completionStatus,
      };

  /// Money the business is still owed on this sale.
  int get outstandingKobo =>
      paymentStatus == 'paid' || paymentStatus == 'refunded' ? 0 : totalKobo;

  bool get isCancelled => orderStatus == 'cancelled';
  bool get isCompleted => completionStatus == 'completed';
  bool get needsAttention => !isCompleted && !isCancelled;
}

DateTime _date(dynamic value) =>
    DateTime.tryParse(value as String? ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);

/// One line the owner has composed but not yet saved.
class DraftItem {
  DraftItem({
    required this.name,
    required this.quantity,
    required this.unitPriceKobo,
    this.productId,
  });

  String name;
  int quantity;
  int unitPriceKobo;
  String? productId;

  int get subtotalKobo => unitPriceKobo * quantity;

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        if (productId == null) 'name': name,
        if (productId == null) 'unit_price_kobo': unitPriceKobo,
        'quantity': quantity,
      };
}

/// Phase 9-11 transaction state: composing a sale, listing history, and the
/// detail view with its Phase 8 timeline.
class TransactionRepository extends ChangeNotifier {
  TransactionRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  List<Transaction> _transactions = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  // Filters (Phase 11). Search and every filter are applied by the API so that
  // paging stays correct as the history grows.
  String _search = '';
  String? _orderStatus;
  String? _paymentStatus;
  String? _deliveryStatus;
  String? _completionStatus;
  String? _source;
  String? _customerId;
  DateTime? _from;
  DateTime? _to;
  int _limit = 25;
  int _offset = 0;

  // The transaction currently open in the detail screen.
  Transaction? _detail;
  bool _detailLoading = false;
  String? _detailError;

  List<Transaction> get transactions => _transactions;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  String get search => _search;
  String? get orderStatus => _orderStatus;
  String? get paymentStatus => _paymentStatus;
  String? get deliveryStatus => _deliveryStatus;
  String? get completionStatus => _completionStatus;
  String? get source => _source;
  String? get customerId => _customerId;
  DateTime? get from => _from;
  DateTime? get to => _to;
  int get offset => _offset;
  bool get hasMore => _transactions.length >= _limit;
  Transaction? get detail => _detail;
  bool get detailLoading => _detailLoading;
  String? get detailError => _detailError;

  /// True when any filter is narrowing the list, so the UI can offer a reset
  /// rather than showing an empty list with no explanation.
  bool get hasFilters =>
      _search.isNotEmpty ||
      _orderStatus != null ||
      _paymentStatus != null ||
      _deliveryStatus != null ||
      _completionStatus != null ||
      _source != null ||
      _customerId != null ||
      _from != null ||
      _to != null;

  int get activeFilterCount => [
        _search.isEmpty ? null : _search,
        _orderStatus,
        _paymentStatus,
        _deliveryStatus,
        _completionStatus,
        _source,
        _customerId,
        _from,
        _to,
      ].where((value) => value != null).length;

  Future<void> load({bool append = false}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    final params = <String, String>{
      if (_search.isNotEmpty) 'search': _search,
      'order_status': ?_orderStatus,
      'payment_status': ?_paymentStatus,
      'delivery_status': ?_deliveryStatus,
      'completion_status': ?_completionStatus,
      'source': ?_source,
      'customer_id': ?_customerId,
      // Sent as UTC. A local DateTime's ISO string carries no offset, so the
      // server would have to guess which zone "23:59:59" was in; UTC says it.
      if (_from != null) 'from': _from!.toUtc().toIso8601String(),
      if (_to != null) 'to': _to!.toUtc().toIso8601String(),
      'limit': '$_limit',
      'offset': '$_offset',
    };
    final query = '?${Uri(queryParameters: params).query}';

    try {
      final data = await _api.get('/transactions$query', token: _token);
      final page = _objectList(data, 'transactions')
          .map(Transaction.fromJson)
          .toList(growable: false);
      _transactions = append ? [..._transactions, ...page] : page;
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

  Future<void> loadMore() async {
    if (_loading || !hasMore) return;
    _offset += _limit;
    await load(append: true);
  }

  Future<void> setSearch(String value) async {
    if (_search == value) return;
    _search = value;
    await _reloadFromStart();
  }

  Future<void> setFilter({String? field, String? value}) async {
    switch (field) {
      case 'order':
        _orderStatus = value;
      case 'payment':
        _paymentStatus = value;
      case 'delivery':
        _deliveryStatus = value;
      case 'completion':
        _completionStatus = value;
      case 'source':
        _source = value;
      case 'customer_id':
        _customerId = value;
      default:
        throw ArgumentError('Unknown transaction filter "$field".');
    }
    await _reloadFromStart();
  }

  Future<void> setDateRange({DateTime? from, DateTime? to}) async {
    _from = from;
    _to = to;
    await _reloadFromStart();
  }

  Future<void> clearFilters() async {
    _search = '';
    _orderStatus = null;
    _paymentStatus = null;
    _deliveryStatus = null;
    _completionStatus = null;
    _source = null;
    _customerId = null;
    _from = null;
    _to = null;
    await _reloadFromStart();
  }

  /// Any filter change invalidates paging, so it goes back to the first page.
  Future<void> _reloadFromStart() async {
    _offset = 0;
    _transactions = const [];
    await load();
  }

  /// Phase 9 — records a sale. Totals are deliberately absent from [body]:
  /// the server recomputes them from the items it trusts.
  Future<Transaction> create({
    required List<DraftItem> items,
    String? customerId,
    int discountKobo = 0,
    int deliveryFeeKobo = 0,
    bool deliveryRequired = false,
    String? deliveryAddress,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ApiException(
        422,
        'validation_failed',
        'Add at least one product to the sale.',
      );
    }

    final data = await _api.post('/transactions', token: _token, body: {
      'items': items.map((item) => item.toJson()).toList(),
      'customer_id': customerId,
      'discount_kobo': discountKobo,
      'delivery_fee_kobo': deliveryFeeKobo,
      'delivery_required': deliveryRequired,
      'delivery_address': _blankToNull(deliveryAddress),
      'notes': _blankToNull(notes),
      // Only manual sales exist until Phase 14 wires WhatsApp in.
      'source': 'manual',
    });

    _offset = 0;
    await load();

    final payload = (data as Map<String, dynamic>)['transaction'];
    if (payload is! Map<String, dynamic>) {
      throw ApiException(
        502,
        'malformed_response',
        'The sale was saved but the server sent an unreadable response. '
        'Check your transactions list before recording it again.',
      );
    }

    // The create response already carries the items, so the owner can navigate
    // straight to the detail screen with a complete transaction.
    final created = Transaction.fromJson(
      payload,
      items: _objectList(payload, 'items').map(TransactionItem.fromJson).toList(),
    );

    // Opening the detail also fetches the Phase 8 timeline. A failure here must
    // NOT fail the whole operation: the sale is already saved, and reporting an
    // error would invite the owner to record it a second time.
    await loadDetail(created.id);

    return _detail ?? created;
  }

  /// Phase 10 detail, including the Phase 8 timeline.
  Future<Transaction?> loadDetail(String id) async {
    _detailLoading = true;
    _detailError = null;
    notifyListeners();

    try {
      final data = await _api.get('/transactions/$id', token: _token) as Map<String, dynamic>;
      final payload = data['transaction'];
      if (payload is! Map<String, dynamic>) {
        _detailError = 'The server did not return that transaction.';
        _detail = null;
        return null;
      }
      final customer = data['customer'];
      _detail = Transaction.fromJson(
        payload,
        items: _objectList(payload, 'items').map(TransactionItem.fromJson).toList(),
        history:
            _objectList(data, 'history').map(StatusHistoryEntry.fromJson).toList(),
        customerName: customer is Map<String, dynamic>
            ? customer['name'] as String?
            : null,
        customerPhone: customer is Map<String, dynamic>
            ? customer['phone'] as String?
            : null,
      );
    } on ApiException catch (error) {
      _detailError = error.message;
      _detail = null;
    } on NetworkException catch (error) {
      _detailError = error.message;
      _detail = null;
    } on TypeError {
      // A response of an unexpected shape is a bad read, not a crash: the
      // detail screen shows an empty state with the reason instead.
      _detailError = 'That transaction could not be read.';
      _detail = null;
    } finally {
      _detailLoading = false;
      notifyListeners();
    }
    return _detail;
  }

  /// Which status values an owner may pick for [axis] right now.
  ///
  /// Returns an empty list when the axis is frozen — a cancelled order can only
  /// ever be refunded, so it offers exactly one action rather than the full set
  /// of values the API would reject.
  List<String> availableTransitions(Transaction transaction, TransactionAxis axis) {
    final wire = axis.wire;
    final current = transaction.valueFor(axis);

    if (transaction.isCancelled) {
      // A refund is the one thing still possible on a cancelled sale. Only from
      // 'paid', though: the server's payment table has no payment_pending →
      // refunded edge, so offering it here would only earn a rejection.
      if (wire == 'payment' && current == 'paid') return const ['refunded'];
      return const [];
    }

    // A completed sale is finished. Cancelling one is refused outright by the
    // server — "a cancelled transaction cannot also be completed" — so the
    // order axis must freeze too, not just completion.
    if (transaction.isCompleted) return const [];

    // Delivery can only start on a sale that is actually going somewhere.
    if (wire == 'delivery' && !transaction.deliveryRequired) return const [];

    // Completing is a combination rather than a single field: the server checks
    // that payment settled and delivery finished in the same request. Offering
    // the button before that is true would invite the owner into a rejection,
    // which is exactly what this table exists to prevent.
    if (wire == 'completion' && current == 'open' && !_completionUnlocked(transaction)) {
      return const [];
    }

    return axisTransitions[wire]?[current] ?? const [];
  }

  /// The two prerequisites `assertTransactionStateChange` enforces before it
  /// will accept a completion.
  bool _completionUnlocked(Transaction t) =>
      t.paymentStatus == 'paid' &&
      (t.deliveryStatus == 'not_required' || t.deliveryStatus == 'delivered');

  /// Completing is only offered once the two things it depends on are true, so
  /// the owner is not invited into a rejection.
  bool get canCompleteNow {
    final txn = _detail;
    if (txn == null) return false;
    return availableTransitions(txn, TransactionAxis.completion).contains('completed');
  }

  /// Phase 7 write. Any subset of the axes may move; the server decides whether
  /// the combination is legal. A note alone is allowed — a staff member
  /// annotates a sale without moving it.
  Future<Transaction?> updateStatuses(Map<String, String> changes, {String? note}) async {
    final hasNote = note != null && note.trim().isNotEmpty;
    if (changes.isEmpty && !hasNote) return _detail;

    final body = <String, dynamic>{...changes};
    if (hasNote) body['note'] = note.trim();

    final data = await _api.patch(
      '/transactions/${_detail?.id}/statuses',
      token: _token,
      body: body,
    );

    final updated =
        Transaction.fromJson((data as Map<String, dynamic>)['transaction'] as Map<String, dynamic>);

    // The list still shows this row with the old status, so patch it in place
    // rather than making the owner pull to refresh after every tap.
    _transactions = _transactions
        .map((txn) => txn.id == updated.id ? updated : txn)
        .toList(growable: false);

    await loadDetail(updated.id);
    notifyListeners();
    return _detail;
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
    _transactions = const [];
    _loading = false;
    _loaded = false;
    _error = null;
    _search = '';
    _orderStatus = null;
    _paymentStatus = null;
    _deliveryStatus = null;
    _completionStatus = null;
    _source = null;
    _customerId = null;
    _from = null;
    _to = null;
    _limit = 25;
    _offset = 0;
    _detail = null;
    _detailLoading = false;
    _detailError = null;
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