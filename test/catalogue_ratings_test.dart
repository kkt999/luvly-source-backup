import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/catalogue/gown_filters.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/reviews/gown_rating.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/src/model.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'fake_catalogue.dart';
import 'gown_product_reviews_test.dart' show ProductApi;
import 'gown_filters_test.dart' show gown;

class CatalogueApi extends ProductApi {
  bool failRatings = false;
  List<Map<String, dynamic>> ratings = [];
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (path == '/v1/reviews/ratings') {
      paths.add(path);
      if (failRatings) throw const PaymentFailure('Unavailable');
      return {'ratings': ratings};
    }
    return super.call(path, body: body);
  }
}

const products = [
  [
    'demo-elegant',
    'Elegant Bridal Gown',
    'elegant-local-review',
    'elegant_bridal',
  ],
  [
    'demo-francine',
    'Francine Gown',
    'francine-reference',
    'francine_reference',
  ],
  [
    'demo-princess',
    'Princess Wedding Dress',
    'princess-wedding',
    'princess_wedding',
  ],
  ['CRSQVMlGpVqIscfXfTJd', 'white dress', '', 'golden'],
];
Future<void> catalogue(
  WidgetTester t,
  CatalogueApi api, {
  bool large = false,
}) async {
  viewport(t, Size(large ? 320 : 390, 844));
  await fonts();
  final repo = FakeCatalogue();
  addTearDown(repo.changes.close);
  for (final row in products) {
    repo.records[row[0]] = CatalogueDress.fromFields(row[0], {
      ...sampleDress(name: row[1]).toFields(),
      'revision': 1,
      'imageUrl': '',
      'photoRevision': 1,
      'arModelId': row[2],
      'priceCents': row[0] == 'demo-francine' ? 49900 : 54900,
    });
    final bytes = await rootBundle.load('assets/images/${row[3]}.jpg');
    repo.photos[row[0]] = compressDressPhoto(bytes.buffer.asUint8List());
  }
  final model = AppModel.live()..accountId = 'bride';
  addTearDown(model.dispose);
  await t.pumpWidget(
    AppScope(
      model: model,
      child: CatalogueScope(
        repository: repo,
        child: RepaintBoundary(
          key: const Key('ratings-artifact'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: Scaffold(body: LiveCatalogueScreen(reviewApi: api)),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.runAsync(() async {
    for (final photo in repo.photos.values) {
      await precacheImage(
        MemoryImage(photo.imageBytes),
        t.element(find.byType(LiveCatalogueScreen)),
      );
    }
  });
  await t.pumpAndSettle();
}

List<Map<String, dynamic>> emptyRatings() => [
  for (final row in products) {'dressId': row[0], 'count': 0, 'average': 0},
];
Future<void> capture(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('ratings-artifact')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('work/ratings-2108')..createSync(recursive: true);
    File(
      '${folder.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  test(
    'rating thresholds combine with existing constraints; unrated sort last and ties are stable',
    () {
      final gowns = [
        gown('A', 10000, 'S, M', 'Ivory'),
        gown('B', 20000, 'M', 'White'),
        gown('C', 9000, 'S', 'Ivory'),
      ];
      final ratings = {
        'A': const GownRating(average: 4.5, count: 2),
        'B': const GownRating(average: 4.49, count: 8),
      };
      expect(
        const GownFilters(
          minRating: 4.5,
        ).apply(gowns, ratings: ratings).map((d) => d.id),
        ['A'],
      );
      expect(
        const GownFilters(
          minRating: 4,
        ).apply(gowns, ratings: ratings).map((d) => d.id),
        ['A', 'B'],
      );
      expect(
        const GownFilters(
          minRating: 4,
          colour: 'Ivory',
          size: 'M',
          maxPriceCents: 10000,
        ).apply(gowns, ratings: ratings).map((d) => d.id),
        ['A'],
      );
      expect(
        const GownFilters(
          sort: GownSort.ratingHigh,
        ).apply(gowns, ratings: ratings).map((d) => d.id),
        ['A', 'B', 'C'],
      );
      ratings['B'] = const GownRating(average: 4.5, count: 8);
      expect(
        const GownFilters(
          sort: GownSort.ratingHigh,
        ).apply(gowns, ratings: ratings).map((d) => d.id),
        ['B', 'A', 'C'],
      );
      expect(gowns.map((d) => d.id), ['A', 'B', 'C']);
    },
  );
  test('zero-count products have no rating and malformed numbers fail', () {
    final ratings = catalogueRatings({
      'ratings': [
        {'dressId': 'demo-elegant', 'count': 2, 'average': 4},
        {'dressId': 'demo-francine', 'count': 0, 'average': 0},
        {'dressId': 'new-gown', 'count': 0, 'average': 0},
      ],
    });
    expect(ratings['demo-elegant']!.average, 4);
    expect(ratings['demo-francine']!.label, 'No reviews yet');
    expect(ratings.containsKey('demo-princess'), false);
    expect(ratings['new-gown']!.label, 'No reviews yet');
    for (final row in [
      {'dressId': 'a', 'count': -1, 'average': 4},
      {'dressId': 'a', 'count': 0, 'average': 5},
      {'dressId': 'a', 'count': 1, 'average': 6},
    ]) {
      expect(
        () => catalogueRatings({
          'ratings': [row],
        }),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'cards show ratings; filters use the displayed source and refreshing after details keeps selections',
    (t) async {
      final api = CatalogueApi()..ratings = emptyRatings();
      addTearDown(api.close);
      for (final (id, average) in [
        ('demo-elegant', 4.7),
        ('demo-francine', 4.3),
        ('demo-princess', 4.7),
        ('CRSQVMlGpVqIscfXfTJd', 4.3),
      ]) {
        api.ratings.firstWhere((row) => row['dressId'] == id)
          ..['count'] = 3
          ..['average'] = average;
      }
      await catalogue(t, api);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('gown-rating-demo-elegant')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('4.7 (3)'), findsNWidgets(2));
      expect(find.text('4.3 (3)'), findsNWidgets(2));
      await t.scrollUntilVisible(
        find.byKey(const Key('open-catalogue-filters')),
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('open-catalogue-filters')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open-catalogue-filters')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('filter-rating-4.5')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('apply-gown-filters')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Elegant Bridal Gown'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Francine Gown'), findsNothing);
      expect(find.text('white dress'), findsNothing);
      expect(api.paths.where((p) => p == '/v1/reviews/ratings').length, 1);
      await t.tap(find.text('Elegant Bridal Gown'));
      await t.pumpAndSettle();
      api.ratings[0] = {'dressId': 'demo-elegant', 'count': 1, 'average': 4};
      await t.pageBack();
      await t.pumpAndSettle();
      expect(api.paths.where((p) => p == '/v1/reviews/ratings').length, 2);
      await t.scrollUntilVisible(
        find.text('Princess Wedding Dress'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Elegant Bridal Gown'), findsNothing);
      expect(find.text('Princess Wedding Dress'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'a rating outage does not create demo ratings or hide the catalogue; retry recovers',
    (t) async {
      final api = CatalogueApi()
        ..failRatings = true
        ..ratings = emptyRatings();
      addTearDown(api.close);
      await catalogue(t, api);
      await t.scrollUntilVisible(
        find.text('Retry ratings'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Ratings are temporarily unavailable.'), findsOneWidget);
      expect(find.text('4.7 (3)'), findsNothing);
      api.failRatings = false;
      await t.tap(find.text('Retry ratings'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Elegant Bridal Gown'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Elegant Bridal Gown'), findsOneWidget);
      expect(find.text('No reviews yet'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
  for (final large in [false, true]) {
    testWidgets('catalogue rating layout ${large ? 'large text' : 'phone'}', (
      t,
    ) async {
      final api = CatalogueApi()..ratings = emptyRatings();
      addTearDown(api.close);
      await catalogue(t, api, large: large);
      await t.scrollUntilVisible(
        find.text('Elegant Bridal Gown'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await capture(t, large ? 'collection-large' : 'collection');
      await t.scrollUntilVisible(
        find.byKey(const Key('open-catalogue-filters')),
        -240,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('open-catalogue-filters')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open-catalogue-filters')));
      await t.pumpAndSettle();
      await capture(t, large ? 'filters-large' : 'filters');
      expect(t.takeException(), isNull);
    });
  }
}
