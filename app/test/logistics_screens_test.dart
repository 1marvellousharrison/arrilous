import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/theme/app_theme.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:dee_app/core/state/dashboard_repository.dart';
import 'package:dee_app/core/state/logistics_repository.dart';
import 'package:dee_app/core/state/transaction_repository.dart';
import 'package:dee_app/features/home/dashboard_screen.dart';
import 'package:dee_app/features/logistics/business_logistics_screen.dart';
import 'package:dee_app/features/logistics/delivery_requests_list_screen.dart';
import 'package:dee_app/features/logistics/logistics_workspace_screen.dart';
import 'package:dee_app/features/logistics/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// Integrated Build Specification v3 — the screens this phase added.
///
/// Spec 41 (business dashboard logistics strip), spec 6 (three entry options),
/// spec 42/43 (organization and rider dashboards) and spec 44 (business-facing
/// provider selection). Every assertion checks content the API actually sent,
/// so a placeholder sneaking in would fail here.
void main() {
  const base = 'http://localhost:4000/api/v1';

  late List<http.Request> log;

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> session(String role) => {
        'access_token': 'access-token-1',
        'refresh_token': 'refresh-token-1',
        'user': {
          'id': 'user-123',
          'fullName': 'Ada Lovelace',
          'email': 'ada@example.com',
          'role': role,
        },
      };

  Future<({ApiClient api, AuthRepository auth})> signInAs(
    String role,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final client = MockClient((request) async {
      log.add(request);
      if (request.url.path.endsWith('/auth/login')) return json(session(role));
      return handler(request);
    });
    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(api, SessionStore(secure: FakeUnavailableSecureStorage()));
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');
    return (api: api, auth: auth);
  }

  setUp(() {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('spec 41 — business dashboard logistics strip', () {
    testWidgets('shows the delivery workload and the nearby supply', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/dashboard/summary')) {
          return json({
            'totals': {
              'transactionCount': 3,
              'grossSalesKobo': 100000,
              'collectedKobo': 100000,
              'outstandingKobo': 0,
            },
            'counts': {
              'pendingOrder': 0,
              'pendingPayment': 0,
              'awaitingDelivery': 1,
              'inTransit': 1,
              'completed': 1,
              'failed': 0,
              'cancelled': 0,
            },
            'catalog': {'activeProducts': 4, 'customers': 2},
            'logistics': {
              'pendingRequests': 2,
              'activeDeliveries': 1,
              'deliveryFailures': 3,
              'nearbyProviders': 5,
              'nearbyRiders': 7,
            },
            'recent': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DashboardScreen(
          dashboard: DashboardRepository(session.api, session.auth),
          business: BusinessRepository(session.api, session.auth),
          transactions: TransactionRepository(session.api, session.auth),
          catalog: CatalogRepository(session.api, session.auth),
          customers: CustomerRepository(session.api, session.auth),
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Logistics'), findsOneWidget);
      expect(find.text('2'), findsWidgets, reason: 'pending requests');
      expect(find.text('5'), findsOneWidget, reason: 'nearby providers');
      expect(find.text('7'), findsOneWidget, reason: 'nearby riders');
      expect(find.text('3'), findsOneWidget, reason: 'delivery failures');
      expect(find.text('Pending requests'), findsOneWidget);
      expect(find.text('Nearby providers'), findsOneWidget);
      expect(find.text('Delivery failures'), findsOneWidget);
    });

    testWidgets('an account with no delivery activity says so rather than lying', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/dashboard/summary')) {
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
            'catalog': {'activeProducts': 0, 'customers': 0},
            'logistics': {
              'pendingRequests': 0,
              'activeDeliveries': 0,
              'deliveryFailures': 0,
              'nearbyProviders': 0,
              'nearbyRiders': 0,
            },
            'recent': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DashboardScreen(
          dashboard: DashboardRepository(session.api, session.auth),
          business: BusinessRepository(session.api, session.auth),
          transactions: TransactionRepository(session.api, session.auth),
          catalog: CatalogRepository(session.api, session.auth),
          customers: CustomerRepository(session.api, session.auth),
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No delivery activity yet.'), findsOneWidget);
      expect(find.text('0'), findsWidgets, reason: 'an empty zero is still a zero');
    });
  });

  group('spec 6 — three entry options', () {
    testWidgets('the dashboard lists all three, with only manual entry available', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/dashboard/summary')) {
          return json({
            'totals': {
              'transactionCount': 1,
              'grossSalesKobo': 100,
              'collectedKobo': 100,
              'outstandingKobo': 0,
            },
            'counts': {
              'pendingOrder': 0,
              'pendingPayment': 0,
              'awaitingDelivery': 0,
              'inTransit': 0,
              'completed': 1,
              'failed': 0,
              'cancelled': 0,
            },
            'catalog': {'activeProducts': 1, 'customers': 1},
            'logistics': {
              'pendingRequests': 0,
              'activeDeliveries': 0,
              'deliveryFailures': 0,
              'nearbyProviders': 0,
              'nearbyRiders': 0,
            },
            'recent': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DashboardScreen(
          dashboard: DashboardRepository(session.api, session.auth),
          business: BusinessRepository(session.api, session.auth),
          transactions: TransactionRepository(session.api, session.auth),
          catalog: CatalogRepository(session.api, session.auth),
          customers: CustomerRepository(session.api, session.auth),
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Manual Entry'), findsOneWidget);
      expect(find.text('WhatsApp AI'), findsOneWidget, reason: 'visible but inactive');
      expect(find.text('Screenshot / Photo'), findsOneWidget, reason: 'visible but inactive');
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Coming soon'), findsNWidgets(2));
    });

    testWidgets('the inactive methods explain themselves instead of failing silently', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/dashboard/summary')) {
          return json({
            'totals': {
              'transactionCount': 1,
              'grossSalesKobo': 100,
              'collectedKobo': 100,
              'outstandingKobo': 0,
            },
            'counts': {
              'pendingOrder': 0,
              'pendingPayment': 0,
              'awaitingDelivery': 0,
              'inTransit': 0,
              'completed': 1,
              'failed': 0,
              'cancelled': 0,
            },
            'catalog': {'activeProducts': 1, 'customers': 1},
            'logistics': {
              'pendingRequests': 0,
              'activeDeliveries': 0,
              'deliveryFailures': 0,
              'nearbyProviders': 0,
              'nearbyRiders': 0,
            },
            'recent': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DashboardScreen(
          dashboard: DashboardRepository(session.api, session.auth),
          business: BusinessRepository(session.api, session.auth),
          transactions: TransactionRepository(session.api, session.auth),
          catalog: CatalogRepository(session.api, session.auth),
          customers: CustomerRepository(session.api, session.auth),
          onOpenTransaction: (_) {},
          onManualEntry: () {},
          onSeeAllTransactions: () {},
          onAddProduct: () {},
          onAddCustomer: () {},
        ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('WhatsApp AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WhatsApp AI'));
      await tester.pumpAndSettle();

      expect(
        find.text('This method is coming soon. Use Manual Entry for now.'),
        findsOneWidget,
      );
    });
  });

  group('spec 42 — organization workspace', () {
    testWidgets('shows summary, fleet, riders, coverage and pricing', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('logistics_partner', (request) async {
        if (request.url.path.endsWith('/logistics/organization/riders')) {
          return json({
            'riders': [
              {
                'id': 'rider-1',
                'fullName': 'Michael Rider',
                'isAvailable': true,
                'activeJobs': 2,
              },
              {
                'id': 'rider-2',
                'fullName': 'Grace Rider',
                'isAvailable': false,
                'activeJobs': 0,
              },
            ],
          });
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({
            'deliveryRequests': [
              {
                'id': 'req-1',
                'transactionNumber': 'TXN-2026-00001',
                'status': 'requested',
                'pickupCity': 'Warri',
                'destinationCity': 'Effurun',
              },
              {
                'id': 'req-2',
                'transactionNumber': 'TXN-2026-00002',
                'status': 'failed',
                'pickupCity': 'Warri',
                'destinationCity': 'Ughelli',
                'failureReason': 'Customer unavailable',
              },
            ],
          });
        }
        if (request.url.path.endsWith('/logistics/organization')) {
          return json({
            'organization': {
              'id': 'org-1',
              'name': 'FastMove Logistics',
              'isAvailable': true,
              'availabilityExpiresAt':
                  DateTime.now().add(const Duration(hours: 4)).toIso8601String(),
            },
            'serviceAreas': [
              {'id': 'area-1', 'city': 'Warri', 'area': 'Effurun', 'state': 'Delta'},
            ],
            'pricing': [
              {'destination': 'Warri', 'priceKobo': 250000},
            ],
            'vehicles': [
              {
                'vehicleType': 'motorcycle',
                'totalQuantity': 8,
                'availableQuantity': 5,
                'capacityCategory': 'small',
                'startingPriceKobo': 250000,
              },
            ],
          });
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      // Home page — a dashboard: the earnings headline, the state counts and
      // the requests that need a decision. The availability card is not here.
      expect(find.text('Total earnings'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('New requests'), findsOneWidget);
      expect(find.text('TXN-2026-00001'), findsOneWidget, reason: 'the new request is on the home page');
      expect(find.text('Accept delivery'), findsWidgets);
      expect(find.text('No active delivery'), findsOneWidget);
      expect(find.textContaining('Active — accepting new requests'), findsNothing,
          reason: 'the availability card lives on the Active tab, not Home');

      // Active page — the availability card: identity, switch and closing time.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Active'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('FastMove Logistics'), findsOneWidget);
      expect(find.textContaining('Active — accepting new requests'), findsOneWidget);
      expect(find.text('Automatic closing'), findsOneWidget);

      // Setup page — the manageable network: fleet, riders, coverage, pricing.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Setup'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Fleet'), findsOneWidget);
      expect(find.text('Riders'), findsOneWidget);
      expect(find.text('Service areas & pricing'), findsOneWidget);
      expect(find.text('5 of 8 available'), findsOneWidget);
      expect(find.textContaining('small • from'), findsWidgets);
      expect(find.text('1 active • 1 inactive'), findsOneWidget);
      expect(find.text('Michael Rider'), findsOneWidget);
      expect(find.text('2 jobs'), findsOneWidget);
      expect(find.text('Warri, Effurun, Delta'), findsOneWidget);
      expect(find.text('₦2,500.00'), findsOneWidget, reason: 'published fee');
    });
  });

  group('spec 43 — rider workspace', () {
    testWidgets('offers availability extension, modes, active delivery and history', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('rider', (request) async {
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({
            'deliveryRequests': [
              {
                'id': 'req-1',
                'transactionNumber': 'TXN-2026-00001',
                'status': 'in_transit',
                'pickupCity': 'Warri',
                'destinationCity': 'Effurun',
                'riderName': 'Michael Rider',
              },
              {
                'id': 'req-2',
                'transactionNumber': 'TXN-2026-00002',
                'status': 'delivered',
                'pickupCity': 'Warri',
                'destinationCity': 'Ughelli',
              },
              {
                'id': 'req-3',
                'transactionNumber': 'TXN-2026-00003',
                'status': 'failed',
                'pickupCity': 'Warri',
                'destinationCity': 'Sapele',
                'failureReason': 'Wrong address',
              },
            ],
          });
        }
        if (request.url.path.endsWith('/logistics/rider')) {
          return json({
            'rider': {
              'id': 'rider-1',
              'userId': 'user-123',
              'fullName': 'Michael Rider',
              'isAvailable': true,
              'availabilityExpiresAt':
                  DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
            },
            'serviceAreas': <Object>[],
            'modes': [
              {
                'mode': 'motorcycle',
                'capacityCategory': 'small',
                'rateKobo': 250000,
                'isPrimary': true,
              },
            ],
          });
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Rider workspace'), findsOneWidget);

      // Home page — summary plus the ride currently being carried.
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Active delivery'), findsOneWidget);
      expect(find.text('Warri to Effurun'), findsOneWidget);
      expect(find.text('In transit'), findsWidgets);

      // Active page — the on-duty controls and the overtime extension.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Active'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Availability extension'), findsOneWidget);
      expect(find.text('+30 min'), findsOneWidget);
      expect(find.text('+1 hour'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('On the road'), findsOneWidget);

      // History page — the earnings ledger and every past delivery.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('History'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Total earnings'), findsOneWidget);
      expect(find.text('₦0.00'), findsOneWidget);
      expect(find.text('Warri to Ughelli'), findsOneWidget);
      expect(find.text('Warri to Sapele'), findsOneWidget);
      expect(find.text('Wrong address'), findsOneWidget);
      expect(find.text('Past deliveries'), findsOneWidget);

      // Setup page — modes and service areas.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Setup'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Delivery modes'), findsOneWidget);
      expect(find.text('motorcycle'), findsWidgets);
      expect(find.text('Rate ₦2,500.00'), findsOneWidget);
    });
  });

  group('spec 19, 22 and 24 — the network is manageable from the workspace', () {
    testWidgets('a partner adds a vehicle and the API receives it', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('logistics_partner', (request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/logistics/organization/vehicles')) {
          return json({'vehicle': <String, Object>{}}, status: 201);
        }
        if (request.url.path.endsWith('/logistics/organization/riders')) {
          return json({'riders': <Object>[]});
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        if (request.url.path.endsWith('/logistics/organization')) {
          return json({
            'organization': {'id': 'org-1', 'name': 'FastMove Logistics', 'isAvailable': true},
            'vehicles': <Object>[],
            'serviceAreas': <Object>[],
            'pricing': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: logistics,
          onOpenSettings: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Settings'), findsOneWidget, reason: 'settings is not business-only');

      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Setup'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Add vehicle'), findsOneWidget);

      await tester.tap(find.text('Add vehicle'));
      await tester.pumpAndSettle();
      expect(find.text('Add vehicle'), findsWidgets);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '3');
      await tester.enterText(fields.at(1), '2500');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final request = log.where((entry) =>
          entry.method == 'POST' && entry.url.path.endsWith('/logistics/organization/vehicles'));
      expect(request, isNotEmpty, reason: 'the form actually posts to the fleet endpoint');
      final body = jsonDecode(request.last.body) as Map<String, dynamic>;
      expect(body['vehicle_type'], 'motorcycle');
      expect(body['total_quantity'], 3);
      expect(body['available_quantity'], 3);
      expect(body['starting_price_kobo'], 250000);
    });

    testWidgets('a rider adds a delivery mode and the API receives it', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('rider', (request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/logistics/rider/modes')) {
          return json({'mode': <String, Object>{}}, status: 201);
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        if (request.url.path.endsWith('/logistics/rider')) {
          return json({
            'rider': {'id': 'rider-1', 'userId': 'user-123', 'fullName': 'Michael Rider', 'isAvailable': true},
            'serviceAreas': <Object>[],
            'modes': <Object>[],
          });
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Setup'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Add mode'), findsOneWidget);
      await tester.tap(find.text('Add mode'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsOneWidget, reason: 'only the rate needs typing');
      await tester.enterText(fields, '1500');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final request = log.where((entry) =>
          entry.method == 'POST' && entry.url.path.endsWith('/logistics/rider/modes'));
      expect(request, isNotEmpty, reason: 'the form actually posts to the modes endpoint');
      final body = jsonDecode(request.last.body) as Map<String, dynamic>;
      expect(body['mode'], 'motorcycle');
      expect(body['rate_kobo'], 150000);
      expect(body['is_primary'], true);
    });
  });

  group('spec 44 — business-facing provider selection', () {
    testWidgets('a provider card carries distance, coverage and rates', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/logistics/providers')) {
          return json({
            'providers': [
              {
                'organization': {
                  'id': 'org-1',
                  'name': 'FastMove Logistics',
                  'isAvailable': true,
                  'availabilityExpiresAt': '2099-01-01T20:00:00.000Z',
                },
                'distanceKm': 2.4,
                'serviceAreas': [
                  {'city': 'Warri', 'area': 'Effurun'},
                ],
                'vehicles': [
                  {
                    'vehicleType': 'motorcycle',
                    'totalQuantity': 8,
                    'availableQuantity': 5,
                    'capacityCategory': 'small',
                    'startingPriceKobo': 250000,
                  },
                  {
                    'vehicleType': 'car',
                    'totalQuantity': 2,
                    'availableQuantity': 1,
                    'capacityCategory': 'large',
                    'startingPriceKobo': 600000,
                  },
                ],
                'pricing': [
                  {'destination': 'Warri', 'priceKobo': 250000},
                ],
              },
            ],
            'riders': <Object>[],
          });
        }
        if (request.url.path.endsWith('/logistics/notifications')) {
          return json({'notifications': <Object>[], 'unreadCount': 0});
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        if (request.url.path.endsWith('/transactions')) {
          return json({'transactions': <Object>[], 'pagination': {'total': 0}});
        }
        if (request.url.path.endsWith('/business')) {
          return json({
            'business': {
              'id': 'biz-1',
              'ownerUserId': 'user-123',
              'businessName': 'ABC Fashion Store',
              'location': {'id': 'loc-1', 'businessId': 'biz-1', 'address': '1 Market Road', 'city': 'Warri'},
            },
          });
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      final business = BusinessRepository(session.api, session.auth);
      final transactions = TransactionRepository(session.api, session.auth);
      await business.load();
      await tester.pumpWidget(MaterialApp(
        home: BusinessLogisticsScreen(
          business: business,
          transactions: transactions,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Find providers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find providers'));
      await tester.pumpAndSettle();

      expect(find.text('FastMove Logistics'), findsOneWidget);
      expect(find.text('2.4 km away'), findsOneWidget, reason: 'distance from business');
      // The pill plus the spec 14 request summary both say "Active".
      expect(find.text('Active'), findsWidgets);
      expect(find.textContaining('Available until'), findsWidgets, reason: 'spec 14 — availability closing time');
      for (final label in const ['New', 'Completed', 'Failed']) {
        expect(find.text(label), findsWidgets, reason: 'spec 14 — request status summary');
      }
      expect(find.textContaining('Covers: Effurun, Warri'), findsOneWidget);
      expect(find.textContaining('Available vehicles: motorcycle, car'), findsOneWidget);
      expect(find.textContaining('motorcycle — from'), findsOneWidget);
      expect(find.textContaining('car — from'), findsOneWidget);
      expect(find.textContaining('Published rate ₦2,500.00'), findsOneWidget);

      // The screen must ask the server, not filter locally.
      expect(
        log.any((request) => request.url.path.endsWith('/logistics/providers') && request.url.query.contains('destination_city')),
        isTrue,
      );
    });

    /// The request list on the logistics tab is a sample — three cards so the
    /// tab stays scannable — and More leads to the full list with nothing
    /// filtered away.
    testWidgets('the logistics tab previews three requests and More reaches the rest', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/business')) {
          return json({
            'business': {
              'id': 'biz-1',
              'ownerUserId': 'user-123',
              'businessName': 'ABC Fashion Store',
              'location': {'id': 'loc-1', 'businessId': 'biz-1', 'address': '1 Market Road', 'city': 'Warri'},
            },
          });
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({
            'deliveryRequests': [
              for (var index = 1; index <= 5; index++)
                {
                  'id': 'req-$index',
                  'transactionNumber': 'TXN-0000$index',
                  'status': 'requested',
                  'pickupCity': 'Warri',
                  'destinationCity': 'Effurun',
                },
            ],
          });
        }
        if (request.url.path.endsWith('/logistics/notifications')) {
          return json({'notifications': <Object>[], 'unreadCount': 0});
        }
        if (request.url.path.endsWith('/transactions')) {
          return json({'transactions': <Object>[], 'pagination': {'total': 0}});
        }
        if (request.url.path.endsWith('/logistics/providers')) {
          return json({'providers': <Object>[], 'riders': <Object>[]});
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      final business = BusinessRepository(session.api, session.auth);
      final transactions = TransactionRepository(session.api, session.auth);
      await business.load();
      await tester.pumpWidget(MaterialApp(
        home: BusinessLogisticsScreen(
          business: business,
          transactions: transactions,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      for (var index = 1; index <= 3; index++) {
        expect(find.text('TXN-0000$index'), findsOneWidget, reason: 'three requests are previewed');
      }
      expect(find.text('TXN-00004'), findsNothing, reason: 'the fourth waits behind More');
      expect(find.text('TXN-00005'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'More'));
      await tester.pumpAndSettle();

      expect(find.byType(DeliveryRequestsListScreen), findsOneWidget);
      for (var index = 1; index <= 5; index++) {
        expect(find.text('TXN-0000$index'), findsOneWidget, reason: 'the full list carries every request');
      }
    });

    /// The notification list on the logistics tab is a sample too — seven cards
    /// so the tab stays scannable — and More leads to the full page with
    /// nothing sampled away.
    testWidgets('the logistics tab previews seven notifications and More reaches the rest', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('business', (request) async {
        if (request.url.path.endsWith('/business')) {
          return json({
            'business': {
              'id': 'biz-1',
              'ownerUserId': 'user-123',
              'businessName': 'ABC Fashion Store',
              'location': {'id': 'loc-1', 'businessId': 'biz-1', 'address': '1 Market Road', 'city': 'Warri'},
            },
          });
        }
        if (request.url.path.endsWith('/logistics/notifications')) {
          return json({
            'notifications': [
              for (var index = 1; index <= 10; index++)
                {
                  'id': 'note-$index',
                  'deliveryRequestId': null,
                  'kind': 'quote_received',
                  'title': 'Alert $index',
                  'body': 'Delivery update number $index.',
                  'readAt': null,
                  'createdAt': '2026-10-01T09:00:00Z',
                },
            ],
            'unreadCount': 10,
          });
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        if (request.url.path.endsWith('/transactions')) {
          return json({'transactions': <Object>[], 'pagination': {'total': 0}});
        }
        if (request.url.path.endsWith('/logistics/providers')) {
          return json({'providers': <Object>[], 'riders': <Object>[]});
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      final business = BusinessRepository(session.api, session.auth);
      final transactions = TransactionRepository(session.api, session.auth);
      await business.load();
      await tester.pumpWidget(MaterialApp(
        home: BusinessLogisticsScreen(
          business: business,
          transactions: transactions,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      for (var index = 1; index <= 7; index++) {
        expect(find.text('Alert $index'), findsOneWidget, reason: 'seven notifications are previewed');
      }
      expect(find.text('Alert 8'), findsNothing, reason: 'the eighth waits behind More');
      expect(find.text('Alert 9'), findsNothing);
      expect(find.text('Alert 10'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'More'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
      for (var index = 1; index <= 10; index++) {
        expect(find.text('Alert $index'), findsOneWidget, reason: 'the full page carries every notification');
      }
    });
  });

  group('spec 28 and 53 — a delivery can be opened and read', () {
    Map<String, dynamic> detailPayload() => {
          'id': 'req-4',
          'transactionId': 'tx-4',
          'transactionNumber': 'TXN-2026-00004',
          'status': 'requested',
          'pickupCity': 'Warri',
          'destinationCity': 'Effurun',
          'packageDescription': 'Two boxes of shoes',
          'packageSize': 'small',
          'pickup': {
            'address': '1 Market Road',
            'area': 'Market Quarter',
            'city': 'Warri',
            'state': 'Delta',
            'country': 'Nigeria',
          },
          'destination': {'address': '2 Airport Road, Warri', 'city': 'Effurun'},
          'business': {
            'name': 'Sunrise Fabrics',
            'ownerName': 'Ngozi Eze',
            'phone': '+2348033333333',
          },
          'customer': {
            'name': 'Ada Obi',
            'phone': '+2348011111111',
            'email': 'ada@example.com',
            'address': '7 Palm Street',
          },
          'rider': {'name': 'Michael Rider', 'phone': '+2348022222222'},
          'organization': {'name': 'FastMove Logistics', 'phone': '+2348044444444'},
          'totals': {
            'subtotalKobo': 300000,
            'discountKobo': 0,
            'deliveryFeeKobo': 0,
            'totalKobo': 300000,
          },
          'events': [
            {
              'id': 'ev-1',
              'eventType': 'requested',
              'actorName': 'Ngozi Eze',
              'createdAt': '2026-10-01T10:00:00Z',
            },
          ],
        };

    Map<String, dynamic> riderWorkspaceRequests() => {
          'deliveryRequests': [
            {
              'id': 'req-4',
              'transactionNumber': 'TXN-2026-00004',
              'status': 'requested',
              'pickupCity': 'Warri',
              'destinationCity': 'Effurun',
            },
            {
              'id': 'req-1',
              'transactionNumber': 'TXN-2026-00001',
              'status': 'in_transit',
              'pickupCity': 'Warri',
              'destinationCity': 'Ughelli',
            },
          ],
        };

    Future<({ApiClient api, AuthRepository auth})> riderSession(WidgetTester tester) {
      return signInAs('rider', (request) async {
        if (request.url.path.endsWith('/logistics/requests/req-4')) {
          return json({'deliveryRequest': detailPayload()});
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json(riderWorkspaceRequests());
        }
        if (request.url.path.endsWith('/logistics/rider')) {
          return json({
            'rider': {
              'id': 'rider-1',
              'userId': 'user-123',
              'fullName': 'Michael Rider',
              'isAvailable': true,
              'availabilityExpiresAt':
                  DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
            },
            'serviceAreas': <Object>[],
            'modes': <Object>[],
          });
        }
        return json(<String, Object>{});
      });
    }

    testWidgets('the rider is offered the new request and can accept or decline it', (tester) async {
      useTallSurface(tester);
      final session = await riderSession(tester);

      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: LogisticsRepository(session.api, session.auth),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('New requests'), findsOneWidget, reason: 'the list behind the count exists on the page');
      expect(find.text('TXN-2026-00004'), findsOneWidget);
      expect(find.text('Accept delivery'), findsOneWidget, reason: 'spec 29 — the rider can take the job');
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('opening the request names both sides, with phone numbers, and the timeline', (tester) async {
      useTallSurface(tester);
      final session = await riderSession(tester);

      final logistics = LogisticsRepository(session.api, session.auth);
      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TXN-2026-00004'));
      await tester.pumpAndSettle();

      expect(find.text('Delivery request'), findsOneWidget, reason: 'the breakdown screen opened');
      expect(find.text('Pickup — collection point'), findsOneWidget);
      expect(find.text('Sunrise Fabrics'), findsOneWidget, reason: 'spec 28 — the business at the pickup point');
      expect(find.text('+2348033333333'), findsOneWidget, reason: 'spec 28 — a phone number to call');
      expect(find.text('Address'), findsWidgets, reason: 'both cards carry an address row');
      expect(find.text('1 Market Road'), findsOneWidget, reason: 'spec 53 — the pickup as the owner typed it');
      expect(find.text('Area'), findsOneWidget, reason: 'spec 53 — the area the partner reads off the pickup');
      expect(find.text('Market Quarter'), findsOneWidget);
      expect(find.text('City'), findsOneWidget);
      expect(find.text('Warri'), findsOneWidget);
      expect(find.text('State'), findsOneWidget);
      expect(find.text('Delta'), findsOneWidget);
      expect(find.text('Drop-off — customer location'), findsOneWidget);
      expect(find.text('Ada Obi'), findsOneWidget, reason: 'spec 28 — who receives it');
      expect(find.text('+2348011111111'), findsOneWidget);
      expect(find.textContaining('2 Airport Road, Warri'), findsOneWidget, reason: 'spec 53 — where it goes');
      expect(find.text('Carried by'), findsOneWidget);
      expect(find.text('Michael Rider'), findsOneWidget);
      expect(find.text('₦3,000.00'), findsOneWidget, reason: 'spec 53 — the money travels with the delivery');
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Delivery requested'), findsOneWidget, reason: 'spec 53 — how it got here');

      expect(
        log.any((request) => request.url.path.endsWith('/logistics/requests/req-4')),
        isTrue,
        reason: 'the breakdown comes from the API, not from the list row',
      );
    });
    testWidgets('the New count opens the dedicated list of new deliveries', (tester) async {
      useTallSurface(tester);
      final session = await riderSession(tester);

      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: LogisticsRepository(session.api, session.auth),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('New'));
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();

      expect(find.text('New delivery requests'), findsOneWidget, reason: 'the count links to its own page');
      expect(find.text('TXN-2026-00004'), findsOneWidget);
      expect(find.text('Warri to Effurun'), findsOneWidget);
      expect(find.text('TXN-2026-00001'), findsNothing, reason: 'in-transit work is not new');
    });
  });

  group('spec 16 and 17 — going active or inactive is confirmed first', () {
    testWidgets('a rider cancels and nothing changes, then confirms and the API hears it', (tester) async {
      useTallSurface(tester);
      var active = false;
      final session = await signInAs('rider', (request) async {
        if (request.method == 'PATCH' && request.url.path.endsWith('/logistics/rider/availability')) {
          active = true;
          return json({
            'rider': {
              'id': 'rider-1',
              'userId': 'user-123',
              'fullName': 'Michael Rider',
              'isAvailable': true,
              'availabilityExpiresAt':
                  DateTime.now().add(const Duration(hours: 8)).toIso8601String(),
            },
            'serviceAreas': <Object>[],
            'modes': <Object>[],
          });
        }
        if (request.url.path.endsWith('/logistics/rider')) {
          return json({
            'rider': {
              'id': 'rider-1',
              'userId': 'user-123',
              'fullName': 'Michael Rider',
              'isAvailable': active,
              'availabilityExpiresAt':
                  active ? DateTime.now().add(const Duration(hours: 8)).toIso8601String() : null,
            },
            'serviceAreas': <Object>[],
            'modes': <Object>[],
          });
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: LogisticsRepository(session.api, session.auth),
        ),
      ));
      await tester.pumpAndSettle();

      // The availability card lives on the Active tab now.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Active')));
      await tester.pumpAndSettle();

      expect(find.text('Inactive — not accepting new requests'), findsOneWidget);

      final dot = tester.widget<Icon>(find.byIcon(Icons.bolt));
      expect(dot.color, isNot(AppColors.success), reason: 'the app-bar dot is on the standby colour while offline');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Go active?'), findsOneWidget, reason: 'the switch asks before it acts');
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Yes, go active'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Go active?'), findsNothing);
      expect(log.where((request) => request.method == 'PATCH'), isEmpty, reason: 'cancelling never reaches the API');
      expect(find.text('Inactive — not accepting new requests'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, go active'));
      await tester.pumpAndSettle();

      expect(
        log.where((request) => request.method == 'PATCH' && request.url.path.endsWith('/availability')),
        isNotEmpty,
        reason: 'only an explicit yes makes the rider active',
      );
      expect(find.text('Active — accepting new requests'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.bolt)).color,
        AppColors.success,
        reason: 'the app-bar dot turns green the moment the provider is live',
      );
    });

    testWidgets('a partner going inactive is asked the same way', (tester) async {
      useTallSurface(tester);
      var active = true;
      final session = await signInAs('logistics_partner', (request) async {
        if (request.method == 'PATCH' && request.url.path.endsWith('/logistics/organization/availability')) {
          active = false;
          return json({
            'organization': {
              'id': 'org-1',
              'name': 'FastMove Logistics',
              'isAvailable': false,
              'availabilityExpiresAt': null,
            },
            'serviceAreas': <Object>[],
            'pricing': <Object>[],
            'vehicles': <Object>[],
          });
        }
        if (request.url.path.endsWith('/logistics/organization')) {
          return json({
            'organization': {
              'id': 'org-1',
              'name': 'FastMove Logistics',
              'isAvailable': active,
              'availabilityExpiresAt':
                  active ? DateTime.now().add(const Duration(hours: 4)).toIso8601String() : null,
            },
            'serviceAreas': <Object>[],
            'pricing': <Object>[],
            'vehicles': <Object>[],
          });
        }
        if (request.url.path.endsWith('/logistics/organization/riders')) {
          return json({'riders': <Object>[]});
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: LogisticsRepository(session.api, session.auth),
        ),
      ));
      await tester.pumpAndSettle();

      // The availability card lives on the Active tab now.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Active')));
      await tester.pumpAndSettle();

      expect(find.text('Active — accepting new requests'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('Go inactive?'), findsOneWidget, reason: 'leaving is confirmed too');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(log.where((request) => request.method == 'PATCH'), isEmpty);
      expect(find.text('Active — accepting new requests'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, go inactive'));
      await tester.pumpAndSettle();

      expect(
        log.where((request) => request.method == 'PATCH' && request.url.path.endsWith('/availability')),
        isNotEmpty,
      );
      expect(find.text('Inactive — not accepting new requests'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.bolt)).color,
        isNot(AppColors.success),
        reason: 'going offline returns the app-bar dot to its standby colour',
      );
    });

    testWidgets("activation asks for the exact working time and time can be added or trimmed", (tester) async {
      useTallSurface(tester);
      var active = false;
      DateTime? expiresAt;
      DateTime? startedAt;
      late http.Request lastPatch;
      late http.Request lastExtend;

      DateTime? closesAtIn(http.Request request) {
        final raw = RegExp(r'"availability_expires_at":"([^"]+)"').firstMatch(request.body)?.group(1);
        return raw == null ? null : DateTime.parse(raw).toLocal();
      }

      String riderBody() => jsonEncode({
            'rider': {
              'id': 'rider-1',
              'userId': 'user-123',
              'fullName': 'Michael Rider',
              'isAvailable': active,
              'availabilityExpiresAt': expiresAt?.toIso8601String(),
              'availabilityStartedAt': startedAt?.toIso8601String(),
              'plannedHours': expiresAt == null || startedAt == null ? null : expiresAt!.difference(startedAt!).inHours.clamp(1, 24),
            },
            'serviceAreas': <Object>[],
            'modes': <Object>[],
          });

      final session = await signInAs('rider', (request) async {
        if (request.method == 'PATCH' && request.url.path.endsWith('/logistics/rider/availability')) {
          lastPatch = request;
          active = request.body.contains('"is_available":true');
          if (active) {
            startedAt = DateTime.now();
            expiresAt = closesAtIn(request) ?? startedAt!.add(const Duration(hours: 8));
          } else {
            startedAt = null;
            expiresAt = null;
          }
          return http.Response(riderBody(), 200, headers: {'content-type': 'application/json'});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/availability/extend')) {
          lastExtend = request;
          final minutes = int.tryParse(RegExp(r'"minutes":(-?\d+)').firstMatch(request.body)?.group(1) ?? '0') ?? 0;
          final next = (expiresAt ?? DateTime.now()).add(Duration(minutes: minutes));
          if (next.isAfter(DateTime.now())) {
            expiresAt = next;
            active = true;
          } else {
            active = false;
            startedAt = null;
            expiresAt = null;
          }
          return http.Response(riderBody(), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.endsWith('/logistics/rider')) {
          return http.Response(riderBody(), 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        return json(<String, Object>{});
      });

      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: LogisticsRepository(session.api, session.auth),
        ),
      ));
      await tester.pumpAndSettle();

      // The availability card lives on the Active tab now.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Active')));
      await tester.pumpAndSettle();

      // Preset work-until times run noon → 7pm. After 7pm local there is nothing
      // left to choose today, so only nothing-to-pick nights skip the flow.
      const presets = [12, 13, 14, 15, 16, 17, 18, 19];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final future = presets.where((hour) => today.add(Duration(hours: hour)).isAfter(now)).toList();
      if (future.isEmpty) return;
      final expectedActivationHour = future.first;
      final replanHour = future.length > 1 ? future[1] : future.first;

      // Going active asks for the exact time of day to work until (noon → 7pm).
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Go active?'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '12:00 PM'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '7:00 PM'), findsOneWidget);
      await tester.tap(find.text('Yes, go active'));
      await tester.pumpAndSettle();
      final plannedTime = closesAtIn(lastPatch);
      expect(plannedTime, isNotNull, reason: 'the chosen work-until time travels with activation');
      expect(plannedTime!.hour, expectedActivationHour,
          reason: 'the first still-future preset is what the API hears');

      // The Active page shows the closing time and a re-plan edit that reaches the API.
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Active')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Work until'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Update plan')), findsOneWidget);
      final replanLabel = TimeOfDay(hour: replanHour, minute: 0).format(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.widgetWithText(ChoiceChip, replanLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update plan'));
      await tester.pumpAndSettle();
      expect(closesAtIn(lastPatch)?.hour, replanHour,
          reason: 're-planning moves the closing time to the new hour');
      expect(find.text('Remove time'), findsOneWidget);

      // Add and then trim time from the shift; both arrive with the right sign.
      expect(find.text('-30 min'), findsOneWidget);
      expect(find.text('Trim more'), findsOneWidget);
      await tester.tap(find.text('+1 hour'));
      await tester.pumpAndSettle();
      expect(lastExtend.body, contains('"minutes":60'));
      await tester.tap(find.text('-30 min'));
      await tester.pumpAndSettle();
      expect(lastExtend.body, contains('"minutes":-30'));
    });
  });

  group('status bolt — the availability word reveals and retracts', () {
    testWidgets('tapping the bolt unrolls the matching pill, which rolls itself back up', (tester) async {
      useTallSurface(tester);
      final session = await signInAs('rider', (request) async {
        if (request.url.path.endsWith('/logistics/rider')) {
          return json({
            'rider': {'id': 'rider-1', 'userId': 'user-123', 'fullName': 'Michael Rider', 'isAvailable': true},
            'serviceAreas': <Object>[],
            'modes': <Object>[],
          });
        }
        if (request.url.path.endsWith('/logistics/requests')) {
          return json({'deliveryRequests': <Object>[]});
        }
        return json(<String, Object>{});
      });

      final logistics = LogisticsRepository(session.api, session.auth);
      await tester.pumpWidget(MaterialApp(
        home: LogisticsWorkspaceScreen(
          user: session.auth.session!.user,
          logistics: logistics,
        ),
      ));
      await tester.pumpAndSettle();

      final expand = find.byKey(const ValueKey('status-pill-expand'));
      expect(tester.widget<SizeTransition>(expand).sizeFactor.value, 0, reason: 'collapsed until told otherwise');
      expect(tester.widget<Icon>(find.byIcon(Icons.bolt)).color, AppColors.success, reason: 'green while live');

      await tester.tap(find.byIcon(Icons.bolt));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      expect(tester.widget<SizeTransition>(expand).sizeFactor.value, greaterThan(0.2), reason: 'the pill is unrolling');
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Active')), findsOneWidget, reason: 'the status word rides the pill');

      // The pill holds for a few seconds, then rolls itself back up and the
      // neighbouring app-bar icons slide back to where they were.
      await tester.pump(const Duration(seconds: 3, milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.widget<SizeTransition>(expand).sizeFactor.value, 0, reason: 'back to the plain bolt');

      // Tapping again reveals it once more.
      await tester.tap(find.byIcon(Icons.bolt));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Active')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3, milliseconds: 200));
      await tester.pumpAndSettle();
    });
  });
}
