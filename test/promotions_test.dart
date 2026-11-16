import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/promotions/promotion_api.dart';
import 'package:luvly_app/promotions/promotion_screen.dart';
import 'package:luvly_app/promotions/promotion_admin.dart';
import 'package:luvly_app/promotions/campaign_visuals.dart';
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/src/model.dart';
import 'package:luvly_app/src/home.dart';
import 'checkout_redesign_test.dart' show viewport, fonts;
import 'planning_fixture.dart';

Map<String, dynamic> offer({String id = 'welcome', bool active = true}) => {
  'id': id,
  'revision': 1,
  'kind': 'Offer',
  'title': 'A welcome for your wedding',
  'description':
      'Enjoy RM50 off your bridal package. A thoughtful start to your day.',
  'code': 'WELCOME50',
  'discountType': 'Fixed',
  'value': 5000,
  'maxDiscountCents': 0,
  'minimumCents': 89900,
  'packageId': 'bridal',
  'packageName': 'Bridal Essentials',
  // Stable, deliberately synthetic fixture dates keep screenshots independent
  // of the machine's current calendar day. No production campaigns use this.
  'startDate': '2020-01-01',
  'endDate': '2099-11-17',
  'active': active,
  'banner': true,
};

class FakePromotions implements PromotionApi {
  List<Campaign> rows = [Campaign(offer())];
  final saved = <Map<String, dynamic>>[], applied = <List<dynamic>>[];
  int removed = 0;
  int listCalls = 0;
  bool fail = false;
  Completer<void>? pending;
  Completer<List<Campaign>>? pendingList;
  @override
  Future<List<Campaign>> list() async {
    listCalls++;
    if (pendingList != null) return pendingList!.future;
    if (fail) throw const PaymentFailure('Connection unavailable.');
    return rows;
  }

  @override
  Future<void> save(Map<String, dynamic> d) async {
    saved.add(d);
    if (fail) throw const PaymentFailure('Refresh before saving.');
  }

  @override
  Future<void> remove(Campaign p) async {
    removed++;
    rows = [];
  }

  @override
  Future<void> apply(String id, String code, int revision) async {
    applied.add([id, code, revision]);
    if (pending != null) await pending!.future;
    if (fail) throw const PaymentFailure('Code is not eligible.');
  }

  @override
  void close() {}
}

Future<void> render(WidgetTester t, Widget child, {double scale = 1}) async {
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: luvlyTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: child,
    ),
  );
  await t.pumpAndSettle();
}

Finder label(String v) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == v,
);

Future<void> warmCampaignImages(WidgetTester t) async {
  final context = t.element(find.byType(MaterialApp));
  await t.runAsync(() async {
    for (final asset in ['essentials', 'signature', 'luxe']) {
      await precacheImage(
        AssetImage('assets/images/promo_${asset}_v1.png'),
        context,
      );
    }
  });
  await t.pumpAndSettle();
}

FakePromotions threeOffers() => FakePromotions()
  ..rows = [
    Campaign({
      ...offer(id: 'essentials'),
      'packageId': 'bridal-essentials',
      'packageName': 'Bridal Essentials',
    }),
    Campaign({
      ...offer(id: 'signature'),
      'packageId': 'signature-bridal',
      'packageName': 'Signature Bridal',
      'title': 'Your Signature Moment',
      'value': 10000,
      'code': 'SIGNATURE100',
      'minimumCents': 179900,
    }),
    Campaign({
      ...offer(id: 'luxe'),
      'packageId': 'luxe-bridal',
      'packageName': 'Luxe Bridal',
      'title': 'A Little More Luxury',
      'value': 15000,
      'code': 'LUXE150',
      'minimumCents': 299900,
    }),
  ];

