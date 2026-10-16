import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../state/auth_repository.dart';
import '../utils/text.dart';

/// The business profile and its single location.
class BusinessProfile {
  const BusinessProfile({
    required this.id,
    required this.ownerUserId,
    required this.businessName,
    this.businessCategory,
    this.businessDescription,
    this.phone,
    this.email,
    this.logoUrl,
    this.location,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) =>
      BusinessProfile(
        id: json['id'] as String,
        ownerUserId: json['ownerUserId'] as String? ?? '',
        businessName: json['businessName'] as String? ?? '',
        businessCategory: json['businessCategory'] as String?,
        businessDescription: json['businessDescription'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        logoUrl: json['logoUrl'] as String?,
        location: json['location'] is Map<String, dynamic>
            ? BusinessLocation.fromJson(
                json['location'] as Map<String, dynamic>,
              )
            : null,
      );

  final String id;
  final String ownerUserId;
  final String businessName;
  final String? businessCategory;
  final String? businessDescription;
  final String? phone;
  final String? email;

  /// An optional image data URL for the shop's logo. Null means the owner never
  /// set one, and the UI falls back to the first letter of the name.
  final String? logoUrl;
  final BusinessLocation? location;

  /// The name to show, with its first letter upper-cased.
  String get displayName => capitalizeName(businessName);

  /// True once the owner has both a profile and a location, which is the gate
  /// for reaching the rest of the app.
  bool get isComplete => location != null;

  /// True once everything the delivery partner needs from the business is on
  /// file: the name they call, the contact number, and the location as typed
  /// (city, area, state). Anything missing sends the owner back to business
  /// details, because a rider cannot call a shop with no number and cannot
  /// find one with no address.
  bool get hasLogisticsDetails {
    if (businessName.trim().isEmpty) return false;
    if ((phone ?? '').trim().isEmpty) return false;
    final location = this.location;
    if (location == null) return false;
    return location.city?.trim().isNotEmpty == true &&
        location.area?.trim().isNotEmpty == true &&
        location.state?.trim().isNotEmpty == true;
  }
}

class BusinessLocation {
  const BusinessLocation({
    required this.id,
    required this.businessId,
    required this.address,
    this.city,
    this.area,
    this.state,
    this.country,
    this.latitude,
    this.longitude,
  });

  factory BusinessLocation.fromJson(Map<String, dynamic> json) =>
      BusinessLocation(
        id: json['id'] as String,
        businessId: json['businessId'] as String? ?? '',
        address: json['address'] as String? ?? '',
        city: json['city'] as String?,
        area: json['area'] as String?,
        state: json['state'] as String?,
        country: json['country'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  final String id;
  final String businessId;
  final String address;
  final String? city;
  final String? area;
  final String? state;
  final String? country;
  final double? latitude;
  final double? longitude;

  String get oneLine => [
        address,
        if (area != null) area,
        if (city != null) city,
        if (state != null) state,
        if (country != null) country,
      ].whereType<String>().join(', ');

  bool get hasCoordinates => latitude != null && longitude != null;
}

/// A one-time code challenge that proves an owner before business details may
/// be edited. Mirrors the auth OTP shape so the UI can be reused.
class BusinessEditChallenge {
  const BusinessEditChallenge({
    required this.challengeId,
    required this.destination,
    this.devCode,
    this.expiresAt,
  });

  final String challengeId;
  final String destination;
  final String? devCode;
  final DateTime? expiresAt;
}

/// Owns the business profile for the signed-in owner (Phases 1-2).
///
/// The profile is always fetched from the API rather than inferred from the
/// session: which business an owner belongs to is server state, and caching it
/// in the token would let a stale token keep showing a business the owner has
/// since removed.
class BusinessRepository extends ChangeNotifier {
  BusinessRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  BusinessProfile? _business;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  BusinessProfile? get business => _business;
  bool get loading => _loading;
  String? get error => _error;

  bool get hasProfile => _business != null;
  bool get hasLocation => _business?.location != null;

  /// False while loading so the app does not flash the setup flow at a signed-in
  /// owner who already finished setup.
  bool get isReady => _loaded && !_loading;

  /// True when the owner must complete setup before using the rest of the app.
  bool get needsSetup => isReady && !(_business?.isComplete ?? false);

  /// True when setup is done but the details logistics depends on (contact and
  /// the city/area/state of the pickup address) are still missing. The owner
  /// is sent back to business details for those — the full-screen setup gate
  /// only owns "no location at all".
  bool get needsLogisticsDetails =>
      isReady && !needsSetup && !(business?.hasLogisticsDetails ?? false);

  Future<void> load() async {
    final session = _auth.session;
    if (session == null) {
      _business = null;
      _loaded = true;
      _loading = false;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _api.get('/business', token: session.accessToken);
      final raw = (data as Map<String, dynamic>)['business'];
      _business = raw is Map<String, dynamic>
          ? BusinessProfile.fromJson(raw)
          : null;
    } on ApiException catch (error) {
      _error = error.message;
      // A role that cannot own a business is a permanent answer, not a
      // transient failure, so it must not leave the UI spinning on "retry".
      _business = null;
    } on NetworkException catch (error) {
      _error = error.message;
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  Future<BusinessProfile> createProfile({
    required String businessName,
    String? category,
    String? description,
    String? phone,
    String? email,
    String? logo,
  }) async {
    final data = await _api.post(
      '/business',
      token: _token,
      body: {
        'business_name': businessName,
        'business_category': _blankToNull(category),
        'business_description': _blankToNull(description),
        'phone': _blankToNull(phone),
        'email': _blankToNull(email),
        'logo_url': _blankToNull(logo),
      },
    );
    return _adopt(data);
  }

  Future<BusinessProfile> updateProfile({
    String? businessName,
    String? category,
    String? description,
    String? phone,
    String? email,
    String? logo,
    String? editToken,
  }) async {
    final body = <String, dynamic>{
      'business_name': ?businessName,
      'business_category': ?category,
      'business_description': ?description,
      // A blank phone, email or logo clears the field on the server, so these
      // are sent as an explicit null rather than omitted from the patch.
      if (phone != null) 'phone': _blankToNull(phone),
      if (email != null) 'email': _blankToNull(email),
      if (logo != null) 'logo_url': _blankToNull(logo),
    };
    if (body.isEmpty) return _business!;

    final data = await _api.patch(
      '/business',
      token: _token,
      body: body,
      headers: _editHeaders(editToken),
    );
    return _adopt(data);
  }

  /// Upserts the single location. Safe to call on every confirmation: the server
  /// replaces the existing row rather than adding a second address.
  Future<BusinessProfile> saveLocation({
    required String address,
    String? city,
    String? area,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    String? editToken,
  }) async {
    final data = await _api.put(
      '/business/location',
      token: _token,
      headers: _editHeaders(editToken),
      body: {
        'address': address,
        'city': _blankToNull(city),
        'area': _blankToNull(area),
        'state': _blankToNull(state),
        'country': _blankToNull(country),
        'latitude': latitude,
        'longitude': longitude,
      },
    );
    return _adopt(data);
  }

  /// Asks the server to email a one-time code to the owner. The code proves it is
  /// really the owner before an existing profile is changed.
  Future<BusinessEditChallenge> requestEditOtp() async {
    final data = await _api.post('/business/edit-otp', token: _token)
        as Map<String, dynamic>;
    return BusinessEditChallenge(
      challengeId: data['challenge_id'] as String,
      destination: data['destination'] as String? ?? 'your email',
      devCode: data['dev_code'] as String?,
      expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? ''),
    );
  }

  /// Verifies the code and returns the short-lived token every profile write of
  /// this editing session must carry.
  Future<String> verifyEditOtp({
    required String challengeId,
    required String code,
  }) async {
    final data = await _api.post(
      '/business/edit-otp/verify',
      token: _token,
      body: {'challenge_id': challengeId, 'code': code},
    ) as Map<String, dynamic>;
    final token = data['edit_token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException(
        502,
        'malformed_response',
        'The server did not return an edit token. Please try again.',
      );
    }
    return token;
  }

  Map<String, String>? _editHeaders(String? editToken) =>
      (editToken == null || editToken.isEmpty)
          ? null
          : {'x-business-edit-token': editToken};

  BusinessProfile _adopt(dynamic data) {
    final raw = (data as Map<String, dynamic>)['business'];
    if (raw is! Map<String, dynamic>) {
      // A successful write that comes back without the profile means the client
      // and server disagree about the state of setup. Failing loudly here is
      // better than caching null and letting the UI silently drop the owner back
      // into the setup flow.
      throw ApiException(
        502,
        'malformed_response',
        'The server did not return your business profile. Pull to refresh and try again.',
      );
    }
    _business = BusinessProfile.fromJson(raw);
    _error = null;
    _loaded = true;
    _loading = false;
    notifyListeners();
    return _business!;
  }

  String get _token {
    final session = _auth.session;
    if (session == null) {
      throw ApiException(401, 'unauthorized', 'You need to sign in to continue.');
    }
    return session.accessToken;
  }

  /// Empty optional fields are sent as null so the server clears them instead of
  /// storing "" as a real value.
  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void reset() {
    _business = null;
    _loading = false;
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
