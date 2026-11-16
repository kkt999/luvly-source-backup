import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/admin/live_directory.dart';
import 'package:luvly_app/catalogue/stock_filters.dart';
import 'package:luvly_app/catalogue/variant_stock_screen.dart';
import 'package:luvly_app/packages/package_filters.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/shared/list_controls.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/bookings/appointment_workspace.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/promotions/promotion_admin.dart';
import 'package:luvly_app/promotions/promotion_api.dart';
import 'package:luvly_app/support/support_repository.dart';
import 'package:luvly_app/support/support_screens.dart';
import 'appointment_workspace_test.dart' show sample;
import 'promotions_test.dart' show FakePromotions, offer;
import 'support_flow_test.dart' show MemorySupport;
import 'packages/package_test.dart' show FakePackages;
import 'packages/staff_rental_workspace_test.dart' show staffSelection;
import 'variant_stock_test.dart' show dress;
import 'checkout_redesign_test.dart' show fonts;

const jane = DirectoryRecord(
  id: 'a',
  name: 'Jane Lim',
  email: 'jane@example.com',
  phone: '012345',
  eventDates: ['2030-10-24'],
);
const john = DirectoryRecord(
  id: 'b',
  name: 'John Tan',
  email: 'john@example.com',
  phone: '019999',
  role: 'staff',
  active: true,
);

class MemoryDirectory implements DirectoryApi {
  MemoryDirectory(this.rows, {this.fail = false});
  final List<DirectoryRecord> rows;
  bool fail;
  @override
  Future<List<DirectoryRecord>> list(bool staffAccounts) async {
    if (fail) throw const PaymentFailure('Directory unavailable');
    return rows;
  }

  @override
  void close() {}
}

class ManySupport extends MemorySupport {
  @override
  Stream<List<SupportCase>> cases({String? uid}) => Stream.value([
    for (final item in [
      ('a', 'Ivory fitting', 'Appointments', 'Open'),
      ('b', 'Ivory gown', 'Dresses & AR', 'Closed'),
    ])
      SupportCase(item.$1, {
        'uid': 'customer',
        'name': 'Jane Lim',
        'subject': item.$2,
        'category': item.$3,
        'status': item.$4,
        'revision': 1,
      }),
  ]);
}

