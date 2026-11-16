import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/analytics_api.dart';
import 'package:luvly_app/admin/analytics_detail.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/payments/payment_api.dart';
import '../checkout_redesign_test.dart' show viewport, fonts;
import '../availability_calendar_test.dart' show tapVisible;
import 'analytics_test.dart' show FakeAnalytics, reportFixture, render;

Map<String, dynamic> detailedFixture() {
  final data = reportFixture();
  final paid = DateTime.utc(2026, 10, 15, 3).millisecondsSinceEpoch;
  data['totals'] = {
    ...data['totals'],
    'serviceCents': 252350,
    'securityCents': 30000,
    'grossCents': 282350,
    'packageSelections': 2,
    'paidPackageBookings': 1,
    'completedFittings': 2,
    'convertedFittings': 1,
    'conversionPercent': 50.0,
  };
  data['details'] = {
    'service': {
      'totalCents': 252350,
      'receipts': [
        for (final pair in [
          (5000, 'Fitting fee'),
          (39950, 'Booking deposit'),
          (107400, 'Package balance'),
          (100000, 'Additional rental days'),
        ])
          {
            'id': 'invoice-${pair.$1}',
            'receipt': 'RC-${pair.$1}',
            'customer': 'Jane Lim',
            'title': 'Bridal Essentials · ${pair.$2}',
            'category': pair.$2,
            'paidAt': paid,
            'amountCents': pair.$1,
          },
      ],
    },
    'security': {
      'totalCents': 30000,
      'receipts': [
        {
          'id': 'security',
          'receipt': 'RC-security',
          'customer': 'Jane Lim',
          'title': 'Refundable gown security',
          'category': 'Refundable security',
          'paidAt': paid,
          'amountCents': 30000,
        },
      ],
    },
    'selections': [
      {
        'id': 'selection-a',
        'name': 'Bridal Essentials',
        'customer': 'Jane Lim',
        'createdAt': paid,
        'paidBooking': true,
      },
      {
        'id': 'selection-b',
        'name': 'Signature Bridal',
        'customer': 'Mei Wong',
        'createdAt': paid,
        'paidBooking': false,
      },
    ],
    'conversion': [
      {
        'id': 'visit-a',
        'customer': 'Jane Lim',
        'attendedAt': paid,
        'converted': true,
      },
      {
        'id': 'visit-b',
        'customer': 'Mei Wong',
        'attendedAt': paid,
        'converted': false,
      },
    ],
  };
  return data;
}

class LiveFixture extends FakeAnalytics implements LiveAnalyticsApi {
  Map<String, dynamic> data = detailedFixture();
  final events = StreamController<String>.broadcast();
  int connections = 0, cancellations = 0;
  @override
  Stream<String> changes() {
    late StreamController<String> stream;
    StreamSubscription<String>? subscription;
    stream = StreamController<String>(
      onListen: () {
        connections++;
        subscription = events.stream.listen(
          stream.add,
          onError: stream.addError,
        );
      },
      onCancel: () async {
        cancellations++;
        await subscription?.cancel();
      },
    );
    return stream.stream;
  }

  @override
  Future<AnalyticsSnapshot> report(DateTime start, DateTime end) async {
    reportCalls++;
    from = start;
    to = end;
    if (pending != null) return pending!.future;
    if (this.fail) {
      throw const PaymentFailure('Cannot connect to Luvly right now.');
    }
    final copy = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)))
      ..['range'] = {'from': analyticsDate(start), 'to': analyticsDate(end)};
    return AnalyticsSnapshot(copy, requireReports: true);
  }
}

AnalyticsSnapshot snapshot([Map<String, dynamic>? data]) =>
    AnalyticsSnapshot(data ?? detailedFixture(), requireReports: true);
