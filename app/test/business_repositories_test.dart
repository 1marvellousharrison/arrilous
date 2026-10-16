import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

void main() {
  const base = 'http://localhost:4000/api/v1';

  late List<http.Request> log;
  late AuthRepository auth;

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

  final businessBody = {
    'business': {
      'id': 'business-1',
      'ownerUserId': 'user-123',
      'businessName': 'Ada Provisions',
      'businessCategory': 'Groceries',
      'businessDescription': null,
      'phone': null,
      'email': null,
      'location': null,
    },
  };

  /// Builds one repository wired to a scripted HTTP handler, after signing a
  /// business owner in so the access token exists.
  Future<T> withRepo<T>(
    Future<http.Response> Function(http.Request request) handler,
    T Function(BusinessRepository business, CatalogRepository catalog,
            CustomerRepository customers)
        build,
  ) async {
    final client = MockClient((request) {
      log.add(request);
      if (request.url.path.endsWith('/auth/login')) {
        return Future.value(json(sessionBody));
      }
      return handler(request);
    });
    final api = ApiClient(baseUrl: base, client: client);
    auth = AuthRepository(
      api,
      SessionStore(secure: FakeUnavailableSecureStorage()),
    );
    await auth.signIn(identifier: 'ada@example.com', password: 'Str0ngPass!23');

    final business = BusinessRepository(api, auth);
    final catalog = CatalogRepository(api, auth);
    final customers = CustomerRepository(api, auth);
    return build(business, catalog, customers);
  }

  setUp(() {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('BusinessRepository', () {
    test('reports no business before setup, and ready once loaded', () async {
      await withRepo(
        (_) async => json({'business': null}),
        (business, _, _) async {
          await business.load();
          expect(business.isReady, isTrue);
          expect(business.hasProfile, isFalse);
          expect(business.needsSetup, isTrue);
        },
      );
    });

    test('is not ready while setup has completed', () async {
      await withRepo(
        (_) async => json({
          'business': {
            ...businessBody['business'] as Map<String, dynamic>,
            'location': {
              'id': 'loc-1',
              'businessId': 'business-1',
              'address': '12 Allen Avenue',
              'area': 'Allen Hill',
              'city': 'Ikeja',
              'state': null,
              'country': 'Nigeria',
              'latitude': null,
              'longitude': null,
            },
          },
        }),
        (business, _, _) async {
          await business.load();
          expect(business.hasProfile, isTrue);
          expect(business.hasLocation, isTrue);
          expect(business.needsSetup, isFalse);
          expect(business.business!.location!.oneLine, '12 Allen Avenue, Allen Hill, Ikeja, Nigeria');
        },
      );
    });

    test('asks for the details logistics needs until they are all on file', () async {
      Map<String, dynamic> profile({
        String? phone,
        String? area,
        bool withLocation = true,
      }) =>
          {
            ...businessBody['business'] as Map<String, dynamic>,
            'phone': phone,
            'location': withLocation
                ? {
                    'id': 'loc-1',
                    'businessId': 'business-1',
                    'address': '12 Allen Avenue',
                    'area': area,
                    'city': 'Ikeja',
                    'state': 'Lagos',
                  }
                : null,
          };

      await withRepo(
        (_) async => json({
          'business': profile(phone: '+2348012345678', area: 'Allen Hill'),
        }),
        (business, _, _) async {
          await business.load();
          expect(business.needsLogisticsDetails, isFalse, reason: 'the name, the contact and city/area/state are on file');
        },
      );

      await withRepo(
        (_) async => json({'business': profile(phone: '+2348012345678')}),
        (business, _, _) async {
          await business.load();
          expect(business.needsLogisticsDetails, isTrue, reason: 'the area the rider reads is missing');
        },
      );

      await withRepo(
        (_) async => json({'business': profile(area: 'Allen Hill', withLocation: false)}),
        (business, _, _) async {
          await business.load();
          expect(business.needsLogisticsDetails, isFalse, reason: 'no location yet — the setup gate owns that case');
        },
      );

      await withRepo(
        (_) async => json({'business': null}),
        (business, _, _) async {
          await business.load();
          expect(business.needsLogisticsDetails, isFalse, reason: 'no business at all — the setup gate owns that case');
        },
      );
    });

    test('never sends an owner id, because the server derives it from the token',
        () async {
      await withRepo(
        (_) async => json(businessBody, status: 201),
        (business, _, _) async {
          await business.createProfile(
            businessName: 'Ada Provisions',
            category: 'Groceries',
          );
          final body = jsonDecode(log.last.body) as Map<String, dynamic>;
          expect(body.containsKey('owner_user_id'), isFalse);
          expect(body['business_name'], 'Ada Provisions');
          expect(log.last.headers['authorization'], 'Bearer access-token-1');
        },
      );
    });

    test('sends blank optional fields as null so they are cleared', () async {
      await withRepo(
        (_) async => json(businessBody, status: 201),
        (business, _, _) async {
          await business.createProfile(businessName: 'Ada', phone: '   ');
          final body = jsonDecode(log.last.body) as Map<String, dynamic>;
          expect(body['phone'], isNull);
        },
      );
    });

    test('upserts the location and adopts the returned profile', () async {
      await withRepo(
        (_) async => json({
          'location': {'id': 'loc-1', 'businessId': 'business-1', 'address': 'New Address'},
          'business': {
            ...businessBody['business'] as Map<String, dynamic>,
            'location': {
              'id': 'loc-1',
              'businessId': 'business-1',
              'address': 'New Address',
            },
          },
        }),
        (business, _, _) async {
          await business.saveLocation(
            address: 'New Address',
            area: 'Allen Hill',
            latitude: 9.0579,
            longitude: 7.4895,
          );
          expect(log.last.method, 'PUT');
          final body = jsonDecode(log.last.body) as Map<String, dynamic>;
          expect(body['area'], 'Allen Hill');
          expect(body['latitude'], 9.0579);
          expect(body['longitude'], 7.4895);
          expect(business.hasLocation, isTrue);
          // The response carries the refreshed profile, so the cache must hold
          // the new address without a second round trip.
          expect(business.business!.location!.address, 'New Address');
        },
      );
    });

    test('sends the owner-confirmation token on profile and location writes', () async {
      await withRepo(
        (_) async => json(businessBody),
        (business, _, _) async {
          await business.updateProfile(businessName: 'Ada', editToken: 'edit-token-1');
          expect(log.last.headers['x-business-edit-token'], 'edit-token-1');

          await business.saveLocation(address: 'New Address', editToken: 'edit-token-1');
          expect(log.last.headers['x-business-edit-token'], 'edit-token-1');
        },
      );
    });

    test('omits the edit token when none is held, as first-time setup does', () async {
      await withRepo(
        (_) async => json(businessBody, status: 201),
        (business, _, _) async {
          await business.createProfile(businessName: 'Ada');
          expect(log.last.headers.containsKey('x-business-edit-token'), isFalse);
        },
      );
    });

    test('requests an edit-otp challenge and reads where it was sent', () async {
      await withRepo(
        (_) async => json({
          'challenge_id': 'edit-1',
          'destination': 'a***@example.com',
        }),
        (business, _, _) async {
          final challenge = await business.requestEditOtp();
          expect(challenge.challengeId, 'edit-1');
          expect(challenge.destination, 'a***@example.com');
          expect(log.last.method, 'POST');
          expect(log.last.url.path.endsWith('/business/edit-otp'), isTrue);
        },
      );
    });

    test('verifies the edit code and returns the token it mints', () async {
      await withRepo(
        (_) async => json({'edit_token': 'edit-token-1'}),
        (business, _, _) async {
          final token = await business.verifyEditOtp(challengeId: 'edit-1', code: '123456');
          expect(token, 'edit-token-1');
          final body = jsonDecode(log.last.body) as Map<String, dynamic>;
          expect(body['challenge_id'], 'edit-1');
          expect(body['code'], '123456');
        },
      );
    });

    test('surfaces a server field error for the form', () async {
      await withRepo(
        (_) async => json({
          'error': {
            'code': 'validation_failed',
            'message': 'Some fields need your attention.',
            'details': [
              {'field': 'business_name', 'message': 'Business name is required.'},
            ],
          },
        }, status: 422),
        (business, _, _) async {
          try {
            await business.createProfile(businessName: '');
            fail('expected ApiException');
          } on ApiException catch (error) {
            expect(error.isValidation, isTrue);
            expect(error.fieldError('business_name'), 'Business name is required.');
          }
        },
      );
    });

    test('reset clears cached state so the next sign-in starts empty', () async {
      await withRepo(
        (_) async => json(businessBody),
        (business, _, _) async {
          await business.load();
          expect(business.hasProfile, isTrue);
          business.reset();
          expect(business.hasProfile, isFalse);
          expect(business.isReady, isFalse);
        },
      );
    });
  });

  group('CatalogRepository', () {
    final productJson = {
      'id': 'product-1',
      'businessId': 'business-1',
      'name': 'Rice 50kg',
      'priceKobo': 2500050,
      'stockQuantity': 0,
      'active': true,
    };

    test('parses prices as integer kobo', () async {
      await withRepo(
        (_) async => json({'products': [productJson]}),
        (_, catalog, _) async {
          await catalog.load();
          expect(catalog.products.single.name, 'Rice 50kg');
          expect(catalog.products.single.priceKobo, 2500050);
          expect(catalog.products.single.isOutOfStock, isTrue);
        },
      );
    });

    test('sends search and category as query parameters', () async {
      await withRepo(
        (_) async => json({'products': <Object>[]}),
        (_, catalog, _) async {
          await catalog.setSearch('rice');
          await catalog.setCategory('Grains');
          expect(log.last.url.queryParameters['search'], 'rice');
          expect(log.last.url.queryParameters['category'], 'Grains');
        },
      );
    });

    test('omits the archived filter until it is switched on', () async {
      await withRepo(
        (_) async => json({'products': <Object>[]}),
        (_, catalog, _) async {
          await catalog.load();
          expect(log.last.url.queryParameters.containsKey('include_archived'), isFalse);
          await catalog.setIncludeArchived(true);
          expect(log.last.url.queryParameters['include_archived'], 'true');
        },
      );
    });

    test('POSTs a new product with the kobo price as a number', () async {
      await withRepo(
        (_) async => json({'product': productJson}, status: 201),
        (_, catalog, _) async {
          await catalog.save(
            name: 'Rice 50kg',
            priceKobo: 2500050,
            stockQuantity: 10,
          );
          // save() reloads the list afterwards, so target the product write
          // itself rather than whatever request happened to come last.
          final post = log.firstWhere(
            (request) => request.method == 'POST' && request.url.path.endsWith('/products'),
          );
          final body = jsonDecode(post.body) as Map<String, dynamic>;
          expect(body['price_kobo'], 2500050);
          expect(body['price_kobo'], isA<int>());
          expect(body['stock_quantity'], 10);
        },
      );
    });

    test('PATCHes an existing product', () async {
      await withRepo(
        (_) async => json({'product': productJson}),
        (_, catalog, _) async {
          await catalog.save(
            id: 'product-1',
            name: 'Rice 50kg',
            priceKobo: 100,
            stockQuantity: 1,
          );
          final patch = log.firstWhere((request) => request.method == 'PATCH');
          expect(patch.url.path, '/api/v1/products/product-1');
        },
      );
    });

    test('archives and restores through separate endpoints', () async {
      await withRepo(
        (_) async => json({'product': productJson}),
        (_, catalog, _) async {
          await catalog.setArchived('product-1', true);
          expect(log.any((r) => r.url.path.endsWith('/archive')), isTrue);
          await catalog.setArchived('product-1', false);
          expect(log.any((r) => r.url.path.endsWith('/restore')), isTrue);
        },
      );
    });

    test('reads categories as a plain string list', () async {
      await withRepo(
        (_) async => json({'categories': ['Grains', 'Noodles']}),
        (_, catalog, _) async {
          await catalog.loadCategories();
          expect(catalog.categories, ['Grains', 'Noodles']);
        },
      );
    });
  });

  group('CustomerRepository', () {
    final customerJson = {
      'id': 'customer-1',
      'businessId': 'business-1',
      'name': 'Ada Nwosu',
      'phone': '+2348011111111',
      'email': null,
      'address': null,
      'notes': null,
      'transactionCount': 2,
      'totalSpentKobo': 600000,
    };

    test('reads the list with its spend summary', () async {
      await withRepo(
        (_) async => json({'customers': [customerJson]}),
        (_, _, customers) async {
          await customers.load();
          expect(customers.customers.single.name, 'Ada Nwosu');
          expect(customers.customers.single.totalSpentKobo, 600000);
          expect(customers.customers.single.transactionCount, 2);
          expect(customers.customers.single.initials, 'AN');
        },
      );
    });

    test('builds initials from a single name', () async {
      await withRepo(
        (_) async => json({'customers': [customerJson]}),
        (_, _, customers) async {
          await customers.load();
          final single = Customer.fromJson({...customerJson, 'name': 'Cher'});
          expect(single.initials, 'C');
          final empty = Customer.fromJson({...customerJson, 'name': '  '});
          expect(empty.initials, '?');
        },
      );
    });

    test('loads a customer with their transactions', () async {
      await withRepo(
        (_) async => json({
          'customer': customerJson,
          'transactions': [
            {
              'id': 'txn-1',
              'transactionNumber': 'TXN-2026-00001',
              'totalKobo': 250000,
              'createdAt': '2026-01-05T10:00:00.000Z',
              'paymentStatus': 'paid',
            },
          ],
        }),
        (_, _, customers) async {
          final detail = await customers.detail('customer-1');
          expect(detail.customer.name, 'Ada Nwosu');
          expect(detail.transactions.single.transactionNumber, 'TXN-2026-00001');
          expect(detail.transactions.single.paymentStatus, 'paid');
        },
      );
    });

    test('sends blank contact fields as null', () async {
      await withRepo(
        (_) async => json({'customer': customerJson}, status: 201),
        (_, _, customers) async {
          await customers.save(name: 'Ada', phone: '  ');
          // save() reloads the list afterwards, so target the write itself.
          final post = log.firstWhere(
            (request) =>
                request.method == 'POST' && request.url.path.endsWith('/customers'),
          );
          final body = jsonDecode(post.body) as Map<String, dynamic>;
          expect(body['name'], 'Ada');
          expect(body['phone'], isNull);
          expect(body['email'], isNull);
        },
      );
    });
  });
}
