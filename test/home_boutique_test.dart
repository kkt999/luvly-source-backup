import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/design.dart';
import 'package:luvly_app/src/home.dart';
import 'package:luvly_app/src/home_boutique.dart';
import 'package:luvly_app/src/model.dart';
import 'checkout_redesign_test.dart' show viewport, fonts;
import 'planning_fixture.dart';
import 'promotions_test.dart' show threeOffers, warmCampaignImages;

Future<void> render(WidgetTester t, Widget child, {double scale = 1}) async {
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: luvlyTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );
  await t.pumpAndSettle();
}

HomeBoutiqueSections sections(void Function(String) tap) =>
    HomeBoutiqueSections(
      onCollection: () => tap('collection'),
      onPackages: () => tap('packages'),
      onBookings: () => tap('appointments'),
      onPayments: () => tap('payments'),
      onShortlist: () => tap('shortlist'),
      onTryOn: () => tap('try-on'),
      onSupport: () => tap('support'),
    );

Future<void> warmStory(WidgetTester t) async {
  final context = t.element(find.byType(MaterialApp));
  await t.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/bridal_welcome_hd.png'),
      context,
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('all seven Home editorial actions retain their destinations', (
    t,
  ) async {
    viewport(t, const Size(390, 844));
    final calls = <String>[];
    await render(
      t,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: sections(calls.add),
        ),
      ),
    );
    for (final key in [
      'collection',
      'packages',
      'appointments',
      'payments',
      'shortlist',
      'try-on',
      'support',
    ]) {
      final target = find.byKey(ValueKey('home-$key'));
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      await t.tap(target);
      await t.pumpAndSettle();
      expect(calls.last, key);
    }
    expect(calls.length, 7);
    expect(t.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Home editorial sections fit $width at text scale $scale', (
        t,
      ) async {
        viewport(t, Size(width, 844));
        await render(
          t,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: sections((_) {}),
            ),
          ),
          scale: scale,
        );
        await warmStory(t);
        expect(t.takeException(), isNull);
        for (final key in [
          'collection',
          'packages',
          'appointments',
          'payments',
          'shortlist',
          'try-on',
          'support',
        ]) {
          await t.ensureVisible(find.byKey(ValueKey('home-$key')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: key);
        }
      });
    }
  }

  testWidgets(
    'live Home preserves plan-first hierarchy and live tab navigation',
    (t) async {
      viewport(t, const Size(390, 844));
      final model = AppModel.live()
        ..accountId = 'bride'
        ..name = 'Amelia';
      addTearDown(model.dispose);
      final tabs = <int>[];
      await render(
        t,
        AppScope(
          model: model,
          child: Scaffold(
            body: HomeScreen(
              onTab: tabs.add,
              promotionApi: threeOffers(),
              planningApi: FakePlanningApi(),
            ),
          ),
        ),
      );
      expect(find.text('YOUR BRIDAL PLAN'), findsOneWidget);
      expect(find.text('Settle your package balance'), findsOneWidget);
      expect(find.text('Quick Access'), findsNothing);
      expect(find.byType(DemoNote), findsNothing);
      await t.scrollUntilVisible(
        find.byKey(const Key('home-collection')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      for (final pair in [
        ('collection', 1),
        ('appointments', 2),
        ('support', 3),
      ]) {
        final target = find.byKey(ValueKey('home-${pair.$1}'));
        await t.ensureVisible(target);
        await t.pumpAndSettle();
        await t.tap(target);
        await t.pumpAndSettle();
        expect(tabs.last, pair.$2);
      }
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'redesigned Home visual: planning, offers, collection and essentials',
    (t) async {
      viewport(t, const Size(390, 844));
      await fonts();
      final model = AppModel.live()
        ..accountId = 'bride'
        ..name = 'Amelia';
      addTearDown(model.dispose);
      await render(
        t,
        AppScope(
          model: model,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(
                'Luvly',
                style: TextStyle(
                  fontFamily: 'LuvlySerif',
                  fontStyle: FontStyle.italic,
                  fontSize: 26,
                  color: rose,
                ),
              ),
            ),
            body: HomeScreen(
              onTab: (_) {},
              promotionApi: threeOffers(),
              planningApi: FakePlanningApi(),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.checkroom_outlined),
                  label: 'Dresses',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  label: 'Bookings',
                ),
                NavigationDestination(
                  icon: Icon(Icons.support_agent),
                  label: 'Support',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      );
      await warmCampaignImages(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/home-editorial-top.png'),
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('home-collection')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await warmStory(t);
      await t.ensureVisible(find.byKey(const Key('home-collection-cover')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/home-editorial-discover.png'),
      );
      await t.ensureVisible(find.byKey(const Key('home-support')));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/home-editorial-services.png'),
      );
      expect(t.takeException(), isNull);
    },
  );
}
