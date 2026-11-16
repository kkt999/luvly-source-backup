import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/packages/accessory_catalogue.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;

void main() {
  for (final width in [320.0, 390.0, 1000.0]) {
    testWidgets('product details scroll with a reachable action at $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalogue = (await tester.runAsync(AccessoryCatalogue.load))!;
      final item = catalogue.items.firstWhere((i) => i.id == 'ring-halo');
      await tester.runAsync(() async {
        for (final font in {'LuvlySans':'assets/fonts/roboto-regular.ttf',
          'LuvlySerif':'assets/fonts/CormorantGaramond.ttf',
          'MaterialIcons':'fonts/MaterialIcons-Regular.otf'}.entries) {
          await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
        }
      });
      const key = ValueKey('details-preview');
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
        debugShowCheckedModeBanner: false, theme: luvlyTheme,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(width == 320 ? 1.4 : 1)), child: child!),
        home: AccessoryDetailsScreen(item: item, isSelected: false,
          allowanceCents: 7000, resultingExtraCents: 0, changeCents: 0),
      )));
      await tester.runAsync(() => precacheImage(AssetImage(item.image), tester.element(find.byType(AccessoryDetailsScreen))));
      await tester.pumpAndSettle();
      expect(find.text('Add to selection').hitTestable(), findsOneWidget);
      expect(find.text('No change to your package total'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(find.byKey(key), matchesGoldenFile('previews/accessory-details-${width.toInt()}.png'));
      await tester.scrollUntilVisible(find.text('About this style'), 180,
        scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('About this style'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AI-generated illustrations'), findsOneWidget);
      expect(find.text('Add to selection').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unconfigured stock blocks adding but permits removing an old selection', (tester) async {
    final catalogue = (await tester.runAsync(AccessoryCatalogue.load))!;
    final item = catalogue.items.first;
    for (final selected in [false, true]) {
      await tester.pumpWidget(MaterialApp(home: AccessoryDetailsScreen(
        item: item, isSelected: selected, allowanceCents: 7000,
        resultingExtraCents: 0, changeCents: 0, unavailableReason: 'Not available to book yet')));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null, selected);
    }
  });
}
