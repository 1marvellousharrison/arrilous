import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error thrown for any non-2xx API response, already decoded into the
/// server's standard `{ "error": { "code", "message", "details" } }` envelope.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, {this.details});

  final int statusCode;
  final String code;
  final String message;
  final List<FieldError>? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isValidation => statusCode == 422;

  /// Returns the server-side message for a given input field, if any.
  String? fieldError(String field) {
    for (final detail in details ?? const <FieldError>[]) {
      if (detail.field == field) return detail.message;
    }
    return null;
  }

  @override
  String toString() => message;
}

class FieldError {
  const FieldError({required this.field, required this.message});

  factory FieldError.fromJson(Map<String, dynamic> json) => FieldError(
        field: json['field'] as String? ?? 'form',
        message: json['message'] as String? ?? 'Invalid value.',
      );

  final String field;
  final String message;
}

class NetworkException implements Exception {
  NetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A signed-in user, as returned by `/api/v1/auth/me`.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.emailVerified = false,
    this.phoneVerified = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        fullName: json['fullName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        role: json['role'] as String? ?? 'business',
        emailVerified: json['emailVerified'] as bool? ?? false,
        phoneVerified: json['phoneVerified'] as bool? ?? false,
      );

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final bool emailVerified;
  final bool phoneVerified;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    this.expiresAt,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final String refreshToken;
  final DateTime? expiresAt;
  final AuthUser user;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt?.toIso8601String(),
        'user': {
          'id': user.id,
          'fullName': user.fullName,
          'email': user.email,
          'phone': user.phone,
          'role': user.role,
          'emailVerified': user.emailVerified,
          'phoneVerified': user.phoneVerified,
        },
      };

  factory AuthSession.fromStored(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.tryParse(json['expires_at'] as String),
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

/// Low-level HTTP wrapper. Knows nothing about auth beyond attaching a bearer
/// token; token refresh lives in AuthRepository.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.onUnauthorized,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  /// Called when an authenticated request (one carrying a bearer token) is
  /// refused with a 401, i.e. the session is no longer valid. The app uses this
  /// to sign the user out and drop them back on the login screen instead of
  /// leaving them stuck on an error. Sign-in and refresh calls carry no token,
  /// so a wrong password never triggers it.
  final void Function()? onUnauthorized;

  Future<dynamic> get(String path, {String? token}) =>
      _send('GET', path, token: token);

  Future<dynamic> post(String path, {Map<String, dynamic>? body, String? token}) =>
      _send('POST', path, body: body, token: token);

  Future<dynamic> put(String path, {Map<String, dynamic>? body, String? token}) =>
      _send('PUT', path, body: body, token: token);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body, String? token}) =>
      _send('PATCH', path, body: body, token: token);

  Future<dynamic> delete(String path, {String? token}) =>
      _send('DELETE', path, token: token);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };

    late http.Response response;
    try {
      response = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ),
        'PUT' => _client.put(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ),
        'PATCH' => _client.patch(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          ),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw ArgumentError('Unsupported method $method'),
      }
          .timeout(timeout);
    } on ArgumentError {
      rethrow;
    } on Exception catch (error) {
      throw NetworkException(
        'Cannot reach the server. Check your connection and try again.\n($error)',
      );
    }

    final text = response.body;
    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // A successful response should be JSON (or empty, e.g. 204). Anything
      // else means the request did not reach the API — typically a host that
      // served the SPA fallback (HTML) because no /api proxy is configured.
      if (text.isNotEmpty && decoded == null) {
        throw ApiException(
          response.statusCode,
          'invalid_response',
          'The server returned an unexpected response. Please try again.',
        );
      }
      return decoded;
    }

    // A 401 on a request that carried a token means the session has expired or
    // been revoked. Alert the app before the error propagates so it can sign
    // out; the request still throws so the caller sees the failure.
    if (response.statusCode == 401 && token != null && token.isNotEmpty) {
      onUnauthorized?.call();
    }

    if (decoded is Map<String, dynamic> && decoded['error'] is Map<String, dynamic>) {
      final error = decoded['error'] as Map<String, dynamic>;
      final rawDetails = error['details'];
      throw ApiException(
        response.statusCode,
        error['code'] as String? ?? 'unknown',
        error['message'] as String? ?? 'Something went wrong.',
        details: rawDetails is List
            ? rawDetails
                .whereType<Map<String, dynamic>>()
                .map(FieldError.fromJson)
                .toList()
            : null,
      );
    }

    throw ApiException(
      response.statusCode,
      'http_${response.statusCode}',
      'Something went wrong (HTTP ${response.statusCode}).',
    );
  }

  void close() => _client.close();
}
