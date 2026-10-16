import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

/// Persists the serialised session between launches.
///
/// Tokens land in platform secure storage (Android Keystore, iOS Keychain,
/// libsecret, Windows DPAPI, WebCrypto). Targets that cannot offer secure
/// storage — notably a Flutter web build served over plain HTTP — fall back to
/// SharedPreferences instead of dropping the session.
class SessionStore {
  SessionStore({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  static const String key = 'dee.auth.session';

  final FlutterSecureStorage _secure;
  SharedPreferences? _cachedPrefs;
  bool _fallback = false;

  bool get usingFallback => _fallback;

  Future<String?> read() async {
    if (!_fallback) {
      try {
        return await _secure.read(key: key);
      } on Object {
        _fallback = true;
      }
    }
    return (await _prefs())?.getString(key);
  }

  Future<void> write(String value) async {
    if (!_fallback) {
      try {
        await _secure.write(key: key, value: value);
        final prefs = _cachedPrefs;
        if (prefs != null) await prefs.remove(key);
        return;
      } on Object {
        _fallback = true;
      }
    }
    await (await _prefs())?.setString(key, value);
  }

  Future<void> clear() async {
    _fallback = false;
    await _secure.delete(key: key).onError<Object>((_, _) => null);
    await (await _prefs())?.remove(key);
  }

  Future<SharedPreferences?> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();
}

/// Owns the authenticated session: sign-up, sign-in, sign-out, silent refresh
/// and persistence.
///
/// This is the single place the app talks to `/api/v1/auth/*`. Later phases
/// (business profile, products, transactions) must go through
/// [AuthRepository.currentUserId] to scope data to the signed-in user.
class AuthRepository extends ChangeNotifier {
  AuthRepository(this._api, [SessionStore? store]) : _store = store ?? SessionStore();

  final ApiClient _api;
  final SessionStore _store;

  AuthSession? _session;

  AuthSession? get session => _session;
  bool get isSignedIn => _session != null;
  String? get currentUserId => _session?.user.id;

  /// Restores a persisted session on launch. Returns true when the stored
  /// session is still usable.
  Future<bool> restore() async {
    final raw = await _store.read();
    if (raw == null || raw.isEmpty) return false;

    AuthSession stored;
    try {
      stored = AuthSession.fromStored(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await clear();
      return false;
    }

    _session = stored;

    // Validate against the server so a revoked or deleted account cannot enter
    // the app on a stale token.
    try {
      final refreshed = await refresh();
      return refreshed != null;
    } on ApiException {
      await clear();
      return false;
    } on NetworkException {
      // Offline: keep the cached session so the app is usable when the
      // connection returns.
      return true;
    }
  }

  Future<AuthSession> signUp({
    required String fullName,
    required String email,
    required String password,
    String role = 'business',
  }) async {
    final data = await _api.post(
      '/auth/signup',
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role,
      },
    );
    return _persist(AuthSession.fromJson(data as Map<String, dynamic>));
  }

  Future<AuthSession> signIn({
    required String identifier,
    required String password,
  }) async {
    final data = await _api.post(
      '/auth/login',
      body: {'identifier': identifier, 'password': password},
    );
    return _persist(AuthSession.fromJson(data as Map<String, dynamic>));
  }

  /// Step 1 of staff activation: proves the code the owner handed over exists
  /// and is still unclaimed. No session is created — the staff sets a password
  /// next, then signs in like anyone else.
  Future<StaffClaim> claimStaffCode(String staffCode) async {
    final data = await _api.post(
      '/staff/claim',
      body: {'staff_code': staffCode.trim()},
    ) as Map<String, dynamic>;
    return StaffClaim.fromJson(data);
  }

  /// Step 2 of staff activation: sets the staff's own password. The owner never
  /// sees or chooses it.
  Future<void> activateStaff({
    required String staffCode,
    required String password,
  }) async {
    await _api.post(
      '/staff/activate',
      body: {'staff_code': staffCode.trim(), 'password': password},
    );
  }

  /// Asks the server for a one-time code. In development the API echoes the
  /// code as `dev_code`; the UI shows it so the flow is testable without an
  /// SMS provider.
  ///
  /// Returns null when the account is unknown: the API answers with a plain
  /// `{"status":"success"}` so that callers cannot probe which identifiers are
  /// registered.
  Future<OtpChallenge?> requestOtp({
    required String identifier,
    String purpose = 'login_verification',
    String? channel,
  }) async {
    final data = await _api.post(
      '/auth/request-otp',
      body: {'identifier': identifier, 'purpose': purpose, 'channel': ?channel},
    ) as Map<String, dynamic>;

    return _challengeFrom(data, identifier);
  }

  OtpChallenge? _challengeFrom(Map<String, dynamic> data, String identifier) {
    final challengeId = data['challenge_id'] as String?;
    if (challengeId == null || challengeId.isEmpty) return null;
    return OtpChallenge(
      challengeId: challengeId,
      destination: data['destination'] as String? ?? identifier,
      channel: data['channel'] as String? ?? 'sms',
      expiresAt: DateTime.tryParse(data['expires_at'] as String? ?? ''),
      devCode: data['dev_code'] as String?,
    );
  }

  Future<AuthSession> verifyOtp({
    required String challengeId,
    required String code,
  }) async {
    final data = await _api.post(
      '/auth/verify-otp',
      body: {'challenge_id': challengeId, 'code': code},
    );
    return _persist(AuthSession.fromJson(data as Map<String, dynamic>));
  }

  /// Starts a password reset. Returns null when no account matches the
  /// identifier, mirroring the API's anti-enumeration behaviour.
  Future<OtpChallenge?> requestPasswordReset({required String identifier}) async {
    final data = await _api.post(
      '/auth/request-password-reset',
      body: {'identifier': identifier},
    ) as Map<String, dynamic>;

    return _challengeFrom(data, identifier);
  }

  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/reset-password',
      body: {'challenge_id': challengeId, 'code': code, 'new_password': newPassword},
    );
  }

