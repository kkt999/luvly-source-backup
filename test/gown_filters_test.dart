import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/gown_filters.dart';

CatalogueDress gown(String id, int price, String size, String colour) =>
    CatalogueDress(
      id: id,
      name: id,
      category: 'A-Line',
      description: 'Wedding dress for testing.',
      colour: colour,
      sizes: size,
      priceCents: price,
      imageUrl: '',
      published: true,
    );

void main() {
  testWidgets(
    'controlled filters preserve budget typing and restore selected rating',
    (tester) async {
      var value = const GownFilters(minRating: 4.5, sort: GownSort.ratingHigh);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, update) => GownFilterPanel(
                  value: value,
                  includeRatings: true,
                  onChanged: (next) => update(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Refine your selection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '1',
      );
      await tester.enterText(find.byType(TextField), '12.5');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12.5',
      );
      expect(value.maxPriceCents, 1250);
      expect(value.minRating, 4.5);
      expect(value.sort, GownSort.ratingHigh);
      expect(tester.takeException(), isNull);
    },
  );
  final gowns = [
    gown('A', 10001, 'S, M', 'Ivory'),
    gown('B', 20000, 'M, L', 'White'),
    gown('C', 10000, 'Made to measure', 'Ivory'),
  ];
  test('combined filters require exact size and include budget boundary', () {
    expect(
      const GownFilters(
        size: 'M',
        colour: 'Ivory',
        maxPriceCents: 10001,
      ).apply(gowns).map((d) => d.id),
      ['A'],
    );
    expect(
      const GownFilters(size: 'M', maxPriceCents: 10000).apply(gowns),
      isEmpty,
    );
    expect(
      const GownFilters(size: 'Made to measure').apply(gowns).single.id,
      'C',
    );
  });
  test('sorting is deterministic and does not mutate catalogue', () {
    expect(
      const GownFilters(sort: GownSort.priceHigh).apply(gowns).map((d) => d.id),
      ['B', 'A', 'C'],
    );
    expect(gowns.map((d) => d.id), ['A', 'B', 'C']);
  });
  testWidgets(
    'budget validation avoids silently treating invalid input as unlimited',
    (tester) async {
      GownFilters? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GownFilterPanel(onChanged: (v) => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Refine your selection'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '100.01');
      await tester.pump();
      expect(value!.maxPriceCents, 10001);
      await tester.enterText(find.byType(TextField), '-5');
      await tester.pump();
      expect(find.textContaining('Enter a positive RM'), findsOneWidget);
      expect(value!.maxPriceCents, 10001);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(value!.maxPriceCents, isNull);
    },
  );
  testWidgets('included gowns do not expose standalone price filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GownFilterPanel(includePrice: false, onChanged: (_) {}),
        ),
      ),
    );
    await tester.tap(find.text('Refine your selection'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Colour'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
