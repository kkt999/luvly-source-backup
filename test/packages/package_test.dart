import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/package_presentation.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';

class ListingPackages extends FakePackages {
  @override
  Future<List<BridalPackage>> catalogue() async => [
    BridalPackage.fromJson({
      ...bridal.toJson(),
      'id': 'premium',
      'name': 'A Longer Signature Wedding Package Name',
      'description': List.filled(
        10,
        'A longer description with details.',
      ).join(' '),
      'includedGownCount': 2,
    }),
    BridalPackage.fromJson({
      ...bridal.toJson(),
      'id': 'essential',
      'name': 'Bridal Essentials',
      'basePriceCents': 89900,
      'includedGownCount': 1,
    }),
  ];
}

const bridal = BridalPackage(
  id: 'essential',
  name: 'Essential Bridal',
  description: 'A dress and personal consultation for your special day.',
  basePriceCents: 250000,
  revision: 1,
  active: true,
  services: [
    PackageServiceItem(
      id: 'rental',
      name: 'Dress rental',
      description: 'Your selected gown',
      kind: 'Required',
      priceCents: 0,
    ),
    PackageServiceItem(
      id: 'styling',
      name: 'Accessories styling',
      description: 'Styling assistance',
      kind: 'Optional',
      priceCents: 15000,
    ),
    PackageServiceItem(
      id: 'makeup',
      name: 'Makeup trial',
      description: 'A trial before the wedding',
      kind: 'Add-on',
      priceCents: 35000,
    ),
  ],
);

final packageWithoutAccessories = BridalPackage(
  id: bridal.id,
  name: bridal.name,
  description: bridal.description,
  revision: bridal.revision,
  basePriceCents: bridal.basePriceCents,
  active: true,
  services: bridal.services.where((s) => !s.isAccessory).toList(),
);

class FakePackages implements PackageApi, PackageGownLimitApi {
  @override
  bool get configured => true;
  bool fail = false;
  int maxGowns = 4;
  int selectionsSaved = 0, packagesSaved = 0;
  BridalPackage? savedPackage;
  int invoicesIssued = 0;
  String? invoiceSelection, invoiceAppointment;
  Set<String> removed = {}, extras = {};
  final rows = <PackageSelection>[];
  @override
  Future<List<BridalPackage>> catalogue() async => [bridal];
  @override
  Future<List<CatalogueDress>> gowns() async => [];
  @override
  Future<int> gownLimit() async => maxGowns;
  @override
  Future<List<PackageSelection>> selections() async => rows;
  @override
  Future<BridalPackage> save(BridalPackage p) async {
    packagesSaved++;
    savedPackage = p;
    return p;
  }

  @override
  Future<void> select(
    BridalPackage p,
    Set<String> removedIds,
    Set<String> addonIds,
    String requestId, {
    List<Map<String, dynamic>> gowns = const [],
    List<Map<String, dynamic>> accessories = const [],
    int? accessoryCatalogueVersion,
  }) async {
    if (fail) {
      throw const PaymentFailure(
        'This package has changed. Reopen it to review the latest details and price.',
      );
    }
    selectionsSaved++;
    removed = {...removedIds};
    extras = {...addonIds};
  }

  @override
  Future<BookingOutcome?> book(
    String id,
    String type,
    DateTime start,
    String notes,
    String requestId,
  ) async {
    return null;
  }

  @override
  Future<void> invoice(String id, String appointment) async {
    invoicesIssued++;
    invoiceSelection = id;
    invoiceAppointment = appointment;
  }

