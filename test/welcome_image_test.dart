import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/account.dart';
import 'package:luvly_app/src/design.dart';

void main() {
  testWidgets('sharp welcome image fits the existing mobile arch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await (FontLoader('LuvlySans')
            ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
          .load();
      await (FontLoader(
        'LuvlySerif',
      )..addFont(rootBundle.load('assets/fonts/CormorantGaramond.ttf'))).load();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: luvlyTheme,
        home: const RepaintBoundary(
          key: Key('welcome'),
          child: WelcomeScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/bridal_welcome_hd.png'),
        tester.element(find.byType(WelcomeScreen)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const Key('welcome')),
      matchesGoldenFile('previews/welcome-hd.png'),
    );
  });
}
