import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/gown_filter_sheet.dart';
import 'package:luvly_app/catalogue/gown_filters.dart';
import 'package:luvly_app/reviews/gown_rating.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'gown_filters_test.dart' show gown;

final candidates = [
  gown('A', 49900, 'S, M', 'Ivory'),
  gown('B', 59900, 'M, L', 'White'),
  gown('C', 89900, 'XL', 'White'),
];
const ratings = {
  'A': GownRating(average: 4.7, count: 3),
  'B': GownRating(average: 4.3, count: 3),
  'C': GownRating(average: 0, count: 0),
};

Future<void> open(
  WidgetTester t, {
  GownFilters initial = const GownFilters(),
  bool large = false,
  bool ratingsReady = true,
  required ValueChanged<GownBrowseFilters?> result,
}) async {
  viewport(t, Size(large ? 320 : 390, 844));
  await fonts();
  await t.pumpWidget(
    RepaintBoundary(
      key: const Key('sheet-artifact'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: luvlyTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result(
                  await showGownFilterSheet(
                    context,
                    initial: initial,
                    availableOnly: false,
                    candidates: candidates,
                    ratings: ratings,
                    includeRatings: true,
                    ratingsReady: ratingsReady,
                  ),
                ),
                child: const Text('Open filters'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open filters'));
  await t.pumpAndSettle();
}

Future<void> option(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  await t.scrollUntilVisible(
    target,
    180,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('gown-filter-options')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await t.pumpAndSettle();
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('sheet-artifact')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('work/filters-2109')..createSync(recursive: true);
    File(
      '${folder.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'selections stay draft until applied and the result count combines constraints',
    (t) async {
      GownBrowseFilters? applied;
      await open(t, result: (value) => applied = value);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await t.tap(find.byKey(const Key('filter-sort-ratingHigh')));
      await t.tap(find.byKey(const Key('filter-rating-4.5')));
      await t.pumpAndSettle();
      expect(applied, isNull);
      expect(find.text('Show 1 gown'), findsOneWidget);
      await option(t, 'filter-colour-Ivory');
      await t.tap(find.byKey(const Key('filter-colour-Ivory')));
      await option(t, 'filter-size-M');
      await t.tap(find.byKey(const Key('filter-size-M')));
      await t.tap(find.byKey(const Key('apply-gown-filters')));
      await t.pumpAndSettle();
      expect(applied!.filters.colour, 'Ivory');
      expect(applied!.filters.size, 'M');
      expect(applied!.filters.minRating, 4.5);
      expect(applied!.filters.sort, GownSort.ratingHigh);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'close discards changes and reset clears the entire draft before apply',
    (t) async {
      GownBrowseFilters? applied;
      var returned = false;
      const initial = GownFilters(
        colour: 'Ivory',
        size: 'M',
        minRating: 4.5,
        maxPriceCents: 50000,
        sort: GownSort.ratingHigh,
      );
      await open(
        t,
        initial: initial,
        result: (value) {
          returned = true;
          applied = value;
        },
      );
      await t.tap(find.byKey(const Key('filter-rating-any')));
      await t.tap(find.byKey(const Key('close-gown-filters')));
      await t.pumpAndSettle();
      expect(returned, true);
      expect(applied, isNull);
      await t.tap(find.text('Open filters'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const Key('filter-rating-4.5')))
            .selected,
        true,
      );
      await t.tap(find.byKey(const Key('reset-gown-filters')));
      await t.pumpAndSettle();
      expect(find.text('Show 3 gowns'), findsOneWidget);
      await t.tap(find.byKey(const Key('apply-gown-filters')));
      await t.pumpAndSettle();
      expect(applied!.filters.hasProductConstraints, false);
      expect(applied!.filters.sort, GownSort.name);
      expect(applied!.availableOnly, false);
    },
  );
  testWidgets(
    'invalid budget cannot apply and unavailable rating controls do not fabricate counts',
    (t) async {
      await open(t, ratingsReady: false, result: (_) {});
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const Key('filter-rating-4.5')))
            .onSelected,
        isNull,
      );
      expect(
        t
            .widget<ChoiceChip>(find.byKey(const Key('filter-sort-ratingHigh')))
            .onSelected,
        isNull,
      );
      await option(t, 'filter-rental-budget');
      await t.enterText(find.byKey(const Key('filter-rental-budget')), '-50');
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('apply-gown-filters')))
            .onPressed,
        isNull,
      );
      await t.enterText(find.byKey(const Key('filter-rental-budget')), '500');
      await t.pump();
      expect(find.text('Show 1 gown'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('filter-rental-budget')))
            .controller!
            .text,
        '500',
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'filter sheet is readable and actions remain accessible ${large ? 'large text' : 'phone'}',
      (t) async {
        await open(t, large: large, result: (_) {});
        await capture(t, large ? 'top-large' : 'top');
        await option(t, 'filter-rental-budget');
        await t.pumpAndSettle();
        await capture(t, large ? 'budget-large' : 'budget');
        t.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(t.view.resetViewInsets);
        await t.showKeyboard(find.byKey(const Key('filter-rental-budget')));
        await t.pumpAndSettle();
        expect(
          t.getCenter(find.byKey(const Key('apply-gown-filters'))).dy,
          lessThan(844 - 260),
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
