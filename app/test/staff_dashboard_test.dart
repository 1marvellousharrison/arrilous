import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/dashboard_repository.dart';
import 'package:dee_app/features/home/staff_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// The staff home: their own money for today, their code, quick actions and the
/// sales they personally recorded — never the owner's business report.
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

  Map<String, Object?> sessionBody() => {
        'token_type': 'Bearer',
        'access_token': 'access-token-1',
        'expires_in': 900,
        'expires_at': '2030-01-01T00:00:00.000Z',
        'refresh_token': 'refresh-token-1',
        'refresh_expires_at': '2030-02-01T00:00:00.000Z',
        'user': {
          'id': 'user-staff',
          'fullName': 'Musa Bello',
          'email': null,
          'phone': null,
          'role': 'staff',
          'emailVerified': false,
          'phoneVerified': false,
        },
      };

  Map<String, Object?> businessBody() => {
        'business': {
          'id': 'business-1',
          'ownerUserId': 'user-owner',
          'businessName': 'Ada Provisions',
          'businessCategory': 'Groceries',
          'businessDescription': null,
          'phone': '+2348012345678',
          'email': null,
          'logoUrl': null,
          'businessCode': 'ABC47',
          'location': {
            'id': 'loc-1',
            'businessId': 'business-1',
            'address': '12 Allen Avenue',
            'area': 'Allen Hill',
            'city': 'Ikeja',
            'state': 'Lagos',
            'country': 'Nigeria',
            'latitude': 6.6018,
            'longitude': 3.3515,
          },
        },
      };

  Map<String, Object?> sale(String number, {int total = 1_500_000}) => {
        'id': 'txn-$number',
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
        'deliveryRequired': false,
        'orderStatus': 'pending',
        'paymentStatus': 'unpaid',
        'deliveryStatus': 'not_required',
        'completionStatus': 'open',
        'createdAt': '2026-10-01T09:00:00.000Z',
        'updatedAt': '2026-10-01T09:00:00.000Z',
      };

  Map<String, Object?> period({
    required int count,
    required int gross,
    required int collected,
    required int outstanding,
  }) =>
      {
        'transactionCount': count,
        'grossSalesKobo': gross,
        'collectedKobo': collected,
        'outstandingKobo': outstanding,
      };

  Map<String, Object?> summaryBody() => {
        'totals': {
          'transactionCount': 2,
          'grossSalesKobo': 3_000_000,
          'collectedKobo': 1_000_000,
          'outstandingKobo': 2_000_000,
        },
        'counts': {
          'pendingOrder': 1,
          'pendingPayment': 2,
          'awaitingDelivery': 1,
          'inTransit': 0,
          'completed': 0,
          'failed': 0,
          'cancelled': 0,
        },
        'catalog': {'activeProducts': 7, 'customers': 3},
        'logistics': {
          'pendingRequests': 2,
          'activeDeliveries': 1,
          'deliveryFailures': 0,
          'nearbyProviders': 4,
          'nearbyRiders': 6,
        },
        'recent': [sale('TXN-2026-00002'), sale('TXN-2026-00001', total: 1_000_000)],
        'staff': {
          'id': 'staff-1',
          'fullName': 'Musa Bello',
          'phone': null,
          'staffCode': 'ABC47-03',
          'status': 'active',
          'activatedAt': '2026-01-02T00:00:00.000Z',
          'salesCount': 2,
        },
        'periods': {
          'today': period(count: 2, gross: 3_000_000, collected: 1_000_000, outstanding: 2_000_000),
          'week': period(count: 4, gross: 5_000_000, collected: 2_000_000, outstanding: 3_000_000),
          'month': period(count: 6, gross: 9_000_000, collected: 4_000_000, outstanding: 5_000_000),
          'allTime': period(count: 8, gross: 12_000_000, collected: 6_000_000, outstanding: 6_000_000),
        },
        'topProducts': [
          {'name': 'Blue Bag', 'quantity': 4, 'revenueKobo': 6_000_000},
          {'name': 'Black Shirt', 'quantity': 2, 'revenueKobo': 3_000_000},
        ],
      };

  Future<(DashboardRepository, BusinessRepository, AuthRepository)> signedInStaff(
    MockClient client,
  ) async {
    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ABC47-03', password: 'Str0ngPass!23');
    return (DashboardRepository(api, auth), BusinessRepository(api, auth), auth);
  }

  MockClient clientWith(Map<String, Object?> summary) => MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.url.path.endsWith('/business')) return json(businessBody());
        if (request.url.path.endsWith('/dashboard/summary')) return json(summary);
        return json(<String, Object>{});
      });

  List<String> mockClipboard(WidgetTester tester) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return copied;
  }

  Future<void> pumpDashboard(
    WidgetTester tester,
    DashboardRepository dashboard,
    BusinessRepository business,
    AuthRepository auth, {
    VoidCallback? onManualEntry,
    VoidCallback? onAddCustomer,
    VoidCallback? onOpenProducts,
    VoidCallback? onGoToAiChat,
    VoidCallback? onGoToLogistics,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await business.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StaffDashboardScreen(
            dashboard: dashboard,
            business: business,
            user: auth.session!.user,
            onOpenTransaction: (_) {},
            onManualEntry: onManualEntry ?? () {},
            onSeeAllTransactions: () {},
            onAddCustomer: onAddCustomer ?? () {},
            onOpenProducts: onOpenProducts ?? () {},
            onGoToAiChat: onGoToAiChat ?? () {},
            onGoToLogistics: onGoToLogistics ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('leads with the staff member, their code and their own money', (tester) async {
    final (dashboard, business, auth) = await signedInStaff(clientWith(summaryBody()));
    await pumpDashboard(tester, dashboard, business, auth);

    expect(find.text('Musa'), findsOneWidget);
    expect(find.text('ABC47-03'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('₦30,000.00'), findsWidgets);
    expect(find.text('2 sales'), findsOneWidget);

    expect(find.text('Blue Bag'), findsOneWidget);
    expect(find.text('4 sold'), findsOneWidget);
    expect(find.text('TXN-2026-00002'), findsOneWidget);

    // The owner's report and actions are not on a staff home.
    expect(find.text('Add product'), findsNothing);
    expect(find.text('Your business'), findsNothing);
  });

  testWidgets('switching the period changes the figure it describes', (tester) async {
    final (dashboard, business, auth) = await signedInStaff(clientWith(summaryBody()));
    await pumpDashboard(tester, dashboard, business, auth);

    expect(find.text('₦30,000.00'), findsWidgets);

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('₦50,000.00'), findsOneWidget);
    expect(find.text('4 sales'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('₦120,000.00'), findsOneWidget);
    expect(find.text('8 sales'), findsOneWidget);
  });

  testWidgets('copies the staff code from their home', (tester) async {
    final clipboard = mockClipboard(tester);
    final (dashboard, business, auth) = await signedInStaff(clientWith(summaryBody()));
    await pumpDashboard(tester, dashboard, business, auth);

    await tester.tap(find.byTooltip('Copy code'));
    await tester.pumpAndSettle();

    expect(clipboard, ['ABC47-03']);
    expect(find.text('Code copied.'), findsOneWidget);
  });

  testWidgets('quick actions reach the staff-appropriate screens', (tester) async {
    var newSale = false;
    var addCustomer = false;
    var products = false;
    var ai = false;
    var logistics = false;

    final (dashboard, business, auth) = await signedInStaff(clientWith(summaryBody()));
    await pumpDashboard(
      tester,
      dashboard,
      business,
      auth,
      onManualEntry: () => newSale = true,
      onAddCustomer: () => addCustomer = true,
      onOpenProducts: () => products = true,
      onGoToAiChat: () => ai = true,
      onGoToLogistics: () => logistics = true,
    );

    await tester.tap(find.text('New sale'));
    await tester.tap(find.text('Add customer'));
    await tester.tap(find.text('Products'));
    await tester.tap(find.text('Import sale'));
    await tester.pumpAndSettle();

    expect(newSale, isTrue);
    expect(addCustomer, isTrue);
    expect(products, isTrue);
    expect(ai, isTrue);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(logistics, isTrue);
  });

  testWidgets('an empty day invites the first sale instead of showing zeros only', (tester) async {
    final empty = summaryBody()
      ..['totals'] = {
        'transactionCount': 0,
        'grossSalesKobo': 0,
        'collectedKobo': 0,
        'outstandingKobo': 0,
      }
      ..['recent'] = <Object>[]
      ..['topProducts'] = <Object>[]
      ..['periods'] = {
        'today': period(count: 0, gross: 0, collected: 0, outstanding: 0),
        'week': period(count: 0, gross: 0, collected: 0, outstanding: 0),
        'month': period(count: 0, gross: 0, collected: 0, outstanding: 0),
        'allTime': period(count: 0, gross: 0, collected: 0, outstanding: 0),
      };

    final (dashboard, business, auth) = await signedInStaff(clientWith(empty));
    await pumpDashboard(tester, dashboard, business, auth);

    expect(find.text('No sales yet.'), findsOneWidget);
    expect(find.text('Record your first sale'), findsOneWidget);
  });
}