Future<void> choose(WidgetTester tester, String label, String option) async {
  final field = find.byWidgetPredicate(
    (w) => w is ListFilterSelect && w.label == label,
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .ancestor(
          of: find.text(option),
          matching: find.byType(CheckedPopupMenuItem<String>),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

Future<void> directory(
  WidgetTester tester,
  DirectoryApi api, {
  bool staff = false,
  double width = 1100,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: portalTheme,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: LiveDirectoryPage(staffAccounts: staff, api: api),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'connected directory empty state does not show legacy setup placeholder',
    (tester) async {
      final model = PortalModel.live(
        member: TeamMember('uid', 'John', 'john@example.com', PortalRole.staff),
      );
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PortalScope(
            model: model,
            child: Scaffold(
              body: LiveDirectoryPage(
                staffAccounts: false,
                api: MemoryDirectory([]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No customer records are available in your scope.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('until this section is connected'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'support topic, lifecycle and multiple words combine without changing tickets',
    (tester) async {
      final repo = ManySupport();
      addTearDown(repo.changes.close);
      await tester.pumpWidget(
        SupportScope(
          repository: repo,
          child: const MaterialApp(
            home: Scaffold(
              body: LiveSupportScreen(uid: 'staff', name: 'John', staff: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'IVORY Jane');
      await tester.pumpAndSettle();
      expect(find.text('Ivory fitting'), findsOneWidget);
      expect(find.text('Ivory gown'), findsNothing);
      await choose(tester, 'Topic', 'Dresses & AR');
      expect(find.text('No conversations match this view.'), findsOneWidget);
      await tester.tap(find.text('Closed').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Ivory gown'), findsOneWidget);
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.text('Ivory fitting'), findsOneWidget);
      expect(repo.messages, isEmpty);
    },
  );
  testWidgets(
    'campaign type and lifecycle are separate AND filters; reset is read-only',
    (tester) async {
      final api = FakePromotions()
        ..rows = [
          Campaign(offer()),
          Campaign({
            ...offer(id: 'news'),
            'kind': 'Announcement',
            'title': 'Boutique opening',
            'active': false,
          }),
        ];
      await tester.pumpWidget(
        MaterialApp(home: PromotionManagementScreen(api: api)),
      );
      await tester.pumpAndSettle();
      await choose(tester, 'Campaign type', 'Announcement');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
      await tester.pumpAndSettle();
      expect(find.text('No matching campaigns.'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Inactive'));
      await tester.enterText(find.byType(TextField), 'BOUTIQUE opening');
      await tester.pumpAndSettle();
      expect(find.text('Boutique opening'), findsOneWidget);
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(find.text('All types'), findsOneWidget);
      expect(api.saved, isEmpty);
      expect(api.removed, 0);
    },
  );
  testWidgets('appointments combine visit type, status and multi-word query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    final first = sample('a', 'Confirmed');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppointmentWorkspace(
            rows: [
              first,
              BookingRequest('b', {
                ...sample('b', 'Completed', name: 'Maya Lee').data,
                'type': 'Bridal Consultation',
              }),
            ],
            staff: true,
            manager: false,
            onUpdate: (_, _) => writes++,
            onRefresh: () {},
            onPackage: (_) {},
            onPayments: () {},
            onBook: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester, 'Visit type', 'Bridal Consultation');
    await tester.enterText(find.byType(TextField), 'MAYA signature');
    await tester.pumpAndSettle();
    expect(find.text('Maya Lee'), findsOneWidget);
    expect(find.text('Alyssa Tan'), findsNothing);
    await choose(tester, 'Status', 'Confirmed');
    await tester.pumpAndSettle();
    expect(find.text('Maya Lee'), findsNothing);
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(find.text('All visits'), findsOneWidget);
    expect(writes, 0);
  });
  test(
    'search uses all case-insensitive words, ignores whitespace, and supports Chinese',
    () {
      expect(
        matchesListSearch('  JANE  Ivory ', ['Jane Lim', null, 'Ivory M']),
        isTrue,
      );
      expect(matchesListSearch('Jane black', ['Jane Lim', 'Ivory']), isFalse);
      expect(matchesListSearch('婚纱 白色', ['白色婚纱']), isTrue);
      expect(matchesListSearch(' [ ', ['[not regex]']), isTrue);
      expect(matchesListSearch('  ', []), isTrue);
    },
  );
  test('date range includes whole MYT days, not device-local UTC dates', () {
    final range = DateTimeRange(
      start: DateTime(2030, 10, 24),
      end: DateTime(2030, 10, 24),
    );
    expect(
      matchesMalaysiaDateRange(DateTime.utc(2030, 10, 23, 15, 59), range),
      isFalse,
    );
    expect(
      matchesMalaysiaDateRange(DateTime.utc(2030, 10, 23, 16), range),
      isTrue,
    );
    expect(
      matchesMalaysiaDateRange(DateTime.utc(2030, 10, 24, 15, 59, 59), range),
      isTrue,
    );
    expect(
      matchesMalaysiaDateRange(DateTime.utc(2030, 10, 24, 16), range),
      isFalse,
    );
  });
  test('package price bands have exact non-overlapping boundaries', () {
    for (final amount in [99999, 100000, 199999, 200000]) {
      expect(
        packagePriceBands.skip(1).where((b) => matchesPackagePrice(amount, b)),
        hasLength(1),
      );
    }
    expect(matchesPackagePrice(100000, 'Under RM 1,000'), isFalse);
    expect(matchesPackagePrice(199999, 'RM 1,000–1,999'), isTrue);
    expect(matchesPackagePrice(200000, 'RM 2,000 and above'), isTrue);
  });
  test('My packages combines lifecycle, gown name and rental date query', () {
    final s = staffSelection();
    expect(matchesPackageSelection(s, 'LUNA 2030-10-24', 'Reserved'), isTrue);
    expect(matchesPackageSelection(s, 'Luna', 'Returned'), isFalse);
    expect(matchesPackageSelection(s, 'missing', 'Reserved'), isFalse);
  });
  test('stock never presents unknown or custom-order quantities as zero', () {
    expect(matchesStockQuantity({'size': 'M'}, 'Zero total'), isFalse);
    expect(matchesStockQuantity({'size': 'M'}, 'Not configured'), isTrue);
    expect(
      matchesStockQuantity({'size': 'L', 'quantity': 0}, 'Zero total'),
      isTrue,
    );
    expect(
      matchesStockQuantity({'size': 'S', 'quantity': 2}, 'Positive total'),
      isTrue,
    );
    expect(
      matchesStockQuantity({
        'size': 'Made to measure',
        'quantity': 0,
      }, 'Zero total'),
      isFalse,
    );
    expect(
      matchesStockQuantity({'size': 'Made to measure'}, 'Custom order'),
      isTrue,
    );
  });
  test('directory combines query with role, access and saved-date filters', () {
    expect(
      matchesDirectory(
        jane,
        staffAccounts: false,
        query: 'LIM 2030-10-24',
        dates: 'With saved dates',
      ),
      isTrue,
    );
    expect(
      matchesDirectory(jane, staffAccounts: false, dates: 'No saved dates'),
      isFalse,
    );
    expect(
      matchesDirectory(
        john,
        staffAccounts: true,
        query: 'john 019',
        role: 'Staff',
        status: 'Active',
      ),
      isTrue,
    );
    expect(
      matchesDirectory(john, staffAccounts: true, role: 'Manager'),
      isFalse,
    );
    expect(
      matchesDirectory(john, staffAccounts: true, status: 'Inactive'),
      isFalse,
    );
  });
  test(
    'directory requests authenticated read-only endpoint; rejects partial lists',
    () async {
      var limited = false;
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/v1/directory/customers');
          expect(r.url.hasQuery, isFalse);
          expect(r.headers['authorization'], 'Bearer token');
          return http.Response(
            jsonEncode({
              'limited': limited,
              'records': [
                {
                  'id': 'a',
                  'name': 'Jane',
                  'email': '',
                  'phone': '',
                  'eventDates': [],
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final api = HttpDirectoryApi(transport: transport);
      expect((await api.list(false)).single.name, 'Jane');
      limited = true;
      await expectLater(api.list(false), throwsA(isA<PaymentFailure>()));
    },
  );
  testWidgets(
    'controlled search preserves typing spaces and resets visible text',
    (tester) async {
      var query = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => Column(
                children: [
                  ListSearchField(
                    value: query,
                    hint: 'Search',
                    onChanged: (v) => set(() => query = v),
                  ),
                  TextButton(
                    onPressed: () => set(() => query = ''),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Jane ');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Jane ',
      );
      await tester.enterText(find.byType(TextField), 'Jane Lim');
      await tester.pump();
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      await tester.enterText(find.byType(TextField), 'Luna');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(query, '');
    },
  );
  testWidgets(
    'directory paginates complete results; filtering and reset return to page one',
    (tester) async {
      final rows = List.generate(
        25,
        (i) => DirectoryRecord(
          id: '$i',
          name: 'Customer $i',
          email: '',
          phone: '',
        ),
      );
      await directory(tester, MemoryDirectory(rows));
      expect(find.text('25 matching customers'), findsOneWidget);
      expect(find.text('Customer 0'), findsOneWidget);
      expect(find.text('Customer 20'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      await tester.ensureVisible(find.byType(ListSearchField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Customer 24');
      await tester.pumpAndSettle();
      expect(find.text('1 matching customers'), findsOneWidget);
      expect(find.text('Page 1 of 1'), findsOneWidget);
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    },
  );
  testWidgets('staff directory is read-only and combines role/access/query', (
    tester,
  ) async {
    await directory(tester, MemoryDirectory([jane, john]), staff: true);
    await choose(tester, 'Role', 'Staff');
    await choose(tester, 'Access status', 'Inactive');
    expect(
      find.text('No records match your search and filters.'),
      findsOneWidget,
    );
    await choose(tester, 'Access status', 'Active');
    await tester.enterText(find.byType(TextField), 'JOHN 019');
    await tester.pumpAndSettle();
    expect(find.text('John Tan'), findsOneWidget);
    expect(find.text('Jane Lim'), findsNothing);
    expect(find.text('Add staff'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });
  testWidgets(
    'real empty and failed directory are distinct, retry can recover',
    (tester) async {
      final api = MemoryDirectory([], fail: true);
      await directory(tester, api);
      expect(find.text('Directory unavailable'), findsOneWidget);
      expect(find.text('0 matching customers'), findsNothing);
      api.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('No customer records are available in your scope.'),
        findsOneWidget,
      );
      expect(
        find.text('No records match your search and filters.'),
        findsNothing,
      );
    },
  );
  testWidgets('My packages search and status combine and reset', (
    tester,
  ) async {
    final api = FakePackages()
      ..rows.addAll([
        staffSelection(),
        staffSelection(char: 'f', stage: 'Returned'),
      ]);
    await tester.pumpWidget(
      MaterialApp(home: LivePackageScreen(api: api, initialSelections: true)),
    );
    await tester.pumpAndSettle();
    await choose(tester, 'Rental status', 'Returned');
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('No matching packages'), findsOneWidget);
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Rental status · All packages'), findsOneWidget);
  });
  testWidgets('stock size and quantity combine, reset is read-only', (
    tester,
  ) async {
    final api = HttpPaymentApi(
      baseUrl: 'https://example.com',
      token: () async => 'token',
      client: MockClient((r) async {
        expect(r.method, 'GET');
        return http.Response(
          jsonEncode({
            'variants': [
              {'size': 'M', 'quantity': 2},
              {'size': 'L', 'quantity': 0},
              {'size': 'S'},
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VariantStockScreen(dress: dress, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await choose(tester, 'Stock quantity', 'Zero total');
    expect(find.text('Size L'), findsOneWidget);
    expect(find.text('Size M'), findsNothing);
    await tester.enterText(find.byType(TextField), 'M');
    await tester.pumpAndSettle();
    expect(
      find.text('No sizes match your search and filters.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(find.text('Size M'), findsOneWidget);
  });
  for (final width in [320.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('directory filters fit $width at text $scale', (
        tester,
      ) async {
        await directory(
          tester,
          MemoryDirectory([john]),
          staff: true,
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('directory desktop visual with synthetic data', (tester) async {
    await tester.runAsync(fonts);
    await directory(tester, MemoryDirectory([jane, john]));
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('previews/customer-directory.png'),
    );
  });
}
