import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

void main() {
  const base = 'http://localhost:4000/api/v1';

  late List<http.Request> log;

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  final sessionBody = {
    'token_type': 'Bearer',
    'access_token': 'access-token-1',
    'expires_in': 900,
    'expires_at': '2030-01-01T00:00:00.000Z',
    'refresh_token': 'refresh-token-1',
    'refresh_expires_at': '2030-02-01T00:00:00.000Z',
    'user': {
      'id': 'user-123',
      'fullName': 'Ada Lovelace',
      'email': 'ada@example.com',
      'phone': null,
      'role': 'business',
      'emailVerified': false,
      'phoneVerified': false,
    },
  };

  AuthRepository buildRepo(Future<http.Response> Function(http.Request) handler) {
    final client = MockClient((request) {
      log.add(request);
      return handler(request);
    });
    return AuthRepository(
      ApiClient(baseUrl: base, client: client),
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
  }

  setUp(() async {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('sign in', () {
    test('posts the identifier and stores the session', () async {
      final repo = buildRepo((_) async => json(sessionBody));

      final session = await repo.signIn(
        identifier: 'ada@example.com',
        password: 'Str0ngPass!23',
      );

      expect(session.user.id, 'user-123');
      expect(session.accessToken, 'access-token-1');
      expect(repo.isSignedIn, isTrue);
      expect(repo.currentUserId, 'user-123');

      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['identifier'], 'ada@example.com');
      expect(body['password'], 'Str0ngPass!23');
    });

    test('persists the session so a relaunch stays signed in', () async {
      final repo = buildRepo((_) async => json(sessionBody));
      await repo.signIn(identifier: 'ada@example.com', password: 'x');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessionStore.key), isNotNull);
    });
  });

  group('sign up', () {
    test('sends the account type selected on the first screen', () async {
      final repo = buildRepo((_) async => json(sessionBody, status: 201));

      await repo.signUp(
        fullName: 'Rider One',
        email: 'rider@example.com',
        password: 'Str0ngPass!23',
        phone: '+2348031234567',
        role: 'rider',
      );

      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['role'], 'rider');
      expect(body['phone'], '+2348031234567');
      expect(body['full_name'], 'Rider One');
    });

    test('omits the phone key when none was collected', () async {
      final repo = buildRepo((_) async => json(sessionBody, status: 201));

      await repo.signUp(
        fullName: 'Owner',
        email: 'owner@example.com',
        password: 'Str0ngPass!23',
      );

      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body.containsKey('phone'), isFalse);
    });
  });

  group('error handling', () {
    test('surfaces the server message and per-field details', () async {
      final repo = buildRepo(
        (_) async => json({
          'error': {
            'code': 'validation_failed',
            'message': 'Some fields need your attention.',
            'details': [
              {'field': 'password', 'message': 'Password must be at least 8 characters.'},
            ],
          }
        }, status: 422),
      );

      await expectLater(
        repo.signIn(identifier: 'ada@example.com', password: 'short'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message',
                  'Some fields need your attention.')
              .having((e) => e.fieldError('password'), 'password error',
                  'Password must be at least 8 characters.'),
        ),
      );
    });

    test('marks 401 responses as unauthorized', () async {
      final repo = buildRepo(
        (_) async => json({
          'error': {'code': 'unauthorized', 'message': 'Incorrect email/phone or password.'}
        }, status: 401),
      );

      await expectLater(
        repo.signIn(identifier: 'ada@example.com', password: 'wrong'),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });

    test('turns a transport failure into NetworkException', () async {
      final repo = buildRepo((_) async => throw const SocketLikeException());

      await expectLater(
        repo.signIn(identifier: 'ada@example.com', password: 'x'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('session restore', () {
    test('returns false and stays signed out when nothing was stored', () async {
      final repo = buildRepo((_) async => json(sessionBody));
      expect(await repo.restore(), isFalse);
      expect(repo.isSignedIn, isFalse);
    });

    test('validates a stored session against the server', () async {
      SharedPreferences.setMockInitialValues({
        SessionStore.key: jsonEncode(sessionBody),
      });

      final repo = buildRepo((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return json({
            ...sessionBody,
            'access_token': 'access-token-2',
            'refresh_token': 'refresh-token-2',
          });
        }
        return json(sessionBody);
      });

      expect(await repo.restore(), isTrue);
      expect(repo.currentUserId, 'user-123');
      expect(repo.session!.accessToken, 'access-token-2');
    });

    test('signs the user out when the stored token was revoked', () async {
      SharedPreferences.setMockInitialValues({
        SessionStore.key: jsonEncode(sessionBody),
      });

      final repo = buildRepo(
        (_) async => json({
          'error': {'code': 'unauthorized', 'message': 'Invalid refresh token.'}
        }, status: 401),
      );

      expect(await repo.restore(), isFalse);
      expect(repo.isSignedIn, isFalse);
    });

    test('keeps the cached session when the server is unreachable', () async {
      SharedPreferences.setMockInitialValues({
        SessionStore.key: jsonEncode(sessionBody),
      });

      final repo = buildRepo((_) async => throw const SocketLikeException());

      expect(await repo.restore(), isTrue, reason: 'offline tolerance');
      expect(repo.isSignedIn, isTrue);
    });
  });

  group('one-time codes', () {
    test('surfaces the development code and masked destination', () async {
      final repo = buildRepo(
        (_) async => json({
          'status': 'success',
          'challenge_id': 'challenge-1',
          'channel': 'sms',
          'destination': '*********4567',
          'expires_at': '2030-01-01T00:00:00.000Z',
          'dev_code': '123456',
        }, status: 201),
      );

      final challenge = await repo.requestOtp(identifier: '+2348031234567');

      expect(challenge, isNotNull);
      expect(challenge!.challengeId, 'challenge-1');
      expect(challenge.devCode, '123456');
      expect(challenge.destination, '*********4567');
      expect(challenge.channel, 'sms');
    });

    test('signs in once the code is verified', () async {
      final repo = buildRepo(
        (_) async => json(sessionBody),
      );

      final session = await repo.verifyOtp(
        challengeId: 'challenge-1',
        code: '123456',
      );

      expect(session.user.id, 'user-123');
      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['challenge_id'], 'challenge-1');
      expect(body['code'], '123456');
    });

    test('returns null for an unknown account instead of throwing', () async {
      final repo = buildRepo(
        (_) async => json({'status': 'success'}, status: 201),
      );

      expect(
        await repo.requestOtp(identifier: 'nobody@example.com'),
        isNull,
      );
    });
  });

  group('password reset', () {
    test('returns the reset challenge for a known account', () async {
      final repo = buildRepo(
        (_) async => json({
          'status': 'success',
          'challenge_id': 'reset-1',
          'channel': 'email',
          'destination': 'a***@example.com',
          'expires_at': '2030-01-01T00:00:00.000Z',
          'dev_code': '654321',
        }, status: 201),
      );

      final challenge = await repo.requestPasswordReset(
        identifier: 'ada@example.com',
      );

      expect(challenge!.challengeId, 'reset-1');
      expect(challenge.devCode, '654321');

      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['identifier'], 'ada@example.com');
      expect(log.single.url.path, endsWith('/auth/request-password-reset'));
    });

    test('returns null for an unknown account to avoid account probing', () async {
      final repo = buildRepo(
        (_) async => json({'status': 'success'}, status: 201),
      );

      expect(
        await repo.requestPasswordReset(identifier: 'nobody@example.com'),
        isNull,
      );
    });

    test('posts the code and new password together', () async {
      final repo = buildRepo((_) async => json({'status': 'success'}));

      await repo.resetPassword(
        challengeId: 'reset-1',
        code: '654321',
        newPassword: 'N3wStr0ng!',
      );

      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['challenge_id'], 'reset-1');
      expect(body['code'], '654321');
      expect(body['new_password'], 'N3wStr0ng!');
      expect(log.single.url.path, endsWith('/auth/reset-password'));
    });

    test('does not sign the user in when the reset is rejected', () async {
      final repo = buildRepo(
        (_) async => json({
          'error': {'code': 'bad_request', 'message': 'Incorrect verification code.'}
        }, status: 400),
      );

      await expectLater(
        repo.resetPassword(
          challengeId: 'reset-1',
          code: '000000',
          newPassword: 'N3wStr0ng!',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repo.isSignedIn, isFalse);
    });
  });

  group('sign out', () {
    test('clears the session even if the server call fails', () async {
      final repo = buildRepo((_) async => json(sessionBody));
      await repo.signIn(identifier: 'ada@example.com', password: 'x');

      final offline = AuthRepository(
        ApiClient(
          baseUrl: base,
          client: MockClient((_) async => throw const SocketLikeException()),
        ),
      );
      await offline.signOut();
      expect(offline.isSignedIn, isFalse);
      expect(repo.isSignedIn, isTrue);
    });

    test('removes the persisted session', () async {
      final repo = buildRepo((_) async => json(sessionBody));
      await repo.signIn(identifier: 'ada@example.com', password: 'x');
      await repo.signOut();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SessionStore.key), isNull);
      expect(repo.isSignedIn, isFalse);
    });
  });
}

/// Stand-in for a transport-level failure.
class SocketLikeException implements Exception {
  const SocketLikeException();

  @override
  String toString() => 'connection failed';
}
