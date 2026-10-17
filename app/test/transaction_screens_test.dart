import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:dee_app/core/state/dashboard_repository.dart';
import 'package:dee_app/core/state/transaction_repository.dart';
import 'package:dee_app/core/theme/app_theme.dart';
import 'package:dee_app/features/home/dashboard_screen.dart';
import 'package:dee_app/features/transactions/new_transaction_screen.dart';
import 'package:dee_app/features/transactions/transaction_detail_screen.dart';
import 'package:dee_app/features/transactions/transactions_screen.dart';
import 'package:dee_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// Phases 9-12 screens.
void main() {
  const base = 'http://localhost:4000/api/v1';

  late List<http.Request> log;

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

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

  Map<String, dynamic> transactionJson({
    String id = 'txn-1',
    String number = 'TXN-2026-00001',
    String orderStatus = 'pending',
    String paymentStatus = 'unpaid',
    String deliveryStatus = 'not_required',
    String completionStatus = 'open',
    bool deliveryRequired = false,
    int total = 1_500_000,
  }) =>
      {
        'id': id,
        'businessId': 'business-1',
        'customerId': null,
        'transactionNumber': number,
        'source': 'manual',
        'subtotalKobo': total,
        'discountKobo': 0,
        'deliveryFeeKobo': 0,
        'totalKobo': total,
        'notes': null,
        'deliveryAddress': null,
        'deliveryRequired': deliveryRequired,
        'orderStatus': orderStatus,
        'paymentStatus': paymentStatus,
        'deliveryStatus': deliveryStatus,
        'completionStatus': completionStatus,
        'createdAt': '2026-10-01T09:00:00.000Z',
        'updatedAt': '2026-10-01T09:00:00.000Z',
      };

  Future<
      ({
        BusinessRepository business,
        CatalogRepository catalog,
        CustomerRepository customers,
        TransactionRepository transactions,
        DashboardRepository dashboard,
      })> signInOwner(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final client = MockClient((request) {
      log.add(request);
      if (request.url.path.endsWith('/auth/login')) {
        return Future.value(json(sessionBody));
      }
      return handler(request);
    });
    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');

    return (
      business: BusinessRepository(api, auth),
      catalog: CatalogRepository(api, auth),
      customers: CustomerRepository(api, auth),
      transactions: TransactionRepository(api, auth),
      dashboard: DashboardRepository(api, auth),
    );
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  setUp(() {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('dashboard', () {
    testWidgets('shows real totals rather than placeholders', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.contains('/dashboard/summary')) {
          return json({
            'totals': {
              'transactionCount': 12,
              'grossSalesKobo': 4_500_000,
              'collectedKobo': 3_000_000,
              'outstandingKobo': 1_500_000,
            },
            'counts': {
              'pendingOrder': 2,
              'pendingPayment': 1,
              'awaitingDelivery': 1,
              'inTransit': 0,
              'completed': 8,
              'failed': 0,
              'cancelled': 1,
            },
            // A distinct amount, so each assertion below identifies one figure rather than
            // matching an unrelated one.
            'recent': [transactionJson(total: 750_000)],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          dashboard: repos.dashboard,
          business: repos.business,
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('₦45,000.00'), findsOneWidget, reason: 'total sales');
      expect(find.text('₦30,000.00'), findsOneWidget, reason: 'collected');
      expect(find.text('₦15,000.00'), findsOneWidget, reason: 'outstanding');
      expect(find.textContaining('across 12 transactions'), findsOneWidget);
      expect(find.text('TXN-2026-00001'), findsOneWidget);
      expect(find.text('₦7,500.00'), findsOneWidget, reason: 'the recent sale');
    });

    /// The home page is a preview, not the archive: seven recent sales, then
    /// the button into the full list. Nothing beyond the seventh is rendered,
    /// so the page stays scannable.
    testWidgets('previews at most seven recent sales before the see-all button', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.contains('/dashboard/summary')) {
          return json({
            'totals': {
              'transactionCount': 9,
              'grossSalesKobo': 9_000_000,
              'collectedKobo': 0,
              'outstandingKobo': 9_000_000,
            },
            'counts': {
              'pendingOrder': 9,
              'pendingPayment': 0,
              'awaitingDelivery': 0,
              'inTransit': 0,
              'completed': 0,
              'failed': 0,
              'cancelled': 0,
            },
            'recent': [
              for (var index = 1; index <= 9; index++)
                transactionJson(
                  id: 'txn-$index',
                  number: 'TXN-2026-${index.toString().padLeft(5, '0')}',
                ),
            ],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          dashboard: repos.dashboard,
          business: repos.business,
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
      ));
      await tester.pumpAndSettle();

      for (var index = 1; index <= 7; index++) {
        expect(
          find.text('TXN-2026-${index.toString().padLeft(5, '0')}'),
          findsOneWidget,
          reason: 'the first seven recent sales are previewed',
        );
      }
      expect(find.text('TXN-2026-00008'), findsNothing, reason: 'beyond the cap nothing is rendered');
      expect(find.text('TXN-2026-00009'), findsNothing);
      expect(find.text('See all transactions'), findsOneWidget, reason: 'the full list stays reachable');
    });

    testWidgets('invites the first sale when nothing has been recorded',
        (tester) async {
      useTallSurface(tester);
      var asked = false;
      final repos = await signInOwner((request) async {
        if (request.url.path.contains('/dashboard/summary')) {
          return json({
            'totals': {
              'transactionCount': 0,
              'grossSalesKobo': 0,
              'collectedKobo': 0,
              'outstandingKobo': 0,
            },
            'counts': {
              'pendingOrder': 0,
              'pendingPayment': 0,
              'awaitingDelivery': 0,
              'inTransit': 0,
              'completed': 0,
              'failed': 0,
              'cancelled': 0,
            },
            'recent': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          dashboard: repos.dashboard,
          business: repos.business,
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onOpenTransaction: (_) {},
          onManualEntry: () => asked = true,
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No sales recorded yet.'), findsOneWidget);
      await tapText(tester, 'Record your first sale');
      expect(asked, isTrue);
    });

    testWidgets('surfaces a dashboard failure instead of showing zeros',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.contains('/dashboard/summary')) {
          return json(
            {'error': {'code': 'internal', 'message': 'Could not load figures.'}},
            status: 500,
          );
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          dashboard: repos.dashboard,
          business: repos.business,
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Could not load figures.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    /// The "Your business" space is an auto-advancing reel: it opens on the
    /// shop's name on its ribbon, then walks every active product — one per
    /// slide, the photo filling most of it beside the name and the count left —
    /// slipping the full-bleed logo in between so the products never run in a row.
    testWidgets('features the shop on an auto-advancing showcase slide', (tester) async {
      useTallSurface(tester);
      const png =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business')) {
          return json({
            'business': {
              'id': 'business-1',
              'ownerUserId': 'user-123',
              'businessName': 'Ada Provisions',
              'businessCategory': 'Groceries',
              'businessDescription': null,
              'phone': '+2348012345678',
              'email': null,
              'logoUrl': png,
              'location': {
                'id': 'loc-1',
                'businessId': 'business-1',
                'address': '12 Allen Avenue',
                'city': 'Ikeja',
                'state': 'Lagos',
                'country': 'Nigeria',
              },
            },
          });
        }
        if (request.url.path.endsWith('/products')) {
          return json({
            'products': [
              {
                'id': 'p1',
                'businessId': 'business-1',
                'name': 'Rice 50kg',
                'priceKobo': 2_500_000,
                'stockQuantity': 4,
                'active': true,
                'category': 'Grains',
                'imageUrl': png,
              },
              {
                'id': 'p2',
                'businessId': 'business-1',
                'name': 'Palm Oil',
                'priceKobo': 180_000,
                'stockQuantity': 20,
                'active': true,
                'category': 'Oils',
              },
              {
                'id': 'p3',
                'businessId': 'business-1',
                'name': 'Detergent',
                'priceKobo': 90_000,
                'stockQuantity': 0,
                'active': true,
                'category': 'Cleaning',
              },
            ],
          });
        }
        return json(<String, Object>{});
      });
      await repos.business.load();

      await tester.pumpWidget(MaterialApp(
        home: DashboardScreen(
          dashboard: repos.dashboard,
          business: repos.business,
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // It opens on the shop's name riding the ribbon, sector underneath.
      expect(find.byType(PageView), findsOneWidget, reason: 'the space is a slide');
      expect(find.text('WELCOME TO'), findsOneWidget);
      expect(find.text('ADA PROVISIONS'), findsOneWidget);
      expect(find.text('GROCERIES'), findsOneWidget);

      // Rice has a photo, so it fills most of the slide and no letter shows.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Rice 50kg'), findsOneWidget);
      expect(find.text('left'), findsOneWidget);
      expect(find.text('R'), findsNothing, reason: 'a photo leaves no lettered fallback');

      // Palm Oil has none, so its initial stands in.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Palm Oil'), findsOneWidget);
      expect(find.text('left'), findsOneWidget);
      expect(find.text('P'), findsOneWidget);

      // The logo is slipped in between the products, filling the whole slide.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Palm Oil'), findsNothing, reason: 'the logo takes a slide of its own');
      expect(find.byType(Image), findsWidgets);

      // A product with nothing on the shelf says so.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Detergent'), findsOneWidget);
      expect(find.text('OUT'), findsOneWidget);
      expect(find.text('of stock'), findsOneWidget);
    });

    testWidgets('dresses the reel for light mode even when the app is dark',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business')) {
          return json({
            'business': {
              'id': 'business-1',
              'ownerUserId': 'user-123',
              'businessName': 'Ada Provisions',
              'businessCategory': 'Groceries',
              'businessDescription': null,
              'phone': '+2348012345678',
              'email': null,
              'logoUrl': null,
              'location': {
                'id': 'loc-1',
                'businessId': 'business-1',
                'address': '12 Allen Avenue',
                'city': 'Ikeja',
                'state': 'Lagos',
                'country': 'Nigeria',
              },
            },
          });
        }
        if (request.url.path.endsWith('/products')) {
          return json({'products': <Object>[]});
        }
        return json(<String, Object>{});
      });
      await repos.business.load();

      await tester.pumpWidget(MaterialApp(
        theme: buildDarkTheme(),
        home: DashboardScreen(
          dashboard: repos.dashboard,
          business: repos.business,
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // The reel keeps its light-mode ink even though the app is dark.
      final welcome = tester.widget<Text>(find.text('WELCOME TO'));
      expect(welcome.style?.color, AppColors.lightText.withValues(alpha: 0.5));
    });
  });

  group('transaction list', () {
    testWidgets('shows an empty state that leads to the first sale',
        (tester) async {
      useTallSurface(tester);
      var asked = false;
      final repos = await signInOwner(
        (_) async => json({'transactions': <Object>[]}),
      );

      await tester.pumpWidget(MaterialApp(
        home: TransactionsScreen(
          transactions: repos.transactions,
          onOpen: (_) {},
          onCreate: () => asked = true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No transactions yet'), findsOneWidget);
      await tapText(tester, 'New transaction');
      expect(asked, isTrue);
    });

    testWidgets('explains an empty result caused by filters', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner(
        (_) async => json({'transactions': <Object>[]}),
      );
      await repos.transactions.setFilter(field: 'payment', value: 'refunded');

      await tester.pumpWidget(MaterialApp(
        home: TransactionsScreen(
          transactions: repos.transactions,
          onOpen: (_) {},
          onCreate: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No matching transactions'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Payment: Refunded'), findsOneWidget);
    });

    testWidgets('lists a sale with its money and statuses', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({
            'transactions': [
              transactionJson(
                orderStatus: 'confirmed',
                paymentStatus: 'paid',
                completionStatus: 'completed',
                total: 2_500_000,
              ),
            ],
          }));

      await tester.pumpWidget(MaterialApp(
        home: TransactionsScreen(
          transactions: repos.transactions,
          onOpen: (_) {},
          onCreate: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Walk-in customer'), findsOneWidget);
      // The card renders the number and the date as one line.
      expect(find.textContaining('TXN-2026-00001'), findsOneWidget);
      expect(find.text('₦25,000.00'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('opens a transaction when a row is tapped', (tester) async {
      useTallSurface(tester);
      String? opened;
      final repos = await signInOwner(
        (_) async => json({'transactions': [transactionJson()]}),
      );

      await tester.pumpWidget(MaterialApp(
        home: TransactionsScreen(
          transactions: repos.transactions,
          onOpen: (t) => opened = t.id,
          onCreate: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // Tapping anywhere on the card opens it.
      await tapText(tester, 'Walk-in customer');
      expect(opened, 'txn-1');
    });
  });

  group('new transaction', () {
    testWidgets('will not record a sale with nothing in it', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json(<String, Object>{}));

      await tester.pumpWidget(MaterialApp(
        home: NewTransactionScreen(
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onCreated: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Add at least one product.'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: 'the button stays disabled');
    });

    testWidgets('adds a catalog product and posts the sale', (tester) async {
      useTallSurface(tester);
      const png =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'transaction': transactionJson()}, status: 201);
        }
        if (request.url.path.contains('/transactions/txn-1')) {
          return json({
            'transaction': {
              ...transactionJson(),
              'items': [
                {
                  'id': 'item-1',
                  'transactionId': 'txn-1',
                  'productId': 'product-1',
                  'name': 'Black Shirt',
                  'quantity': 1,
                  'unitPriceKobo': 1_500_000,
                  'subtotalKobo': 1_500_000,
                },
              ],
            },
            'customer': null,
            'history': <Object>[],
          });
        }
        if (request.url.path.endsWith('/products')) {
          return json({
            'products': [
              {
                'id': 'product-1',
                'businessId': 'business-1',
                'name': 'Black Shirt',
                'priceKobo': 1_500_000,
                'stockQuantity': 4,
                'active': true,
                'imageUrl': png,
              },
            ],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: NewTransactionScreen(
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
          onCreated: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      await tapText(tester, 'Add product');
      await tester.pumpAndSettle();

      // The picker leads each product with its picture, not just its name.
      expect(find.byType(ProductThumb), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('B'), findsNothing, reason: 'the photo replaces the letter tile');

      await tapText(tester, 'Black Shirt');
      await tester.pumpAndSettle();

      expect(find.text('₦15,000.00'), findsWidgets, reason: 'line total and charge total');

      await tapText(tester, 'Record sale • ₦15,000.00');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/transactions'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      final item = (body['items'] as List).first as Map<String, dynamic>;
      expect(item['product_id'], 'product-1');
      expect(body.containsKey('total_kobo'), isFalse, reason: 'the server owns the total');
    });

    testWidgets('records a one-off line with its own price', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'transaction': transactionJson()}, status: 201);
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: NewTransactionScreen(
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
        ),
      ));
      await tester.pumpAndSettle();

      await tapText(tester, 'Add product');
      await tester.pumpAndSettle();
      await tapText(tester, 'One-off');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Singe pair');
      await tester.enterText(
        find.widgetWithText(TextField, 'Unit price'),
        '450',
      );
      await tester.pumpAndSettle();

      await tapText(tester, 'Add line');
      await tester.pumpAndSettle();
      expect(find.text('Singe pair'), findsOneWidget);

      await tapText(tester, 'Record sale • ₦450.00');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/transactions'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      final item = (body['items'] as List).first as Map<String, dynamic>;
      expect(item['name'], 'Singe pair');
      expect(item['unit_price_kobo'], 45_000);
      expect(item.containsKey('product_id'), isFalse);
    });

    testWidgets('a discount larger than the subtotal is refused before sending',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'transaction': transactionJson()}, status: 201);
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: NewTransactionScreen(
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
        ),
      ));
      await tester.pumpAndSettle();

      await tapText(tester, 'Add product');
      await tester.pumpAndSettle();
      await tapText(tester, 'One-off');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Cap');
      await tester.enterText(find.widgetWithText(TextField, 'Unit price'), '5000');
      await tester.pumpAndSettle();
      await tapText(tester, 'Add line');
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Discount'), '9000');
      await tester.pumpAndSettle();

      expect(find.text('The discount cannot be more than the items total.'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('delivery requires an address', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'transaction': transactionJson()}, status: 201);
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: NewTransactionScreen(
          transactions: repos.transactions,
          catalog: repos.catalog,
          customers: repos.customers,
        ),
      ));
      await tester.pumpAndSettle();

      await tapText(tester, 'Add product');
      await tester.pumpAndSettle();
      await tapText(tester, 'One-off');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Item name'), 'Cap');
      await tester.enterText(find.widgetWithText(TextField, 'Unit price'), '5000');
      await tester.pumpAndSettle();
      await tapText(tester, 'Add line');
      await tester.pumpAndSettle();

      await tapText(tester, 'Needs delivery');
      await tester.pumpAndSettle();

      expect(
        find.text('Add the address this order should be delivered to.'),
        findsOneWidget,
      );
    });
  });

  group('transaction detail', () {
    Future<void> pumpDetail(
      WidgetTester tester,
      TransactionRepository transactions,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: TransactionDetailScreen(
          transactions: transactions,
          transactionId: 'txn-1',
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the money, the items and the timeline', (tester) async {
      useTallSurface(tester);
      const png =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC';
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/transactions/txn-1')) {
          return json({
            'transaction': {
              ...transactionJson(),
              'subtotalKobo': 3_000_000,
              'totalKobo': 3_000_000,
              'items': [
                {
                  'id': 'item-1',
                  'transactionId': 'txn-1',
                  'productId': 'product-1',
                  'name': 'Black Shirt',
                  'quantity': 2,
                  'unitPriceKobo': 1_500_000,
                  'subtotalKobo': 3_000_000,
                  'imageUrl': png,
                },
              ],
            },
            'customer': {'id': 'c1', 'name': 'Ada Nwosu'},
            'history': [
              {
                'id': 'h1',
                'transactionId': 'txn-1',
                'statusType': 'order',
                'oldValue': null,
                'newValue': 'pending',
                'note': 'Transaction created',
                'createdAt': '2026-10-01T09:00:00.000Z',
              },
              {
                'id': 'h2',
                'transactionId': 'txn-1',
                'statusType': 'order',
                'oldValue': 'pending',
                'newValue': 'confirmed',
                'note': null,
                'createdAt': '2026-10-01T10:00:00.000Z',
              },
            ],
          });
        }
        return json({'transactions': <Object>[]});
      });

      await pumpDetail(tester, repos.transactions);

      expect(find.text('TXN-2026-00001'), findsWidgets);
      expect(find.text('₦30,000.00'), findsWidgets);
      expect(find.text('Black Shirt'), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);
      // The record keeps the picture the item was sold with.
      expect(find.byType(ProductThumb), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Ada Nwosu'), findsOneWidget);
      // The timeline reads as sentences rather than raw values.
      expect(find.text('Order set to Pending'), findsOneWidget);
      expect(find.text('Order: Pending → Confirmed'), findsOneWidget);
    });

    testWidgets('offers only the statuses that are legal now', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/transactions/txn-1')) {
          return json({
            'transaction': transactionJson(),
            'customer': null,
            'history': <Object>[],
          });
        }
        return json({'transactions': <Object>[]});
      });

      await pumpDetail(tester, repos.transactions);

      expect(find.text('Order: Confirmed'), findsOneWidget);
      expect(find.text('Order: Cancelled'), findsOneWidget);
      expect(find.text('Payment: Paid'), findsOneWidget);
      // This sale is not a delivery and payment is unpaid, so completing is not
      // reachable yet and must not be offered.
      expect(find.text('Completion: Completed'), findsNothing);
      expect(find.textContaining('Delivery:'), findsNothing);
    });

    testWidgets('a completed sale offers nothing further', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/transactions/txn-1')) {
          return json({
            'transaction': transactionJson(
              orderStatus: 'confirmed',
              paymentStatus: 'paid',
              completionStatus: 'completed',
            ),
            'customer': null,
            'history': <Object>[],
          });
        }
        return json({'transactions': <Object>[]});
      });

      await pumpDetail(tester, repos.transactions);
      expect(find.text('This transaction is complete.'), findsOneWidget);
    });

    testWidgets('a cancelled sale shows the refund as its only action',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/transactions/txn-1')) {
          return json({
            'transaction': transactionJson(
              orderStatus: 'cancelled',
              paymentStatus: 'paid',
            ),
            'customer': null,
            'history': <Object>[],
          });
        }
        return json({'transactions': <Object>[]});
      });

      await pumpDetail(tester, repos.transactions);
      expect(find.text('Payment: Refunded'), findsOneWidget);
      expect(find.text('Order: Confirmed'), findsNothing);
      expect(find.text('Completion: Completed'), findsNothing);
    });

    testWidgets('reports a transaction that cannot be loaded', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner(
        (_) async => json(
          {'error': {'code': 'not_found', 'message': 'That transaction does not exist.'}},
          status: 404,
        ),
      );

      await pumpDetail(tester, repos.transactions);
      expect(find.text('Transaction unavailable'), findsOneWidget);
      expect(find.text('That transaction does not exist.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}