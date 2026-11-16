import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package_test.dart' show FakePackages, bridal;
import 'package:luvly_app/packages/package_gowns.dart';
import 'package_gowns_test.dart' show GownPackages, testGown;

void main() {
  for (final scene in [
    'customer',
    'customize',
    'editor',
    'editor-preview',
    'editor-services',
    'manager',
    'staff-catalogue',
    'customer-rentals',
    'gowns',
    'gowns-selected',
  ]) {
    testWidgets('Package layout $scene', (tester) async {
      final workspace = [
        'manager',
        'staff-catalogue',
        'customer-rentals',
      ].contains(scene);
      final editor = scene.startsWith('editor');
      tester.view.physicalSize = Size(workspace || editor ? 1366 : 390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final api = FakePackages();
      api.rows.add(
        PackageSelection({
          'id': 'selection',
          'name': bridal.name,
          'customerName': 'Sample Bride',
          'totalCents': 250000,
          'services': bridal.services
              .where((s) => s.kind != 'Add-on')
              .map((s) => s.toJson())
              .toList(),
          'appointments': [],
          'invoice': null,
        }),
      );
      const capture = ValueKey('capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: workspace || editor ? portalTheme : luvlyTheme,
            home: switch (scene) {
              'gowns' => PackageGownPicker(
                api: GownPackages(),
                eligibleIds: {'gown1'},
                allowance: 1,
              ),
              'gowns-selected' => PackageGownPicker(
                api: GownPackages(),
                eligibleIds: {'gown1'},
                allowance: 1,
                initial: const [PackageGownChoice(testGown, 'M')],
              ),
              'customize' => PackageChoiceScreen(package: bridal, api: api),
              'editor' ||
              'editor-preview' ||
              'editor-services' => PackageEditor(
                api: api,
                package: BridalPackage(
                  id: bridal.id,
                  name: 'Bridal Essentials',
                  description:
                      'A gown rental and personal styling for your wedding day.',
                  basePriceCents: 89900,
                  revision: 1,
                  active: false,
                  draft: true,
                  includedGownCount: 1,
                  eligibleDressIds: const ['first-gown', 'second-gown'],
                  services: [
                    bridal.services.first,
                    const PackageServiceItem(
                      id: 'veil',
                      name: 'Veil rental',
                      description:
                          'Choose a veil from the boutique collection.',
                      kind: 'Optional',
                      priceCents: 7000,
                      serviceType: PackageServiceType.veil,
                      accessoryAllowanceCents: 8000,
                    ),
                    const PackageServiceItem(
                      id: 'day',
                      name: 'Additional rental day',
                      description: '',
                      kind: 'Add-on',
                      priceCents: 8000,
                      serviceType: PackageServiceType.extraRentalDay,
                    ),
                  ],
                ),
              ),
              'manager' => LivePackageScreen(
                api: api,
                staff: true,
                manager: true,
              ),
              'staff-catalogue' => LivePackageScreen(api: api, staff: true),
              'customer-rentals' => LivePackageScreen(
                api: api,
                staff: true,
                initialSelections: true,
              ),
              _ => LivePackageScreen(api: api),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scene == 'customize') {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
      }
      if (scene == 'editor-preview') {
        await tester.tap(find.text('Review package'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Veil rental'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckboxListTile, 'Additional rental day'),
        );
        await tester.pumpAndSettle();
      }
      if (scene == 'editor-services') {
        final add = find.text('Add service');
        await tester.ensureVisible(add);
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile('previews/$scene.png'),
      );
    });
  }
}
