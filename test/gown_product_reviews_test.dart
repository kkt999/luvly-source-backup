import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/reviews/gown_reviews.dart';
import 'package:luvly_app/reviews/review_api.dart';
import 'package:luvly_app/reviews/review_screen.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/src/model.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'customer_reviews_test.dart' show savedReview;
import 'fake_catalogue.dart';

class ProductApi extends ReviewApi {
  final paths = <String>[];
  bool fail = false;
  List<Map<String, dynamic>> rows = [];
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    paths.add(path);
    if (fail) throw const PaymentFailure('Reviews unavailable. Retry.');
    if (Uri.parse(path).path.endsWith('/eligible')) {
      return {'rentals': <Map<String, dynamic>>[]};
    }
    return {
      'reviews': rows,
      'summary': {
        'count': rows.length,
        'average': rows.isEmpty ? 0 : 4.0,
        'distribution': {'5': 0, '4': rows.length, '3': 0, '2': 0, '1': 0},
      },
      'canManage': false,
    };
  }
}

Future<void> capture(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('product-artifact')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('work/product-2106')..createSync(recursive: true);
    File(
      '${folder.path}/$name.png',
    ).writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'empty product reviews show no invented score and writing filters eligible rentals',
    (t) async {
      final api = ProductApi();
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: Scaffold(
            body: GownReviews(
              dressId: 'gown-a',
              dressName: 'Synthetic gown',
              api: api,
              builder: (rating, section) =>
                  ListView(children: [rating, section]),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(api.paths.single, '/v1/reviews?scope=all&dressId=gown-a');
      expect(find.text('No reviews yet'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      await t.tap(find.text('Write a review'));
      await t.pumpAndSettle();
      expect(api.paths.last, '/v1/reviews/eligible?dressId=gown-a');
      expect(find.byType(ReviewEditor), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'product errors remain distinct from empty reviews; retry and all/mine retain product filter',
    (t) async {
      final api = ProductApi()..fail = true;
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: Scaffold(
            body: GownReviews(
              dressId: 'gown-a',
              dressName: 'Synthetic gown',
              api: api,
              builder: (rating, section) =>
                  ListView(children: [rating, section]),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('No reviews yet'), findsNothing);
      expect(find.text('Reviews unavailable. Retry.'), findsOneWidget);
      api.fail = false;
      api.rows = [savedReview(owner: false)];
      await t.tap(find.text('Retry reviews'));
      await t.pumpAndSettle();
      expect(find.text('Verified rental'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Read all reviews'), 200);
      await t.tap(find.text('Read all reviews'));
      await t.pumpAndSettle();
      expect(find.byType(ReviewsScreen), findsOneWidget);
      expect(api.paths.last, '/v1/reviews?scope=all&dressId=gown-a');
      await t.tap(find.text('My reviews'));
      await t.pumpAndSettle();
      expect(api.paths.last, '/v1/reviews?scope=mine&dressId=gown-a');
      expect(t.takeException(), isNull);
    },
  );
  test(
    'product details roundtrip and reject unknown, empty and oversized metadata',
    () {
      final fields = {
        ...sampleDress().toFields(),
        'revision': 1,
        'productDetails': {
          'neckline': 'Folded neckline',
          'features': 'Sculpted folds',
        },
      };
      final dress = CatalogueDress.fromFields('gown', fields);
      expect(dress.validationError, isNull);
      expect(dress.toFields()['productDetails'], fields['productDetails']);
      for (final invalid in [
        {'other': 'Extra'},
        {'features': 'x' * 601},
        {'neckline': ''},
      ]) {
        expect(
          CatalogueDress.fromFields('gown', {
            ...fields,
            'productDetails': invalid,
          }).validationError,
          isNotNull,
        );
      }
    },
  );
  for (final large in [false, true]) {
    testWidgets(
      'product photos, information and review layout ${large ? '320 double text' : '390 phone'}',
      (t) async {
        viewport(t, Size(large ? 320 : 390, 844));
        await fonts();
        final api = ProductApi()..rows = [savedReview(owner: false)];
        addTearDown(api.close);
        final repo = FakeCatalogue();
        addTearDown(repo.changes.close);
        final dress = CatalogueDress.fromFields('demo-elegant', {
          ...sampleDress(name: 'Elegant Bridal Gown').toFields(),
          'revision': 1,
          'photoRevision': 1,
          'imageUrl': '',
          'arModelId': 'elegant-local-review',
          'priceCents': 54900,
          'colour': 'White',
          'sizes': 'S, M, L, XL',
          'description':
              'A graceful white A-line silhouette with a defined bodice and a softly spreading skirt. Delicate sheer-effect layers and an extended train create an airy, romantic bridal look.',
          'productDetails': {
            'neckline': 'Sculpted bridal bodice',
            'fabricAppearance': 'Light, sheer-layer effect',
            'train': 'A-line skirt with an extended train',
            'features': 'A defined waist balances the flowing skirt.',
          },
        });
        repo.records[dress.id] = dress;
        final bytes = await rootBundle.load('assets/images/elegant_bridal.jpg');
        repo.photos[dress.id] = compressDressPhoto(bytes.buffer.asUint8List());
        final model = AppModel.live()..accountId = 'bride';
        addTearDown(model.dispose);
        await t.pumpWidget(
          AppScope(
            model: model,
            child: CatalogueScope(
              repository: repo,
              child: RepaintBoundary(
                key: const Key('product-artifact'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: luvlyTheme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: child!,
                  ),
                  home: LiveDressDetailScreen(id: dress.id, reviewApi: api),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(
          () => precacheImage(
            MemoryImage(repo.photos[dress.id]!.imageBytes),
            t.element(find.byType(LiveDressDetailScreen)),
          ),
        );
        await t.pumpAndSettle();
        await capture(t, large ? 'top-large' : 'top');
        await t.ensureVisible(find.text('About this gown'));
        await t.pumpAndSettle();
        await capture(t, large ? 'details-large' : 'details');
        expect(find.text('Neckline'), findsOneWidget);
        await t.scrollUntilVisible(find.text('Customer reviews'), 250);
        await t.pumpAndSettle();
        await capture(t, large ? 'reviews-large' : 'reviews');
        expect(find.text('Verified rental'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