void main() {
  test(
    'money uses integer cents and rejects negative, exponent or excess precision',
    () {
      expect(promotionCents('50.01'), 5001);
      for (final v in ['-1', 'NaN', '1e3', '1.001']) {
        expect(promotionCents(v), null);
      }
    },
  );
  test(
    'transport sends code and revision only, never a client calculated discount',
    () async {
      final calls = <http.Request>[];
      final transport = HttpPaymentApi(
        baseUrl: 'https://test.trycloudflare.com',
        token: () async => 'test-token',
        client: MockClient((r) async {
          calls.add(r);
          return http.Response(
            jsonEncode({
              'campaigns': [offer()],
            }),
            200,
          );
        }),
      );
      final api = HttpPromotionApi(transport: transport);
      addTearDown(api.close);
      expect((await api.list()).single.code, 'WELCOME50');
      await api.apply('a' * 32, 'WELCOME50', 2);
      expect(calls.last.headers['authorization'], 'Bearer test-token');
      expect(jsonDecode(calls.last.body), {'code': 'WELCOME50', 'revision': 2});
    },
  );
  testWidgets(
    'offers search and filter are real; error is not an empty catalogue',
    (t) async {
      final api = FakePromotions();
      api.rows.add(
        Campaign({
          ...offer(id: 'news'),
          'kind': 'Announcement',
          'title': 'Your boutique visit',
          'code': '',
        }),
      );
      await render(t, OffersScreen(api: api));
      expect(find.text('A welcome for your wedding'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'not a code');
      await t.pumpAndSettle();
      expect(find.textContaining('No matching offers'), findsOneWidget);
      await t.enterText(find.byType(TextField), '');
      await t.tap(find.text('Offers'));
      await t.pumpAndSettle();
      expect(find.text('Your boutique visit'), findsNothing);
      api.fail = true;
      await t.tap(find.byTooltip('Refresh offers'));
      await t.pumpAndSettle();
      expect(find.text('Connection unavailable.'), findsOneWidget);
      expect(find.textContaining('No matching offers'), findsNothing);
    },
  );
  testWidgets(
    'coupon application waits for server and preserves amount on rejection',
    (t) async {
      final api = FakePromotions()..fail = true;
      int reloads = 0;
      final s = PackageSelection({
        'id': 'selection',
        'totalCents': 89900,
        'selectedGowns': [
          {'name': 'Gown'},
        ],
      });
      await render(
        t,
        Scaffold(
          body: PackagePromotion(
            selection: s,
            api: api,
            reload: () => reloads++,
          ),
        ),
      );
      await t.tap(find.text('Add promo code'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'welcome50');
      await t.tap(find.text('Apply code'));
      await t.pumpAndSettle();
      expect(api.applied.single, ['selection', 'WELCOME50', 0]);
      expect(reloads, 0);
      expect(s.totalCents, 89900);
      expect(find.text('Code is not eligible.'), findsOneWidget);
    },
  );
  testWidgets('existing invoices have discount breakdown but no code editing', (
    t,
  ) async {
    await render(
      t,
      Scaffold(
        body: PackagePromotion(
          selection: PackageSelection({
            'id': 'selection',
            'invoiceId': 'old',
            'totalCents': 84900,
            'promotion': {
              'code': 'WELCOME50',
              'subtotalCents': 89900,
              'discountCents': 5000,
            },
            'selectedGowns': [{}],
          }),
          api: FakePromotions(),
          reload: () {},
        ),
      ),
    );
    expect(find.text('Change promo code'), findsNothing);
    expect(find.text('Package subtotal  RM 899.00'), findsOneWidget);
    expect(find.text('WELCOME50  −RM 50.00'), findsOneWidget);
  });
  testWidgets(
    'staff campaign list is read-only and manager delete requires confirmation',
    (t) async {
      final api = FakePromotions();
      await render(t, PromotionManagementScreen(api: api));
      expect(find.text('Create campaign'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      await render(
        t,
        PromotionManagementScreen(
          key: const ValueKey('manager'),
          api: api,
          canManage: true,
        ),
      );
      await t.ensureVisible(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(api.removed, 0);
      await t.tap(find.text('Keep campaign'));
      await t.pumpAndSettle();
      expect(api.removed, 0);
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete campaign'));
      await t.pumpAndSettle();
      expect(api.removed, 1);
    },
  );
  testWidgets(
    'campaign editor validates fields and saves a draft with stable identity on retry',
    (t) async {
      viewport(t, const Size(800, 2200));
      final api = FakePromotions()..fail = true;
      await render(t, CampaignEditor(api: api, packages: const []));
      final save = find.text('Save inactive campaign');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      for (final v in {
        'Title': 'A welcome for your wedding',
        'Description': 'Enjoy RM50 off an eligible gown package.',
        'Unique promo code': 'WELCOME50',
      }.entries) {
        await t.ensureVisible(label(v.key));
        await t.pumpAndSettle();
        await t.enterText(label(v.key), v.value);
      }
      await t.ensureVisible(save);
      await t.pumpAndSettle();
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.saved.length, 1);
      expect(api.saved.single['active'], false);
      expect(api.saved.single['value'], 5000);
      expect(api.saved.single['minimumCents'], 89900);
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.saved.length, 2);
      expect(api.saved[0]['id'], api.saved[1]['id']);
      expect(find.text('Refresh before saving.'), findsOneWidget);
    },
  );
  testWidgets(
    'manager can create a welcome voucher with the correct defaults',
    (t) async {
      viewport(t, const Size(800, 2200));
      final api = FakePromotions();
      await render(t, CampaignEditor(api: api, packages: const []));
      final restriction = find.widgetWithText(
        SwitchListTile,
        'New customers only',
      );
      await t.ensureVisible(restriction);
      await t.tap(restriction);
      await t.pumpAndSettle();
      final save = find.text('Save inactive campaign');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      final saved = api.saved.single;
      expect(saved['newCustomerOnly'], true);
      expect(saved['code'], 'WELCOME50');
      expect(saved['value'], 5000);
      expect(saved['minimumCents'], 89900);
      expect(
        Campaign(saved).terms,
        contains('first 30 days after registration'),
      );
      expect(Campaign(offer()).terms, isNot(contains('first 30 days')));
    },
  );
  for (final scale in [1.0, 1.5]) {
    testWidgets('offers and banner visual at $scale', (t) async {
      viewport(t, const Size(390, 844));
      await fonts();
      await render(t, OffersScreen(api: FakePromotions()), scale: scale);
      await warmCampaignImages(t);
      expect(t.takeException(), null);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/offers-$scale.png'),
      );
      await render(
        t,
        Scaffold(
          appBar: AppBar(title: const Text('Luvly')),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: HomeOfferBanner(api: threeOffers()),
          ),
        ),
        scale: scale,
      );
      await warmCampaignImages(t);
      expect(t.takeException(), null);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/offer-banner-$scale.png'),
      );
    });
  }
  testWidgets(
    'three offers occupy one carousel; next and swipe preserve exact offer navigation',
    (t) async {
      viewport(t, const Size(390, 844));
      await render(
        t,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: HomeOfferBanner(api: threeOffers()),
          ),
        ),
      );
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      await t.tap(find.byTooltip('Next offer'));
      await t.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
      await t.drag(
        find.byKey(const Key('home-offer-carousel')),
        const Offset(-320, 0),
      );
      await t.pumpAndSettle();
      expect(find.text('3/3'), findsOneWidget);
      await t.tap(find.byType(CampaignCreative).last);
      await t.pumpAndSettle();
      expect(find.byType(OffersScreen), findsOneWidget);
      expect(find.text('LUXE150'), findsOneWidget);
      expect(find.text('SIGNATURE100'), findsNothing);
      expect(find.text(campaignImageDisclosure), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('home offers distinguish loading, failure and recovery', (
    t,
  ) async {
    viewport(t, const Size(390, 844));
    final api = FakePromotions()..pendingList = Completer<List<Campaign>>();
    await t.pumpWidget(
      MaterialApp(
        theme: luvlyTheme,
        home: Scaffold(body: HomeOfferBanner(api: api)),
      ),
    );
    await t.pump();
    expect(find.byKey(const Key('home-offers-loading')), findsOneWidget);
    expect(find.byType(CampaignCreative), findsNothing);
    api.pendingList!.completeError(const PaymentFailure('Unavailable'));
    await t.pumpAndSettle();
    expect(find.text('We couldn’t load your offers.'), findsOneWidget);
    expect(find.text('New offers are on their way.'), findsNothing);
    api.pendingList = null;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(api.listCalls, 2);
    expect(find.byType(CampaignCreative), findsOneWidget);
    expect(find.text('RM50'), findsOneWidget);
    expect(find.text('We couldn’t load your offers.'), findsNothing);
  });
  testWidgets('returning to Home and resuming retry offers without polling', (
    t,
  ) async {
    viewport(t, const Size(390, 844));
    final api = FakePromotions()..fail = true;
    var active = true;
    late StateSetter rebuild;
    await render(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Scaffold(
            body: HomeOfferBanner(api: api, active: active),
          );
        },
      ),
    );
    expect(api.listCalls, 1);
    rebuild(() => active = false);
    await t.pumpAndSettle();
    api.fail = false;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(api.listCalls, 1); // Hidden tabs do not fetch on resume.
    rebuild(() => active = true);
    await t.pumpAndSettle();
    expect(api.listCalls, 2);
    expect(find.byType(CampaignCreative), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(api.listCalls, 3);
    await t.pump(const Duration(minutes: 2));
    expect(api.listCalls, 3);
  });
  testWidgets(
    'See all opens the full feed, not just the three featured cards',
    (t) async {
      viewport(t, const Size(390, 844));
      final api = threeOffers()
        ..rows.add(
          Campaign({
            ...offer(id: 'fourth'),
            'code': 'FOURTH50',
            'banner': false,
          }),
        );
      await render(t, Scaffold(body: HomeOfferBanner(api: api)));
      expect(find.text('1/3'), findsOneWidget);
      await t.tap(find.text('See all'));
      await t.pumpAndSettle();
      final screen = t.widget<OffersScreen>(find.byType(OffersScreen));
      expect(screen.initialCampaignId, isNull);
      await t.enterText(find.byType(TextField), 'FOURTH50');
      await t.pumpAndSettle();
      expect(find.byType(CampaignCard), findsOneWidget);
      expect(
        t.widget<CampaignCard>(find.byType(CampaignCard)).campaign.id,
        'fourth',
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(api.listCalls, 3); // Initial Home, full feed, revalidated Home.
    },
  );
  testWidgets(
    'Home does not advertise expired, scheduled or disabled campaigns',
    (t) async {
      final api = FakePromotions()
        ..rows = [
          Campaign(offer(active: false)),
          Campaign({...offer(id: 'expired'), 'endDate': '2020-01-01'}),
          Campaign({
            ...offer(id: 'scheduled'),
            'startDate': '2099-01-01',
            'endDate': '2099-02-01',
          }),
        ];
      await render(t, Scaffold(body: HomeOfferBanner(api: api)));
      expect(find.byType(CampaignCreative), findsNothing);
      expect(find.text('New offers are on their way.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('See all'), findsOneWidget);
    },
  );
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('320px campaign creatives fit all tiers at text scale $scale', (
      t,
    ) async {
      viewport(t, const Size(320, 1000));
      for (final p in threeOffers().rows) {
        await render(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: CampaignCreative(campaign: p),
              ),
            ),
          ),
          scale: scale,
        );
        await warmCampaignImages(t);
        expect(t.takeException(), isNull, reason: p.packageId);
      }
      await render(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: HomeOfferBanner(api: threeOffers()),
            ),
          ),
        ),
        scale: scale,
      );
      await warmCampaignImages(t);
      await t.ensureVisible(find.byTooltip('Next offer'));
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byTooltip('Next offer'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    });
  }
  testWidgets('photo-led offers in the actual customer home composition', (
    t,
  ) async {
    viewport(t, const Size(390, 844));
    await fonts();
    final model = AppModel.live()
      ..accountId = 'preview-only'
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
                color: Color(0xFFA65360),
              ),
            ),
            actions: const [
              IconButton(onPressed: null, icon: Icon(Icons.notifications_none)),
            ],
          ),
          body: HomeScreen(
            onTab: (_) {},
            promotionApi: threeOffers(),
            planningApi: FakePlanningApi(body: planningFixture(empty: true)),
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
    expect(find.byKey(const Key('home-plan-summary')), findsNothing);
    expect(t.takeException(), isNull);
    for (final tier in ['essentials', 'signature', 'luxe']) {
      await t.ensureVisible(find.byTooltip('Next offer'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/home-promotion-$tier.png'),
      );
      await t.tap(find.byTooltip('Next offer'));
      await t.pumpAndSettle();
    }
  });
  testWidgets('campaign management desktop visual', (t) async {
    viewport(t, const Size(1280, 900));
    await fonts();
    await render(
      t,
      PromotionManagementScreen(api: FakePromotions(), canManage: true),
    );
    expect(t.takeException(), null);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/campaign-management.png'),
    );
  });
}
