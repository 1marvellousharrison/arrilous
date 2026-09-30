import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/features/auth/reset_password_screen.dart';
import 'package:dee_app/features/auth/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// [OtpCodeInput] caps each box at one character, so the code has to be typed
/// box by box rather than pasted in one go.
Future<void> enterCode(WidgetTester tester, String code) async {
  for (var i = 0; i < code.length; i++) {
    await tester.enterText(find.byType(TextField).at(i), code[i]);
  }
}

void main() {
  const base = 'http://localhost:4000/api/v1';

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

  late List<http.Request> log;

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

  http.Response json(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  setUp(() async {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('sign-up form', () {
    for (final role in ['business', 'logistics_partner', 'rider']) {
      testWidgets('asks for an email when signing up as $role', (tester) async {
        final repo = buildRepo((_) async => json(sessionBody, status: 201));

        await tester.pumpWidget(
          MaterialApp(
            home: SignUpScreen(
              auth: repo,
              initialRole: role,
              onSignedIn: (_) {},
              onBack: () {},
            ),
          ),
        );

        expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'Ada Lovelace');
        await tester.enterText(fields.at(1), 'ada@example.com');
        await tester.enterText(fields.at(3), 'Str0ngPass!23');

        final button = find.text('Create account');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        final body = jsonDecode(log.single.body) as Map<String, dynamic>;
        expect(body['email'], 'ada@example.com');
        expect(body['role'], role);
      });
    }

    testWidgets('blocks submission when the email is empty', (tester) async {
      final repo = buildRepo((_) async => json(sessionBody, status: 201));

      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(
            auth: repo,
            initialRole: 'rider',
            onSignedIn: (_) {},
            onBack: () {},
          ),
        ),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Rider One');
      await tester.enterText(fields.at(3), 'Str0ngPass!23');

      final button = find.text('Create account');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(log, isEmpty);
      expect(find.text('Email is required.'), findsOneWidget);
    });
  });

  group('reset password form', () {
    testWidgets('requests a code then posts the new password', (tester) async {
      final repo = buildRepo((request) async {
        if (request.url.path.endsWith('/auth/request-password-reset')) {
          return json({
            'status': 'success',
            'challenge_id': 'reset-1',
            'channel': 'email',
            'destination': 'a***@example.com',
            'expires_at': '2030-01-01T00:00:00.000Z',
            'dev_code': '654321',
          }, status: 201);
        }
        return json({'status': 'success'});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ResetPasswordScreen(auth: repo, initialIdentifier: 'ada@example.com'),
        ),
      );

      final send = find.text('Send reset code');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.text('Create a new password'), findsOneWidget);
      expect(find.text('Development mode — your code is 654321'), findsOneWidget);

      final fields = find.byType(TextFormField);
      await enterCode(tester, '654321');
      await tester.enterText(fields.at(0), 'N3wStr0ng!');
      await tester.enterText(fields.at(1), 'N3wStr0ng!');

      final submit = find.text('Reset password');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(log.length, 2);
      final body = jsonDecode(log.last.body) as Map<String, dynamic>;
      expect(body['challenge_id'], 'reset-1');
      expect(body['new_password'], 'N3wStr0ng!');
    });

    testWidgets('does not reveal whether an account exists', (tester) async {
      final repo = buildRepo((_) async => json({'status': 'success'}, status: 201));

      await tester.pumpWidget(MaterialApp(home: ResetPasswordScreen(auth: repo)));

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'nobody@example.com');

      final send = find.text('Send reset code');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.textContaining('If an account exists'), findsOneWidget);
      expect(find.text('Create a new password'), findsNothing);
    });

    testWidgets('rejects mismatched passwords before calling the API', (tester) async {
      final repo = buildRepo((request) async {
        if (request.url.path.endsWith('/auth/request-password-reset')) {
          return json({
            'status': 'success',
            'challenge_id': 'reset-1',
            'channel': 'email',
            'destination': 'a***@example.com',
            'dev_code': '654321',
          }, status: 201);
        }
        return json({'status': 'success'});
      });

      await tester.pumpWidget(MaterialApp(home: ResetPasswordScreen(auth: repo)));

      await tester.enterText(find.byType(TextFormField).at(0), 'ada@example.com');
      final send = find.text('Send reset code');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await enterCode(tester, '654321');
      await tester.enterText(fields.at(0), 'N3wStr0ng!');
      await tester.enterText(fields.at(1), 'Different1!');

      final submit = find.text('Reset password');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(log.length, 1, reason: 'the reset call must not be sent');
      expect(find.text('The two passwords do not match.'), findsOneWidget);
    });
  });
}
