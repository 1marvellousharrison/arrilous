import 'dart:convert';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/dashboard_repository.dart';
import 'package:dee_app/core/state/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// Phases 9-12 client state.
///
/// The interesting assertions here are the ones about what the client refuses
/// to send: a sale must never carry a total, and a catalog line must never carry
/// a price. Those are the guarantees that keep the server's recomputation
/// meaningful rather than decorative.
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

  Map<String, dynamic> transactionJson({
    String id = 'txn-1',
    String number = 'TXN-2026-00001',
    String orderStatus = 'pending',
    String paymentStatus = 'unpaid',
    String deliveryStatus = 'not_required',
    String completionStatus = 'open',
    bool deliveryRequired = false,
    int subtotal = 1_500_000,
    int discount = 0,
    int deliveryFee = 0,
    int total = 1_500_000,
  }) =>
      {
        'id': id,
        'businessId': 'business-1',
        'customerId': null,
        'transactionNumber': number,
        'source': 'manual',
        'subtotalKobo': subtotal,
        'discountKobo': discount,
        'deliveryFeeKobo': deliveryFee,
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

  Future<T> withRepo<T>(
    Future<http.Response> Function(http.Request request) handler,
    T Function(TransactionRepository transactions, DashboardRepository dashboard)
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

    final transactions = TransactionRepository(api, auth);
    final dashboard = DashboardRepository(api, auth);
    return build(transactions, dashboard);
  }

  /// The POST that records a sale.
  ///
  /// Signing in is also a POST, so matching on the method alone picks the login
  /// request and quietly asserts against the wrong body.
  http.Request salePost() => log.firstWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/transactions'),
      );

  setUp(() {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('TransactionRepository — creating a sale', () {
    test('sends items and charges but never a total', () async {
      await withRepo(
        (request) async {
          if (request.method == 'POST') {
            return json({'transaction': transactionJson()}, status: 201);
          }
          return json({'transactions': []});
        },
        (transactions, _) async {
          await transactions.create(
            items: [
              DraftItem(name: 'Black Shirt', productId: 'product-1', quantity: 2, unitPriceKobo: 1_500_000),
            ],
            discountKobo: 100_000,
            deliveryFeeKobo: 50_000,
          );

          final post = salePost();
          final body = jsonDecode(post.body) as Map<String, dynamic>;

          expect(body['discount_kobo'], 100_000);
          expect(body['delivery_fee_kobo'], 50_000);
          expect(body['source'], 'manual');
          expect(body.containsKey('subtotal_kobo'), isFalse);
          expect(body.containsKey('total_kobo'), isFalse);
        },
      );
    });

    test('a catalog line sends only the product id and quantity', () async {
      await withRepo(
        (request) async => request.method == 'POST'
            ? json({'transaction': transactionJson()}, status: 201)
            : json({'transactions': []}),
        (transactions, _) async {
          await transactions.create(
            items: [
              DraftItem(
                name: 'Black Shirt',
                productId: 'product-1',
                quantity: 3,
                unitPriceKobo: 1_500_000,
              ),
            ],
          );

          final body = jsonDecode(salePost().body)
              as Map<String, dynamic>;
          final item = (body['items'] as List).first as Map<String, dynamic>;

          expect(item['product_id'], 'product-1');
          expect(item['quantity'], 3);
          // The server reads name and price from the catalog, so sending them
          // would only offer a way to sell at the wrong price.
          expect(item.containsKey('unit_price_kobo'), isFalse);
          expect(item.containsKey('name'), isFalse);
        },
      );
    });

    test('a one-off line sends its own name and price', () async {
      await withRepo(
        (request) async => request.method == 'POST'
            ? json({'transaction': transactionJson()}, status: 201)
            : json({'transactions': []}),
        (transactions, _) async {
          await transactions.create(
            items: [
              DraftItem(name: 'Singe pair', quantity: 2, unitPriceKobo: 45_000),
            ],
          );

          final body = jsonDecode(salePost().body)
              as Map<String, dynamic>;
          final item = (body['items'] as List).first as Map<String, dynamic>;

          expect(item['name'], 'Singe pair');
          expect(item['unit_price_kobo'], 45_000);
          expect(item.containsKey('product_id'), isFalse);
        },
      );
    });

    test('refuses to create a sale with no items', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          await expectLater(
            transactions.create(items: const []),
            throwsA(isA<ApiException>()),
          );
          // Signing in is also a POST, so check the sale endpoint specifically.
          expect(
            log.where((r) => r.method == 'POST' && r.url.path.endsWith('/transactions')),
            isEmpty,
          );
        },
      );
    });

    test('a sale that saves is reported as saved even if the refresh fails', () async {
      // The dangerous case: the POST succeeds but the follow-up detail read
      // fails. Throwing here would tell the owner their sale failed when it
      // exists, and their retry would create a duplicate.
      await withRepo(
        (request) async {
          if (request.method == 'POST') {
            return json({
              'transaction': {
                ...transactionJson(),
                'items': [
                  {
                    'id': 'item-1',
                    'transactionId': 'txn-1',
                    'productId': 'product-1',
                    'name': 'Black Shirt',
                    'quantity': 2,
                    'unitPriceKobo': 1_500_000,
                    'subtotalKobo': 3_000_000,
                  },
                ],
              },
            }, status: 201);
          }
          if (request.method == 'GET') {
            return json(
              {'error': {'code': 'not_found', 'message': 'Gone for now.'}},
              status: 404,
            );
          }
          return json({'transactions': []});
        },
        (transactions, _) async {
          final created = await transactions.create(
            items: [
              DraftItem(
                name: 'Black Shirt',
                productId: 'product-1',
                quantity: 2,
                unitPriceKobo: 1_500_000,
              ),
            ],
          );

          expect(created.transactionNumber, 'TXN-2026-00001');
          expect(created.items, hasLength(1), reason: 'the items from the create response are kept');
        },
      );
    });

    test('an unreadable create response says so instead of pretending', () async {
      await withRepo(
        (request) async => request.method == 'POST'
            ? json({'ok': true}, status: 201)
            : json({'transactions': []}),
        (transactions, _) async {
          await expectLater(
            transactions.create(
              items: [DraftItem(name: 'Shirt', quantity: 1, unitPriceKobo: 100)],
            ),
            throwsA(isA<ApiException>()),
          );
        },
      );
    });

    test('blank notes and addresses are sent as null', () async {
      await withRepo(
        (request) async => request.method == 'POST'
            ? json({'transaction': transactionJson()}, status: 201)
            : json({'transactions': []}),
        (transactions, _) async {
          await transactions.create(
            items: [DraftItem(name: 'Shirt', quantity: 1, unitPriceKobo: 100)],
            notes: '   ',
            deliveryAddress: '',
          );

          final body = jsonDecode(salePost().body)
              as Map<String, dynamic>;
          expect(body['notes'], isNull);
          expect(body['delivery_address'], isNull);
        },
      );
    });
  });

  group('TransactionRepository — reading', () {
    test('sends filters as query parameters', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          await transactions.load();
          await transactions.setSearch('TXN-9');
          await transactions.setFilter(field: 'payment', value: 'paid');
          await transactions.setFilter(field: 'source', value: 'manual');

          final urls = log.map((r) => r.url.toString()).toList();
          expect(urls.any((u) => u.contains('search=TXN-9')), isTrue);
          expect(urls.any((u) => u.contains('payment_status=paid')), isTrue);
          expect(urls.any((u) => u.contains('source=manual')), isTrue);
        },
      );
    });

    test('clearing a filter sends it as absent, not empty', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          await transactions.setFilter(field: 'payment', value: 'paid');
          await transactions.setFilter(field: 'payment');

          final last = log.last.url.toString();
          expect(last.contains('payment_status=paid'), isFalse);
          expect(transactions.hasFilters, isFalse);
        },
      );
    });

    test('an unknown filter field is a programming error, not a silent no-op',
        () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          expect(
            () => transactions.setFilter(field: 'colour', value: 'red'),
            throwsArgumentError,
          );
        },
      );
    });

    test('a date range is sent', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          await transactions.setDateRange(
            from: DateTime(2026, 10, 1),
            to: DateTime(2026, 10, 31),
          );
          expect(transactions.from, isNotNull);
          expect(transactions.to, isNotNull);
          // UTC, so the server does not have to guess the client's zone.
          expect(log.last.url.query, contains('from='));
          expect(log.last.url.query, contains('Z'));
          expect(
            log.last.url.queryParameters['from'],
            DateTime(2026, 10, 1).toUtc().toIso8601String(),
          );
        },
      );
    });

    test('changing a filter resets paging', () async {
      await withRepo(
        (_) async => json({
          // A full page, so there is more to fetch and paging is exercised.
          'transactions': [
            for (var i = 0; i < 25; i++) transactionJson(id: 'txn-$i'),
          ],
        }),
        (transactions, _) async {
          await transactions.load();
          await transactions.loadMore();
          expect(transactions.offset, greaterThan(0));

          await transactions.setFilter(field: 'order', value: 'confirmed');
          expect(transactions.offset, 0, reason: 'a new filter starts from the top again');
        },
      );
    });

    test('the detail view carries items, customer and the Phase 8 timeline',
        () async {
      await withRepo(
        (request) async {
          if (request.url.path.endsWith('/transactions/txn-1')) {
            return json({
              'transaction': {
                ...transactionJson(),
                'items': [
                  {
                    'id': 'item-1',
                    'transactionId': 'txn-1',
                    'productId': 'product-1',
                    'name': 'Black Shirt',
                    'quantity': 2,
                    'unitPriceKobo': 1_500_000,
                    'subtotalKobo': 3_000_000,
                  },
                ],
              },
              'customer': {'id': 'customer-1', 'name': 'Ada Nwosu'},
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
          return json({'transactions': []});
        },
        (transactions, _) async {
          await transactions.loadDetail('txn-1');
          final detail = transactions.detail!;

          expect(detail.customerName, 'Ada Nwosu');
          expect(detail.items, hasLength(1));
          expect(detail.items.first.subtotalKobo, 3_000_000);
          expect(detail.items.first.isAdHoc, isFalse);
          expect(detail.history, hasLength(2));

          // A creation entry has no previous value and must not read as
          // "null -> pending".
          expect(detail.history.first.isCreation, isTrue);
          expect(detail.history.first.label, 'Order set to Pending');
          expect(detail.history.last.label, 'Order: Pending → Confirmed');
        },
      );
    });

    test('a missing transaction surfaces the server message', () async {
      await withRepo(
        (_) async => json(
          {
            'error': {'code': 'not_found', 'message': 'That transaction does not exist.'},
          },
          status: 404,
        ),
        (transactions, _) async {
          await transactions.loadDetail('nope');
          expect(transactions.detail, isNull);
          expect(transactions.detailError, 'That transaction does not exist.');
        },
      );
    });
  });

  group('TransactionRepository — status actions', () {
    test('a pending order offers confirm and cancel', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          final txn = Transaction.fromJson(transactionJson());
          expect(
            transactions.availableTransitions(txn, TransactionAxis.order),
            ['confirmed', 'cancelled'],
          );
        },
      );
    });

    test('a cancelled order is frozen on every axis except a refund', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          final txn = Transaction.fromJson(
            transactionJson(orderStatus: 'cancelled', paymentStatus: 'paid'),
          );
          // Payment is deliberately excluded here: a cancelled sale that took
          // money can still be refunded, which has its own test below.
          for (final axis in const [
            TransactionAxis.order,
            TransactionAxis.delivery,
            TransactionAxis.completion,
          ]) {
            expect(
              transactions.availableTransitions(txn, axis),
              isEmpty,
              reason: 'a cancelled sale is frozen on ${axis.wire}',
            );
          }
        },
      );
    });

    test('a cancelled sale that took money still offers exactly one refund',
        () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          final txn = Transaction.fromJson(
            transactionJson(orderStatus: 'cancelled', paymentStatus: 'paid'),
          );
          expect(
            transactions.availableTransitions(txn, TransactionAxis.payment),
            ['refunded'],
          );
          // Completing a cancelled sale is never offered.
          expect(
            transactions.availableTransitions(txn, TransactionAxis.completion),
            isEmpty,
          );
        },
      );
    });

    test('a refund is not offered from payment_pending, which cannot reach it',
        () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          // The server's payment table has no payment_pending → refunded edge,
          // so offering it would be an action the API always refuses.
          final txn = Transaction.fromJson(
            transactionJson(orderStatus: 'cancelled', paymentStatus: 'payment_pending'),
          );
          expect(
            transactions.availableTransitions(txn, TransactionAxis.payment),
            isEmpty,
          );
        },
      );
    });

    test('completing waits for payment and delivery, as the server requires',
        () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          // Unpaid and undelivered: the server would reject a completion.
          final unpaid = Transaction.fromJson(transactionJson());
          expect(
            transactions.availableTransitions(unpaid, TransactionAxis.completion),
            isEmpty,
          );

          // Paid, nothing to deliver.
          final paid = Transaction.fromJson(transactionJson(paymentStatus: 'paid'));
          expect(
            transactions.availableTransitions(paid, TransactionAxis.completion),
            ['completed'],
          );

          // Paid but still out for delivery.
          final inFlight = Transaction.fromJson(
            transactionJson(
              paymentStatus: 'paid',
              deliveryRequired: true,
              deliveryStatus: 'in_transit',
            ),
          );
          expect(
            transactions.availableTransitions(inFlight, TransactionAxis.completion),
            isEmpty,
          );

          // Paid and delivered.
          final delivered = Transaction.fromJson(
            transactionJson(
              paymentStatus: 'paid',
              deliveryRequired: true,
              deliveryStatus: 'delivered',
            ),
          );
          expect(
            transactions.availableTransitions(delivered, TransactionAxis.completion),
            ['completed'],
          );
        },
      );
    });

    test('a completed sale is frozen, including cancelling it', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          // Cancelling a completed sale is refused by the server ("a cancelled
          // transaction cannot also be completed"), so it must not be offered.
          final txn = Transaction.fromJson(
            transactionJson(
              orderStatus: 'confirmed',
              paymentStatus: 'paid',
              completionStatus: 'completed',
            ),
          );
          for (final axis in TransactionAxis.values) {
            expect(
              transactions.availableTransitions(txn, axis),
              isEmpty,
              reason: 'nothing may move on a completed sale (${axis.wire})',
            );
          }
        },
      );
    });

    test('delivery actions are hidden when the sale needs no delivery', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          final txn = Transaction.fromJson(transactionJson());
          expect(
            transactions.availableTransitions(txn, TransactionAxis.delivery),
            isEmpty,
          );

          final delivering = Transaction.fromJson(
            transactionJson(deliveryRequired: true, deliveryStatus: 'pending'),
          );
          expect(
            transactions.availableTransitions(delivering, TransactionAxis.delivery),
            ['accepted', 'failed'],
          );
        },
      );
    });

    test('a finished axis offers nothing', () async {
      await withRepo(
        (_) async => json({'transactions': []}),
        (transactions, _) async {
          final txn = Transaction.fromJson(
            transactionJson(completionStatus: 'completed', paymentStatus: 'paid'),
          );
          expect(
            transactions.availableTransitions(txn, TransactionAxis.completion),
            isEmpty,
          );
          // Delivery is a separate axis and keeps its own state.
          expect(
            transactions.availableTransitions(txn, TransactionAxis.delivery),
            isEmpty,
            reason: 'this sale is not a delivery',
          );
        },
      );
    });

    test('updating a status sends only the changed axis', () async {
      await withRepo(
        (request) async {
          if (request.method == 'PATCH') {
            return json({
              'transaction': transactionJson(orderStatus: 'confirmed'),
            });
          }
          return json({'transactions': []});
        },
        (transactions, _) async {
          await transactions.loadDetail('txn-1');
          await transactions.updateStatuses(
            {'orderStatus': 'confirmed'},
            note: 'Confirmed by phone',
          );

          final patch = log.firstWhere((r) => r.method == 'PATCH');
          final body = jsonDecode(patch.body) as Map<String, dynamic>;

          expect(body['orderStatus'], 'confirmed');
          expect(body['note'], 'Confirmed by phone');
          expect(body.containsKey('paymentStatus'), isFalse);
          expect(body.containsKey('completionStatus'), isFalse);
        },
      );
    });

    test('an empty note is not sent', () async {
      await withRepo(
        (request) async => request.method == 'PATCH'
            ? json({'transaction': transactionJson(paymentStatus: 'paid')})
            : json({'transactions': []}),
        (transactions, _) async {
          await transactions.loadDetail('txn-1');
          await transactions.updateStatuses({'paymentStatus': 'paid'}, note: '   ');

          final body = jsonDecode(log.firstWhere((r) => r.method == 'PATCH').body)
              as Map<String, dynamic>;
          expect(body.containsKey('note'), isFalse);
        },
      );
    });
  });

  group('DashboardRepository', () {
    test('reads totals, counts and recent transactions', () async {
      await withRepo(
        (_) async => json({
          'totals': {
            'transactionCount': 4,
            'grossSalesKobo': 4_500_000,
            'collectedKobo': 3_000_000,
            'outstandingKobo': 1_500_000,
          },
          'counts': {
            'pendingOrder': 2,
            'pendingPayment': 1,
            'awaitingDelivery': 1,
            'inTransit': 0,
            'completed': 1,
            'failed': 0,
            'cancelled': 1,
          },
          'recent': [transactionJson()],
          'catalog': {'activeProducts': 6, 'customers': 3},
        }),
        (_, dashboard) async {
          await dashboard.load();
          final summary = dashboard.summary!;

          expect(summary.transactionCount, 4);
          expect(summary.grossSalesKobo, 4_500_000);
          expect(summary.collectedKobo, 3_000_000);
          expect(summary.outstandingKobo, 1_500_000);
          expect(summary.pendingPayment, 1);
          expect(summary.completed, 1);
          expect(summary.cancelled, 1);
          expect(summary.recent, hasLength(1));
          expect(summary.activeProducts, 6, reason: 'from the API, not a loaded page');
          expect(summary.customerCount, 3);
          expect(summary.needsAttention, isTrue, reason: 'money is still owed');
        },
      );
    });

    test('a brand new business is empty rather than an error', () async {
      await withRepo(
        (_) async => json({
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
        }),
        (_, dashboard) async {
          await dashboard.load();
          expect(dashboard.summary!.isEmpty, isTrue);
          expect(dashboard.summary!.needsAttention, isFalse);
          expect(dashboard.error, isNull);
        },
      );
    });

    test('a missing totals block does not crash the dashboard', () async {
      await withRepo(
        (_) async => json({'recent': <Object>[]}),
        (_, dashboard) async {
          await dashboard.load();
          expect(dashboard.summary, isNotNull);
          expect(dashboard.summary!.grossSalesKobo, 0);
        },
      );
    });

    test('a server error is surfaced, not rendered as zero', () async {
      await withRepo(
        (_) async => json(
          {'error': {'code': 'internal', 'message': 'Something broke.'}},
          status: 500,
        ),
        (_, dashboard) async {
          await dashboard.load();
          expect(dashboard.summary, isNull);
          expect(dashboard.error, 'Something broke.');
        },
      );
    });

    test('requests the summary endpoint', () async {
      await withRepo(
        (_) async => json({'totals': <String, Object>{}, 'recent': <Object>[]}),
        (_, dashboard) async {
          await dashboard.load();
          expect(log.last.url.path, '/api/v1/dashboard/summary');
        },
      );
    });
  });
}