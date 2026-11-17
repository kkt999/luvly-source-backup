import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_gowns.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package_test.dart' show FakePackages, bridal, phone, tapVisible;

const testGown = CatalogueDress(
  id: 'gown1',
  name: 'Ivory gown',
  category: 'A-Line',
  description: 'An ivory wedding gown.',
  colour: 'Ivory',
  sizes: 'S, M',
  priceCents: 990000,
  imageUrl: '',
  published: true,
  revision: 2,
);
BridalPackage gownPackage({int count = 1, bool accessories = true}) =>
    BridalPackage(
      id: bridal.id,
      name: bridal.name,
      description: bridal.description,
      basePriceCents: bridal.basePriceCents,
      revision: bridal.revision,
      active: true,
      services: accessories
          ? bridal.services
          : bridal.services.where((s) => !s.isAccessory).toList(),
      includedGownCount: count,
      eligibleDressIds: ['gown1'],
    );

class GownPackages extends FakePackages {
  List<Map<String, dynamic>> savedGowns = [];
  @override
  Future<List<CatalogueDress>> gowns() async => [testGown];
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
    savedGowns = gowns;
    await super.select(p, removedIds, addonIds, requestId, gowns: gowns);
  }
}

void main() {
  testWidgets(
    'upgrading to Luxe keeps a compatible gown and asks for one more',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1040);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = gownPackage(count: 2);
      final luxe = BridalPackage.fromJson({
        ...base.toJson(),
        'id': 'luxe-bridal',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(
            package: luxe,
            api: GownPackages(),
            revising: PackageSelection({
              'packageId': 'bridal-essentials',
              'selectedGowns': [
                {'dressId': testGown.id, 'size': 'M'},
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ivory gown · M'), findsOneWidget);
      expect(find.text('1 of 2 selected'), findsOneWidget);
      final addGown = find.text('Add another gown');
      await tester.scrollUntilVisible(
        addGown.hitTestable(),
        64,
        scrollable: find.byType(Scrollable).first,
      );
      expect(addGown.hitTestable(), findsOneWidget);
    },
  );
  testWidgets(
    'size chart is on demand rather than duplicated on the gown card',
    (tester) async {
      phone(tester);
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(
              request.url.path == '/v1/package-gowns'
                  ? {
                      'dresses': [
                        {
                          'id': testGown.id,
                          ...testGown.toFields(),
                          'revision': testGown.revision,
                        },
                      ],
                    }
                  : {
                      'variants': [
                        {'size': 'S', 'measurements': null},
                        {
                          'size': 'M',
                          'measurements': {
                            'bustMin': 80,
                            'bustMax': 90,
                            'waistMin': 60,
                            'waistMax': 70,
                            'hipMin': 90,
                            'hipMax': 100,
                          },
                        },
                      ],
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PackageGownPicker(
            api: HttpPackageApi(transport: transport),
            eligibleIds: {'gown1'},
            allowance: 1,
            initial: const [PackageGownChoice(testGown, 'S')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Body measurement ranges (cm)'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('gown-gown1')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Size guide'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Size guide'));
      await tester.pumpAndSettle();
      expect(find.text('Size chart'), findsOneWidget);
      expect(find.text('80–90'), findsOneWidget);
      expect(
        find.text('— Measurements pending. Contact Luvly for guidance.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Find my size'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextFormField).at(i),
          ['85', '65', '95'][i],
        );
      }
      final calculate = find.widgetWithText(FilledButton, 'Find my size');
      await tester.ensureVisible(calculate);
      await tester.pumpAndSettle();
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Reference size: M'), findsOneWidget);
      await tester.ensureVisible(find.text('Use M'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use M'));
      await tester.pumpAndSettle();
      expect(find.text('Selected size: M'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'contacting support does not complete a selection; a real size is required',
    (tester) async {
      phone(tester);
      var contactCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PackageGownPicker(
            api: GownPackages(),
            eligibleIds: {'gown1'},
            allowance: 1,
            onContactSupport: () => contactCount++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gown-gown1')));
      await tester.pumpAndSettle();
      expect(find.text('Ask staff to confirm'), findsNothing);
      expect(find.text('Size guide & fit check'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Select this gown'),
            )
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Need help choosing? Contact Luvly'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Need help choosing? Contact Luvly'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Need help choosing? Contact Luvly'));
      await tester.pumpAndSettle();
      expect(contactCount, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use selected gowns (0/1)'),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('gown-gown1')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('gown-gown1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('size-gown1-M')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('size-gown1-M')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select this gown'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use selected gowns (1/1)'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  test(
    'package gown metadata and historical snapshots parse without changing prices',
    () {
      final p = gownPackage();
      final decoded = BridalPackage.fromJson(p.toJson());
      expect(decoded.includedGownCount, 1);
      expect(decoded.eligibleDressIds, ['gown1']);
      expect(decoded.total({}, {}), bridal.basePriceCents);
      final old = Map<String, dynamic>.from(p.toJson())
        ..remove('includedGownCount')
        ..remove('eligibleDressIds');
      expect(BridalPackage.fromJson(old).includedGownCount, 0);
      expect(
        PackageSelection({
          'selectedGowns': [
            {'name': 'Old name', 'size': 'M'},
          ],
        }).selectedGowns.single['name'],
        'Old name',
      );
    },
  );

  testWidgets(
    'customer must choose a gown and a size; standalone price is not added',
    (tester) async {
      phone(tester);
      final api = GownPackages();
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(
            package: gownPackage(accessories: false),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Review selection'),
            )
            .onPressed,
        isNull,
      );
      expect(api.selectionsSaved, 0);
      expect(
        find.text('Select each included gown and its size before review.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Explore wedding gowns'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final explore = find.text('Explore wedding gowns');
      await Scrollable.ensureVisible(tester.element(explore), alignment: .5);
      await tester.pumpAndSettle();
      await tester.tap(explore);
      await tester.pumpAndSettle();
      expect(find.textContaining('RM 9900'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('gown-gown1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Select this gown'),
            )
            .onPressed,
        isNull,
      );
      final sizePicker = find.byKey(const ValueKey('size-gown1-M'));
      await tester.ensureVisible(sizePicker);
      await tester.pumpAndSettle();
      await tester.tap(sizePicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select this gown'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use selected gowns (1/1)'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Review selection'));
      await tapVisible(tester, find.text('Save package selection'));
      expect(api.savedGowns, [
        {'dressId': 'gown1', 'size': 'M', 'revision': 2},
      ]);
      expect(api.selectionsSaved, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two-gown package cannot reuse one gown or proceed when stock is insufficient',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PackageGownPicker(
            api: GownPackages(),
            eligibleIds: {'gown1'},
            allowance: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Only 1 gown is available'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Use selected gowns (0/2)'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('gown-gown1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker excludes dresses outside package eligibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackageGownPicker(
          api: GownPackages(),
          eligibleIds: {'different'},
          allowance: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ivory gown'), findsNothing);
    expect(find.text('No matching gowns.'), findsOneWidget);
  });

  testWidgets('staff can edit eligibility without selecting customer sizes', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: PackageGownPicker(api: GownPackages(), eligibleIds: {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gown-gown1')));
    await tester.pumpAndSettle();
    expect(find.text('Use 1 eligible gowns'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });
}
