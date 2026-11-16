import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/admin/design.dart' show portalTheme;
import 'package:luvly_app/packages/package_api.dart';
import 'package:luvly_app/packages/package_screen.dart';
import 'package:luvly_app/packages/staff_package_catalogue.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/payments/staff_payment_workspace.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/shared/list_controls.dart';
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'availability_calendar_test.dart' show tapVisible;
import 'payment_search_test.dart' show SearchPayments;
import 'packages/package_test.dart' show FakePackages, bridal;

SandboxInvoice bill(
  int n, {
  String state = 'Quoted',
  String purpose = 'PackageBalance',
  String? review,
  Map<String, dynamic>? resolution,
  int? expires,
}) => SandboxInvoice(
  id: '${n.toRadixString(16).padLeft(2, '0')}${'a' * 30}',
  title:
      'Bridal Essentials · ${purpose == 'SecurityDeposit' ? 'refundable security' : 'package payment'}',
  appointmentId: 'visit$n',
  packageSelectionId: 'a' * 32,
  customerName: [
    'Jane Lim',
    'Mei Wong',
    'Sarah Lee',
    'Aina Tan',
    'Nora Lee',
    'Amy Tan',
  ][(n - 1) % 6],
  amountCents: purpose == 'SecurityDeposit' ? 30000 : 42450,
  state: state,
  purpose: purpose,
  reviewReason: review,
  reviewResolution: resolution,
  createdAt: DateTime.utc(2026, 10, 20, n).millisecondsSinceEpoch,
  paidAt: state == 'SandboxPaid'
      ? DateTime.utc(2026, 10, 21, n).millisecondsSinceEpoch
      : null,
  invoiceNo: state == 'SandboxPaid' ? 'TP-2026-$n' : null,
  pickupDueDate: '2026-10-25',
  holdExpiresAt: expires,
);
List<SandboxInvoice> sampleBills() => [
  bill(1),
  bill(2, state: 'Pending'),
  bill(3, state: 'SandboxPaid', purpose: 'SecurityDeposit'),
  bill(4, state: 'ReviewRequired', review: 'Amount needs review'),
  bill(
    5,
    purpose: 'BookingDeposit',
    expires: DateTime.utc(2026, 10, 19, 8).millisecondsSinceEpoch,
  ),
  bill(
    6,
    state: 'SandboxPaid',
    review: 'Original review retained',
    resolution: {'state': 'RefundRecorded', 'refundCents': 42450},
  ),
];
BridalPackage pack(String id, String name, int cents, {bool active = true}) =>
    BridalPackage(
      id: id,
      name: name,
      description:
          'A thoughtfully planned bridal package with gown rental and fitting.',
      basePriceCents: cents,
      revision: 4,
      active: active,
      services: bridal.services,
      includedGownCount: 1,
      eligibleDressIds: const ['gown-one', 'gown-two'],
    );

class CatalogueFixture extends FakePackages implements PackageDeletionApi {
  final packages = [
    pack('essential', 'Bridal Essentials', 89900),
    pack('signature', 'Signature Bridal', 189900),
    pack('luxe', 'Luxe Bridal', 259900, active: false),
  ];
  final saved = <BridalPackage>[];
  int selectionReads = 0, deleted = 0;
  bool refuseDelete = false;
  @override
  Future<List<BridalPackage>> catalogue() async => List.of(packages);
  @override
  Future<List<PackageSelection>> selections() async {
    selectionReads++;
    return [];
  }

  @override
  Future<BridalPackage> save(BridalPackage p) async {
    saved.add(p);
    packages[packages.indexWhere((r) => r.id == p.id)] = p;
    return p;
  }

  @override
  Future<void> remove(BridalPackage p) async {
    if (refuseDelete) {
      throw const PaymentFailure(
        'Existing customer records require deactivation instead.',
      );
    }
    deleted++;
    packages.removeWhere((r) => r.id == p.id);
  }
}

Future<void> mount(
  WidgetTester t,
  Widget child, {
  double width = 1440,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1100));
  await fonts();
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: portalTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String label, String option) async {
  final target = find.byWidgetPredicate(
    (w) => w is ListFilterSelect && w.label == label,
  );
  await tapVisible(t, target.first);
  await t.tap(
    find
        .ancestor(
          of: find.text(option),
          matching: find.byType(CheckedPopupMenuItem<String>),
        )
        .last,
  );
  await t.pumpAndSettle();
}

