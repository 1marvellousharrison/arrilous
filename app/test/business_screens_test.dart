import 'dart:convert';
import 'dart:typed_data';

import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/core/services/location_service.dart';
import 'package:dee_app/core/services/logo_service.dart';
import 'package:dee_app/core/state/auth_repository.dart';
import 'package:dee_app/core/state/business_repository.dart';
import 'package:dee_app/core/state/catalog_repository.dart';
import 'package:dee_app/core/state/customer_repository.dart';
import 'package:dee_app/features/business/business_setup_flow.dart';
import 'package:dee_app/features/customers/customer_form_screen.dart';
import 'package:dee_app/features/products/product_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secure_storage.dart';

/// A location service that never touches the GPS, so widget tests do not depend
/// on device sensors.
class _NoLocationService implements LocationService {
  _NoLocationService(this._failure);

  final LocationUnavailable? _failure;

  @override
  Future<DeviceCoordinates?> current() async => null;

  @override
  Future<LocationUnavailable?> lastFailure() async => _failure;
}

class _FixedLocationService implements LocationService {
  @override
  Future<DeviceCoordinates?> current() async =>
      const DeviceCoordinates(latitude: 9.0579, longitude: 7.4895);

  @override
  Future<LocationUnavailable?> lastFailure() async => null;
}

/// A logo picker that never touches the platform, standing in for the gallery.
class _FakeLogoService implements LogoService {
  _FakeLogoService(this.bytes);

  final Uint8List? bytes;

  @override
  Future<Uint8List?> pick() async => bytes;
}

