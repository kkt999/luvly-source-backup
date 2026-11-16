import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/packages/package_gowns.dart';
import 'package:luvly_app/packages/accessory_catalogue.dart';
import 'package:luvly_app/payments/payment_filters.dart';
import 'package:luvly_app/shared/list_controls.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'packages/package_gowns_test.dart' show GownPackages, testGown;
import 'packages/package_test.dart' show bridal;

Future<void> capture(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('filter-audit-artifact')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('work/filters-2110')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget app(Widget home, {bool portal = false, double scale = 1}) =>
    RepaintBoundary(
      key: const Key('filter-audit-artifact'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: portal ? portalTheme : luvlyTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );

class PickerApi extends GownPackages {
  @override
  Future<List<CatalogueDress>> gowns() async => [
    testGown,
    CatalogueDress.fromFields('gown2', {
      ...testGown.toFields(),
      'revision': 2,
      'name': 'White gown',
      'colour': 'White',
    }),
  ];
}

void main() {
  for (final large in [false, true]) {
    testWidgets(
      'shared filters fit and preserve opaque staff IDs ${large ? '320 double text' : 'desktop'}',
      (t) async {
        viewport(t, Size(large ? 320 : 1200, 900));
        await fonts();
        var selected = 'staff-1';
        const labels = {
          'staff-1': 'Alex Lee — bridal fitting and alterations',
          'staff-2': 'Alex Lee — bridal makeup',
        };
        await t.pumpWidget(
          app(
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: StatefulBuilder(
                  builder: (context, update) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ListFilterSelect(
                        label: 'Employee',
                        value: selected,
                        options: labels.keys.toList(),
                        labels: labels,
                        onChanged: (v) => update(() => selected = v),
                      ),
                      ListFilterSelect(
                        label: 'Status',
                        value: 'Awaiting customer confirmation',
                        options: const [
                          'All statuses',
                          'Awaiting customer confirmation',
                          'Completed',
                        ],
                        onChanged: (_) {},
                      ),
                      ListFilterSelect(
                        label: 'Sort by',
                        value: 'Upcoming first',
                        options: const ['Upcoming first', 'Customer: A–Z'],
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
            portal: true,
            scale: large ? 2 : 1,
          ),
        );
        await t.pumpAndSettle();
        await capture(t, large ? 'staff-large' : 'staff-wide');
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is ListFilterSelect && w.label == 'Employee',
          ),
        );
        await t.pumpAndSettle();
        await capture(t, large ? 'staff-menu-large' : 'staff-menu');
        await t.tap(find.byKey(const ValueKey('list-option-Employee-staff-2')));
        await t.pumpAndSettle();
        expect(selected, 'staff-2');
        expect(find.text(labels['staff-2']!), findsOneWidget);
        expect(find.text('staff-2'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'payment filters retain query, close without applying and keep actions accessible ${large ? 'large' : 'phone'}',
      (t) async {
        viewport(t, Size(large ? 320 : 390, 844));
        await fonts();
        PaymentListFilter? result;
        var completed = false;
        await t.pumpWidget(
          app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    child: const Text('Open payment filters'),
                    onPressed: () async {
                      result = await showPaymentFilters(
                        context,
                        const PaymentListFilter(
                          query: 'Bridal',
                          status: PaymentListStatus.paid,
                        ),
                      );
                      completed = true;
                    },
                  ),
                ),
              ),
            ),
            scale: large ? 2 : 1,
          ),
        );
        await t.tap(find.text('Open payment filters'));
        await t.pumpAndSettle();
        await capture(t, large ? 'payment-large' : 'payment');
        expect(t.getCenter(find.text('Apply filters')).dy, lessThan(844));
        await t.tap(find.byTooltip('Close filters'));
        await t.pumpAndSettle();
        expect(completed, true);
        expect(result, isNull);
        await t.tap(find.text('Open payment filters'));
        await t.pumpAndSettle();
        await t.tap(find.text('Reset'));
        await t.pumpAndSettle();
        expect(
          t
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('payment-filter-status-all')),
              )
              .selected,
          true,
        );
        await t.tap(find.text('Apply filters'));
        await t.pumpAndSettle();
        expect(result!.query, 'Bridal');
        expect(result!.status, PaymentListStatus.all);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'included gown filters omit rental price and preserve a hidden selected gown',
    (t) async {
      viewport(t, const Size(390, 844));
      await fonts();
      await t.pumpWidget(
        app(
          PackageGownPicker(
            api: PickerApi(),
            eligibleIds: const {'gown1', 'gown2'},
            allowance: 1,
            initial: const [PackageGownChoice(testGown, 'M')],
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('package-gown-filters')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('filter-rental-budget')), findsNothing);
      expect(find.text('Sort by'), findsNothing);
      await capture(t, 'included-gowns');
      await t.tap(find.byKey(const Key('filter-colour-White')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('apply-gown-filters')));
      await t.pumpAndSettle();
      expect(find.text('Ivory gown'), findsNothing);
      expect(find.text('White gown'), findsOneWidget);
      expect(find.text('Use selected gowns (1/1)'), findsOneWidget);
      expect(find.textContaining('RM 9900'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'accessory price sorting changes display order without selecting items',
    (t) async {
      viewport(t, const Size(390, 900));
      await fonts();
      final catalogue = (await t.runAsync(AccessoryCatalogue.load))!;
      await t.pumpWidget(
        app(
          AccessoryBrowser(
            catalogue: catalogue,
            service: bridal.services[1],
            initial: const {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Rings'));
      await t.tap(find.widgetWithText(ChoiceChip, 'Rings'));
      await t.pumpAndSettle();
      final sort = find.byType(ListFilterSelect);
      await t.ensureVisible(sort);
      await t.pumpAndSettle();
      await t.tap(sort);
      await t.pumpAndSettle();
      await t.tap(
        find.byKey(const ValueKey('list-option-Sort by-Price: high to low')),
      );
      await t.pumpAndSettle();
      final names = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            ['Aurora Halo Ring', 'Luna Solitaire Ring'].contains(w.data),
      );
      expect(names.evaluate().map((e) => (e.widget as Text).data), [
        'Aurora Halo Ring',
        'Luna Solitaire Ring',
      ]);
      expect(find.textContaining('0 selected'), findsOneWidget);
      await capture(t, 'accessories');
      expect(t.takeException(), isNull);
    },
  );
}
