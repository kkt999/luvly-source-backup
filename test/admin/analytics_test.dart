import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/analytics_api.dart';
import 'package:luvly_app/admin/analytics_screen.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/admin/design.dart';
import 'package:luvly_app/payments/payment_api.dart';
import '../checkout_redesign_test.dart' show fonts, viewport;

final fixedToday = DateTime(2026, 10, 16);
Map<String, dynamic> reportFixture({bool empty = false}) => {
  'environment': 'sandbox',
  'timezone': 'Asia/Kuala_Lumpur',
  'generatedAt': DateTime.utc(2026, 10, 16, 3, 30).millisecondsSinceEpoch,
  'range': {'from': '2026-09-17', 'to': '2026-10-16'},
  'operations': {
    'today': '2026-10-16',
    'todayConfirmed': empty ? 0 : 3,
    'awaitingPayment': 0,
    'openConversations': empty ? 0 : 2,
    'activeHolds': 0,
    'overdueReturns': empty ? 0 : 1,
    'upcoming': empty
        ? []
        : [
            {
              'id': 'visit',
              'name': 'Preview customer',
              'type': 'Dress Trial',
              'startAt': DateTime.utc(2026, 10, 16, 6).millisecondsSinceEpoch,
            },
          ],
  },
  'totals': {
    'serviceCents': empty ? 0 : 234500,
    'securityCents': empty ? 0 : 60000,
    'otherCents': 0,
    'grossCents': empty ? 0 : 294500,
    'paidCount': empty ? 0 : 6,
    'reviewCount': 0,
    'packageSelections': empty ? 0 : 8,
    'paidPackageBookings': empty ? 0 : 2,
    'completedFittings': empty ? 0 : 4,
    'convertedFittings': empty ? 0 : 2,
    'conversionPercent': empty ? 0 : 50.0,
    'appointments': empty ? 0 : 8,
    'customers': empty ? 0 : 5,
    'classifiedProfiles': empty ? 0 : 3,
  },
  'quality': {
    'paidMissingMetadata': 0,
    'selectionsMissingDate': 0,
    'appointmentsMissingDate': 0,
    'unclassifiedProfiles': empty ? 0 : 2,
  },
  'trend': List.generate(
    30,
    (i) => {
      'from': analyticsDate(DateTime(2026, 9, 17).add(Duration(days: i))),
      'serviceCents': !empty && i % 5 == 0 ? 39000 : 0,
      'securityCents': !empty && i % 15 == 0 ? 30000 : 0,
      'otherCents': 0,
    },
  ),
  'packages': empty
      ? []
      : [
          {'name': 'Bridal Essentials', 'selections': 5, 'paidBookings': 1},
          {'name': 'Signature Bridal', 'selections': 2, 'paidBookings': 1},
          {'name': 'Luxe Bridal', 'selections': 1, 'paidBookings': 0},
        ],
  'statuses': [],
  'collectionMix': [],
  'bodyTypes': [
    {'label': 'Hourglass', 'count': empty ? 0 : 1},
    {'label': 'Pear', 'count': empty ? 0 : 2},
    {'label': 'Rectangle', 'count': 0},
    {'label': 'Inverted Triangle', 'count': 0},
    {'label': 'Apple', 'count': 0},
  ],
  'reports': [
    {
      'id': 'packages',
      'title': 'Package Popularity Report',
      'basis':
          'Selections by created date, not reservations. Paid bookings are verified linked deposits as of generation.',
      'summary': empty
          ? '0 recorded selections'
          : '8 selections · 2 paid bookings',
      'headers': [
        'Package',
        'Selections',
        'Paid bookings',
        'Share of selections',
      ],
      'rows': empty
          ? []
          : [
              ['Bridal Essentials', '5', '1', '62.5%'],
              ['Signature Bridal', '2', '1', '25%'],
              ['Luxe Bridal', '1', '0', '12.5%'],
            ],
    },
    {
      'id': 'conversion',
      'title': 'Appointment Conversion Report',
      'basis':
          'Completed Dress Trial cohort only. A verified package deposit after the fitting establishes conversion.',
      'summary': empty
          ? '0 / 0 fittings converted'
          : '2 / 4 completed fittings converted · 50%',
      'headers': ['Appointment ID', 'Fitting date (MYT)', 'Outcome'],
      'rows': empty
          ? []
          : [
              ['visit-a', '2026-10-15', 'Converted'],
              ['visit-b', '2026-10-16', 'Not yet converted'],
            ],
    },
    {
      'id': 'collections',
      'title': 'Revenue Summary Report',
      'basis':
          'Sandbox verified paid dates only; service collections exclude refundable security. Not accounting profit.',
      'summary': empty
          ? 'No successful payments'
          : 'Service collections RM2345.00 · Refundable security RM600.00',
      'headers': ['Receipt', 'Paid date (MYT)', 'Category', 'Amount (RM)'],
      'rows': empty
          ? []
          : List.generate(
              45,
              (i) => ['SB-$i', '2026-10-16', 'Fitting fee', '50.00'],
            ),
    },
    {
      'id': 'body-types',
      'title': 'Body Type Distribution Report',
      'basis':
          'Current saved profile snapshot, not date-filtered. No inferred body types.',
      'summary': empty
          ? '0 classified profiles'
          : '3 classified profiles · 2 not classified',
      'headers': ['Body type', 'Profiles', 'Share'],
      'rows': [
        ['Hourglass', empty ? '0' : '1', empty ? '0%' : '33.3%'],
        ['Pear', empty ? '0' : '2', empty ? '0%' : '66.7%'],
      ],
    },
  ],
};

