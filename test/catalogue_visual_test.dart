import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/admin/live_inventory.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/src/live_catalogue.dart';
import 'package:luvly_app/src/ar_preview.dart';
import 'package:luvly_app/catalogue/ar_models.dart';
import 'fake_catalogue.dart';

void main() {
  for (final scene in [
    'inventory-wide',
    'inventory-narrow',
    'bride',
    'editor',
    'editor-photo-wide',
    'editor-photo-narrow',
    'ar-library',
    'ar-guide',
  ]) {
    testWidgets('Catalogue layout $scene', (tester) async {
      tester.view.physicalSize = Size(
        scene.endsWith('wide') ? 1440 : 390,
        1000,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final entry in {
          'LuvlySans': 'assets/fonts/roboto-regular.ttf',
          'LuvlySerif': 'assets/fonts/CormorantGaramond.ttf',
          'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(rootBundle.load(entry.value));
          await loader.load();
        }
      });
      final repo = FakeCatalogue()..records['dress-1'] = sampleDress();
      final model = PortalModel.live(
        member: TeamMember(
          'uid',
          'CYJ',
          'manager@example.com',
          PortalRole.manager,
        ),
      );
      addTearDown(repo.changes.close);
      addTearDown(model.dispose);
      const capture = ValueKey('catalogue-capture');
      final Widget body = scene == 'ar-library'
          ? const ArDressLibraryScreen()
          : scene == 'ar-guide'
          ? ArTryOnGuideScreen(dress: resolveArDress('princess-wedding')!)
          : scene == 'bride'
          ? const LiveCatalogueScreen()
          : scene.startsWith('editor')
          ? DressEditor(repository: repo, actorUid: 'uid')
          : const LiveInventoryPage();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: CatalogueScope(
            repository: repo,
            child: PortalScope(
              model: model,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: scene == 'bride' || scene.startsWith('ar-')
                    ? luvlyTheme
                    : portalTheme,
                home: scene.startsWith('ar-')
                    ? body
                    : Scaffold(
                        appBar: AppBar(title: const Text('Luvly')),
                        body: body,
                      ),
              ),
            ),
          ),
        ),
      );
      if (scene.startsWith('ar-') || scene == 'bride') {
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          for (final dress in browseArDresses) {
            await precacheImage(
              AssetImage('assets/images/${dress.asset}.jpg'),
              context,
            );
          }
        });
      }
      await tester.pumpAndSettle();
      if (scene.startsWith('editor-photo')) {
        await tester.ensureVisible(find.text('Dress photo'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(capture),
        matchesGoldenFile(
          'catalogue_goldens/$scene${scene.startsWith('ar-')
              ? '-2081'
              : scene == 'bride'
              ? '-2082'
              : ''}.png',
        ),
      );
    });
  }
}
