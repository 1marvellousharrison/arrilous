import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'auth_repository.dart';

class LogisticsRepository extends ChangeNotifier {
  LogisticsRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;
  Map<String, dynamic>? organization;
  Map<String, dynamic>? rider;

  /// The full `GET /organization` / `GET /rider` payloads: profile, fleet,
  /// service areas, pricing and delivery modes. Kept whole so the workspace
  /// dashboards (spec 42/43) never have to guess at a second request.
  Map<String, dynamic>? organizationDetails;
  Map<String, dynamic>? riderDetails;
  List<Map<String, dynamic>> requests = const [];
  List<Map<String, dynamic>> providers = const [];
  List<Map<String, dynamic>> riders = const [];
  List<Map<String, dynamic>> myRiders = const [];

  /// Spec 6 — the earnings ledger, page-rolled like the business dashboard:
  /// a kobo total plus the delivery history that produced it.
  Map<String, dynamic>? organizationEarnings;
  Map<String, dynamic>? riderEarnings;
  bool loading = false;
  String? error;

  String get _token {
    final session = _auth.session;
    if (session == null) throw StateError('Sign in before using logistics.');
    return session.accessToken;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final role = _auth.session?.user.role;
      if (role != 'business') {
        final profile = await _api.get(
          role == 'rider' ? '/logistics/rider' : '/logistics/organization',
          token: _token,
        ) as Map<String, dynamic>;
        organizationDetails = role == 'rider' ? null : profile;
        riderDetails = role == 'rider' ? profile : null;
        organization = profile['organization'] as Map<String, dynamic>?;
        rider = profile['rider'] as Map<String, dynamic>?;
        if (role != 'rider') {
          final roster = await _api.get('/logistics/organization/riders', token: _token) as Map<String, dynamic>;
          myRiders = (roster['riders'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>().toList();
        }
      } else {
        organization = null;
        rider = null;
        organizationDetails = null;
        riderDetails = null;
        myRiders = const [];
      }
      final queued = await _api.get('/logistics/requests', token: _token) as Map<String, dynamic>;
      requests = (queued['deliveryRequests'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>().toList();
      await loadEarnings();
    } on ApiException catch (exception) {
      if (exception.statusCode != 404) error = exception.message;
    } on NetworkException catch (exception) {
      error = exception.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// The ledger behind the History tab. Dedicated so the dashboard never has to
  /// recompute money from the request list.
  Future<void> loadEarnings() async {
    if (_auth.session == null) return;
    final path = _auth.session!.user.role == 'rider'
        ? '/logistics/rider/earnings'
        : '/logistics/organization/earnings';
    try {
      final data = await _api.get(path, token: _token) as Map<String, dynamic>;
      if (_auth.session!.user.role == 'rider') {
        riderEarnings = data;
      } else {
        organizationEarnings = data;
      }
    } on ApiException {
      // A profile that does not exist yet simply has no ledger.
    } on NetworkException catch (exception) {
      error = exception.message;
      notifyListeners();
    }
  }

  Future<void> findProviders(
    String destinationCity, {
    String? packageSize,
    String? preferredMode,
  }) async {
    final city = destinationCity.trim();
    if (city.isEmpty) {
      providers = const [];
      riders = const [];
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final query = <String, String>{'destination_city': city};
      if (packageSize != null && packageSize != 'any') query['package_size'] = packageSize;
      if (preferredMode != null && preferredMode != 'any') query['preferred_mode'] = preferredMode;
      final data = await _api.get(
        '/logistics/providers?${query.entries.map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}').join('&')}',
        token: _token,
      ) as Map<String, dynamic>;
      providers = (data['providers'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>().toList();
      riders = (data['riders'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>().toList();
    } on ApiException catch (exception) {
      error = exception.message;
    } on NetworkException catch (exception) {
      error = exception.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Spec 28 — the opened delivery: pickup, destination, both sides' contact
  /// details, the order and the event timeline for one request.
  Map<String, dynamic>? requestDetail;

  Future<void> loadRequestDetail(String id) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await _api.get('/logistics/requests/$id', token: _token) as Map<String, dynamic>;
      requestDetail = data['deliveryRequest'] as Map<String, dynamic>?;
    } on ApiException catch (exception) {
      error = exception.message;
    } on NetworkException catch (exception) {
      error = exception.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void clearRequestDetail() {
    requestDetail = null;
    notifyListeners();
  }

  /// Spec 27 — the notification history behind the in-app badge, so a new
  /// delivery request is never reachable only through a small bell icon.
  List<Map<String, dynamic>> notifications = const [];
  int unreadCount = 0;

  Future<void> loadNotifications() async {
    try {
      final data = await _api.get('/logistics/notifications', token: _token) as Map<String, dynamic>;
      notifications = (data['notifications'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>().toList();
      unreadCount = (data['unreadCount'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } on ApiException catch (exception) {
      if (exception.statusCode != 403) error = exception.message;
    } on NetworkException catch (exception) {
      error = exception.message;
    }
  }

  Future<void> markNotificationRead(String id) async {
    await _api.patch('/logistics/notifications/$id/read', token: _token);
    await loadNotifications();
  }

  Future<void> requestDelivery({
    required String transactionId,
    String? organizationId,
    String? riderId,
    String? packageSize,
    String? preferredMode,
  }) async {
    await _api.post('/logistics/requests', token: _token, body: {
      'transaction_id': transactionId,
      'organization_id': ?organizationId,
      'rider_id': ?riderId,
      'package_size': ?packageSize,
      'preferred_mode': ?preferredMode,
    });
    await load();
  }

Future<void> createProfile({
  String? organizationName,
  String? phone,
  String? category,
  String? description,
}) async {
  final role = _auth.session!.user.role;
  final profile = <String, dynamic>{
    'phone': phone,
    'category': category,
    'description': description,
  };
  if (role == 'rider') {
    await _api.post('/logistics/rider', token: _token, body: profile);
  } else {
    await _api.post('/logistics/organization', token: _token, body: {
      'name': organizationName,
      ...profile,
    });
  }
  await load();
  await loadEarnings();
}

  Future<void> setAvailability(bool available, {DateTime? closesAt}) async {
    final path = _auth.session!.user.role == 'rider'
        ? '/logistics/rider/availability'
        : '/logistics/organization/availability';
    await _api.patch(path, token: _token, body: {
      'is_available': available,
      if (available && closesAt != null)
        'availability_expires_at': closesAt.toUtc().toIso8601String(),
    });
    await load();
  }

  /// Spec 17 — signed minutes on today's shift: positive lengthens the closing
  /// time, negative trims it. The server closes the shift if a trim removes more
  /// than the time that was left.
  Future<void> adjustAvailability(int minutes) async {
    final role = _auth.session!.user.role;
    final path = role == 'rider'
        ? '/logistics/rider/availability/extend'
        : '/logistics/organization/availability/extend';
    await _api.post(path, token: _token, body: {'minutes': minutes});
    await load();
  }

  Future<void> assign(String requestId, {String? riderId, String? vehicleId}) async {
    await _api.patch('/logistics/requests/$requestId/assign', token: _token, body: {
      'rider_id': ?riderId,
      'vehicle_id': ?vehicleId,
    });
    await load();
  }

  Future<void> updateRequest(String id, String status) async {
    await _api.patch('/logistics/requests/$id/status', token: _token, body: {
      'status': status,
      if (status == 'failed') 'failure_reason': 'Reported by delivery staff.',
    });
    await load();
  }

  /// Spec 19 — coverage is what makes a partner findable at all, so the
  /// workspace can add areas instead of only displaying them.
  Future<void> addServiceArea({
    required String city,
    String? area,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    double? radiusKm,
  }) async {
    final role = _auth.session!.user.role;
    final body = <String, dynamic>{'city': city};
    if (area != null && area.trim().isNotEmpty) body['area'] = area;
    if (state != null && state.trim().isNotEmpty) body['state'] = state;
    if (country != null && country.trim().isNotEmpty) body['country'] = country;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    if (radiusKm != null) body['radius_km'] = radiusKm;
    await _api.post(
      role == 'rider' ? '/logistics/rider/areas' : '/logistics/organization/areas',
      token: _token,
      body: body,
    );
    await load();
  }

  /// Spec 22 — fleet entries the partner actually owns, with the price that is
  /// shown to the business during matching.
  Future<void> addVehicle({
    required String vehicleType,
    required int totalQuantity,
    required int availableQuantity,
    required String capacityCategory,
    required int startingPriceKobo,
  }) async {
    await _api.post('/logistics/organization/vehicles', token: _token, body: {
      'vehicle_type': vehicleType,
      'total_quantity': totalQuantity,
      'available_quantity': availableQuantity,
      'capacity_category': capacityCategory,
      'starting_price_kobo': startingPriceKobo,
    });
    await load();
  }

  /// Spec 20 — published destination pricing.
  Future<void> addPricing({required String destination, required int priceKobo, String? vehicleType}) async {
    final body = <String, dynamic>{'destination': destination, 'price_kobo': priceKobo};
    if (vehicleType != null) body['vehicle_type'] = vehicleType;
    await _api.post('/logistics/organization/pricing', token: _token, body: body);
    await load();
  }

  /// Spec 24 — the modes a rider offers, with the rate shown to businesses.
  Future<void> addMode({
    required String mode,
    required String capacityCategory,
    required int rateKobo,
    bool isPrimary = false,
  }) async {
    await _api.post('/logistics/rider/modes', token: _token, body: {
      'mode': mode,
      'capacity_category': capacityCategory,
      'rate_kobo': rateKobo,
      'is_primary': isPrimary,
    });
    await load();
  }
}