  @override
  void close() {}
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Manager loads approved pricing into the editor without publishing',
    (tester) async {
      final original = BridalPackage.fromJson({
        ...bridal.toJson(),
        'id': 'signature-bridal',
        'name': 'Signature Bridal',
        'includedGownCount': 1,
        'eligibleDressIds': ['gown1'],
        'basePriceCents': 179900,
      });
      final approved = {
        ...original.toJson(),
        'basePriceCents': 172900,
        'services': [
          original.services.first.toJson(),
          const PackageServiceItem(
            id: 'veil-rental',
            name: 'Veil Rental',
            description: 'Standard veil included.',
            kind: 'Optional',
            priceCents: 8000,
            serviceType: PackageServiceType.packageVeil,
            standardVeilId: 'veil-short',
          ).toJson(),
        ],
      };
      final requests = <http.Request>[];
      final api = HttpPackageApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.com',
          token: () async => 'manager',
          client: MockClient((request) async {
            requests.add(request);
            if (request.url.path.endsWith('/approved-pricing')) {
              return http.Response(jsonEncode(approved), 200);
            }
            return http.Response('{"maxGowns":4}', 200);
          }),
        ),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PackageEditor(api: api, package: original),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Load approved pricing'));
      final field = find.widgetWithText(TextFormField, 'Standard price');
      expect(tester.widget<TextFormField>(field).controller!.text, '1729.00');
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      expect(
        requests.where((r) => r.url.path.endsWith('/approved-pricing')),
        hasLength(1),
      );
    },
  );

  testWidgets('appointment shortcut focuses the correct package selection', (
    tester,
  ) async {
    final api = FakePackages();
    for (final id in ['linked', 'other']) {
      api.rows.add(
        PackageSelection({
          'id': id,
          'name': 'Package $id',
          'customerName': 'Jane',
          'totalCents': 250000,
          'services': [],
          'appointments': [],
          'invoice': null,
        }),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: LivePackageScreen(
          api: api,
          staff: true,
          initialSelections: true,
          initialSelectionId: 'linked',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Package linked'), findsOneWidget);
    expect(find.text('Package other'), findsNothing);
    await tester.tap(find.text('Show all selections'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Package other'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Package other'), findsOneWidget);
  });
  testWidgets(
    'editor checks an invalid price even after its field scrolls off-screen',
    (tester) async {
      phone(tester);
      final api = FakePackages();
      final invalid = BridalPackage(
        id: bridal.id,
        name: bridal.name,
        description: bridal.description,
        basePriceCents: 0,
        revision: 1,
        active: true,
        services: bridal.services,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PackageEditor(api: api, package: invalid),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review package'));
      await tester.pumpAndSettle();
      expect(api.packagesSaved, 0);
      expect(
        find.text(
          'Check the package name, description, price and every service row.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('money and optional service deductions are exact', () {
    expect(bridal.total({}, {}), 250000);
    expect(bridal.total({'styling'}, {'makeup'}), 270000);
    expect(bridal.total({'rental'}, {}), 250000);
    expect(serviceCents('350.25'), 35025);
    for (final value in ['abc', '-1', '1.234', 'NaN', '1000001']) {
      expect(serviceCents(value), isNull);
    }
  });
  test(
    'selection request never sends a customer price or owner override',
    () async {
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'verified-test-token',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/package-selections');
          expect(
            request.headers['Authorization'],
            'Bearer verified-test-token',
          );
          final body = jsonDecode(request.body) as Map;
          expect(body.keys.toSet(), {
            'requestId',
            'packageId',
            'revision',
            'removedIds',
            'addonIds',
            'gowns',
          });
          expect(body['revision'], 1);
          expect(body['removedIds'], ['styling']);
          expect(body['gowns'], []);
          return http.Response('{}', 201);
        }),
      );
      await HttpPackageApi(
        transport: transport,
      ).select(bridal, {'styling'}, {'makeup'}, 'retry-id');
    },
  );
  testWidgets(
    'customer can search and sees no package edit controls at phone size',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(home: LivePackageScreen(api: FakePackages())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create package'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Essential Bridal'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Essential Bridal'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'unknown');
      await tester.pumpAndSettle();
      expect(find.text('No packages match your search.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('list sorts by price and filters real customer packages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: LivePackageScreen(api: ListingPackages()),
      ),
    );
    await tester.pumpAndSettle();
    final packageList = tester.widget<ListView>(find.byType(ListView).first);
    final items = packageList.childrenDelegate as SliverChildListDelegate;
    expect(
      items.children.whereType<PackageCollectionCard>().map((card) => card.key),
      [const ValueKey('package-essential'), const ValueKey('package-premium')],
    );
    final card = find.byKey(const ValueKey('package-essential'));
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(card, 180, scrollable: list);
    expect(
      find.descendant(of: card, matching: find.textContaining('COLLECTION ')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.text('RM 899.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('1 gown')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Dress rental')),
      findsNothing,
    );

    final premium = find.byKey(const ValueKey('package-premium'));
    await tester.scrollUntilVisible(premium, 180, scrollable: list);
    expect(
      find.descendant(of: premium, matching: find.text('2 gowns')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.textContaining('A longer description')).maxLines,
      2,
    );

    final price = find.byTooltip('Price: All prices');
    await tester.scrollUntilVisible(price, -180, scrollable: list);
    await tester.tap(price);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('list-option-Price-Under RM 1,000')),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Price: Under RM 1,000'), findsOneWidget);
    await tester.drag(list, const Offset(0, -540));
    await tester.pumpAndSettle();
    expect(premium, findsNothing);
    final explore = find.descendant(
      of: card,
      matching: find.widgetWithText(FilledButton, 'Explore package'),
    );
    await tester.scrollUntilVisible(
      explore.hitTestable(),
      160,
      scrollable: list,
    );
    await tester.pumpAndSettle();
    await tester.tap(explore.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(PackageChoiceScreen), findsOneWidget);
    expect(
      tester
          .widget<PackageChoiceScreen>(find.byType(PackageChoiceScreen))
          .package
          .id,
      'essential',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mandatory services locked; optional removal and add-on confirmed before selection',
    (tester) async {
      phone(tester);
      final api = FakePackages();
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(package: bridal, api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byType(SwitchListTile));
      final bar = find.byType(PackageReviewBar);
      expect(tester.widget<PackageReviewBar>(bar).totalCents, 250000);
      expect(
        find.widgetWithText(CheckboxListTile, 'Dress rental'),
        findsNothing,
      );
      await tapVisible(
        tester,
        find.widgetWithText(CheckboxListTile, 'Accessories styling'),
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(tester.widget<PackageReviewBar>(bar).totalCents, 235000);
      await tapVisible(
        tester,
        find.widgetWithText(CheckboxListTile, 'Makeup trial'),
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(tester.widget<PackageReviewBar>(bar).totalCents, 270000);
      await tapVisible(tester, find.text('Review selection'));
      expect(tester.widget<PackageReviewBar>(bar).totalCents, 270000);
      await tapVisible(tester, find.text('Save package selection'));
      expect(api.selectionsSaved, 1);
      expect(api.removed, {'styling'});
      expect(api.extras, {'makeup'});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changed price preserves review and gives user a readable error',
    (tester) async {
      phone(tester);
      final api = FakePackages()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(
            package: packageWithoutAccessories,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Review selection'));
      await tapVisible(tester, find.text('Save package selection'));
      expect(find.textContaining('This package has changed.'), findsOneWidget);
      expect(api.selectionsSaved, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'standard package needs no customization and must be reviewed before saving',
    (tester) async {
      final api = FakePackages();
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(
            package: packageWithoutAccessories,
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Review selection'));
      expect(api.selectionsSaved, 0);
      await tapVisible(tester, find.text('Save package selection'));
      expect(api.selectionsSaved, 1);
      expect(api.extras, isEmpty);
      expect(api.removed, isEmpty);
    },
  );
  testWidgets(
    'package review bar clears the bottom inset and the app bar returns to packages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 28);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PackageChoiceScreen(
                      package: packageWithoutAccessories,
                      api: FakePackages(),
                    ),
                  ),
                ),
                child: const Text('Open package'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open package'));
      await tester.pumpAndSettle();
      final bar = find.byType(PackageReviewBar);
      final button = find.text('Review selection');
      final firstPosition = tester.getRect(bar);
      expect(tester.getBottomRight(button).dy, lessThanOrEqualTo(612));
      final details = find.text('Payment details');
      await tester.scrollUntilVisible(
        details,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), firstPosition);
      expect(
        tester.getBottomRight(details).dy,
        lessThanOrEqualTo(firstPosition.top),
      );
      expect(find.text('Back to packages'), findsNothing);
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Open package'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('staff and manager can issue package invoices; customer cannot', (
    tester,
  ) async {
    final api = FakePackages();
    api.rows.add(
      PackageSelection({
        'id': 'saved',
        'name': bridal.name,
        'customerName': 'Jane',
        'totalCents': 250000,
        'services': bridal.services
            .where((s) => s.kind != 'Add-on')
            .map((s) => s.toJson())
            .toList(),
        'appointments': [],
        'invoice': null,
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LivePackageScreen(api: api, staff: true, initialSelections: true),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('View details'));
    await tester.tap(find.text('Open rental workspace'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rental-tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rental-tab-2')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Issue package invoice'));
    expect(
      find.text('Confirm the customer’s package appointment first.'),
      findsOneWidget,
    );
    expect(api.invoicesIssued, 0);
    api.rows.first.data['appointments'] = [
      {
        'id': 'confirmed-visit',
        'status': 'Confirmed',
        'startAt': DateTime.utc(2030, 10, 12, 8).millisecondsSinceEpoch,
      },
    ];
    await tapVisible(tester, find.text('Issue package invoice'));
    expect(find.text('Issue invoice · RM 2,500.00'), findsOneWidget);
    expect(api.invoicesIssued, 0);
    await tester.tap(find.textContaining('Confirm invoice for'));
    await tester.pumpAndSettle();
    expect(api.invoicesIssued, 1);
    expect(api.invoiceSelection, 'saved');
    expect(api.invoiceAppointment, 'confirmed-visit');
    await tester.tap(find.byTooltip('Close rental workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close rental details'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: LivePackageScreen(
          key: const ValueKey('manager'),
          api: api,
          staff: true,
          manager: true,
          initialSelections: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('View details'));
    await tester.tap(find.text('Open rental workspace'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rental-tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rental-tab-2')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Issue package invoice'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Issue package invoice'), findsOneWidget);
    expect(find.text('Packages'), findsNothing);
    expect(find.text('Create package'), findsNothing);
    await tester.tap(find.byTooltip('Close rental workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close rental details'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: LivePackageScreen(
          key: const ValueKey('customer'),
          api: api,
          initialSelections: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Issue package invoice'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('editor validates empty inputs rather than sending a package', (
    tester,
  ) async {
    phone(tester);
    final api = FakePackages();
    await tester.pumpWidget(MaterialApp(home: PackageEditor(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsNothing);
    expect(find.text('Unpublished'), findsNothing);
    await tapVisible(tester, find.text('Add service'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Search services'),
      'Custom service',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('package-service-custom')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save unpublished'));
    await tester.pumpAndSettle();
    expect(api.packagesSaved, 0);
    expect(find.text('Enter the service name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'accessory catalogue follows category and updates suggested names',
    (tester) async {
      phone(tester);
      rootBundle.evict('assets/images/accessory-catalogue.json');
      await tester.pumpWidget(
        MaterialApp(home: PackageEditor(api: FakePackages())),
      );
      await tester.pumpAndSettle();
      Future<void> selectCategory(
        PackageServiceType type, {
        bool add = false,
      }) async {
        await tapVisible(
          tester,
          find.text(add ? 'Add service' : 'Change category'),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Search services'),
          type.label,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('package-service-${type.code}')));
        await tester.pumpAndSettle();
      }

      Future<void> openCatalogue(String label) async {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(button);
          await tester.pump();
          await rootBundle.loadString('assets/images/accessory-catalogue.json');
        });
        await tester.pumpAndSettle();
      }

      await selectCategory(PackageServiceType.makeupHair, add: true);
      expect(find.text('View jewellery'), findsNothing);
      await selectCategory(PackageServiceType.itemAccessories);
      final nameField = find.widgetWithText(TextFormField, 'Service name');
      expect(
        tester.widget<TextFormField>(nameField).controller!.text,
        'Bridal Accessories',
      );
      await tester.enterText(nameField, 'My wedding accessories');
      await tester.pumpAndSettle();
      await openCatalogue('View jewellery');
      expect(find.text('Customer accessory choices'), findsOneWidget);
      expect(find.text('Luna Solitaire Ring'), findsOneWidget);
      expect(find.text('Grace Fingertip Veil'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await selectCategory(PackageServiceType.packageVeil);
      expect(
        tester.widget<TextFormField>(nameField).controller!.text,
        'My wedding accessories',
      );
      await openCatalogue('View veils');
      expect(find.text('Grace Fingertip Veil'), findsOneWidget);
      expect(find.text('Luna Solitaire Ring'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'gown count stops at the catalogue limit and saves without linked styles',
    (tester) async {
      final api = FakePackages();
      final draft = BridalPackage(
        id: bridal.id,
        name: bridal.name,
        description: bridal.description,
        basePriceCents: bridal.basePriceCents,
        revision: 1,
        active: false,
        draft: true,
        services: bridal.services,
        includedGownCount: 1,
        eligibleDressIds: const ['first-gown'],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PackageEditor(api: api, package: draft),
        ),
      );
      await tester.pumpAndSettle();
      final increase = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'More gowns',
      );
      await tester.ensureVisible(increase);
      for (var count = 2; count <= 4; count++) {
        await tester.tap(increase);
        await tester.pumpAndSettle();
        expect(find.text('$count gowns'), findsOneWidget);
      }
      expect(tester.widget<IconButton>(increase).onPressed, isNull);
      expect(
        find.text('Up to 4 gowns from the rental catalogue.'),
        findsOneWidget,
      );
      expect(find.text('Edit linked styles'), findsNothing);
      await tester.tap(find.text('Save unpublished'));
      await tester.pumpAndSettle();
      expect(api.savedPackage?.includedGownCount, 4);
      expect(api.savedPackage?.allCatalogueGowns, isTrue);
      expect(api.savedPackage?.eligibleDressIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager can preview the price, save a draft and later publish', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1320, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakePackages();
    final draft = BridalPackage(
      id: bridal.id,
      name: bridal.name,
      description: bridal.description,
      basePriceCents: 89900,
      revision: 1,
      active: false,
      draft: true,
      services: [
        bridal.services.first,
        const PackageServiceItem(
          id: 'option',
          name: 'Styling session',
          description: '',
          kind: 'Optional',
          priceCents: 7000,
        ),
        const PackageServiceItem(
          id: 'extra',
          name: 'Keepsake',
          description: '',
          kind: 'Add-on',
          priceCents: 8000,
        ),
      ],
    );
    Future<void> openEditor() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PackageEditor(api: api, package: draft),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
    }

    await openEditor();
    await tester.tap(find.text('Save unpublished'));
    await tester.pumpAndSettle();
    expect(api.savedPackage?.active, false);

    await openEditor();
    await tester.tap(find.text('Review package'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Styling session'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Keepsake'));
    await tester.pumpAndSettle();
    expect(find.text('RM 909.00'), findsOneWidget);
    await tester.tap(find.text('Publish package'));
    await tester.pumpAndSettle();
    expect(api.savedPackage?.active, true);
    expect(api.savedPackage?.basePriceCents, 89900);
    expect(tester.takeException(), isNull);
  });
}
