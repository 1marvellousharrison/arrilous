import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/ai_repository.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:dee_app/features/home/ai_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

void main() {
  const base = 'http://localhost:4000/api/v1';
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> chatBody({required String importId}) => {
        'messages': [
          {
            'id': 'm1',
            'role': 'user',
            'messageType': 'image',
            'content': 'Uploaded a screenshot/photo for order import',
            'metadata': {'image': 'data:image/png;base64,$png'},
            'orderImportId': importId,
            'createdAt': '2026-01-01T00:00:00Z',
          },
          {
            'id': 'm2',
            'role': 'assistant',
            'messageType': 'order_draft',
            'content': 'Extracted 1 item. Review and confirm to create the order.',
            'metadata': {'incomplete': false},
            'orderImportId': importId,
            'createdAt': '2026-01-01T00:00:01Z',
          },
        ],
      };

  Map<String, dynamic> importBody({
    required String id,
    String status = 'review',
    String? transactionId,
    String? transactionNumber,
  }) => {
        'id': id,
        'status': status,
        'missingFields': <Object>[],
        'customerName': 'Ben Okafor',
        'customerPhone': '+2348037311300',
        'items': [
          {'name': 'Adidas Sneakers', 'quantity': 1, 'unit_price_kobo': 250000},
        ],
        'deliveryRequired': false,
        'deliveryAddress': null,
        'deliveryFeeKobo': null,
        'discountKobo': 0,
        'transactionId': transactionId,
        'transactionNumber': transactionNumber,
      };

  Future<AiRepository> pumpChat(
    WidgetTester tester,
    http.Client client,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');
    final ai = AiRepository(api: api, token: auth.session!.accessToken);

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatScreen(
          ai: ai,
          catalog: CatalogRepository(api, auth),
          customers: CustomerRepository(api, auth),
          onViewTransaction: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ai;
  }

  http.Response session() => json({
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
      });

  testWidgets('opens on the newest chat and searches customers, items and order drafts', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return session();
      if (request.url.path.endsWith('/ai/chat')) return json(chatBody(importId: 'imp-1'));
      if (request.url.path.endsWith('/ai/imports')) {
        return json({'imports': [importBody(id: 'imp-1')]});
      }
      return json(<String, Object>{});
    });

    final ai = await pumpChat(tester, client);
    expect(ai.imports.length, 1);

    final list = tester.widget<ListView>(find.byType(ListView).first);
    expect(list.reverse, isTrue, reason: 'the chat opens at the last message, not the first');
    expect(find.byType(TextField), findsNothing, reason: 'search stays behind an icon until opened');

    await tester.tap(find.byTooltip('Search chats'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'adidas');
    await tester.pumpAndSettle();
    expect(find.text('2 results for “adidas”'), findsOneWidget);
    expect(find.textContaining('Extracted 1 item'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'nothing-like-this');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('deletes a draft that has not become a sale', (tester) async {
    var deleted = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return session();
      if (request.method == 'DELETE' && request.url.path.endsWith('/ai/imports/imp-1')) {
        deleted = true;
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/ai/chat')) {
        return json(deleted ? {'messages': <Object>[]} : chatBody(importId: 'imp-1'));
      }
      if (request.url.path.endsWith('/ai/imports')) {
        return json({'imports': deleted ? <Object>[] : [importBody(id: 'imp-1')]});
      }
      return json(<String, Object>{});
    });

    await pumpChat(tester, client);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Draft deleted.'), findsOneWidget);
    expect(find.text('Turn a screenshot into an order'), findsOneWidget);
  });

  testWidgets('deletes a draft from the review screen too', (tester) async {
    var deleted = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return session();
      if (request.method == 'DELETE' && request.url.path.endsWith('/ai/imports/imp-1')) {
        deleted = true;
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/ai/imports/imp-1')) {
        return json({'import': importBody(id: 'imp-1'), 'customer': null});
      }
      if (request.url.path.endsWith('/ai/customers/match')) {
        return json({'customer': null, 'matchedBy': null});
      }
      if (request.url.path.endsWith('/products')) {
        return json({'products': <Object>[]});
      }
      if (request.url.path.endsWith('/ai/chat')) {
        return json(deleted ? {'messages': <Object>[]} : chatBody(importId: 'imp-1'));
      }
      if (request.url.path.endsWith('/ai/imports')) {
        return json({'imports': deleted ? <Object>[] : [importBody(id: 'imp-1')]});
      }
      return json(<String, Object>{});
    });

    await pumpChat(tester, client);

    await tester.tap(find.text('Review & confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Review order'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete draft'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this draft?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Draft deleted.'), findsOneWidget);
    expect(find.text('Turn a screenshot into an order'), findsOneWidget);
  });

  testWidgets('a created sale has no delete action', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return session();
      if (request.url.path.endsWith('/ai/chat')) return json(chatBody(importId: 'imp-1'));
      if (request.url.path.endsWith('/ai/imports')) {
        return json({
          'imports': [
            importBody(
              id: 'imp-1',
              status: 'completed',
              transactionId: 'txn-1',
              transactionNumber: 'TXN-2026-00001',
            ),
          ],
        });
      }
      return json(<String, Object>{});
    });

    await pumpChat(tester, client);

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('View sale'), findsOneWidget);
  });
}
