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

  Map<String, Object?> alertBody({
    bool unread = true,
    String id = 'note-1',
    String title = 'Order draft needs details',
    String? createdAt = '2026-10-01T09:00:00Z',
    String? actorName,
  }) =>
      {
        'id': id,
        'type': 'order_import_incomplete',
        'title': title,
        'message': 'Missing: delivery fee.',
        'severity': 'warning',
        'orderImportId': 'imp-1',
        'transactionId': null,
        'actorName': actorName,
        'readAt': unread ? null : '2026-10-01T10:00:00Z',
        'createdAt': createdAt,
      };

  Future<({AppNotificationsRepository app, LogisticsRepository logistics})>
      setUpRepos(
    List<http.Request> log, {
    required bool unread,
    List<Map<String, Object?>>? alerts,
  }) async {
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
          'notifications': alerts ?? [alertBody(unread: unread)],
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

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Order draft needs details'), findsOneWidget);
    expect(find.text('Missing: delivery fee.'), findsOneWidget);

    await tester.tap(find.text('Order draft needs details'));
    await tester.pumpAndSettle();

    final patch = log.firstWhere((request) => request.method == 'PATCH');
    expect(patch.url.path, endsWith('/notifications/note-1/read'));
  });

  testWidgets('range chips narrow the history and rows name the staff member', (tester) async {
    final log = <http.Request>[];
    final now = DateTime.now().toUtc();
    final repos = await setUpRepos(
      log,
      unread: false,
      alerts: [
        alertBody(
          unread: false,
          id: 'note-today',
          title: 'Sale recorded today',
          createdAt: now.toIso8601String(),
          actorName: 'Musa Bello',
        ),
        alertBody(
          unread: false,
          id: 'note-old',
          title: 'Old restock',
          createdAt: '2024-03-01T09:00:00Z',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          logistics: repos.logistics,
          appNotifications: repos.app,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // "All" is the default: both the fresh alert and the old one are listed.
    expect(find.text('Sale recorded today'), findsOneWidget);
    expect(find.text('Old restock'), findsOneWidget);
    expect(find.text('by Musa Bello'), findsOneWidget);

    await tester.tap(find.text('7 days').last);
    await tester.pumpAndSettle();

    expect(find.text('Sale recorded today'), findsOneWidget);
    expect(find.text('Old restock'), findsNothing,
        reason: 'the old alert is outside the selected window');
  });

  test('load reads the unread breakdown and the low-stock products', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      if (request.url.path == '/api/v1/notifications') {
        return json({
          'notifications': <Object>[],
          'unreadCount': 3,
          'counts': {
            'unread': 3,
            'lowStock': 2,
            'outOfStock': 1,
            'errors': 1,
            'warnings': 2,
          },
          'lowStock': {
            'count': 2,
            'outOfStock': 1,
            'products': [
              {'id': 'p1', 'name': 'Milk', 'stockQuantity': 0, 'severity': 'error'},
              {'id': 'p2', 'name': 'Sugar', 'stockQuantity': 4, 'severity': 'warning'},
            ],
          },
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
    final app = AppNotificationsRepository(
      api: api,
      token: auth.session?.accessToken,
    );

    await app.load();

    expect(app.unreadCount, 3);
    expect(app.lowStockCount, 2);
    expect(app.outOfStockCount, 1);
    expect(app.errorCount, 1);
    expect(app.hasLowStock, isTrue);
    expect(app.lowStockProducts.map((product) => product.name), ['Milk', 'Sugar']);
    expect(app.lowStockProducts.first.isOutOfStock, isTrue);
  });
}
