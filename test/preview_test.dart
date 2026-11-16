import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/home.dart';
import 'package:luvly_app/src/dresses.dart';
import 'package:luvly_app/src/commerce.dart';
import 'package:luvly_app/src/support.dart';
import 'package:luvly_app/src/account.dart';

void main() {
  for (final scene in [
    'welcome',
    'home',
    'dresses',
    'packages',
    'francine',
    'princess',
    'payments',
    'support',
  ]) {
    testWidgets('render mobile preview $scene', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final sans = FontLoader('LuvlySans');
        for (final weight in ['regular', 'medium', 'bold']) {
          sans.addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/roboto-$weight.ttf').readAsBytesSync(),
              ),
            ),
          );
        }
        final serif = FontLoader('LuvlySerif')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/CormorantGaramond.ttf').readAsBytesSync(),
              ),
            ),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await sans.load();
        await serif.load();
        await icons.load();
      });
      final m = AppModel();
      m.bookings.first.date = DateTime(2026, 10, 14);
      m.payments
        ..clear()
        ..add(
          DemoPayment(
            1000,
            'Online banking',
            DateTime(2026, 10, 11),
            'LV-2026-001',
          ),
        );
      for (final entry in <String, Widget>{
        'welcome': const WelcomeScreen(),
        'home': const HomeShell(),
        'dresses': const PageFrame(
          title: 'Wedding dresses',
          child: CatalogueScreen(),
        ),
        'packages': const PackagesScreen(),
        'francine': DressDetailScreen(
          index: dresses.indexWhere((d) => d.id == 'francine-reference'),
        ),
        'princess': DressDetailScreen(
          index: dresses.indexWhere((d) => d.id == 'princess-wedding'),
        ),
        'payments': const PaymentsScreen(),
        'support': const PageFrame(title: 'Support', child: SupportScreen()),
      }.entries) {
        if (entry.key != scene) continue;
        await tester.pumpWidget(
          AppScope(
            model: m,
            child: RepaintBoundary(
              key: const Key('preview'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: luvlyTheme,
                home: entry.value,
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          for (final name in [
            'bridal_hero',
            'golden',
            'eden',
            'blush',
            'satin',
            'pearl',
            'ivory',
            'francine_reference',
            'princess_wedding',
          ]) {
            await precacheImage(AssetImage('assets/images/$name.jpg'), context);
          }
          await precacheImage(
            const AssetImage('assets/images/bridal_welcome_hd.png'),
            context,
          );
        });
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const Key('preview')),
          matchesGoldenFile('previews/${entry.key}.png'),
        );
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
