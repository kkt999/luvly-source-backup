import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/accessory_draft_screen.dart';
import 'package_test.dart' show FakePackages;

void main() {
  for (final scene in ['editorial', 'collection', 'accessory', 'desktop']) {
    testWidgets('editorial visual $scene', (tester) async {
      tester.view.physicalSize = Size(scene == 'desktop' ? 1100 : 390, 1000);
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
      const key = ValueKey('editorial-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            home: scene == 'accessory'
                ? const AccessoryDraftScreen()
                : LivePackageScreen(api: FakePackages()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scene != 'accessory') {
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/images/bridal_welcome_hd.png'),
            tester.element(find.byType(LivePackageScreen)),
          );
        });
        await tester.pumpAndSettle();
      }
      if (scene == 'collection') {
        await tester.scrollUntilVisible(
          find.text('Explore package'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('previews/redesign-$scene.png'),
      );
    });
  }
}
