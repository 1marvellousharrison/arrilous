import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'auth_repository.dart';
import 'transaction_repository.dart';

/// One staff member of the signed-in owner's business.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.staffCode,
    required this.status,
    required this.salesCount,
    this.phone,
    this.activatedAt,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        phone: json['phone'] as String?,
        staffCode: json['staffCode'] as String? ?? '',
        status: json['status'] as String? ?? 'invited',
        activatedAt: DateTime.tryParse(json['activatedAt'] as String? ?? ''),
        salesCount: (json['salesCount'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String userId;
  final String fullName;
  final String? phone;
  final String staffCode;
  final String status;
  final DateTime? activatedAt;
  final int salesCount;

  bool get isActive => status == 'active';
  bool get isInvited => status == 'invited';
  bool get isDisabled => status == 'disabled';

  String get statusLabel => switch (status) {
        'active' => 'Active',
        'invited' => 'Not activated',
        'disabled' => 'Disabled',
        _ => status,
      };
}

/// Owner-side staff management: adding staff (which issues their code), listing
/// them, enabling or disabling them, and reading one staff member's sales.
class StaffRepository extends ChangeNotifier {
  StaffRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  List<StaffMember> _staff = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  List<StaffMember> get staff => _staff;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.get('/staff', token: _token) as Map<String, dynamic>;
      _staff = _readList(data);
      _loaded = true;
    } on ApiException catch (error) {
      _error = error.message;
    } on NetworkException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Adds a staff member and returns the freshly issued code, which the owner
  /// must hand to the staff.
  Future<StaffMember> create({
    required String fullName,
    String? phone,
  }) async {
    final data = await _api.post('/staff', token: _token, body: {
      'full_name': fullName.trim(),
      'phone': _blankToNull(phone),
    }) as Map<String, dynamic>;

    final created = StaffMember.fromJson(
      data['staff'] as Map<String, dynamic>? ?? const {},
    );
    await load();
    return created;
  }

  /// Disables or re-enables a staff member.
  Future<StaffMember> setStatus(String id, String status) async {
    final data = await _api.patch('/staff/$id', token: _token, body: {
      'status': status,
    }) as Map<String, dynamic>;

    final updated = StaffMember.fromJson(
      data['staff'] as Map<String, dynamic>? ?? const {},
    );
    _staff = _staff
        .map((member) => member.id == updated.id ? updated : member)
        .toList(growable: false);
    notifyListeners();
    return updated;
  }

  /// One staff member, re-read so the detail screen shows live status and count.
  Future<StaffMember> detail(String id) async {
    final data = await _api.get('/staff/$id', token: _token) as Map<String, dynamic>;
    return StaffMember.fromJson(data['staff'] as Map<String, dynamic>? ?? const {});
  }

  /// This staff member's sales, newest first.
  Future<List<Transaction>> sales(String id) async {    final data = await _api.get('/staff/$id/transactions', token: _token)
        as Map<String, dynamic>;
    final rows = data['transactions'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Transaction.fromJson)
        .toList(growable: false);
  }

  List<StaffMember> _readList(Map<String, dynamic> data) {
    final rows = data['staff'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(StaffMember.fromJson)
        .toList(growable: false);
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
    _staff = const [];
    _loading = false;
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
