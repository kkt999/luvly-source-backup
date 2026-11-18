import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/design.dart';
import 'package:luvly_app/packages/custom_package_builder.dart';
import 'package:luvly_app/packages/accessory_catalogue.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/service_pricing_editor.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;

const preview = bool.fromEnvironment('PACKAGE_UX_GOLDENS');
const frame = Key('package-frame');

Future<void> mount(
  WidgetTester tester,
  Widget page,
  ThemeData theme,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  if (preview) {
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader(
        'LuvlySans',
      )..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))).load();
      await (FontLoader(
        'LuvlySerif',
      )..addFont(rootBundle.load('assets/fonts/CormorantGaramond.ttf'))).load();
    });
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: page,
      ),
    ),
  );
  if (page is CustomPackageBuilder) {
    await tester.runAsync(AccessoryCatalogue.load);
    addTearDown(
      () => rootBundle.evict('assets/images/accessory-catalogue.json'),
    );
  }
  await tester.pumpAndSettle();
}

HttpPackageApi mockApi(Object Function(http.Request) respond) {
  final api = HttpPackageApi(
    transport: HttpPaymentApi(
      baseUrl: 'https://example.com',
      token: () async => 'test-account',
      client: MockClient(
        (request) async => http.Response(jsonEncode(respond(request)), 200),
      ),
    ),
  );
  addTearDown(api.close);
  return api;
}

