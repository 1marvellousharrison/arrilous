import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/ai_repository.dart';
import 'package:dee_app/core/state/app_notifications_repository.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:dee_app/core/state/dashboard_repository.dart';
import 'package:dee_app/core/state/logistics_repository.dart';
import 'package:dee_app/core/state/staff_repository.dart';
import 'package:dee_app/core/state/transaction_repository.dart';
import 'package:dee_app/core/state/wallet_repository.dart';
import 'package:dee_app/features/auth/staff_activation_screen.dart';
import 'package:dee_app/features/home/home_shell_screen.dart';
import 'package:dee_app/features/staff/staff_detail_screen.dart';
import 'package:dee_app/features/staff/staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// Staff accounts (docs/staff-accounts.md): the owner adds staff and issues a
/// code; the staff redeems the code, sets a password, and then works inside a
/// restricted shell.
void main() {
  const base = 'http://localhost:4000/api/v1';

  late List<http.Request> log;

  http.Response json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, Object?> sessionBody({String role = 'business'}) => {
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
          'role': role,
          'emailVerified': false,
          'phoneVerified': false,
        },
      };

  Map<String, Object?> staffJson({
    String id = 'staff-1',
    String name = 'Musa Bello',
    String code = 'ABC47-03',
    String status = 'invited',
    int sales = 0,
    bool? activated,
  }) =>
      {
        'id': id,
        'userId': 'user-$id',
        'businessId': 'business-1',
        'fullName': name,
        'phone': null,
        'staffCode': code,
        'status': status,
        'activatedAt': (activated ?? status == 'active')
            ? '2026-01-02T00:00:00.000Z'
            : null,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'salesCount': sales,
      };

  Map<String, Object?> transactionJson({String number = 'TXN-2026-00001'}) => {
        'id': 'txn-1',
        'businessId': 'business-1',
        'customerId': null,
        'transactionNumber': number,
        'source': 'manual',
        'subtotalKobo': 1_500_000,
        'discountKobo': 0,
        'deliveryFeeKobo': 0,
        'totalKobo': 1_500_000,
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

  /// An auth repository signed in against the mock, plus the staff repository
  /// sharing the same client so per-test handlers see every call.
  Future<(AuthRepository, StaffRepository)> signedInStaff(
    Future<http.Response> Function(http.Request request) handler,
  ) async {
    final client = MockClient((request) {
      log.add(request);
      return handler(request);
    });
    final api = ApiClient(baseUrl: base, client: client);
    final auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');
    return (auth, StaffRepository(api, auth));
  }

  /// Captures whatever the app puts on the clipboard, so a copy action can be
  /// asserted without a real platform channel.
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

  setUp(() {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthRepository — staff activation', () {
    test('claim posts the code and reads back who it belongs to', () async {
      final client = MockClient((request) async {
        log.add(request);
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        return json({
          'staff': {'fullName': 'Musa Bello'},
          'business': {'businessName': 'Ada Provisions'},
        });
      });
      final api = ApiClient(baseUrl: base, client: client);
      final auth = AuthRepository(
        api,
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );

      final claim = await auth.claimStaffCode('abc47-03');

      expect(claim.fullName, 'Musa Bello');
      expect(claim.businessName, 'Ada Provisions');
      final request = log.firstWhere((r) => r.url.path.endsWith('/staff/claim'));
      expect((jsonDecode(request.body) as Map<String, dynamic>)['staff_code'], 'abc47-03');
    });

    test('activate posts the code with the chosen password', () async {
      final client = MockClient((request) async {
        log.add(request);
        return json({'status': 'success'});
      });
      final api = ApiClient(baseUrl: base, client: client);
      final auth = AuthRepository(
        api,
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );

      await auth.activateStaff(staffCode: 'ABC47-03', password: 'Str0ngPass!23');

      final request = log.firstWhere((r) => r.url.path.endsWith('/staff/activate'));
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['staff_code'], 'ABC47-03');
      expect(body['password'], 'Str0ngPass!23');
    });

    test('a claimed code surfaces the server message', () async {
      final client = MockClient((request) async => json({
            'error': {
              'code': 'staff_code_claimed',
              'message': 'This code has already been activated. Sign in instead.',
            }
          }, status: 409));
      final api = ApiClient(baseUrl: base, client: client);
      final auth = AuthRepository(
        api,
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );

      await expectLater(
        auth.claimStaffCode('ABC47-03'),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          'This code has already been activated. Sign in instead.',
        )),
      );
    });
  });

  group('StaffRepository', () {
    test('load maps the owner\'s staff list', () async {
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        return json({
          'staff': [
            staffJson(id: 'staff-1', name: 'Musa Bello', code: 'ABC47-03', status: 'active', sales: 4),
            staffJson(id: 'staff-2', name: 'Ngozi Eze', code: 'ABC47-04', status: 'invited'),
          ],
        });
      });

      await staff.load();

      expect(staff.loaded, isTrue);
      expect(staff.staff, hasLength(2));
      expect(staff.staff.first.staffCode, 'ABC47-03');
      expect(staff.staff.first.isActive, isTrue);
      expect(staff.staff.first.salesCount, 4);
      expect(staff.staff.last.statusLabel, 'Not activated');
    });

    test('create sends the name and phone, then refreshes and returns the code', () async {
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.method == 'POST') {
          return json({'staff': staffJson()}, status: 201);
        }
        return json({'staff': [staffJson()]});
      });

      final created = await staff.create(fullName: 'Musa Bello', phone: '+2348031234567');

      expect(created.staffCode, 'ABC47-03');
      expect(staff.staff, hasLength(1), reason: 'the list is refreshed after adding');

      final post = log.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/staff'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['full_name'], 'Musa Bello');
      expect(body['phone'], '+2348031234567');
    });

    test('setStatus disables in place', () async {
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.method == 'PATCH') {
          return json({'staff': staffJson(status: 'disabled')});
        }
        return json({'staff': [staffJson(status: 'active')]});
      });

      await staff.load();
      await staff.setStatus('staff-1', 'disabled');

      expect(staff.staff.single.isDisabled, isTrue);
    });
  });

  group('StaffActivationScreen', () {
    testWidgets('a malformed code is refused before any request', (tester) async {
      final client = MockClient((request) async {
        log.add(request);
        return json({'status': 'success'});
      });
      final auth = AuthRepository(
        ApiClient(baseUrl: base, client: client),
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );

      await tester.pumpWidget(MaterialApp(home: StaffActivationScreen(auth: auth)));

      await tester.enterText(find.byType(TextFormField).first, 'hello');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Staff codes look like ABC47-03.'), findsOneWidget);
      expect(log, isEmpty, reason: 'the claim must not be attempted');
    });

    testWidgets('a valid code reveals the business, then activation pops the code', (tester) async {
      String? popped;
      final client = MockClient((request) async {
        log.add(request);
        if (request.url.path.endsWith('/staff/claim')) {
          return json({
            'staff': {'fullName': 'Musa Bello'},
            'business': {'businessName': 'Ada Provisions'},
          });
        }
        return json({'status': 'success'});
      });
      final auth = AuthRepository(
        ApiClient(baseUrl: base, client: client),
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => StaffActivationScreen(auth: auth)),
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'abc47-03');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Set your password'), findsOneWidget);
      expect(find.text('Ada Provisions'), findsOneWidget);
      expect(find.text('ABC47-03'), findsOneWidget, reason: 'the code is uppercased');

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Str0ngPass!23');
      await tester.enterText(fields.at(1), 'Str0ngPass!23');
      await tester.tap(find.text('Activate account'));
      await tester.pumpAndSettle();

      expect(popped, 'ABC47-03', reason: 'the code is handed back so the login can prefill it');
    });

    testWidgets('mismatched passwords are refused before activating', (tester) async {
      final client = MockClient((request) async {
        log.add(request);
        if (request.url.path.endsWith('/staff/claim')) {
          return json({
            'staff': {'fullName': 'Musa Bello'},
            'business': {'businessName': 'Ada Provisions'},
          });
        }
        return json({'status': 'success'});
      });
      final auth = AuthRepository(
        ApiClient(baseUrl: base, client: client),
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );

      await tester.pumpWidget(MaterialApp(home: StaffActivationScreen(auth: auth)));
      await tester.enterText(find.byType(TextFormField).first, 'ABC47-03');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Str0ngPass!23');
      await tester.enterText(fields.at(1), 'Different1!');
      await tester.tap(find.text('Activate account'));
      await tester.pumpAndSettle();

      expect(log.where((r) => r.url.path.endsWith('/staff/activate')), isEmpty);
      expect(find.text('Passwords do not match.'), findsOneWidget);
    });
  });

  group('StaffScreen', () {
    testWidgets('lists each staff member with their code', (tester) async {
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        return json({
          'staff': [
            staffJson(id: 'staff-1', name: 'Musa Bello', code: 'ABC47-03', status: 'active', sales: 2),
          ],
        });
      });

      await tester.pumpWidget(MaterialApp(home: StaffScreen(staff: staff)));
      await tester.pumpAndSettle();

      expect(find.text('Musa Bello'), findsOneWidget);
      expect(find.text('ABC47-03'), findsOneWidget);
      expect(find.text('2 sales'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('copies an activated staff code from the list', (tester) async {
      final clipboard = mockClipboard(tester);
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        return json({
          'staff': [
            staffJson(status: 'active', sales: 2),
          ],
        });
      });

      await tester.pumpWidget(MaterialApp(home: StaffScreen(staff: staff)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Copy code'));
      await tester.pumpAndSettle();

      expect(clipboard, ['ABC47-03']);
      expect(find.text('Code copied.'), findsOneWidget);
    });

    testWidgets('an empty list explains what staff are for', (tester) async {
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        return json({'staff': <Object>[]});
      });

      await tester.pumpWidget(MaterialApp(home: StaffScreen(staff: staff)));
      await tester.pumpAndSettle();

      expect(find.text('No staff yet'), findsOneWidget);
    });

    testWidgets('adding a staff issues their code', (tester) async {
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.method == 'POST') {
          return json({'staff': staffJson()}, status: 201);
        }
        return json({'staff': <Object>[]});
      });

      await tester.pumpWidget(MaterialApp(home: StaffScreen(staff: staff)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add staff'));
      await tester.pumpAndSettle();

      expect(find.text('Add staff'), findsWidgets);
      await tester.enterText(find.byType(TextFormField).first, 'Musa Bello');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Staff code issued'), findsOneWidget);
      expect(find.text('ABC47-03'), findsWidgets);
    });
  });

  group('StaffDetailScreen', () {
    testWidgets('shows the code, the sales and can disable the staff', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.method == 'PATCH') {
          return json({'staff': staffJson(status: 'disabled', sales: 1, activated: true)});
        }
        if (request.url.path.endsWith('/transactions')) {
          return json({'transactions': [transactionJson()]});
        }
        return json({'staff': staffJson(status: 'active', sales: 1)});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StaffDetailScreen(
            staff: staff,
            member: StaffMember.fromJson(staffJson(status: 'active', sales: 1)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ABC47-03'), findsOneWidget);
      expect(find.textContaining('TXN-2026-00001'), findsOneWidget);

      await tester.tap(find.text('Disable staff'));
      await tester.pumpAndSettle();

      expect(find.text('Enable staff'), findsOneWidget);
      expect(find.text('Musa Bello is now disabled.'), findsOneWidget);
    });

    testWidgets('lists the activity this staff member caused', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.url.path.endsWith('/notifications')) {
          return json({
            'notifications': [
              {
                'id': 'note-1',
                'type': 'sale_recorded',
                'title': 'Sale recorded',
                'message': 'Musa Bello recorded sale TXN-2026-00001 (₦15,000.00).',
                'severity': 'success',
                'transactionId': 'txn-1',
                'createdAt': '2026-10-01T09:00:00.000Z',
              },
              {
                'id': 'note-2',
                'type': 'restock',
                'title': 'Restocked Rice',
                'message': '10 units added; 30 now in stock.',
                'severity': 'info',
                'productId': 'product-1',
                'createdAt': '2026-10-01T10:00:00.000Z',
              },
            ],
          });
        }
        if (request.url.path.endsWith('/transactions')) {
          return json({'transactions': <Object>[]});
        }
        return json({'staff': staffJson(status: 'active', sales: 1)});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StaffDetailScreen(
            staff: staff,
            member: StaffMember.fromJson(staffJson(status: 'active', sales: 1)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Staff activity'), findsOneWidget);
      expect(find.text('Sale recorded'), findsOneWidget);
      expect(
        find.text('Musa Bello recorded sale TXN-2026-00001 (₦15,000.00).'),
        findsOneWidget,
      );
      expect(find.text('Restocked Rice'), findsOneWidget);
      expect(find.textContaining('10 units added'), findsOneWidget);
    });

    testWidgets('copies the code after the staff has activated', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final clipboard = mockClipboard(tester);
      final (_, staff) = await signedInStaff((request) async {
        if (request.url.path.endsWith('/auth/login')) return json(sessionBody());
        if (request.url.path.endsWith('/transactions')) {
          return json({'transactions': <Object>[]});
        }
        return json({'staff': staffJson(status: 'active', activated: true)});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StaffDetailScreen(
            staff: staff,
            member: StaffMember.fromJson(staffJson(status: 'active', activated: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Copy'));
      await tester.pumpAndSettle();

      expect(clipboard, ['ABC47-03']);
      expect(find.text('Code copied.'), findsOneWidget);
    });
  });

  group('the staff shell', () {
    Map<String, Object?> businessProfile() => {
          'business': {
            'id': 'business-1',
            'ownerUserId': 'user-123',
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

    Future<void> pumpStaffShell(
      WidgetTester tester, {
      Map<String, Object?>? profile,
    }) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return json(sessionBody(role: 'staff'));
        }
        if (request.url.path.endsWith('/business')) {
          return json(profile ?? businessProfile());
        }
        return json(<String, Object>{});
      });
      final api = ApiClient(baseUrl: base, client: client);
      final auth = AuthRepository(
        api,
        SessionStore(secure: FakeUnavailableSecureStorage()),
      );
      await auth.signIn(identifier: 'ABC47-03', password: 'Str0ngPass!23');

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
            staff: StaffRepository(api, auth),
            ai: AiRepository(api: api, token: auth.session?.accessToken),
            appNotifications: AppNotificationsRepository(
              api: api,
              token: auth.session?.accessToken,
            ),
            onOpenSettings: () {},
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a staff member is not offered products, staff or business details to manage', (tester) async {
      await pumpStaffShell(tester);

      expect(
        find.byTooltip('Business details'),
        findsNothing,
        reason: 'staff cannot edit the business profile',
      );
      expect(find.text('Add product'), findsNothing, reason: 'staff cannot add products');
      expect(find.text('Add customer'), findsOneWidget, reason: 'staff may add customers');

      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Wallet'), findsNothing, reason: 'the wallet is the owner\'s');
      expect(find.text('Staff'), findsNothing, reason: 'staff do not manage staff');
    });

    testWidgets('a shop without a location still lands on the staff home', (tester) async {
      // The owner may not have finished setup. That is the owner's form to fill
      // in: a staff belongs to a business that already exists, so they get their
      // own home instead of a setup screen whose writes the server refuses.
      final profile = businessProfile();
      (profile['business'] as Map<String, Object?>)['location'] = null;

      await pumpStaffShell(tester, profile: profile);

      expect(find.text('Quick actions'), findsOneWidget);
      expect(find.text('Cannot reach your business yet'), findsNothing);
    });
  });
}
