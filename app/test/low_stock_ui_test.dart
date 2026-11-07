import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/app_notifications_repository.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/features/products/products_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

void main() {
  const base = 'http://localhost:4000/api/v1';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
      'role': 'business',
    },
  };

  Map<String, Object?> product(
    String id,
    String name, {
    required int stock,
  }) =>
      {
        'id': id,
        'businessId': 'business-1',
        'name': name,
        'priceKobo': 100000,
        'stockQuantity': stock,
        'active': true,
        'category': 'Groceries',
      };

  Future<CatalogRepository> signedInCatalog() async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      if (request.url.path.endsWith('/products/categories')) {
        return json({
          'categories': ['Groceries'],
        });
      }
      if (request.url.path.endsWith('/products')) {
        return json({
          'products': [
            product('p1', 'Milk', stock: 0),
            product('p2', 'Sugar', stock: 4),
            product('p3', 'Rice', stock: 40),
          ],
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
    return CatalogRepository(api, auth);
  }

  testWidgets('the catalog warns first, names the products and filters to them',
      (tester) async {
    final catalog = await signedInCatalog();
    await catalog.load();
    await catalog.loadCategories();

    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(
          catalog: catalog,
          businessName: 'Ada Provisions',
          lowStockProducts: const [
            LowStockProduct(
              id: 'p1',
              name: 'Milk',
              stockQuantity: 0,
              severity: 'error',
            ),
            LowStockProduct(
              id: 'p2',
              name: 'Sugar',
              stockQuantity: 4,
              severity: 'warning',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STOCK ALERT'), findsOneWidget);
    expect(find.text('2 products need restocking'), findsOneWidget);
    expect(find.text('1 already out of stock'), findsOneWidget);
    expect(find.text('Milk (out) • Sugar (4 left)'), findsOneWidget);
    expect(find.text('Low stock (2)'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);

    // The banner is a filter as well as a warning: tapping it hides the healthy
    // rows so the owner can go straight down the shelf.
    await tester.tap(find.text('STOCK ALERT'));
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Sugar'), findsOneWidget);
    expect(find.text('Rice'), findsNothing);
  });
}