void main() {
  testWidgets(
    'Custom package can remove the gown and review eligible services with only an event date',
    (tester) async {
      final requests = <http.Request>[];
      final api = mockApi((request) {
        requests.add(request);
        if (request.url.path == '/v1/custom-package-options') {
          return {
            'maxGowns': 4,
            'accessoryCatalogueVersion': 1,
            'services': [
              {
                'id': 'makeup-hair',
                'name': 'Wedding makeup',
                'description': 'One complete look',
                'priceCents': 50000,
                'revision': 1,
                'method': 'fixed',
                'serviceType': 'makeup-hair',
                'standaloneEligible': true,
              },
              {
                'id': 'extra-fitting',
                'name': 'Additional fitting',
                'description': '',
                'priceCents': 8000,
                'revision': 1,
                'method': 'per-session',
                'serviceType': 'extra-fitting',
                'standaloneEligible': false,
              },
            ],
          };
        }
        if (request.url.path == '/v1/package-gowns') {
          return {
            'dresses': [
              {
                'id': 'gown',
                'name': 'Test gown',
                'category': 'Ball gown',
                'description': '',
                'colour': 'Ivory',
                'sizes': 'M',
                'priceCents': 20000,
                'imageUrl': '',
                'availability': 'Available',
                'published': true,
                'revision': 1,
              },
            ],
          };
        }
        return {
          'totalCents': 50000,
          'pricingSnapshot': {
            'gownLines': [],
            'lines': [
              {'name': 'Wedding makeup', 'amountCents': 50000, 'quantity': 1},
            ],
            'selectedAccessories': [],
          },
        };
      });
      final selection = PackageSelection({
        'id': 'existing',
        'includedGownCount': 1,
        'rentalPlan': {
          'eventDate': '2030-04-11',
          'pickupDate': '2030-04-10',
          'returnDate': '2030-04-12',
        },
        'selectedGowns': [
          {'dressId': 'gown', 'size': 'M'},
        ],
        'customServices': [
          {'id': 'makeup-hair', 'revision': 1, 'quantity': 1},
        ],
      });
      await mount(
        tester,
        CustomPackageBuilder(api: api, selection: selection),
        luvlyTheme,
        const Size(390, 844),
      );

      Future<void> tap(String label) async {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      expect(find.text('Wedding or event date'), findsOneWidget);
      await tap('Continue');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tap('0 — No wedding gown rental');
      expect(find.text('Choose gowns and sizes'), findsNothing);
      await tap('Continue');
      final chosen = find.widgetWithText(CheckboxListTile, 'Wedding makeup');
      final dependent = find.widgetWithText(
        CheckboxListTile,
        'Additional fitting',
      );
      expect(tester.widget<CheckboxListTile>(chosen).value, true);
      expect(tester.widget<CheckboxListTile>(dependent).onChanged, null);
      await tap('Continue');
      expect(find.text('Veil rental'), findsNothing);
      await tap('Review selection');
      expect(find.text('RM 500.00'), findsWidgets);
      expect(find.text('Pickup'), findsNothing);
      final quote = jsonDecode(requests.last.body);
      expect(quote['rentalPlan'], {'eventDate': '2030-04-11'});
      expect(quote['gowns'], isEmpty);
      expect(quote['customServices'].single['id'], 'makeup-hair');
    },
  );

  testWidgets(
    'Manager can choose a gown count and retry, search and add catalogue services',
    (tester) async {
      var catalogueLoads = 0;
      final requests = <http.Request>[];
      final api = mockApi((request) {
        requests.add(request);
        if (request.url.path == '/v1/package-gown-limit') {
          return {'maxGowns': 4};
        }
        if (request.url.path == '/v1/bridal-service-prices') {
          if (request.method == 'POST') {
            final row = jsonDecode(request.body) as Map<String, dynamic>;
            final revision = row['revision'] as int;
            if (row['id'] == 'makeup' && revision == 1) {
              row.remove('standaloneEligible');
            }
            return {...row, 'revision': revision + 1};
          }
          catalogueLoads++;
          if (catalogueLoads == 2) throw http.ClientException('test outage');
          return {
            'services': catalogueLoads <= 3
                ? []
                : [
                    {
                      'id': 'makeup',
                      'name': 'Airbrush bridal makeup',
                      'description': '',
                      'serviceType': 'makeup-hair',
                      'method': 'fixed',
                      'active': true,
                      'priceCents': 12000,
                      'revision': 1,
                    },
                    {
                      'id': 'fitting',
                      'name': 'Additional fitting',
                      'description': '',
                      'serviceType': 'extra-fitting',
                      'method': 'per-session',
                      'active': true,
                      'priceCents': 8000,
                      'revision': 1,
                    },
                    {
                      'id': 'inactive',
                      'name': 'Unavailable service',
                      'description': '',
                      'serviceType': 'custom',
                      'method': 'fixed',
                      'active': false,
                      'priceCents': 10000,
                      'revision': 1,
                    },
                  ],
          };
        }
        if (request.method == 'POST') return {'revision': 1};
        return {'published': null, 'draft': null};
      });
      await mount(
        tester,
        ServicePricingEditor(api: api, onPreview: (_) {}),
        portalTheme,
        const Size(1200, 1000),
      );
      expect(find.text('Number of gowns included'), findsOneWidget);
      expect(find.textContaining('price source'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Gown rentals'), findsNothing);
      final count = find.byType(DropdownButtonFormField<int>);
      await tester.ensureVisible(count);
      await tester.tap(count);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2').last);
      await tester.pumpAndSettle();

      Future<void> tap(String label) async {
        final target = find.text(label).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      final add = find.text('Add service');
      await tester.scrollUntilVisible(
        add,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tap('Add service');
      expect(
        find.text('Unable to load services. Please try again.'),
        findsOneWidget,
      );
      await tap('Retry');
      expect(find.text('Veil Rental'), findsOneWidget);
      expect(find.text('Bridal Accessories'), findsOneWidget);
      expect(find.text('Included · Remove to save RM 80.00'), findsOneWidget);
      expect(find.text('Catalogue-based · Variable'), findsOneWidget);
      await tap('Cancel');

      await tap('Add service');
      final search = find.widgetWithText(TextField, 'Search services...');
      await tester.enterText(search, 'portrait');
      await tester.pumpAndSettle();
      expect(find.text('No matching services found.'), findsOneWidget);
      await tester.enterText(search, 'airbrush');
      await tester.pumpAndSettle();
      expect(find.textContaining('RM 120.00'), findsOneWidget);
      await tap('Airbrush bridal makeup');
      expect(find.text('1 selected'), findsOneWidget);
      await tester.enterText(search, 'fitting');
      await tester.pumpAndSettle();
      await tap('Additional fitting');
      expect(find.text('2 selected'), findsOneWidget);
      await tap('Cancel');
      expect(find.text('Airbrush bridal makeup'), findsNothing);

      await tap('Add service');
      final disabled = find.widgetWithText(
        CheckboxListTile,
        'Unavailable service',
      );
      expect(tester.widget<CheckboxListTile>(disabled).onChanged, isNull);
      await tap('Airbrush bridal makeup');
      await tap('Additional fitting');
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/manager-service-multiselect.png'),
        );
      }
      await tap('Add selected (2)');
      expect(find.text('Package role'), findsOneWidget);
      final fittingQuantity = find.byType(DropdownButtonFormField<int>).last;
      await tester.ensureVisible(fittingQuantity);
      await tester.tap(fittingQuantity);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.pumpAndSettle();
      final makeupName = find.text('Airbrush bridal makeup').first;
      final makeupRow = find
          .ancestor(of: makeupName, matching: find.byType(Row))
          .first;
      final role = find.descendant(
        of: makeupRow,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.tap(role);
      await tester.pumpAndSettle();
      await tap('Removable included');
      final edit = find.descendant(
        of: makeupRow,
        matching: find.byTooltip('Edit configuration'),
      );
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '25');
      await tap('Apply configuration');
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/manager-selected-services-table.png'),
        );
      }
      await tap('Add service');
      expect(find.textContaining('Added ·'), findsNWidgets(2));
      await tap('Cancel');
      await tap('Save unpublished');
      final saved = jsonDecode(requests.last.body)['configuration'];
      expect(saved['includedGownCount'], 2);
      expect(saved['pricing']['gownPrices'], isEmpty);
      expect(saved['pricing']['useStandardGownAllowance'], true);
      expect((saved['services'] as List).map((row) => row['id']), [
        'makeup',
        'fitting',
      ]);
      expect(saved['pricing']['components'].last['quantity'], 3);
      expect(saved['services'].first['kind'], 'Optional');
      expect(saved['services'].first['priceCents'], 2500);
      expect(
        requests.where(
          (request) =>
              request.method == 'POST' &&
              request.url.path == '/v1/bridal-service-prices',
        ),
        isEmpty,
      );
      final fittingRow = find
          .ancestor(
            of: find.text('Additional fitting').first,
            matching: find.byType(Row),
          )
          .first;
      await tester.tap(
        find.descendant(
          of: fittingRow,
          matching: find.byTooltip('Remove service'),
        ),
      );
      await tester.pumpAndSettle();
      await tap('Save unpublished');
      final afterRemoval = jsonDecode(requests.last.body)['configuration'];
      expect(afterRemoval['services'].single['id'], 'makeup');
      expect(requests.any((request) => request.method == 'DELETE'), false);
      await tap('Manage service prices');
      expect(find.text('Catalogue services'), findsOneWidget);
      expect(find.text('Standard gown allowance'), findsOneWidget);
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/manager-service-catalogue.png'),
        );
      }
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();

      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      await tester.pumpAndSettle();
      final catalogueMakeupRow = find
          .ancestor(
            of: find.text('Airbrush bridal makeup'),
            matching: find.byType(Row),
          )
          .first;
      await tester.tap(
        find.descendant(
          of: catalogueMakeupRow,
          matching: find.byTooltip('Edit Airbrush bridal makeup'),
        ),
      );
      await tester.pumpAndSettle();
      await tap('Advanced settings');
      await tap('Available without gown rental');
      await tap('Review changes');
      expect(
        find.textContaining('Without gown rental: Available'),
        findsOneWidget,
      );
      await tap('Save changes');
      expect(find.text('Edit service price'), findsOneWidget);
      expect(
        find.textContaining('did not save availability without a gown'),
        findsOneWidget,
      );
      final attempted = jsonDecode(requests.last.body);
      expect(attempted['standaloneEligible'], true);
      expect(attempted['priceCents'], 12000);
      await tap('Review changes');
      await tap('Save changes');
      expect(jsonDecode(requests.last.body)['revision'], 2);
      expect(find.text('Edit service price'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Airbrush bridal makeup'), findsWidgets);
      await tap('Add service');
      await tap('Create new service');
      expect(find.text('Service category').hitTestable(), findsNothing);
      expect(find.text('Standard price (RM)'), findsOneWidget);
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/service-create-simplified.png'),
        );
      }
      await tap('Advanced settings');
      expect(find.text('Service category'), findsOneWidget);
      expect(find.text('Pricing method'), findsOneWidget);
      await tap('Advanced settings');
      await tester.enterText(
        find.widgetWithText(TextField, 'e.g. Bridal consultation'),
        'Bridal consultation',
      );
      await tester.enterText(find.widgetWithText(TextField, '0.00'), '85');
      await tap('Create service');
      await tap('Save unpublished');
      final updated = jsonDecode(requests.last.body)['configuration'];
      expect(
        (updated['services'] as List).map((row) => row['name']),
        containsAll(['Airbrush bridal makeup', 'Bridal consultation']),
      );

      await tap('Add service');
      await tester.enterText(search, 'veil');
      await tester.pumpAndSettle();
      await tap('Veil Rental');
      await tap('Add selected (1)');
      await tap('Save unpublished');
      final veilDraft = jsonDecode(requests.last.body)['configuration'];
      final veil = (veilDraft['services'] as List).singleWhere(
        (row) => row['id'] == 'veil-rental',
      );
      expect(veil['standardVeilId'], 'veil-short');
      expect(veil['kind'], 'Optional');
      expect(veil['priceCents'], 8000);
      expect(
        (veilDraft['services'] as List).map((row) => row['id']),
        isNot(contains('accessory-rental')),
      );

      await tap('Add service');
      await tester.enterText(search, 'veil');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Veil Rental'),
            )
            .onChanged,
        isNull,
      );
      await tester.enterText(search, 'accessories');
      await tester.pumpAndSettle();
      await tap('Bridal Accessories');
      await tap('Add selected (1)');
      await tap('Save unpublished');
      final accessoryDraft = jsonDecode(requests.last.body)['configuration'];
      final accessories = (accessoryDraft['services'] as List).singleWhere(
        (row) => row['id'] == 'accessory-rental',
      );
      expect(accessories['kind'], 'Add-on');
      expect(accessories['serviceType'], 'item-priced-accessories');
      expect(
        (accessoryDraft['pricing']['components'] as List).map(
          (row) => row['serviceId'],
        ),
        isNot(anyOf(contains('veil-rental'), contains('accessory-rental'))),
      );
    },
  );

  testWidgets(
    'Manager keeps the summary in view and displays the reviewed backend discount',
    (tester) async {
      final api = mockApi((request) {
        if (request.url.path == '/v1/package-gown-limit') {
          return {'maxGowns': 4};
        }
        if (request.url.path == '/v1/bridal-service-prices') {
          return {'services': []};
        }
        if (request.url.path.endsWith('/preview')) {
          return {
            'configuration': {'basePriceCents': 9900, 'services': []},
            'pricingSnapshot': {
              'subtotalCents': 11500,
              'discountCents': 1600,
              'sellingPriceCents': 9900,
            },
          };
        }
        if (request.method == 'POST') return {'revision': 1};
        return {'published': null, 'draft': null};
      });
      await mount(
        tester,
        ServicePricingEditor(api: api, onPreview: (_) {}),
        portalTheme,
        const Size(1200, 850),
      );
      expect(find.text('Build your package'), findsOneWidget);
      expect(find.text('Package summary'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Package name'),
        'Bridal Essentials',
      );
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/manager-pricing-restored.png'),
        );
      }
      await tester.tap(find.text('Review package'));
      await tester.pumpAndSettle();
      expect(find.text('Pricing verified'), findsOneWidget);
      expect(find.text('RM 16.00'), findsOneWidget);
      expect(find.text('RM 99.00'), findsOneWidget);
    },
  );

  testWidgets(
    'Custom stages preserve the saved gown, require enabled accessories and display the server quote',
    (tester) async {
      final requests = <http.Request>[];
      final api = mockApi((request) {
        requests.add(request);
        if (request.url.path == '/v1/custom-package-options') {
          return {
            'maxGowns': 4,
            'services': [],
            'accessoryCatalogueVersion': 1,
          };
        }
        if (request.url.path == '/v1/package-gowns') {
          return {
            'dresses': [
              {
                'id': 'test-gown',
                'name': 'Princess Wedding Dress',
                'category': 'Ball gown',
                'description': 'Ivory bridal gown',
                'colour': 'Ivory',
                'sizes': 'M',
                'priceCents': 25000,
                'imageUrl': '',
                'availability': 'Available',
                'published': true,
                'revision': 1,
              },
            ],
          };
        }
        return {
          'totalCents': 27000,
          'pricingSnapshot': {
            'gownLines': [
              {
                'name': 'Princess Wedding Dress',
                'size': 'M',
                'amountCents': 27000,
              },
            ],
            'lines': [],
            'selectedAccessories': [],
          },
        };
      });
      final selection = PackageSelection({
        'id': 'existing',
        'includedGownCount': 1,
        'rentalPlan': {
          'eventDate': '2030-04-11',
          'pickupDate': '2030-04-10',
          'returnDate': '2030-04-12',
        },
        'selectedGowns': [
          {'dressId': 'test-gown', 'size': 'M'},
        ],
        'customServices': [],
      });
      await mount(
        tester,
        CustomPackageBuilder(api: api, selection: selection),
        luvlyTheme,
        const Size(390, 844),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('RM 270.00'), findsWidgets);

      Future<void> tap(String label) async {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tap('Continue');
      expect(find.text('1 of 1 gowns selected'), findsOneWidget);
      await tap('Continue');
      await tap('Continue');
      final veil = find.widgetWithText(CheckboxListTile, 'Veil rental');
      final accessories = find.widgetWithText(
        CheckboxListTile,
        'Bridal accessories',
      );
      expect(tester.widget<CheckboxListTile>(veil).value, false);
      expect(tester.widget<CheckboxListTile>(accessories).value, false);
      await tap('Veil rental');
      await tap('Review selection');
      expect(
        find.text('Choose a veil or turn off veil rental.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tap('Continue');
      expect(tester.widget<CheckboxListTile>(veil).value, true);
      await tap('Veil rental');
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/custom-package-options-restored.png'),
        );
      }
      await tap('Review selection');
      expect(find.text('Save selection'), findsOneWidget);
      expect(find.text('RM 270.00'), findsWidgets);
      expect(
        requests.where((r) => r.url.path.endsWith('/revise')).last.body,
        contains('"previewOnly":true'),
      );
      if (preview) {
        await expectLater(
          find.byKey(frame),
          matchesGoldenFile('previews/custom-package-review-restored.png'),
        );
      }
    },
  );
}
