import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:dee_app/core/state/dashboard_repository.dart';
import 'package:dee_app/core/state/logistics_repository.dart';
import 'package:dee_app/core/state/wallet_repository.dart';
import 'package:dee_app/core/state/transaction_repository.dart';
import 'package:dee_app/features/home/home_shell_screen.dart';
import 'package:dee_app/features/business/business_setup_flow.dart';
import 'package:dee_app/features/logistics/delivery_requests_list_screen.dart';
import 'package:dee_app/features/logistics/notifications_screen.dart';
import 'package:dee_app/features/transactions/new_transaction_screen.dart';
import 'package:dee_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// Regression: the business shell's failure view is the root route, so it used
/// to be a dead end — `Try again` was the only control. It now carries a back
/// arrow and a sign-out action so a stuck account can always leave.
void main() {
  const base = 'http://localhost:4000/api/v1';

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

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a refused business load can be escaped with sign out', (tester) async {
    var signedOut = false;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      if (request.url.path.endsWith('/business')) {
        return json({
          'error': {
            'code': 'forbidden',
            'message': 'This area is only available to business accounts.',
          },
        }, status: 403);
      }
      return json({});
    });

    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShellScreen(
          user: auth.session!.user,
          business: BusinessRepository(api, auth),
          catalog: CatalogRepository(api, auth),
          customers: CustomerRepository(api, auth),
          transactions: TransactionRepository(api, auth),
          dashboard: DashboardRepository(api, auth),
          logistics: LogisticsRepository(api, auth),
          wallet: WalletRepository(api, auth),
          onOpenSettings: () {},
          onSignOut: () async => signedOut = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach your business yet'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });

  /// The default 800x600 surface leaves the quick actions below the fold, so
  /// the dashboard is given a phone-sized surface instead.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// A profile with a location on file. The phone and the area it sits in are
  /// left open so a test can decide which details logistics still lacks.
  Map<String, Object?> businessProfile({
    String name = 'Ada Provisions',
    String? phone,
    String? area,
    String? logoUrl,
    double? latitude,
    double? longitude,
  }) =>
      {
        'business': {
          'id': 'business-1',
          'ownerUserId': 'user-123',
          'businessName': name,
          'businessCategory': 'Groceries',
          'businessDescription': null,
          'phone': phone,
          'email': null,
          'logoUrl': logoUrl,
          'location': {
            'id': 'loc-1',
            'businessId': 'business-1',
            'address': '12 Allen Avenue',
            'area': area,
            'city': 'Ikeja',
            'state': 'Lagos',
            'country': 'Nigeria',
            'latitude': latitude,
            'longitude': longitude,
          },
        },
      };

  /// Signs the owner in and pumps the shell, whose `initState` re-reads the
  /// business exactly the way a refresh does.
  Future<void> pumpShell(WidgetTester tester, {required Map<String, Object?> profile}) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      if (request.url.path.endsWith('/business')) return json(profile);
      return json(<String, Object>{});
    });

    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShellScreen(
          user: auth.session!.user,
          business: BusinessRepository(api, auth),
          catalog: CatalogRepository(api, auth),
          customers: CustomerRepository(api, auth),
          transactions: TransactionRepository(api, auth),
          dashboard: DashboardRepository(api, auth),
          logistics: LogisticsRepository(api, auth),
          wallet: WalletRepository(api, auth),
          onOpenSettings: () {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Spec — login or refresh surfaces the details the delivery partner reads
  /// (contact number, city, area, state), but not the instant the page lands:
  /// the prompt waits a couple of seconds, then leads to the screen that
  /// collects them.
  testWidgets('an owner missing logistics details is prompted on launch, after a short wait', (tester) async {
    useTallSurface(tester);
    await pumpShell(tester, profile: businessProfile(phone: '+2348012345678'));

    expect(find.text('Complete your business details'), findsNothing, reason: 'not the instant the page lands');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Complete your business details'), findsNothing, reason: 'it waits a couple of seconds');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Complete your business details'), findsOneWidget, reason: 'the launch prompt appears once per launch');
    expect(find.textContaining('city, area, state'), findsOneWidget, reason: 'it says what the partner needs');

    await tester.tap(find.text('Open business details'));
    await tester.pumpAndSettle();

    expect(find.byType(BusinessSetupFlow), findsOneWidget, reason: 'the prompt leads to the screen that collects them');
    expect(find.text('Business settings'), findsOneWidget, reason: 'the profile exists, so it opens as settings');
  });

  /// Spec — the same prompt stands in front of a sale, and there it is asked
  /// the moment the button is pressed: the rider's details are exactly what
  /// the job needs, so the owner is not left waiting.
  testWidgets('recording a sale asks immediately for the details the rider needs', (tester) async {
    useTallSurface(tester);
    await pumpShell(tester, profile: businessProfile(phone: null));

    expect(find.text('Complete your business details'), findsNothing, reason: 'the launch prompt has not fired yet');

    await tester.ensureVisible(find.text('New sale'));
    await tester.tap(find.text('New sale'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your business details'), findsOneWidget, reason: 'a sale asks the instant it is started');
    expect(find.byType(NewTransactionScreen), findsNothing, reason: 'the sale form never opened');

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // The launch prompt does not ask the same question again right after it.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Complete your business details'), findsNothing);

    await tester.ensureVisible(find.text('New sale'));
    await tester.tap(find.text('New sale'));
    await tester.pumpAndSettle();
    expect(find.text('Complete your business details'), findsOneWidget, reason: 'a sale always asks while details are missing');

    await tester.tap(find.text('Open business details'));
    await tester.pumpAndSettle();

    expect(find.byType(BusinessSetupFlow), findsOneWidget);
    expect(find.byType(NewTransactionScreen), findsNothing, reason: 'the sale was not recorded behind the owner’s back');
  });

  /// Spec — an owner who has every detail is never interrupted, not at login
  /// and not when reaching for a new sale.
  testWidgets('an owner with every detail is never prompted, even at a new sale', (tester) async {
    useTallSurface(tester);
    await pumpShell(
      tester,
      profile: businessProfile(phone: '+2348012345678', area: 'Allen Hill'),
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Complete your business details'), findsNothing, reason: 'nothing is missing at launch');

    await tester.ensureVisible(find.text('New sale'));
    await tester.tap(find.text('New sale'));
    await tester.pumpAndSettle();

    expect(find.text('Complete your business details'), findsNothing);
    expect(find.byType(NewTransactionScreen), findsOneWidget, reason: 'the sale form opens straight away');
  });

  /// Spec — the Profile tab is the owner's front desk. Notifications and
  /// Delivery requests are two doorways, each opening the whole list on its own
  /// page; nothing is sampled inline, so every item stays reachable.
  testWidgets('the profile tab carries doorways into the notifications and delivery requests lists', (tester) async {
    useTallSurface(tester);

    Map<String, Object?> notification(int index, {bool unread = true}) => {
          'id': 'note-$index',
          'deliveryRequestId': null,
          'kind': 'quote_received',
          'title': 'Alert $index',
          'body': 'Delivery update number $index.',
          'readAt': unread ? null : '2026-10-01T10:00:00Z',
          'createdAt': '2026-10-01T09:00:00Z',
        };

    Map<String, Object?> requestJson(int index) => {
          'id': 'req-$index',
          'transactionNumber': 'TXN-0000$index',
          'status': 'requested',
          'pickupCity': 'Lagos',
          'destinationCity': 'Ibadan',
        };

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) return json(sessionBody);
      if (request.url.path.endsWith('/business')) {
        return json(businessProfile(phone: '+2348012345678', area: 'Allen Hill', latitude: 6.6018, longitude: 3.3515));
      }
        if (request.url.path.endsWith('/logistics/notifications')) {
          return json({
            'notifications': [
              for (var index = 10; index >= 2; index--) notification(index),
              notification(1, unread: false),
            ],
            'unreadCount': 9,
          });
        }
      if (request.url.path.endsWith('/logistics/requests')) {
        return json({
          'deliveryRequests': [
            for (var index = 1; index <= 5; index++) requestJson(index),
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

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShellScreen(
          user: auth.session!.user,
          business: BusinessRepository(api, auth),
          catalog: CatalogRepository(api, auth),
          customers: CustomerRepository(api, auth),
          transactions: TransactionRepository(api, auth),
          dashboard: DashboardRepository(api, auth),
          logistics: LogisticsRepository(api, auth),
          wallet: WalletRepository(api, auth),
          onOpenSettings: () {},
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Profile'),
    ));
    await tester.pumpAndSettle();

    // The shop's own details ride on the banner, coordinates left off. The
    // name shows twice: once in the shell's app bar, once on the banner.
    expect(find.text('Ada Provisions'), findsNWidgets(2), reason: 'the business name heads the banner');
    expect(find.text('Groceries'), findsOneWidget, reason: 'the category is shown as a tag');
    expect(find.text('+2348012345678'), findsOneWidget, reason: 'the contact number is shown');
    expect(find.text('12 Allen Avenue, Allen Hill, Ikeja, Lagos, Nigeria'), findsOneWidget, reason: 'the location is shown as a readable line');
    expect(find.textContaining('Coordinates'), findsNothing, reason: 'coordinates are deliberately not shown on the profile');
    expect(find.textContaining('6.6018'), findsNothing, reason: 'the raw latitude is left off the profile');

    // The two doorways, each with the count that matters on the row.
    expect(find.widgetWithText(ListTile, 'Notifications'), findsOneWidget);
    expect(find.text('9 unread'), findsOneWidget, reason: 'the unread count rides on the row');
    expect(find.widgetWithText(ListTile, 'Delivery requests'), findsOneWidget);
    expect(find.text('5 total'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget, reason: 'Settings stays on the tab');

    // Nothing is sampled inline any more: the lists live behind the doorways.
    expect(find.text('Alert 10'), findsNothing);
    expect(find.text('TXN-00001'), findsNothing);

    // The Notifications doorway opens the whole list, nothing sampled away.
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Notifications'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsOneWidget);
    for (var index = 1; index <= 10; index++) {
      expect(find.text('Alert $index'), findsOneWidget, reason: 'the full page carries every notification');
    }

    await tester.pageBack();
    await tester.pumpAndSettle();

    // The Delivery requests doorway opens the whole list, nothing filtered away.
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Delivery requests'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Delivery requests'));
    await tester.pumpAndSettle();

    expect(find.byType(DeliveryRequestsListScreen), findsOneWidget);
    for (var index = 1; index <= 5; index++) {
      expect(find.text('TXN-0000$index'), findsOneWidget, reason: 'the full list carries every request');
    }
  });

  /// The shop name is shown the way a reader expects it — first letter
  /// capitalised — wherever it appears.
  testWidgets('the profile capitalises the business name', (tester) async {
    useTallSurface(tester);
    await pumpShell(
      tester,
      // Full logistics details, so the launch prompt's timer never fires here.
      profile: businessProfile(
        name: 'ada provisions',
        phone: '+2348012345678',
        area: 'Allen Hill',
      ),
    );

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Profile'),
    ));
    await tester.pumpAndSettle();

    // App bar and banner both carry the capitalised name, never the raw one.
    expect(find.text('Ada provisions'), findsNWidgets(2));
    expect(find.text('ada provisions'), findsNothing);
    expect(find.byType(BusinessLogoAvatar), findsWidgets);
  });
}