void main() {
  test(
    'attention sorting is stable, non-mutating and never treats resolved reviews as new work',
    () {
      final rows = sampleBills(), ids = rows.map((i) => i.id).toList();
      final sorted = sortStaffPayments(rows, 'Attention first');
      expect(sorted.map((i) => i.id), [
        rows[3].id,
        rows[1].id,
        rows[0].id,
        rows[2].id,
        rows[5].id,
        rows[4].id,
      ]);
      expect(rows.map((i) => i.id), ids);
      expect(staffPaymentStage(rows[5]), StaffPaymentStage.resolved);
      expect(staffPaymentStatusLabel(rows[5]), 'Refund recorded');
      expect(staffPaymentStage(rows[0]), StaffPaymentStage.unpaid);
      expect(staffPaymentStage(rows[2]), StaffPaymentStage.paid);
      expect(staffPaymentDate(rows[0]), 'Before pickup · 2026-10-25');
      expect(staffPaymentStage(bill(1, expires: 1)), StaffPaymentStage.closed);
    },
  );
  test(
    'package sorting keeps inactive records and original catalogue order untouched',
    () {
      final rows = CatalogueFixture().packages,
          ids = rows.map((p) => p.id).toList();
      expect(sortStaffPackages(rows, 'Price: high to low').first.id, 'luxe');
      expect(sortStaffPackages(rows, 'Active first').last.active, false);
      expect(rows.map((p) => p.id), ids);
    },
  );
  testWidgets(
    'staff payment list shows a dense table, security distinction and no customer payment controls',
    (t) async {
      final api = SearchPayments()..rows = sampleBills();
      await mount(t, LivePaymentsScreen(api: api, staff: true));
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.byType(CheckoutInvoiceCard), findsNothing);
      expect(find.text('Pay now'), findsNothing);
      expect(find.text('Issue invoice'), findsNothing);
      expect(find.text('Refundable security'), findsOneWidget);
      expect(api.writes, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'payment filters combine customer, stage and type; reset does not issue or check a payment',
    (t) async {
      final api = SearchPayments()..rows = sampleBills();
      await mount(t, LivePaymentsScreen(api: api, staff: true));
      await choose(t, 'Payment status', 'Paid receipts');
      await choose(t, 'Payment type', 'Refundable security');
      expect(find.text('Sarah Lee'), findsOneWidget);
      expect(find.text('Jane Lim'), findsNothing);
      await t.enterText(find.byType(TextField), 'jane');
      await t.pumpAndSettle();
      expect(
        find.text('No payments match your search and filters.'),
        findsOneWidget,
      );
      await tapVisible(t, find.text('Reset filters'));
      expect(find.text('Jane Lim'), findsOneWidget);
      expect(api.writes, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('unresolved and completed reviews remain separate filters', (
    t,
  ) async {
    final api = SearchPayments()..rows = sampleBills();
    await mount(t, LivePaymentsScreen(api: api, staff: true));
    await choose(t, 'Payment status', 'Needs review');
    expect(find.text('Aina Tan'), findsOneWidget);
    expect(find.text('Amy Tan'), findsNothing);
    await choose(t, 'Payment status', 'Review completed');
    expect(find.text('Amy Tan'), findsOneWidget);
    expect(find.text('Aina Tan'), findsNothing);
    expect(find.text('Refund recorded'), findsOneWidget);
    expect(api.writes, 0);
  });
  testWidgets(
    'opening an exact payment rechecks the saved list and preserves filters on return',
    (t) async {
      final api = SearchPayments()..rows = sampleBills();
      await mount(t, LivePaymentsScreen(api: api, staff: true));
      await t.enterText(find.byType(TextField), 'Jane');
      await t.pumpAndSettle();
      await tapVisible(t, find.text('View details'));
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      expect(
        t
            .widget<CheckoutInvoiceCard>(find.byType(CheckoutInvoiceCard))
            .invoice
            .id,
        bill(1).id,
      );
      expect(find.text('Jane Lim'), findsOneWidget);
      expect(find.text('Sarah Lee'), findsNothing);
      expect(api.reads, 2);
      await tapVisible(t, find.text('View all payments & receipts'));
      expect(find.byType(CheckoutInvoiceCard), findsNothing);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Jane',
      );
      expect(find.text('Sarah Lee'), findsNothing);
      expect(api.writes, 0);
    },
  );
  testWidgets(
    'a disappeared invoice cannot be replaced with another customer record',
    (t) async {
      final api = SearchPayments()..rows = sampleBills();
      await mount(t, LivePaymentsScreen(api: api, staff: true));
      await t.enterText(find.byType(TextField), 'Jane');
      await t.pumpAndSettle();
      api.rows.removeAt(0);
      await tapVisible(t, find.text('View details'));
      expect(
        find.textContaining('This invoice is not available'),
        findsOneWidget,
      );
      expect(find.byType(CheckoutInvoiceCard), findsNothing);
      expect(find.text('Sarah Lee'), findsNothing);
      expect(api.writes, 0);
    },
  );
  testWidgets('manager-only invoice entry remains an explicit action', (
    t,
  ) async {
    final api = SearchPayments()..rows = sampleBills();
    await mount(t, LivePaymentsScreen(api: api, staff: true, manager: true));
    expect(find.text('Issue invoice'), findsOneWidget);
    expect(api.writes, 0);
  });
  testWidgets(
    'staff package list never fetches customer rentals or exposes management',
    (t) async {
      final api = CatalogueFixture();
      await mount(t, LivePackageScreen(api: api, staff: true));
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Create package'), findsNothing);
      expect(
        find
            .byType(PopupMenuButton<String>)
            .evaluate()
            .where(
              (e) =>
                  e.findAncestorWidgetOfExactType<ListFilterSelect>() == null,
            ),
        isEmpty,
      );
      expect(api.selectionReads, 0);
      await tapVisible(t, find.text('View details').first);
      expect(find.text('Included services'), findsOneWidget);
      expect(find.text('Optional extras'), findsOneWidget);
      expect(find.textContaining('not in the base price'), findsOneWidget);
      expect(find.text('Select package'), findsNothing);
      expect(api.saved, isEmpty);
    },
  );
  testWidgets(
    'package price, lifecycle and multi-word filters combine without mutations',
    (t) async {
      final api = CatalogueFixture();
      await mount(t, LivePackageScreen(api: api, staff: true));
      await choose(t, 'Package price', 'Under RM 1,000');
      await t.tap(find.widgetWithText(ChoiceChip, 'Inactive'));
      await t.pumpAndSettle();
      expect(
        find.text('No packages match your search and filters.'),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(ChoiceChip, 'Active'));
      await t.enterText(find.byType(TextField), 'ESSENTIALS rental');
      await t.pumpAndSettle();
      expect(find.text('Bridal Essentials'), findsOneWidget);
      expect(find.text('Signature Bridal'), findsNothing);
      expect(api.saved, isEmpty);
      expect(api.deleted, 0);
    },
  );
  testWidgets(
    'manager status menu preserves exact package revision and existing contents',
    (t) async {
      final api = CatalogueFixture();
      await mount(t, LivePackageScreen(api: api, staff: true, manager: true));
      expect(find.text('Delete'), findsNothing);
      await tapVisible(t, find.byTooltip('More actions for Bridal Essentials'));
      await t.tap(find.text('Deactivate'));
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      await t.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await t.pumpAndSettle();
      final saved = api.saved.single;
      expect(saved.id, 'essential');
      expect(saved.revision, 4);
      expect(saved.active, false);
      expect(saved.services, bridal.services);
      expect(saved.includedGownCount, 1);
      expect(saved.eligibleDressIds, ['gown-one', 'gown-two']);
    },
  );
  testWidgets(
    'deletion remains confirmed and referenced-package refusal does not show success',
    (t) async {
      final api = CatalogueFixture()..refuseDelete = true;
      await mount(t, LivePackageScreen(api: api, staff: true, manager: true));
      await tapVisible(t, find.byTooltip('More actions for Bridal Essentials'));
      await t.tap(find.text('Delete'));
      await t.pumpAndSettle();
      expect(find.text('Delete package?'), findsOneWidget);
      expect(api.deleted, 0);
      await t.tap(find.widgetWithText(FilledButton, 'Delete'));
      await t.pumpAndSettle();
      expect(api.deleted, 0);
      expect(
        find.textContaining('Existing customer records require'),
        findsOneWidget,
      );
      expect(find.text('Package deleted.'), findsNothing);
      expect(find.text('Bridal Essentials'), findsOneWidget);
    },
  );
  testWidgets(
    'payment pagination uses all loaded rows and searching resets page',
    (t) async {
      final api = SearchPayments()
        ..rows = [for (var n = 1; n <= 25; n++) bill(n)];
      await mount(t, LivePaymentsScreen(api: api, staff: true));
      await t.scrollUntilVisible(
        find.text('Page 1 of 2 · 20 per page'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Page 1 of 2 · 20 per page'), findsOneWidget);
      await tapVisible(t, find.byTooltip('Next payment page'));
      expect(find.text('Page 2 of 2 · 20 per page'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byType(TextField),
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'missing customer');
      await t.pumpAndSettle();
      expect(find.text('0 records'), findsOneWidget);
      await tapVisible(t, find.text('Reset filters'));
      await t.scrollUntilVisible(
        find.text('Page 1 of 2 · 20 per page'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Page 1 of 2 · 20 per page'), findsOneWidget);
      expect(api.writes, 0);
    },
  );
  for (final width in [320.0, 800.0, 1200.0, 1440.0]) {
    testWidgets('staff workspaces fit $width at enlarged text', (t) async {
      final payments = SearchPayments()..rows = sampleBills();
      await mount(
        t,
        LivePaymentsScreen(api: payments, staff: true),
        width: width,
        scale: 1.8,
      );
      expect(t.takeException(), isNull);
      final packages = CatalogueFixture();
      await mount(
        t,
        LivePackageScreen(api: packages, staff: true, manager: true),
        width: width,
        scale: 1.8,
      );
      expect(t.takeException(), isNull);
      if (width == 320) {
        await tapVisible(
          t,
          find.byKey(const ValueKey('view-package-essential')),
        );
        expect(t.takeException(), isNull);
      }
    });
  }
  for (final scene in ['payments', 'packages', 'package-details']) {
    testWidgets('staff management visual $scene', (t) async {
      final payments = SearchPayments()..rows = sampleBills(),
          packages = CatalogueFixture();
      await mount(
        t,
        scene == 'payments'
            ? LivePaymentsScreen(api: payments, staff: true, manager: true)
            : LivePackageScreen(api: packages, staff: true, manager: true),
      );
      if (scene == 'package-details') {
        await tapVisible(t, find.text('View details').first);
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('previews/staff-$scene-2072.png'),
      );
    });
  }
}