  /// Rotates the refresh token. Returns null when the session is dead.
  Future<AuthSession?> refresh() async {
    final current = _session;
    if (current == null) return null;

    try {
      final data = await _api.post(
        '/auth/refresh',
        body: {'refresh_token': current.refreshToken},
      );
      return await _persist(AuthSession.fromJson(data as Map<String, dynamic>));
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await clear();
        return null;
      }
      rethrow;
    }
  }

  Future<AuthUser> fetchMe() async {
    final session = _session;
    if (session == null) {
      throw ApiException(401, 'unauthorized', 'You need to sign in to continue.');
    }
    final data = await _api.get('/auth/me', token: session.accessToken);
    return AuthUser.fromJson(
      (data as Map<String, dynamic>)['user'] as Map<String, dynamic>,
    );
  }

  Future<void> signOut() async {
    final current = _session;
    if (current != null) {
      try {
        await _api.post('/auth/logout', body: {'refresh_token': current.refreshToken});
      } on Object {
        // Signing out locally must succeed even when the server is unreachable.
      }
    }
    await clear();
  }

  Future<void> clear() async {
    _session = null;
    notifyListeners();
    await _store.clear();
  }

  Future<AuthSession> _persist(AuthSession session) async {
    _session = session;
    notifyListeners();
    await _store.write(jsonEncode(session.toJson()));
    return session;
  }
}

/// What a staff code resolves to before activation: who it belongs to and the
/// business the staff would join.
class StaffClaim {
  const StaffClaim({required this.fullName, required this.businessName});

  factory StaffClaim.fromJson(Map<String, dynamic> json) {
    final staff = json['staff'] as Map<String, dynamic>? ?? const {};
    final business = json['business'] as Map<String, dynamic>? ?? const {};
    return StaffClaim(
      fullName: staff['fullName'] as String? ?? '',
      businessName: business['businessName'] as String? ?? '',
    );
  }

  final String fullName;
  final String businessName;
}

class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.destination,
    required this.channel,
    this.expiresAt,
    this.devCode,
  });

  final String challengeId;
  final String destination;
  final String channel;
  final DateTime? expiresAt;

  /// Only present in development builds, where the API echoes the code.
  final String? devCode;
}
