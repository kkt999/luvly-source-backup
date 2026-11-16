import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/src/model.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'fake_catalogue.dart';

// Rendered review artifacts, not automatically accepted golden baselines.
Future<void> capture(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('review-artifact')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('work/ar-entry-2105')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final large in [false, true]) {
    testWidgets(
      'Single-purpose list and preview group fit ${large ? 'large text' : 'phone'}',
      (t) async {
        viewport(t, Size(large ? 320 : 390, 844));
        await fonts();
        final repo = FakeCatalogue();
        addTearDown(repo.changes.close);
        final model = AppModel.live()..accountId = 'bride';
        addTearDown(model.dispose);
        for (final row in [
          [
            'elegant',
            'Elegant Bridal Gown',
            'elegant-local-review',
            'elegant_bridal',
            54900,
          ],
          [
            'francine',
            'Francine Gown',
            'francine-reference',
            'francine_reference',
            49900,
          ],
          [
            'princess',
            'Princess Wedding Dress',
            'princess-wedding',
            'princess_wedding',
            59900,
          ],
          ['white', 'White dress', '', 'golden', 1000000],
        ]) {
          final id = 'demo-${row[0]}';
          repo.records[id] = CatalogueDress.fromFields(id, {
            ...sampleDress(name: row[1] as String).toFields(),
            'revision': 1,
            'photoRevision': 1,
            'imageUrl': '',
            'arModelId': row[2],
            'priceCents': row[4],
            'category': row[0] == 'francine'
                ? 'Sheath'
                : row[0] == 'elegant'
                ? 'A-Line'
                : 'Ball Gown',
            'colour': row[0] == 'francine'
                ? 'Ivory'
                : row[0] == 'white'
                ? 'Off-white'
                : 'White',
            'sizes': row[0] == 'white' ? 'XXS, XS, 5XL' : 'S, M, L, XL',
          });
          final bytes = await rootBundle.load('assets/images/${row[3]}.jpg');
          repo.photos[id] = compressDressPhoto(bytes.buffer.asUint8List());
        }
        await t.pumpWidget(
          AppScope(
            model: model,
            child: CatalogueScope(
              repository: repo,
              child: RepaintBoundary(
                key: const Key('review-artifact'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: luvlyTheme,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                    child: child!,
                  ),
                  home: const Scaffold(
                    appBar: null,
                    body: SafeArea(child: LiveCatalogueScreen()),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final context = t.element(find.byType(LiveCatalogueScreen));
          for (final photo in repo.photos.values) {
            await precacheImage(MemoryImage(photo.imageBytes), context);
          }
        });
        await t.pumpAndSettle();
        final firstBadge = find.byKey(const ValueKey('ar-badge-demo-elegant'));
        if (firstBadge.evaluate().isEmpty) {
          await t.scrollUntilVisible(
            firstBadge,
            240,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(find.text('AR try-on'), findsNothing);
        expect(firstBadge, findsOneWidget);
        await t.ensureVisible(firstBadge);
        await t.pumpAndSettle();
        await capture(t, large ? 'collection-large' : 'collection');
        final francine = find.text('Francine Gown');
        if (francine.evaluate().isEmpty) {
          await t.scrollUntilVisible(
            francine,
            240,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await t.ensureVisible(francine);
        await t.tap(francine);
        await t.pumpAndSettle();
        expect(find.text('AR try-on'), findsOneWidget);
        expect(find.text('360° view'), findsOneWidget);
        expect(find.text('Model: Francine — reference study'), findsNothing);
        if (large) {
          await t.ensureVisible(find.text('About preview'));
          await t.pumpAndSettle();
        }
        await capture(t, large ? 'detail-large' : 'detail');
        expect(t.takeException(), isNull);
      },
    );
  }
}