class FakeAnalytics implements AnalyticsApi {
  int reportCalls = 0, dashboardCalls = 0;
  bool fail = false, empty = false;
  DateTime? from, to;
  Completer<AnalyticsSnapshot>? pending;
  @override
  Future<AnalyticsSnapshot> report(DateTime start, DateTime end) async {
    reportCalls++;
    from = start;
    to = end;
    if (pending != null) return pending!.future;
    if (fail) throw const PaymentFailure('Cannot connect to Luvly right now.');
    return AnalyticsSnapshot(
      reportFixture(empty: empty)
        ..['range'] = {'from': analyticsDate(start), 'to': analyticsDate(end)},
      requireReports: true,
    );
  }

  @override
  Future<AnalyticsSnapshot> dashboard() async {
    dashboardCalls++;
    if (fail) throw const PaymentFailure('Cannot connect to Luvly right now.');
    final all = reportFixture(empty: empty);
    return AnalyticsSnapshot({
      'environment': all['environment'],
      'timezone': all['timezone'],
      'generatedAt': all['generatedAt'],
      'operations': all['operations'],
    });
  }

  @override
  void close() {}
}

Future<void> render(
  WidgetTester t, {
  required FakeAnalytics api,
  bool manager = true,
  bool dashboard = false,
  double scale = 1,
  bool Function(String, String)? export,
  ValueChanged<PortalPage>? navigate,
}) async {
  final model = PortalModel.live(
    member: TeamMember(
      'uid',
      'Alyssa',
      'preview@example.com',
      manager ? PortalRole.manager : PortalRole.staff,
    ),
  );
  addTearDown(model.dispose);
  await t.pumpWidget(
    PortalScope(
      model: model,
      child: MaterialApp(
        theme: portalTheme,
        debugShowCheckedModeBanner: false,
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(
          body: BusinessAnalyticsPage(
            api: api,
            dashboard: dashboard,
            onNavigate: navigate,
            exportCsv: export,
            today: fixedToday,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

void main() {
  test(
    'report date validation matches the inclusive 366-day backend boundary',
    () {
      expect(
        validateReportDates(
          DateTime(2026, 10, 17),
          fixedToday,
          today: fixedToday,
        ),
        isNotNull,
      );
      expect(
        validateReportDates(
          fixedToday,
          DateTime(2026, 10, 17),
          today: fixedToday,
        ),
        isNotNull,
      );
      expect(
        validateReportDates(
          DateTime(2025, 10, 16),
          fixedToday,
          today: fixedToday,
        ),
        isNull,
      );
      expect(
        validateReportDates(
          DateTime(2025, 10, 15),
          fixedToday,
          today: fixedToday,
        ),
        isNotNull,
      );
    },
  );
  test(
    'CSV exports exact full report, MYT metadata, quotes and formula-safe names',
    () {
      final snapshot = AnalyticsSnapshot(reportFixture(), requireReports: true);
      final csv = safeReportCsv(snapshot.reports.last, snapshot);
      expect(csv, contains('Current snapshot (not date-filtered)'));
      expect(csv, contains('Body Type Distribution Report'));
      expect(csv, contains('"Pear","2","66.7%"'));
    },
  );
  test(
    'CSV quotes commas, quotes, newlines and neutralises spreadsheet formulas',
    () {
      final snapshot = AnalyticsSnapshot(reportFixture(), requireReports: true);
      final report = BusinessReport(
        'packages',
        'A report',
        'Basis',
        ['Name', 'Amount'],
        [
          ['=HYPERLINK("bad")', '100'],
          [' \t+SUM(1,2)', '200'],
          ['Bridal, "Special"\nEdition', '300'],
          ['@evil', '400'],
          ['-1+2', '500'],
        ],
        'Summary',
      );
      final csv = safeReportCsv(report, snapshot);
      expect(csv, contains('BUSINESS REPORT | TEST TRANSACTIONS'));
      expect(csv, contains('2026-10-16T11:30:00.000 MYT'));
      expect(csv, contains('"\'=HYPERLINK(""bad"")"'));
      expect(csv, contains('"\' \t+SUM(1,2)"'));
      expect(csv, contains('"Bridal, ""Special""\nEdition"'));
      expect(csv, contains('"\'@evil"'));
      expect(csv, contains('"\'-1+2"'));
    },
  );
  test(
    'report API sends authenticated GET with server date params and validates missing totals',
    () async {
      final requests = <http.Request>[];
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.test',
        token: () async => 'test-token',
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(jsonEncode(reportFixture()), 200);
        }),
      );
      final api = HttpAnalyticsApi(transport: transport);
      final result = await api.report(DateTime(2026, 10, 1), fixedToday);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.queryParameters, {
        'from': '2026-10-01',
        'to': '2026-10-16',
      });
      expect(requests.single.headers['Authorization'], 'Bearer test-token');
      expect(result.total('serviceCents'), 234500);
      expect(
        () => AnalyticsSnapshot(
          reportFixture()..remove('totals'),
          requireReports: true,
        ),
        throwsA(isA<PaymentFailure>()),
      );
      expect(
        () => AnalyticsSnapshot(
          reportFixture()..['environment'] = 'production',
          requireReports: true,
        ),
        throwsA(isA<PaymentFailure>()),
      );
    },
  );
  testWidgets(
    'staff dashboard is operations-only and cannot open manager reports',
    (t) async {
      viewport(t, const Size(1200, 1100));
      final api = FakeAnalytics();
      await render(t, api: api, manager: false, dashboard: true);
      expect(api.dashboardCalls, 1);
      expect(api.reportCalls, 0);
      expect(find.text('Today in the boutique'), findsOneWidget);
      expect(find.text('Service collections'), findsNothing);
      expect(find.text('Refundable security collected'), findsNothing);
      await render(t, api: api, manager: false);
      expect(find.text('Manager access required'), findsOneWidget);
      expect(api.reportCalls, 0);
    },
  );
  testWidgets(
    'network failure never fabricates zeros and retry fetches fresh data',
    (t) async {
      viewport(t, const Size(1200, 1100));
      final api = FakeAnalytics()..fail = true;
      await render(t, api: api, dashboard: true);
      expect(find.text('Could not load dashboard data.'), findsOneWidget);
      expect(find.text('Service collections'), findsNothing);
      expect(find.textContaining('submitted a payment'), findsNothing);
      api.fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(api.reportCalls, 2);
      expect(find.text('Service collections'), findsNWidgets(2));
      expect(find.text('RM 2345.00'), findsOneWidget);
    },
  );
  testWidgets(
    'four reports, full CSV, table search and pagination use the same snapshot',
    (t) async {
      viewport(t, const Size(1280, 1600));
      final api = FakeAnalytics();
      String? exported;
      await render(
        t,
        api: api,
        export: (name, csv) {
          exported = csv;
          return true;
        },
      );
      expect(find.text('Package Popularity Report'), findsOneWidget);
      await t.tap(find.text('Collections'));
      await t.pumpAndSettle();
      expect(find.text('Revenue Summary Report'), findsOneWidget);
      final download = find.text('Export full CSV');
      await reveal(t, download);
      await t.tap(download);
      await t.pumpAndSettle();
      expect(exported, contains('SB-44'));
      expect(exported, contains('BUSINESS REPORT | TEST TRANSACTIONS'));
      await reveal(t, find.byTooltip('Next report page'));
      await t.tap(find.byTooltip('Next report page'));
      await t.pumpAndSettle();
      expect(find.text('21–40 of 45 matching rows'), findsOneWidget);
      await reveal(t, find.widgetWithText(TextField, 'Search report rows'));
      await t.enterText(
        find.widgetWithText(TextField, 'Search report rows'),
        'SB-44',
      );
      await t.pumpAndSettle();
      expect(find.text('1–1 of 1 matching rows'), findsOneWidget);
      await reveal(t, find.widgetWithText(ChoiceChip, 'Body profiles'));
      await t.tap(find.text('Body profiles'));
      await t.pumpAndSettle();
      expect(find.text('Body Type Distribution Report'), findsOneWidget);
      expect(find.text('Apply filters'), findsNothing);
      expect(find.text('3 classified · 2 not classified'), findsOneWidget);
      await t.tap(find.widgetWithText(ChoiceChip, 'Fitting conversion'));
      await t.pumpAndSettle();
      expect(find.text('Appointment Conversion Report'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'period preset changes request; draft dates disable export until applied',
    (t) async {
      viewport(t, const Size(1280, 1500));
      final api = FakeAnalytics();
      await render(t, api: api);
      await t.tap(find.text('Last 30 days'));
      await t.pumpAndSettle();
      await t.tap(find.text('Last 7 days').last);
      await t.pumpAndSettle();
      expect(api.reportCalls, 2);
      expect(api.from, DateTime(2026, 10, 10));
      await t.tap(find.text('From: 2026-10-10'));
      await t.pumpAndSettle();
      await t.tap(find.text('9').last);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(find.textContaining('Dates changed.'), findsOneWidget);
      final export = t.widget<FilledButton>(
        find.byKey(const Key('export-report-csv')),
      );
      expect(export.onPressed, isNull);
      await reveal(t, find.widgetWithText(ChoiceChip, 'Body profiles'));
      await t.tap(find.widgetWithText(ChoiceChip, 'Body profiles'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('export-report-csv')))
            .onPressed,
        isNotNull,
      );
      await t.tap(find.widgetWithText(ChoiceChip, 'Package demand'));
      await t.pumpAndSettle();
      await reveal(t, find.text('Apply filters'));
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(api.reportCalls, 3);
      expect(api.from, DateTime(2026, 10, 9));
    },
  );
  for (final size in [
    const Size(1440, 1300),
    const Size(390, 1000),
    const Size(320, 1000),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('analytics responsive ${size.width} text $scale', (t) async {
        viewport(t, size);
        await fonts();
        final api = FakeAnalytics();
        await render(t, api: api, dashboard: true, scale: scale);
        expect(t.takeException(), isNull);
        if (size.width == 1440 && scale == 1) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/live-analytics-dashboard.png'),
          );
        }
        await render(t, api: api, scale: scale);
        for (final label in [
          'Package demand',
          'Fitting conversion',
          'Collections',
          'Body profiles',
        ]) {
          await reveal(t, find.widgetWithText(ChoiceChip, label));
          await t.tap(find.widgetWithText(ChoiceChip, label));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: label);
          if (size.width == 1440 && scale == 1 && label == 'Collections') {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('goldens/live-analytics-collections.png'),
            );
          }
        }
      });
    }
  }
  testWidgets(
    'empty live dataset shows honest empty charts without sample records',
    (t) async {
      viewport(t, const Size(1200, 1100));
      await render(t, api: FakeAnalytics()..empty = true, dashboard: true);
      expect(
        find.text('No verified collections in this period.'),
        findsOneWidget,
      );
      expect(
        find.text('No package selections in this period.'),
        findsOneWidget,
      );
      expect(find.text('Preview customer'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