void main() {
  test('every metric has a reconcilable exact-source breakdown', () {
    final data = snapshot();
    expect(AnalyticsBreakdown(data, 'service').total, 252350);
    expect(AnalyticsBreakdown(data, 'service').records, hasLength(4));
    expect(
      AnalyticsBreakdown(data, 'security').records.single['id'],
      'security',
    );
    expect(AnalyticsBreakdown(data, 'selections').records, hasLength(2));
    expect(AnalyticsBreakdown(data, 'conversion').value, '1 ÷ 2 × 100 = 50.0%');
  });
  for (final fault in [
    'sum',
    'duplicate',
    'future',
    'wrong-period',
    'conversion',
    'missing',
  ]) {
    test('invalid $fault rows fail closed without fabricating a breakdown', () {
      final data = detailedFixture();
      if (fault == 'sum') {
        data['details']['service']['receipts'][0]['amountCents'] = 1;
      }
      if (fault == 'duplicate') {
        data['details']['service']['receipts'][1]['id'] = 'invoice-5000';
      }
      if (fault == 'future') {
        data['details']['service']['receipts'][0]['paidAt'] = DateTime.utc(
          2026,
          10,
          17,
        ).millisecondsSinceEpoch;
      }
      if (fault == 'wrong-period') {
        data['details']['service']['receipts'][0]['paidAt'] = DateTime.utc(
          2026,
          9,
          1,
        ).millisecondsSinceEpoch;
      }
      if (fault == 'conversion') {
        data['details']['conversion'][1]['converted'] = true;
      }
      if (fault == 'missing') data.remove('details');
      expect(
        () => AnalyticsBreakdown(
          snapshot(data),
          fault == 'conversion' ? 'conversion' : 'service',
        ),
        throwsA(isA<PaymentFailure>()),
      );
    });
  }
  test(
    'no completed fittings never claims zero divided by zero equals zero',
    () {
      final data = detailedFixture();
      data['details']['conversion'] = [];
      data['totals'] = {
        ...data['totals'],
        'completedFittings': 0,
        'convertedFittings': 0,
        'conversionPercent': 0,
      };
      expect(
        AnalyticsBreakdown(snapshot(data), 'conversion').value,
        contains('Not applicable'),
      );
    },
  );
  testWidgets(
    'metric link opens the exact dated service receipt breakdown, not all payments',
    (t) async {
      viewport(t, const Size(1450, 1100));
      final api = LiveFixture();
      addTearDown(api.events.close);
      await render(t, api: api, dashboard: true);
      await tapVisible(
        t,
        find.byKey(const ValueKey('details-Service collections')),
      );
      expect(find.byType(AnalyticsDetailPage), findsOneWidget);
      expect(find.text('RM 2523.50'), findsOneWidget);
      expect(find.text('RC-security'), findsNothing);
      expect(find.text('RC-5000'), findsOneWidget);
      expect(find.text('RC-39950'), findsOneWidget);
      expect(find.textContaining('2026-09-17 to 2026-10-16'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'push changes refresh after coalescing without pressing Refresh',
    (t) async {
      viewport(t, const Size(1450, 1100));
      final api = LiveFixture();
      addTearDown(api.events.close);
      await render(t, api: api, dashboard: true);
      api.events.add('ready');
      await t.pumpAndSettle();
      expect(find.text('Live updates connected'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      final before = api.reportCalls;
      api.data['totals']['serviceCents'] = 99900;
      for (var n = 0; n < 5; n++) {
        api.events.add('changed');
      }
      await t.pump();
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(api.reportCalls, before + 1);
      expect(find.text('RM 999.00'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      expect(api.cancellations, 1);
    },
  );
  testWidgets(
    'opened detail snapshot stays fixed and announces changed source data',
    (t) async {
      viewport(t, const Size(1450, 1100));
      final api = LiveFixture();
      addTearDown(api.events.close);
      await render(t, api: api, dashboard: true);
      await tapVisible(
        t,
        find.byKey(const ValueKey('details-Service collections')),
      );
      api.events.add('changed');
      await t.pumpAndSettle();
      expect(find.textContaining('Source data changed'), findsOneWidget);
      expect(find.text('RM 2523.50'), findsOneWidget);
      api.data['details']['service']['receipts'][0]['amountCents'] = 6000;
      api.data['details']['service']['totalCents'] = 253350;
      api.data['totals']['serviceCents'] = 253350;
      await tapVisible(t, find.text('Reload details'));
      expect(find.text('RM 2533.50'), findsOneWidget);
      expect(find.textContaining('Source data changed'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'disconnection is visible, reconnection backs off, page disposal closes the stream',
    (t) async {
      viewport(t, const Size(1450, 1100));
      final api = LiveFixture();
      addTearDown(api.events.close);
      await render(t, api: api, dashboard: true);
      api.events.add('unavailable');
      await t.pumpAndSettle();
      expect(find.text('Live disconnected · reconnecting'), findsOneWidget);
      expect(find.text('RM 2523.50'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(api.connections, 2);
      api.events.add('ready');
      await t.pumpAndSettle();
      expect(find.text('Live updates connected'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      expect(api.cancellations, 2);
    },
  );
  testWidgets('access loss removes privileged figures and stops reconnecting', (
    t,
  ) async {
    viewport(t, const Size(1450, 1100));
    final api = LiveFixture();
    addTearDown(api.events.close);
    await render(t, api: api, dashboard: true);
    api.events.add('access-denied');
    await t.pumpAndSettle();
    expect(find.text('RM 2523.50'), findsNothing);
    expect(find.text('Could not load dashboard data.'), findsOneWidget);
    await t.pump(const Duration(seconds: 40));
    expect(api.connections, 1);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'hidden page pauses subscriptions and resumes with a fresh authorised read',
    (t) async {
      viewport(t, const Size(1450, 1100));
      final api = LiveFixture();
      addTearDown(api.events.close);
      await render(t, api: api, dashboard: true);
      api.events.add('ready');
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pumpAndSettle();
      final before = api.reportCalls;
      await t.pump(const Duration(minutes: 2));
      expect(api.reportCalls, before);
      expect(api.cancellations, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(api.reportCalls, before + 1);
      expect(api.connections, 2);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'live refresh uses applied dates, never applies an unfinished date edit',
    (t) async {
      viewport(t, const Size(1450, 1400));
      final api = LiveFixture();
      addTearDown(api.events.close);
      await render(t, api: api, dashboard: true);
      await t.tap(find.text('From: 2026-09-17'));
      await t.pumpAndSettle();
      await t.tap(find.text('16').last);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      api.events.add('changed');
      await t.pump();
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(api.from, DateTime(2026, 9, 17));
      expect(find.text('From: 2026-09-16'), findsOneWidget);
      expect(find.textContaining('Dates changed.'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'SSE uses auth header, no query credentials, validates streaming type and aborts on cancel',
    () async {
      late http.BaseRequest sent;
      final cancelled = Completer<void>();
      final client = MockClient.streaming((r, body) async {
        sent = r;
        (r as http.Abortable).abortTrigger!.then((_) => cancelled.complete());
        return http.StreamedResponse(
          Stream.value(utf8.encode('data: ready\n\ndata: changed\n\n')),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.test',
        token: () async => 'private-token',
        client: client,
      );
      final api = HttpAnalyticsApi(transport: transport);
      final values = await api.changes().toList();
      expect(values, ['ready', 'changed']);
      expect(sent.url.query, isEmpty);
      expect(sent.headers['Authorization'], 'Bearer private-token');
      expect(sent.followRedirects, isFalse);
      await cancelled.future;
      client.close();
    },
  );
  test(
    'leaving the dashboard treats its browser stream abort as normal',
    () async {
      final client = MockClient.streaming((request, _) async {
        final abort = (request as http.Abortable).abortTrigger!;
        final body = StreamController<List<int>>(
          onCancel: () async {
            await abort;
            throw http.RequestAbortedException(request.url);
          },
        );
        body.add(utf8.encode('data: ready\n\n'));
        return http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      addTearDown(client.close);
      final api = HttpAnalyticsApi(
        transport: HttpPaymentApi(
          baseUrl: 'https://example.test',
          token: () async => 'synthetic-token',
          client: client,
        ),
      );
      final ready = Completer<void>();
      final subscription = api.changes().listen((event) {
        expect(event, 'ready');
        ready.complete();
      });
      await ready.future;
      await expectLater(subscription.cancel(), completes);
    },
  );

  for (final kind in ['service', 'security', 'selections', 'conversion']) {
    testWidgets(
      '$kind detail layout at 320 with enlarged text and exact source link',
      (t) async {
        viewport(t, const Size(320, 1000));
        await t.runAsync(fonts);
        final rev = ValueNotifier<int>(0);
        addTearDown(rev.dispose);
        String? selected;
        await t.pumpWidget(
          MaterialApp(
            theme: portalTheme,
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: w!,
            ),
            home: AnalyticsDetailPage(
              snapshot: snapshot(),
              kind: kind,
              revision: rev,
              reload: () async => snapshot(),
              onRecord: (_, id) => selected = id,
            ),
          ),
        );
        await t.pumpAndSettle();
        final id = kind == 'service'
            ? 'invoice-5000'
            : kind == 'security'
            ? 'security'
            : kind == 'selections'
            ? 'selection-a'
            : 'visit-a';
        await tapVisible(t, find.byKey(ValueKey('analytics-source-$id')));
        expect(selected, isNotNull);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('detail preview uses synthetic reconciled records', (t) async {
    viewport(t, const Size(1450, 1100));
    await t.runAsync(fonts);
    final rev = ValueNotifier<int>(0);
    addTearDown(rev.dispose);
    const capture = ValueKey('analytics-detail-preview');
    await t.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: portalTheme,
          home: AnalyticsDetailPage(
            snapshot: snapshot(),
            kind: 'service',
            revision: rev,
            reload: () async => snapshot(),
            onRecord: (_, _) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await expectLater(
      find.byKey(capture),
      matchesGoldenFile('goldens/analytics-service-details-2074.png'),
    );
  });
}
