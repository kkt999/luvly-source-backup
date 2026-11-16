import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/reviews/gown_reviews.dart';
import 'package:luvly_app/src/design.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'gown_product_reviews_test.dart' show ProductApi;
import 'customer_reviews_test.dart' show savedReview;

Widget page(ProductApi api, {double scale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: luvlyTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    appBar: AppBar(title: const Text('Gown reviews')),
    body: GownReviews(
      dressId: 'demo-elegant',
      dressName: 'Elegant Bridal Gown',
      api: api,
      builder: (rating, section) => ListView(
        padding: const EdgeInsets.all(24),
        children: [rating, section],
      ),
    ),
  ),
);

void main() {
  testWidgets('a gown with no reviews shows an honest empty state', (t) async {
    final api = ProductApi();
    addTearDown(api.close);
    await t.pumpWidget(page(api));
    await t.pumpAndSettle();
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('Be the first to share your experience'), findsOneWidget);
    expect(find.text('Demo reviews'), findsNothing);
    expect(api.rows, isEmpty);
    expect(api.paths, ['/v1/reviews?scope=all&dressId=demo-elegant']);
  });
  testWidgets(
    'real ratings replace fixtures and an outage never masquerades as samples',
    (t) async {
      final api = ProductApi()..rows = [savedReview(owner: false)];
      addTearDown(api.close);
      await t.pumpWidget(page(api));
      await t.pumpAndSettle();
      expect(find.text('4.0 · 1 review'), findsOneWidget);
      expect(find.text('Demo reviews'), findsNothing);
      expect(find.text('Verified rental'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      api.rows = [];
      api.fail = true;
      await t.pumpWidget(page(api));
      await t.pumpAndSettle();
      expect(find.text('Reviews unavailable. Retry.'), findsOneWidget);
      expect(find.text('Demo reviews'), findsNothing);
      expect(find.text('4.7 · 3 demo reviews'), findsNothing);
    },
  );
  for (final large in [false, true]) {
    testWidgets('empty review layout ${large ? 'double text' : 'phone'}', (
      t,
    ) async {
      viewport(t, Size(large ? 320 : 390, 844));
      await fonts();
      final api = ProductApi();
      addTearDown(api.close);
      await t.pumpWidget(
        RepaintBoundary(
          key: const Key('demo-review-artifact'),
          child: page(api, scale: large ? 2 : 1),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('No reviews yet'), findsOneWidget);
      await t.pumpAndSettle();
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('demo-review-artifact')),
      );
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory('work/reviews-2112')
          ..createSync(recursive: true);
        File(
          '${folder.path}/${large ? 'large' : 'phone'}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
