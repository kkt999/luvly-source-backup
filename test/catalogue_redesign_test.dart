import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/ar_models.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/live_catalogue.dart';
import 'fake_catalogue.dart';

void main() {
  for (final scene in ['single', 'multiple', 'large-text']) {
    testWidgets('Catalogue 2082 $scene natural layout and actions', (
      tester,
    ) async {
      final large = scene == 'large-text';
      tester.view.physicalSize = Size(large ? 320 : 390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeCatalogue();
      addTearDown(repo.changes.close);
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
        // Bundled image is used only by this in-memory visual fixture.
        final bytes = await rootBundle.load(
          'assets/images/princess_wedding.jpg',
        );
        for (var i = 0; i < (scene == 'single' ? 1 : 2); i++) {
          final id = 'gown-$i';
          repo.records[id] = CatalogueDress.fromFields(id, {
            ...sampleDress(
              name: i == 0 ? 'Ivory Romance' : 'Pearl Lace',
            ).toFields(),
            'photoRevision': 1,
            'revision': 1,
          });
          repo.photos[id] = compressDressPhoto(bytes.buffer.asUint8List());
        }
      });
      await tester.pumpWidget(
        CatalogueScope(
          repository: repo,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Wedding dresses')),
              body: const RepaintBoundary(
                key: ValueKey('capture'),
                child: ColoredBox(color: ivory, child: LiveCatalogueScreen()),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(LiveCatalogueScreen));
        for (final dress in browseArDresses) {
          await precacheImage(
            AssetImage('assets/images/${dress.asset}.jpg'),
            context,
          );
        }
        for (final photo in repo.photos.values) {
          await precacheImage(MemoryImage(photo.imageBytes), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('catalogue_goldens/2082-$scene.png'),
      );

      // Scroll every intermediate viewport, including large-font product cards.
      for (var step = 0; step < (large ? 24 : 8); step++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      final princessViewer = find.descendant(
        of: find.byKey(const ValueKey('ar-reference-princess-wedding')),
        matching: find.text('360° view'),
      );
      await tester.scrollUntilVisible(
        princessViewer,
        -180,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile('catalogue_goldens/2082-$scene-studio.png'),
      );
      MethodCall? received;
      const channel = MethodChannel('luvly/ar');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        received = call;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.tap(princessViewer);
      await tester.pump();
      expect(received?.method, 'openGownViewer');
      expect(received?.arguments['dressId'], 'princess-wedding');
      expect(repo.saves, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
