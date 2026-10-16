import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

void main() {
  const base = 'http://localhost:4000/api/v1';

  final sessionBody = {
    'access_token': 'access-token-1',
    'refresh_token': 'refresh-token-1',
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

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  AuthRepository buildRepo(Future<http.Response> Function(http.Request) handler) {
    return AuthRepository(
      ApiClient(baseUrl: base, client: MockClient(handler)),
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
  }

  Future<void> pumpLogin(WidgetTester tester, AuthRepository repo) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          auth: repo,
          onSignedIn: (_) {},
          onCreateAccount: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('prefills the remembered identifier so only a password is needed', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthRepository.rememberedIdentifierKey: 'ada@example.com',
    });
    final repo = buildRepo((_) async => json(sessionBody));

    await pumpLogin(tester, repo);

    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue, reason: 'remember me is on by default');
  });

  testWidgets('tapping the "Remember me" label toggles the checkbox', (tester) async {
    final repo = buildRepo((_) async => json(sessionBody));
    await pumpLogin(tester, repo);

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.text('Remember me'));
    await tester.pump();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('remembering the identifier lets the next launch prefill it', (tester) async {
    final repo = buildRepo((request) async {
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      return json(<String, Object>{});
    });
    await pumpLogin(tester, repo);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ada@example.com');
    await tester.enterText(fields.at(1), 'Str0ngPass!23');

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(await repo.rememberedIdentifier(), 'ada@example.com');
  });

  testWidgets('an unticked remember me forgets the identifier on the next sign-in', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthRepository.rememberedIdentifierKey: 'old@example.com',
    });
    final repo = buildRepo((_) async => json(sessionBody));
    await pumpLogin(tester, repo);

    await tester.tap(find.text('Remember me'));
    await tester.pump();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ada@example.com');
    await tester.enterText(fields.at(1), 'Str0ngPass!23');

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(await repo.rememberedIdentifier(), isNull);
  });
}
