import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/app_notifications_repository.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/logistics_repository.dart';
import 'package:dee_app/features/logistics/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

void main() {
  const base = 'http://localhost:4000/api/v1';

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  final sessionBody = {
    'access_token': 'access-token-1',
    'refresh_token': 'refresh-token-1',
    'user': {
      'id': 'user-123',
      'fullName': 'Ada Lovelace',
      'email': 'ada@example.com',
      'role': 'business',
    },
  };

  Map<String, Object?> alertBody({bool unread = true}) => {
        'id': 'note-1',
        'type': 'order_import_incomplete',
        'title': 'Order draft needs details',
        'message': 'Missing: delivery fee.',
        'severity': 'warning',
        'orderImportId': 'imp-1',
        'transactionId': null,
        'readAt': unread ? null : '2026-10-01T10:00:00Z',
        'createdAt': '2026-10-01T09:00:00Z',
      };

  Future<({AppNotificationsRepository app, LogisticsRepository logistics})>
      setUpRepos(List<http.Request> log, {required bool unread}) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      log.add(request);
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      if (request.url.path.endsWith('/notifications/note-1/read')) {
        return json({'ok': true});
      }
      if (request.url.path.endsWith('/logistics/notifications')) {
        return json({'notifications': <Object>[], 'unreadCount': 0});
      }
      if (request.url.path.endsWith('/notifications')) {
        return json({
          'notifications': [alertBody(unread: unread)],
          'unreadCount': unread ? 1 : 0,
        });
      }
      return json(<String, Object>{});
    });
    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');
    return (
      app: AppNotificationsRepository(
        api: api,
        token: auth.session?.accessToken,
      ),
      logistics: LogisticsRepository(api, auth),
    );
  }

  test('markRead targets the notification it was given', () async {
    final log = <http.Request>[];
    final repos = await setUpRepos(log, unread: true);

    await repos.app.markRead('note-1');

    final patch = log.firstWhere((request) => request.method == 'PATCH');
    expect(patch.url.path, endsWith('/notifications/note-1/read'));
  });

  testWidgets('the inbox shows app alerts and marks one read on tap', (tester) async {
    final log = <http.Request>[];
    final repos = await setUpRepos(log, unread: true);

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          logistics: repos.logistics,
          appNotifications: repos.app,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Order alerts'), findsOneWidget);
    expect(find.text('Order draft needs details'), findsOneWidget);
    expect(find.text('Missing: delivery fee.'), findsOneWidget);

    await tester.tap(find.text('Order draft needs details'));
    await tester.pumpAndSettle();

    final patch = log.firstWhere((request) => request.method == 'PATCH');
    expect(patch.url.path, endsWith('/notifications/note-1/read'));
  });
}
