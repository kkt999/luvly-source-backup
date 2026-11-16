import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/planning/planning_api.dart';
import 'package:luvly_app/planning/planning_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/src/home.dart';
import 'package:luvly_app/src/model.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'planning_fixture.dart';
import 'promotions_test.dart' show threeOffers, warmCampaignImages;

Future<void> render(
  WidgetTester t,
  FakePlanningApi api, {
  bool compact = false,
  bool active = true,
  double scale = 1,
  String uid = 'bride',
  Future<void> Function(PlanningAction)? onAction,
  RouteObserver<PageRoute<dynamic>>? observer,
}) async {
  await t.pumpWidget(
    PlanningNavigationScope(
      observer: observer ?? RouteObserver<PageRoute<dynamic>>(),
      child: MaterialApp(
        theme: luvlyTheme,
        debugShowCheckedModeBanner: false,
        navigatorObservers: observer == null ? [] : [observer],
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('My bridal journey')),
          body: compact
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: CustomerPlanningView(
                    uid: uid,
                    api: api,
                    compact: true,
                    active: active,
                    onAction: onAction,
                  ),
                )
              : CustomerPlanningView(
                  uid: uid,
                  api: api,
                  active: active,
                  onAction: onAction,
                ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  test(
    'planning transport is authenticated read-only and never accepts a queried customer UID',
    () async {
      final requests = <http.Request>[];
      final api = HttpPlanningApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.test',
          token: () async => 'test-token',
          client: MockClient((r) async {
            requests.add(r);
            return http.Response(
              jsonEncode(planningFixture()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      final result = await api.load('bride');
      expect(result.plans.single.name, 'Bridal Essentials');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/v1/my-planning');
      expect(requests.single.url.hasQuery, isFalse);
      expect(requests.single.headers['Authorization'], 'Bearer test-token');
      expect(
        () => PlanningSnapshot(planningFixture(uid: 'other'), uid: 'bride'),
        throwsA(isA<PaymentFailure>()),
      );
      expect(
        () =>
            PlanningSnapshot(planningFixture()..remove('plans'), uid: 'bride'),
        throwsA(isA<PaymentFailure>()),
      );
      expect(
        () => PlanningSnapshot(
          planningFixture()..['environment'] = 'production',
          uid: 'bride',
        ),
        throwsA(isA<PaymentFailure>()),
      );
    },
  );
  test(
    'unknown statuses do not become completed; missing dates are not invented',
    () {
      expect(planningDone('Confirmed'), isFalse);
      expect(planningDone('Held'), isFalse);
      expect(planningDone('unknown'), isFalse);
      expect(planningDone('Reserved'), isTrue);
      expect(planningDay(null), 'Not set');
      expect(planningDay('2026-10-21'), '21 Oct 2026');
      expect(
        planningTime(DateTime.utc(2026, 10, 15, 16).millisecondsSinceEpoch),
        contains('16 Oct 2026 · 00:00 MYT'),
      );
    },
  );
  testWidgets('empty Home planning view leaves room for discovery', (t) async {
    viewport(t, const Size(390, 844));
    await render(
      t,
      FakePlanningApi(body: planningFixture(empty: true)),
      compact: true,
    );
    expect(find.byKey(const Key('home-plan-summary')), findsNothing);
    expect(find.textContaining('50%'), findsNothing);
    expect(find.text('Bridal Essentials'), findsNothing);
    expect(find.textContaining('5 days'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'failed refresh hides prior data and retries without pretending the account is empty',
    (t) async {
      viewport(t, const Size(390, 1000));
      final api = FakePlanningApi();
      await render(t, api, compact: true);
      expect(find.textContaining('5 days'), findsOneWidget);
      api.fail = true;
      await t.tap(find.byTooltip('Refresh my bridal plan'));
      await t.pumpAndSettle();
      expect(find.text('Your plan is temporarily unavailable'), findsOneWidget);
      expect(find.textContaining('5 days'), findsNothing);
      expect(find.text('Explore packages'), findsNothing);
      api.fail = false;
      await t.tap(find.text('Reload my plan'));
      await t.pumpAndSettle();
      expect(api.calls, 3);
      expect(find.textContaining('5 days'), findsOneWidget);
    },
  );
  testWidgets(
    'next step opens the exact invoice intentionally, never an automatic checkout',
    (t) async {
      viewport(t, const Size(390, 1000));
      final api = FakePlanningApi(), actions = <PlanningAction>[];
      await render(
        t,
        api,
        compact: true,
        onAction: (a) async {
          actions.add(a);
        },
      );
      await t.tap(find.text('Settle your package balance'));
      await t.pumpAndSettle();
      expect(actions.single.type, 'payments');
      expect(actions.single.targetId, 'balance-invoice');
      expect(api.calls, 2);
    },
  );
  testWidgets(
    'Home shows a confirmed fitting once and opens the existing appointment action',
    (t) async {
      viewport(t, const Size(320, 900));
      final body = planningFixture();
      final visit = body['nextAppointment'] as Map<String, dynamic>;
      visit['type'] = 'Dress Trial';
      final plan = (body['plans'] as List).single as Map<String, dynamic>;
      plan['nextAction'] = {
        'type': 'appointments',
        'title': 'Your next fitting is booked',
        'detail': 'Review your appointment time and prepare for your visit.',
        'targetId': null,
      };
      final actions = <PlanningAction>[];
      await render(
        t,
        FakePlanningApi(body: body),
        compact: true,
        scale: 2,
        onAction: (action) async => actions.add(action),
      );
      expect(find.text('Rental reserved'), findsOneWidget);
      expect(find.text('5 days to your event'), findsOneWidget);
      expect(
        find.textContaining(planningTime(visit['startAt'] as int)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-next-visit')), findsNothing);
      final open = find.text('View fitting appointment');
      await reveal(t, open);
      await t.tap(open);
      await t.pumpAndSettle();
      expect(actions.single.type, 'appointments');
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'plan picker searches and preserves each event date and state separately',
    (t) async {
      viewport(t, const Size(390, 1000));
      final body = planningFixture();
      final second =
          jsonDecode(jsonEncode(body['plans'][0])) as Map<String, dynamic>;
      second.addAll({
        'id': 'second-plan',
        'name': 'Signature Bridal',
        'eventDate': '2026-11-03',
        'pickupDate': '2026-11-02',
        'returnDate': '2026-11-04',
        'daysToEvent': 18,
        'rentalState': 'NotReserved',
        'nextVisit': null,
      });
      body['plans'] = [...body['plans'], second];
      final api = FakePlanningApi(body: body);
      await render(t, api, compact: true);
      await t.tap(find.text('Switch plan (2)'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Search packages or event date'),
        'Signature',
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('plan-choice-second-plan')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('plan-choice-0123456789abcdef0123456789abcdef'),
        ),
        findsNothing,
      );
      await t.tap(find.byKey(const ValueKey('plan-choice-second-plan')));
      await t.pumpAndSettle();
      expect(find.textContaining('18 days'), findsOneWidget);
      expect(find.textContaining('3 Nov 2026'), findsOneWidget);
      expect(
        find.textContaining('21 Oct 2026 · Bridal Essentials'),
        findsNothing,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'detailed journey is read-only, separates refundable security and does not duplicate next visit',
    (t) async {
      viewport(t, const Size(390, 1200));
      await render(t, FakePlanningApi());
      expect(find.text('Your rental at a glance'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      await reveal(t, find.text('Your payment overview'));
      expect(find.text('Your payment overview'), findsOneWidget);
      expect(
        find.textContaining('Refundable security is separate'),
        findsOneWidget,
      );
      expect(find.text('Bridal Consultation'), findsOneWidget);
      expect(find.textContaining('50% complete'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('returning to Home tab reloads current backend data', (t) async {
    viewport(t, const Size(390, 1000));
    final api = FakePlanningApi();
    await render(t, api, compact: true, active: false);
    expect(api.calls, 1);
    api.body['plans'][0]['daysToEvent'] = 4;
    await render(t, api, compact: true, active: true);
    expect(api.calls, 2);
    expect(find.textContaining('4 days'), findsOneWidget);
  });
  testWidgets('return from journey refreshes the visible Home snapshot', (
    t,
  ) async {
    viewport(t, const Size(390, 1000));
    final api = FakePlanningApi();
    final observer = RouteObserver<PageRoute<dynamic>>();
    await render(t, api, compact: true, observer: observer);
    await t.tap(find.text('View journey'));
    await t.pumpAndSettle();
    expect(api.calls, 2);
    api.body['plans'][0]['daysToEvent'] = 4;
    await t.pageBack();
    await t.pumpAndSettle();
    expect(api.calls, 3);
    expect(find.textContaining('4 days'), findsOneWidget);
    expect(api.closed, isFalse);
  });
  testWidgets(
    'review and completed rentals do not retain a misleading Reserved hero badge',
    (t) async {
      viewport(t, const Size(390, 1000));
      final api = FakePlanningApi();
      api.body['plans'][0]['needsReview'] = true;
      await render(t, api, compact: true);
      expect(find.text('Team review needed'), findsOneWidget);
      expect(find.text('Reserved'), findsNothing);
      api.body['plans'][0]['needsReview'] = false;
      api.body['plans'][0]['completed'] = true;
      await t.tap(find.byTooltip('Refresh my bridal plan'));
      await t.pumpAndSettle();
      expect(find.text('Returned'), findsOneWidget);
      expect(find.text('Reserved'), findsNothing);
    },
  );
  testWidgets(
    'a hold expiration triggers one refresh, not continuous polling',
    (t) async {
      viewport(t, const Size(390, 1000));
      final body = planningFixture();
      body['plans'][0]['deposit']['expiresAt'] = body['generatedAt'] + 1000;
      final api = FakePlanningApi(body: body);
      await render(t, api, compact: true);
      api.body['generatedAt'] += 2000;
      api.body['plans'][0]['deposit']['expiresAt'] = null;
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(api.calls, 2);
      await t.pump(const Duration(minutes: 2));
      expect(api.calls, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'late response from a prior account cannot replace the new customer plan',
    (t) async {
      viewport(t, const Size(390, 1000));
      final first = Completer<PlanningSnapshot>(), api = FakePlanningApi();
      api.onLoad = (uid) async {
        if (uid == 'first') return first.future;
        final d = planningFixture(uid: uid);
        d['plans'][0]['name'] = 'New customer plan';
        return PlanningSnapshot(d, uid: uid);
      };
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: Scaffold(
            body: CustomerPlanningView(uid: 'first', api: api, compact: true),
          ),
        ),
      );
      await t.pump();
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: Scaffold(
            body: CustomerPlanningView(uid: 'second', api: api, compact: true),
          ),
        ),
      );
      await t.pumpAndSettle();
      final old = planningFixture(uid: 'first');
      old['plans'][0]['name'] = 'Old customer plan';
      first.complete(PlanningSnapshot(old, uid: 'first'));
      await t.pumpAndSettle();
      expect(find.textContaining('New customer plan'), findsOneWidget);
      expect(find.textContaining('Old customer plan'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 480.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('bridal planning layout $width text $scale', (t) async {
        viewport(t, Size(width, 1000));
        await fonts();
        final api = FakePlanningApi();
        await render(t, api, compact: true, scale: scale);
        expect(t.takeException(), isNull);
        if (width == 390 && scale == 1) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('previews/planning-home-summary.png'),
          );
        }
        await render(t, api, scale: scale);
        if (width == 390 && scale == 1) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('previews/planning-journey.png'),
          );
        }
        await reveal(t, find.text('Other recorded visits'));
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'actual Home puts personal planning before offers without the old generic Bridal Prep card',
    (t) async {
      viewport(t, const Size(390, 844));
      await fonts();
      final model = AppModel.live()
        ..accountId = 'bride'
        ..name = 'Amelia';
      addTearDown(model.dispose);
      await t.pumpWidget(
        AppScope(
          model: model,
          child: MaterialApp(
            theme: luvlyTheme,
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Luvly',
                  style: TextStyle(
                    fontFamily: 'LuvlySerif',
                    fontStyle: FontStyle.italic,
                    color: Color(0xFFA65360),
                    fontSize: 26,
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
        ),
      );
      await t.pumpAndSettle();
      await warmCampaignImages(t);
      expect(find.text('YOUR BRIDAL PLAN'), findsOneWidget);
      expect(find.text('Bridal Prep'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/planning-customer-home.png'),
      );
      expect(t.takeException(), isNull);
    },
  );
}