void main() {
  const base = 'http://localhost:4000/api/v1';

  late List<http.Request> log;

  /// The default 800x600 test surface leaves submit buttons below the fold, so
  /// every screen is given a phone-sized surface instead.
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

  final businessJson = {
    'id': 'business-1',
    'ownerUserId': 'user-123',
    'businessName': 'Ada Provisions',
    'businessCategory': 'Groceries',
    'businessDescription': null,
    'phone': null,
    'email': null,
    'location': null,
  };

  /// Signs a business owner in and returns the three repositories.
  Future<
      ({
        BusinessRepository business,
        CatalogRepository catalog,
        CustomerRepository customers,
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
    );
  }

  Widget wrap(Widget child) => MaterialApp(home: child);

  /// The text currently held by the field carrying [label], since a TextField
  /// renders its value through EditableText rather than a descendant Text.
  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(find.widgetWithText(TextFormField, label)).controller!.text;

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  /// Types into the field carrying [label] after making sure it is on screen.
  Future<void> enterField(WidgetTester tester, String label, String text) async {
    final field = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, text);
  }

  /// Picks a category from the dropdown — the field is a list now, so nothing
  /// can be typed into it.
  Future<void> pickCategory(WidgetTester tester, String category) async {
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(category));
    await tester.pumpAndSettle();
  }

  /// Picks [value] from the dropdown carrying [label] — state and city are
  /// lists now, so a location is chosen rather than typed.
  Future<void> pickDropdown(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final dropdown =
        find.widgetWithText(DropdownButtonFormField<String>, label);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  /// Spec 6 — a business profile is only complete with a phone number, a
  /// category and a description of what is sold, so every setup test fills
  /// them alongside the name.
  Future<void> fillProfileDetails(WidgetTester tester, String name) async {
    await enterField(tester, 'Business name', name);
    // The field carries the +234 code itself, so only the ten digits are typed.
    await enterField(tester, 'Phone number', '8012345678');
    await pickCategory(tester, 'Groceries & Provisions');
    await enterField(
      tester,
      'Add what you sell',
      'Provisions and household goods.',
    );
  }

  /// Spec — the delivery partner reads the city, area and state off the pickup
  /// address, so the location step collects all three, not just the street.
  Future<void> fillLocationDetails(
    WidgetTester tester, {
    String address = '12 Allen Avenue',
    String area = 'Allen Hill',
    String city = 'Ikeja',
    String state = 'Lagos',
  }) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Street address'),
      address,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Area'),
      area,
    );
    // The state is chosen first; the city list is the towns of that state.
    await pickDropdown(tester, 'State', state);
    await pickDropdown(tester, 'City / town', city);
  }

  setUp(() {
    log = <http.Request>[];
    SharedPreferences.setMockInitialValues({});
  });

  group('business setup flow', () {
    testWidgets('asks for the business name before moving to the location step',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({'business': null}));

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      expect(find.text('Set up your business'), findsOneWidget);
      expect(find.text('Business name'), findsOneWidget);
      expect(find.text('Street address'), findsNothing);

      // An empty name is rejected without a round trip to the server.
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();
      expect(find.text('Enter your business name.'), findsOneWidget);
      expect(
        log.where((request) => request.url.path.endsWith('/business')),
        isEmpty,
      );
    });

    testWidgets('creates the profile then asks for the address', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business') && request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await fillProfileDetails(tester, 'Ada Provisions');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      expect(find.text('Where is your shop?'), findsOneWidget);
      expect(find.text('Street address'), findsOneWidget);
    });

    testWidgets('an optional logo is picked, previewed and sent with the profile',
        (tester) async {
      useTallSurface(tester);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC',
      );
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business') && request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
        logoService: _FakeLogoService(png),
      )));

      expect(find.text('Business logo (optional)'), findsOneWidget);
      expect(find.text('Add logo'), findsOneWidget);

      await tapLabel(tester, 'Add logo');
      await tester.pumpAndSettle();

      // The picked image replaces the letter tile and a way to remove it shows.
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Remove'), findsOneWidget);

      await fillProfileDetails(tester, 'ada provisions');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['logo_url'], startsWith('data:image/png;base64,'));
      expect(
        body['business_name'],
        'ada provisions',
        reason: 'the name is stored as typed; only its display is capitalised',
      );
    });

    testWidgets('leaving the logo empty falls back to the first letter and sends none',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business') && request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
        logoService: _FakeLogoService(null),
      )));

      await fillProfileDetails(tester, 'ada provisions');
      await tester.pumpAndSettle();

      // No image: the fallback is the capitalised first letter, shown live.
      expect(find.byType(Image), findsNothing);
      expect(find.text('A'), findsOneWidget);

      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['logo_url'], isNull, reason: 'an empty logo is sent as null');
    });

    testWidgets('explains a denied permission and still offers manual entry',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.permissionDenied),
      )));

      await fillProfileDetails(tester, 'Ada');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      await tapLabel(tester, 'Use my current location');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Location permission was declined'),
        findsOneWidget,
      );
      // The manual path is still fully usable.
      expect(find.text('Street address'), findsOneWidget);
    });

    testWidgets('saves a device pin alongside the typed address', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business/location')) {
          return json({
            'business': {
              ...businessJson,
              'location': {
                'id': 'loc-1',
                'businessId': 'business-1',
                'address': '12 Allen Avenue',
              },
            },
          });
        }
        return json({'business': businessJson}, status: 201);
      });

      var completed = false;

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () => completed = true,
        locationService: _FixedLocationService(),
      )));

      await fillProfileDetails(tester, 'Ada');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      await tapLabel(tester, 'Use my current location');
      await tester.pumpAndSettle();
      expect(find.textContaining('Pin added'), findsOneWidget);

      await fillLocationDetails(tester);
      await tapLabel(tester, 'Finish setup');
      await tester.pumpAndSettle();

      expect(
        find.text('Are your details correct?'),
        findsOneWidget,
        reason: 'the owner confirms the details before leaving setup',
      );
      await tester.tap(find.text('Yes, take me back'));
      await tester.pumpAndSettle();

      final put = log.firstWhere((request) => request.method == 'PUT');
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['address'], '12 Allen Avenue');
      expect(body['area'], 'Allen Hill', reason: 'the area the delivery partner reads is saved');
      expect(body['city'], 'Ikeja');
      expect(body['state'], 'Lagos');
      expect(body['latitude'], closeTo(9.0579, 0.0001));
      expect(body['longitude'], closeTo(7.4895, 0.0001));
      expect(completed, isTrue);
    });

    testWidgets('shows the server message on a rejected address', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business/location')) {
          return json({
            'error': {
              'code': 'validation_failed',
              'message': 'Some fields need your attention.',
              'details': [
                {'field': 'address', 'message': 'That street does not exist.'},
              ],
            },
          }, status: 422);
        }
        return json({'business': businessJson}, status: 201);
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await fillProfileDetails(tester, 'Ada');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      await fillLocationDetails(tester);
      await tapLabel(tester, 'Finish setup');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yes, take me back'));
      await tester.pumpAndSettle();

      expect(find.text('That street does not exist.'), findsOneWidget);
      expect(
        find.text('Where is your shop?'),
        findsOneWidget,
        reason: 'a rejected address keeps the owner in business details',
      );
    });

    testWidgets('refuses a location without the city, area and state the rider needs', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business/location')) {
          return json({'business': businessJson});
        }
        return json({'business': businessJson}, status: 201);
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await fillProfileDetails(tester, 'Ada');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Street address'),
        '12 Allen Avenue',
      );
      await tapLabel(tester, 'Finish setup');
      await tester.pumpAndSettle();

      expect(find.text('Enter the area your shop is in.'), findsOneWidget);
      // State and city are chosen from lists now, so the messages name the
      // list rather than asking for a typed word.
      expect(find.text('Select a state.'), findsOneWidget);
      expect(find.text('Choose a state first.'), findsOneWidget);
      expect(
        find.text('Country (optional)'),
        findsNothing,
        reason: 'the shop is found by its city, area and state — no country field',
      );
      expect(
        log.where((request) => request.method == 'PUT'),
        isEmpty,
        reason: 'nothing is saved until the delivery partner can find the shop',
      );
    });

    testWidgets('the category is chosen from a list rather than typed', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await enterField(tester, 'Business name', 'Ada Provisions');
      await enterField(tester, 'Phone number', '8012345678');
      await enterField(tester, 'Add what you sell', 'Rice and beans');

      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      expect(find.text('Fashion & Clothing'), findsOneWidget, reason: 'the fixed list is offered');
      expect(find.text('Farm Produce'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);

      await tester.tap(find.text('Farm Produce'));
      await tester.pumpAndSettle();
      expect(find.text('Farm Produce'), findsOneWidget, reason: 'the choice shows in the field');

      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['business_category'], 'Farm Produce');
    });

    testWidgets('Other lets the owner type a category the list is missing', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await enterField(tester, 'Business name', 'Ada Pharmacy');
      await enterField(tester, 'Phone number', '8012345678');
      await enterField(tester, 'Add what you sell', 'Drugs and supplements');

      expect(find.text('Your own category'), findsNothing);

      await pickCategory(tester, 'Other');
      expect(
        find.text('Your own category'),
        findsOneWidget,
        reason: 'choosing Other opens a field for the trade the list does not carry',
      );

      // An empty answer is refused like any other field.
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();
      expect(find.text('Type the category you sell under.'), findsOneWidget);
      expect(
        log.where(
          (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
        ),
        isEmpty,
      );

      await enterField(tester, 'Your own category', 'Chemicals');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(
        body['business_category'],
        'Chemicals',
        reason: 'their own wording is saved and works like any listed category',
      );
      expect(find.text('Where is your shop?'), findsOneWidget);
    });

    testWidgets('what you sell is a list of points added with the plus icon', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await enterField(tester, 'Business name', 'Ada Provisions');
      await enterField(tester, 'Phone number', '8012345678');
      await pickCategory(tester, 'Groceries & Provisions');

      Future<void> addPoint(String text) async {
        await enterField(tester, 'Add what you sell', text);
        await tester.tap(find.byTooltip('Add another thing you sell'));
        await tester.pumpAndSettle();
      }

      await addPoint('Rice');
      await addPoint('Beans');
      await addPoint('Ankara fabric');

      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Beans'), findsOneWidget);
      expect(find.text('Ankara fabric'), findsOneWidget);
      expect(
        find.byTooltip('Remove'),
        findsNWidgets(3),
        reason: 'each point can be taken back',
      );

      await tester.tap(find.byTooltip('Remove').last);
      await tester.pumpAndSettle();
      expect(find.text('Ankara fabric'), findsNothing);

      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(
        body['business_description'],
        'Rice\nBeans',
        reason: 'one point per line, so they come back as points when edited',
      );
      expect(find.text('Where is your shop?'), findsOneWidget);
    });

    testWidgets('the phone field carries +234 and takes only its ten digits', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.method == 'POST') {
          return json({'business': businessJson}, status: 201);
        }
        return json({'business': null});
      });

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () {},
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      final phoneField = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Phone number'),
          matching: find.byType(TextField),
        ),
      );
      expect(
        phoneField.decoration?.prefixText,
        '+234 ',
        reason: 'the Nigerian code sits on the field before the digits',
      );

      // Letters never make it into the field: only numbers can be written.
      await enterField(tester, 'Phone number', 'call me on 803');
      expect(fieldText(tester, 'Phone number'), '803', reason: 'only numbers can be written');

      // The digits land in the '+234 *** *** ****' shape, spaced 3-3-4, and
      // nothing longer than a full number can be entered.
      await enterField(tester, 'Phone number', '+23480123456789999');
      expect(
        fieldText(tester, 'Phone number'),
        '801 234 5678',
        reason: 'the code is folded away and the ten digits are spaced 3-3-4',
      );

      // A number dialled in local format folds its leading zero away instead
      // of being refused: the code is only added back when the number is saved.
      await enterField(tester, 'Business name', 'Ada');
      await enterField(tester, 'Phone number', '08031234567');
      expect(
        fieldText(tester, 'Phone number'),
        '803 123 4567',
        reason: 'the local leading zero is folded away from the ten digits',
      );
      await pickCategory(tester, 'Groceries & Provisions');
      await enterField(tester, 'Add what you sell', 'Rice');

      // The ten digits are all the owner types; the code is added back on save.
      await enterField(tester, 'Phone number', '8012345678');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/business'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(
        body['phone'],
        '+2348012345678',
        reason: 'the +234 code is put back when the number is saved',
      );
    });

    testWidgets('the details are confirmed before the owner goes back', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((request) async {
        if (request.url.path.endsWith('/business/location')) {
          return json({
            'business': {
              ...businessJson,
              'location': {
                'id': 'loc-1',
                'businessId': 'business-1',
                'address': '12 Allen Avenue',
                'area': 'Allen Hill',
                'city': 'Ikeja',
                'state': 'Lagos',
              },
            },
          });
        }
        return json({'business': businessJson}, status: 201);
      });

      var completed = false;

      await tester.pumpWidget(wrap(BusinessSetupFlow(
        business: repos.business,
        onComplete: () => completed = true,
        locationService: _NoLocationService(LocationUnavailable.unavailable),
      )));

      await fillProfileDetails(tester, 'Ada');
      await tapLabel(tester, 'Continue');
      await tester.pumpAndSettle();

      await fillLocationDetails(tester);
      await tapLabel(tester, 'Finish setup');
      await tester.pumpAndSettle();

      expect(find.text('Are your details correct?'), findsOneWidget);

      await tester.tap(find.text('No, let me review'));
      await tester.pumpAndSettle();
      expect(completed, isFalse, reason: 'the main page waits for a yes');
      expect(find.text('Where is your shop?'), findsOneWidget, reason: 'still inside business details');
      expect(
        log.where((request) => request.method == 'PUT'),
        isEmpty,
        reason: 'nothing is saved until the owner confirms',
      );

      await tapLabel(tester, 'Finish setup');
      await tester.pumpAndSettle();
      expect(find.text('Are your details correct?'), findsOneWidget);

      await tester.tap(find.text('Yes, take me back'));
      await tester.pumpAndSettle();
      expect(completed, isTrue, reason: 'a yes hands the owner back the main page');
    });
  });

  group('product form', () {
    testWidgets('prefills the price in naira when editing', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({'product': {}}));
      const product = Product(
        id: 'product-1',
        businessId: 'business-1',
        name: 'Rice 50kg',
        priceKobo: 175025,
        stockQuantity: 5,
        active: true,
      );

      await tester.pumpWidget(wrap(ProductFormScreen(
        catalog: repos.catalog,
        product: product,
      )));

      // 175025 kobo must come back as "1750.25", not "175025", or saving would
      // quietly multiply the price by 100.
      expect(fieldText(tester, 'Price'), '1750.25');
      expect(fieldText(tester, 'Stock quantity'), '5');
      expect(find.text('Edit product'), findsOneWidget);
    });

    testWidgets('shows the kobo equivalent under the price field', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({'product': {}}));

      await tester.pumpWidget(wrap(ProductFormScreen(catalog: repos.catalog)));

      await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '15000');
      await tester.pumpAndSettle();

      expect(find.text('Stored as ₦15,000.00'), findsOneWidget);
    });

    testWidgets('rejects a price with more than two decimals before calling the API',
        (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({'product': {}}));

      await tester.pumpWidget(wrap(ProductFormScreen(catalog: repos.catalog)));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Rice',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price'),
        '10.005',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stock quantity'),
        '1',
      );
      await tapLabel(tester, 'Add product');
      await tester.pumpAndSettle();

      expect(find.text('Use at most two decimal places.'), findsOneWidget);
      expect(
        log.where((request) => request.url.path.endsWith('/products')),
        isEmpty,
      );
    });

    testWidgets('sends the price as integer kobo', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner(
        (_) async => json({
          'product': {
            'id': 'product-1',
            'name': 'Rice',
            'priceKobo': 1500000,
            'stockQuantity': 1,
            'active': true,
          },
        }, status: 201),
      );

      await tester.pumpWidget(wrap(ProductFormScreen(catalog: repos.catalog)));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Rice',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '15000');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stock quantity'),
        '3',
      );
      await tapLabel(tester, 'Add product');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/products'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['price_kobo'], 1500000);
      expect(body['price_kobo'], isA<int>());
    });

    testWidgets('sends a picked photo as an image data URL', (tester) async {
      useTallSurface(tester);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP478oAAAOLAUV+7IS+AAAAAElFTkSuQmCC',
      );
      final repos = await signInOwner(
        (_) async => json({
          'product': {
            'id': 'product-1',
            'name': 'Rice',
            'priceKobo': 1500000,
            'stockQuantity': 1,
            'active': true,
          },
        }, status: 201),
      );

      await tester.pumpWidget(wrap(ProductFormScreen(
        catalog: repos.catalog,
        logoService: _FakeLogoService(png),
      )));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Rice',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '15000');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Stock quantity'),
        '3',
      );

      await tapLabel(tester, 'Add photo');
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets, reason: 'the pick previews in place');

      await tapLabel(tester, 'Add product');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/products'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['image_url'], startsWith('data:image/png;base64,'));
    });
  });

  group('customer form', () {
    testWidgets('requires a name', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({'customer': {}}));

      await tester.pumpWidget(wrap(CustomerFormScreen(customers: repos.customers)));

      await tapLabel(tester, 'Add customer');
      await tester.pumpAndSettle();

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(
        log.where((request) => request.url.path.endsWith('/customers')),
        isEmpty,
      );
    });

    testWidgets('accepts a customer with only a name', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner(
        (_) async => json({
          'customer': {'id': 'customer-1', 'name': 'Ada'},
        }, status: 201),
      );

      await tester.pumpWidget(wrap(CustomerFormScreen(customers: repos.customers)));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer name'),
        'Ada',
      );
      await tapLabel(tester, 'Add customer');
      await tester.pumpAndSettle();

      final post = log.firstWhere(
        (request) => request.method == 'POST' && request.url.path.endsWith('/customers'),
      );
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['name'], 'Ada');
      expect(body['phone'], isNull);
    });

    testWidgets('shows a server field error on the phone field', (tester) async {
      useTallSurface(tester);
      final repos = await signInOwner((_) async => json({
            'error': {
              'code': 'validation_failed',
              'message': 'Some fields need your attention.',
              'details': [
                {'field': 'phone', 'message': 'Enter a valid phone number.'},
              ],
            },
          }, status: 422));

      await tester.pumpWidget(wrap(CustomerFormScreen(customers: repos.customers)));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer name'),
        'Ada',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone (optional)'),
        '+2348011111111',
      );
      await tapLabel(tester, 'Add customer');
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid phone number.'), findsOneWidget);
    });
  });
}
