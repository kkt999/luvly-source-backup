import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/accessory_catalogue.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package_test.dart' show FakePackages, bridal;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      -180,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'standard veil is selected by default and a catalogue upgrade adds only the difference',
    (tester) async {
      addTearDown(
        () => rootBundle.evict('assets/images/accessory-catalogue.json'),
      );
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const veil = PackageServiceItem(
        id: 'veil-rental',
        name: 'Veil Rental',
        description: '',
        kind: 'Optional',
        priceCents: 8000,
        serviceType: PackageServiceType.packageVeil,
        standardVeilId: 'veil-short',
      );
      final package = BridalPackage(
        id: bridal.id,
        name: bridal.name,
        description: bridal.description,
        revision: 1,
        active: true,
        basePriceCents: 172900,
        services: [bridal.services.first, veil],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(package: package, api: FakePackages()),
        ),
      );
      await tester.runAsync(AccessoryCatalogue.load);
      await tester.pumpAndSettle();
      final picker = find.byType(AccessoryServicePicker);
      await tester.scrollUntilVisible(
        picker,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AccessoryServicePicker>(picker).selected, {
        'veil-short',
      });
      expect(find.textContaining('RM 1,729.00'), findsWidgets);
      await tapVisible(tester, find.text('Edit veil'));
      expect(find.textContaining('Included in the package'), findsWidgets);
      final upgrade = find.text('+ RM 50.00 upgrade');
      await tester.scrollUntilVisible(
        upgrade,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final card = find
          .ancestor(of: upgrade, matching: find.byType(Column))
          .first;
      await tapVisible(
        tester,
        find.descendant(of: card, matching: find.text('Select')),
      );
      await tester.tap(find.text('Use these accessories'));
      await tester.pumpAndSettle();
      expect(tester.widget<AccessoryServicePicker>(picker).selected, {
        'veil-long',
      });
      expect(find.textContaining('RM 1,779.00'), findsWidgets);
      await tapVisible(
        tester,
        find.widgetWithText(CheckboxListTile, 'Veil Rental'),
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('RM 1,649.00'), findsWidgets);
    },
  );
  testWidgets('category filter, search, details and independent selection', (
    tester,
  ) async {
    final c = (await tester.runAsync(AccessoryCatalogue.load))!;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessoryBrowser(
          catalogue: c,
          service: bridal.services[1],
          initial: const {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Rings'));
    expect(find.text('Luna Solitaire Ring'), findsOneWidget);
    expect(find.text('Aurora Halo Ring'), findsOneWidget);
    expect(find.text('Belle Pearl Pendant'), findsNothing);
    await tapVisible(tester, find.text('Select').first);
    expect(find.textContaining('1 selected'), findsOneWidget);
    await tapVisible(tester, find.text('View details').first);
    await tester.scrollUntilVisible(
      find.textContaining('Adjustable open band'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('Adjustable open band'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Necklaces'));
    expect(find.text('Luna Solitaire Ring'), findsNothing);
    expect(find.text('Belle Pearl Pendant'), findsOneWidget);
    await tapVisible(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'no such style');
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching accessories'), findsOneWidget);
    expect(find.textContaining('1 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'veil choices exclude jewellery; pricing allowance is applied once',
    (tester) async {
      final c = (await tester.runAsync(AccessoryCatalogue.load))!;
      const veil = PackageServiceItem(
        id: 'veil',
        name: 'Veil rental',
        description: '',
        kind: 'Optional',
        priceCents: 8000,
      );
      expect(c.choices(veil).length, 2);
      expect(c.extra(veil, {'veil-long'}), 5000);
      const jewellery = PackageServiceItem(
        id: 'jewels',
        name: 'Accessory rental',
        description: '',
        kind: 'Optional',
        priceCents: 7000,
      );
      expect(c.extra(jewellery, {'tiara', 'necklace-floral'}), 4500);
      expect(c.extra(jewellery, {'necklace-pearl'}), 0);
      const combined = PackageServiceItem(
        id: 'veil-accessories',
        name: 'Veil and accessory set rental',
        description: '',
        kind: 'Optional',
        priceCents: 15000,
      );
      expect(
        c.choices(combined).map((item) => item.id),
        containsAll(['veil-short', 'ring-halo']),
      );
      expect(c.extra(combined, {'veil-short', 'ring-halo'}), 0);
      expect(c.extra(combined, {'veil-long', 'ring-halo'}), 1500);
    },
  );
  testWidgets('unchecking service hides and clears selected accessories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PackageChoiceScreen(package: bridal, api: FakePackages()),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Choose accessories'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Rings'));
    await tapVisible(tester, find.text('Select').first);
    await tester.tap(find.text('Use these accessories'));
    await tester.pumpAndSettle();
    final pickerFinder = find.byType(AccessoryServicePicker);
    expect(
      tester.widget<AccessoryServicePicker>(pickerFinder).selected,
      hasLength(1),
    );
    await tapVisible(tester, find.text('Accessory details'));
    await tapVisible(tester, find.text('Accessory details'));
    expect(
      tester.widget<AccessoryServicePicker>(pickerFinder).selected,
      hasLength(1),
    );
    await tapVisible(
      tester,
      find.widgetWithText(CheckboxListTile, 'Accessories styling'),
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.byType(AccessoryServicePicker), findsNothing);
    await tapVisible(tester, find.byType(SwitchListTile));
    await tapVisible(tester, find.byType(SwitchListTile));
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Accessories styling'),
          )
          .value,
      isFalse,
    );
    await tapVisible(
      tester,
      find.widgetWithText(CheckboxListTile, 'Accessories styling'),
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    final picker = tester.widget<AccessoryServicePicker>(
      find.byType(AccessoryServicePicker),
    );
    expect(picker.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'optional item-priced accessories block review until a valid style is chosen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const extras = PackageServiceItem(
        id: 'extras',
        name: 'Bridal Accessories',
        description: '',
        kind: 'Add-on',
        priceCents: 0,
        serviceType: PackageServiceType.itemAccessories,
      );
      final p = BridalPackage(
        id: bridal.id,
        name: bridal.name,
        description: bridal.description,
        basePriceCents: 179900,
        revision: 1,
        active: true,
        services: [bridal.services.first, extras],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PackageChoiceScreen(package: p, api: FakePackages()),
        ),
      );
      await tester.runAsync(AccessoryCatalogue.load);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review selection'));
      await tester.pumpAndSettle();
      expect(find.text('Review your package'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(
        CheckboxListTile,
        'Bridal Accessories',
      );
      await tapVisible(tester, toggle);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Please choose at least one'), findsOneWidget);
      await tester.tap(find.text('Review selection'));
      await tester.pumpAndSettle();
      expect(find.text('Review your package'), findsNothing);
      await tapVisible(tester, find.text('Choose accessories'));
      final use = find.widgetWithText(FilledButton, 'Use these accessories');
      expect(tester.widget<FilledButton>(use).onPressed, isNull);
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Rings'));
      await tapVisible(tester, find.text('Select').first);
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(find.textContaining('RM 1,819.00'), findsWidgets);
      await tapVisible(tester, find.text('Edit accessories (1)'));
      expect(find.textContaining('1 selected · RM 20.00'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review selection'));
      await tester.pumpAndSettle();
      expect(find.text('Review your package'), findsOneWidget);
      expect(find.textContaining('RM 1,819.00'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Edit accessories (1)'));
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Rings'));
      await tapVisible(tester, find.text('Selected ✓'));
      await tester.tap(find.text('Clear accessories'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Please choose at least one'), findsOneWidget);
      expect(find.textContaining('RM 1,799.00'), findsWidgets);
      await tapVisible(tester, toggle);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('RM 1,799.00'), findsWidgets);
      expect(find.byType(AccessoryServicePicker), findsNothing);
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    testWidgets('accessory visual ${width.toInt()}', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = (await tester.runAsync(AccessoryCatalogue.load))!;
      const key = ValueKey('accessory-capture');
      await tester.runAsync(() async {
        for (final entry in {
          'LuvlySans': 'assets/fonts/roboto-regular.ttf',
          'LuvlySerif': 'assets/fonts/CormorantGaramond.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          await (FontLoader(
            entry.key,
          )..addFont(rootBundle.load(entry.value))).load();
        }
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            home: AccessoryBrowser(
              catalogue: c,
              service: bridal.services[1],
              initial: const {},
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (final i in c.items) {
          await precacheImage(
            AssetImage(i.image),
            tester.element(find.byType(AccessoryBrowser)),
          );
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('previews/accessory-catalogue-${width.toInt()}.png'),
      );
    });
  }
}
