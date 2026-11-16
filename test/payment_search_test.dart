import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_filters.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/payments/payment_method_dialog.dart';
import 'package:luvly_app/payments/receipt_screen.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'checkout_redesign_test.dart' show fonts;

SandboxInvoice record(
  int n, {
  String state = 'Quoted',
  String? purpose = 'BookingDeposit',
  String? review,
  int? createdAt,
  int? paidAt,
  int? expires,
  bool blocked = false,
  bool validReceipt = true,
  int? amount,
  String? title,
  String? due,
  String? checkoutUrl,
  Map<String, dynamic>? resolution,
}) => SandboxInvoice(
  id: n.toRadixString(16).padLeft(32, '0'),
  title:
      title ?? (n == 1 ? 'Bridal Essentials deposit' : 'Luxe Bridal balance'),
  appointmentId: 'internal-visit',
  amountCents: amount ?? (n == 1 ? 30000 : 42450),
  state: state,
  purpose: purpose,
  invoiceNo: state == 'SandboxPaid' && validReceipt ? 'TP261017$n' : null,
  customerName: 'Alyssa Tan',
  reviewReason: review,
  createdAt: createdAt,
  paidAt: paidAt,
  holdExpiresAt: expires,
  paymentBlocked: blocked,
  pickupDueDate: due,
  checkoutUrl: checkoutUrl,
  reviewResolution: resolution,
);

class SearchPayments implements PaymentApi {
  List<SandboxInvoice> rows = [
    record(1),
    record(
      2,
      state: 'SandboxPaid',
      purpose: 'PackageBalance',
      paidAt: DateTime.utc(2026, 10, 17, 6).millisecondsSinceEpoch,
    ),
  ];
  int reads = 0, writes = 0;
  final checks = <String>[];
  Completer<void>? waiting;
  bool fail = false;
  @override
  bool get configured => true;
  @override
  Future<List<SandboxInvoice>> list() async {
    reads++;
    await waiting?.future;
    if (fail) throw StateError('Internal error text');
    return List.of(rows);
  }

  @override
  Future<SandboxInvoice> refresh(String id) async {
    checks.add(id);
    return rows.firstWhere((i) => i.id == id);
  }

  @override
  Future<SandboxInvoice> checkout(
    String id, {
    String paymentMethod = 'FPX',
  }) async {
    writes++;
    return rows.first;
  }

  @override
  Future<SandboxInvoice> quote(String id, String purpose, int cents) async {
    writes++;
    return rows.first;
  }

  @override
  void close() {}
}

Future<void> render(
  WidgetTester t,
  SearchPayments api, {
  double width = 390,
  double scale = 1,
  String? focused,
  bool settle = true,
  bool reduceMotion = false,
}) async {
  t.view.physicalSize = Size(width, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: LivePaymentsScreen(api: api, initialInvoiceId: focused),
    ),
  );
  if (settle) await t.pumpAndSettle();
}

Finder historyCard(SandboxInvoice invoice) => find.byKey(ValueKey(invoice.id));
Finder cardText(SandboxInvoice invoice, String label) =>
    find.descendant(of: historyCard(invoice), matching: find.text(label));

void main() {
  test(
    'search is case-insensitive, token-based and never exposes internal IDs to customer search',
    () {
      final i = record(1, state: 'SandboxPaid');
      expect(
        const PaymentListFilter(query: ' ESSENTIALS  deposit ').matches(i),
        true,
      );
      expect(const PaymentListFilter(query: 'TP2610171').matches(i), true);
      expect(const PaymentListFilter(query: '300.00').matches(i), true);
      expect(
        const PaymentListFilter(query: 'internal-visit').matches(i),
        false,
      );
      expect(
        const PaymentListFilter(
          query: 'internal-visit',
        ).matches(i, staff: true),
        true,
      );
      expect(
        const PaymentListFilter(query: 'Alyssa').matches(i, staff: true),
        true,
      );
      expect(
        const PaymentListFilter(query: 'Essentials wrong').matches(i),
        false,
      );
    },
  );
  test(
    'payment states are mutually exclusive; expired paid receipts stay paid and reviews never look settled',
    () {
      expect(
        paymentListStatus(record(1, state: 'Pending')),
        PaymentListStatus.processing,
      );
      expect(
        paymentListStatus(record(1, state: 'Creating')),
        PaymentListStatus.processing,
      );
      expect(
        paymentListStatus(record(1, expires: 1)),
        PaymentListStatus.closed,
      );
      expect(
        paymentListStatus(record(1, blocked: true)),
        PaymentListStatus.closed,
      );
      expect(
        paymentListStatus(record(1, state: 'SandboxPaid', expires: 1)),
        PaymentListStatus.paid,
      );
      expect(
        paymentListStatus(
          record(1, state: 'SandboxPaid', review: 'Needs review'),
        ),
        PaymentListStatus.review,
      );
      expect(
        const PaymentListFilter(
          status: PaymentListStatus.paid,
        ).matches(record(1)),
        false,
      );
    },
  );
  test(
    'date range includes entire Malaysia calendar days, uses paid then issued date, not appointment dates',
    () {
      final range = DateTimeRange(
        start: DateTime(2026, 10, 18),
        end: DateTime(2026, 10, 18),
      );
      final filter = PaymentListFilter(dates: range);
      int ms(String value) => DateTime.parse(value).millisecondsSinceEpoch;
      expect(
        filter.matches(record(1, createdAt: ms('2026-10-17T16:00:00Z'))),
        true,
      );
      expect(
        filter.matches(record(1, createdAt: ms('2026-10-18T15:59:59Z'))),
        true,
      );
      expect(
        filter.matches(record(1, createdAt: ms('2026-10-17T15:59:59Z'))),
        false,
      );
      expect(
        filter.matches(record(1, createdAt: ms('2026-10-18T16:00:00Z'))),
        false,
      );
      expect(
        filter.matches(
          record(
            1,
            createdAt: ms('2026-10-17T00:00:00Z'),
            paidAt: ms('2026-10-18T00:00:00Z'),
          ),
        ),
        true,
      );
      expect(filter.matches(record(1)), false);
      expect(filter.copyWith(clearDates: true).matches(record(1)), true);
    },
  );
  test(
    'purpose and status and search combine; deposit types and legacy types remain discoverable',
    () {
      const f = PaymentListFilter(
        query: 'essentials',
        type: PaymentListType.deposit,
        status: PaymentListStatus.toPay,
      );
      expect(f.matches(record(1)), true);
      expect(f.matches(record(1, purpose: 'AppointmentDeposit')), true);
      expect(f.matches(record(1, purpose: 'SecurityDeposit')), false);
      expect(paymentListType(record(1, purpose: null)), PaymentListType.other);
      expect(
        paymentListType(record(1, purpose: 'RentalExtension')),
        PaymentListType.extension,
      );
    },
  );
  test(
    'partial server history is refused instead of presenting incomplete search results',
    () async {
      final api = HttpPaymentApi(
        baseUrl: 'https://example.com',
        token: () async => 'token',
        client: MockClient(
          (r) async =>
              http.Response(jsonEncode({'invoices': [], 'limited': true}), 200),
        ),
      );
      addTearDown(api.close);
      await expectLater(api.list(), throwsA(isA<PaymentFailure>()));
    },
  );
  testWidgets(
    'compact history only offers relevant payment actions and preserves timing',
    (t) async {
      final issued = DateTime.utc(2026, 10, 17, 2).millisecondsSinceEpoch;
      final paidAt = DateTime.utc(2026, 10, 17, 6).millisecondsSinceEpoch;
      final due = record(
        1,
        createdAt: issued,
        title: 'Booking deposit: Bridal Essentials',
      );
      final pending = record(
        3,
        state: 'Pending',
        purpose: 'FittingFee',
        checkoutUrl: 'https://dev.toyyibpay.com/abc',
      );
      final paid = record(
        2,
        state: 'SandboxPaid',
        purpose: 'PackageBalance',
        paidAt: paidAt,
        checkoutUrl: 'https://dev.toyyibpay.com/xyz',
      );
      final api = SearchPayments()..rows = [due, pending, paid];
      await render(t, api);
      expect(find.text('3 payments'), findsOneWidget);
      expect(cardText(due, 'Bridal Essentials'), findsOneWidget);
      expect(cardText(due, 'RM 300.00'), findsOneWidget);
      expect(cardText(due, 'Amount due'), findsOneWidget);
      expect(cardText(due, 'Issued · 17 Oct 2026 · 10:00 MYT'), findsOneWidget);
      expect(cardText(paid, '17 Oct 2026 · 14:00 MYT'), findsOneWidget);
      expect(cardText(paid, 'Paid'), findsOneWidget);
      expect(cardText(paid, 'Amount paid'), findsOneWidget);
      expect(cardText(paid, 'Check status'), findsNothing);
      expect(cardText(pending, 'Verification pending'), findsOneWidget);
      expect(cardText(pending, 'Payment amount'), findsOneWidget);
      await t.tap(cardText(due, 'Pay now'));
      await t.pumpAndSettle();
      expect(find.byType(PaymentMethodDialog), findsOneWidget);
      Navigator.of(t.element(find.byType(PaymentMethodDialog))).pop();
      await t.pumpAndSettle();
      expect(api.writes, 0);
      await t.tap(cardText(pending, 'Check status'));
      await t.pumpAndSettle();
      expect(api.checks, [pending.id]);
      final action = cardText(paid, 'View receipt');
      await t.ensureVisible(action);
      await t.pumpAndSettle();
      await t.tap(action);
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<VerifiedReceiptScreen>(find.byType(VerifiedReceiptScreen))
            .invoice
            .id,
        paid.id,
      );
    },
  );
  testWidgets(
    'security payment and recorded refund are distinct and details survive refresh',
    (t) async {
      final plain = record(
        1,
        state: 'SandboxPaid',
        purpose: 'SecurityDeposit',
        title: 'Refundable gown security deposit: Bridal Essentials',
        createdAt: DateTime.utc(2026, 10, 1, 10).millisecondsSinceEpoch,
        validReceipt: false,
      );
      final partial = record(
        2,
        state: 'SandboxPaid',
        purpose: 'SecurityDeposit',
        amount: 30000,
        blocked: true,
        resolution: {
          'state': 'PartialRefundRecorded',
          'refundCents': 20000,
          'retainedCents': 10000,
        },
      );
      final api = SearchPayments()..rows = [plain, partial];
      await render(t, api);
      expect(cardText(plain, 'Paid'), findsOneWidget);
      expect(cardText(plain, 'Refunded'), findsNothing);
      expect(cardText(plain, 'View receipt'), findsNothing);
      expect(
        cardText(plain, 'Issued · 1 Oct 2026 · 18:00 MYT'),
        findsOneWidget,
      );
      expect(cardText(partial, 'Partial refund recorded'), findsOneWidget);
      expect(cardText(partial, 'Original amount paid'), findsOneWidget);
      expect(cardText(partial, 'RM 300.00'), findsOneWidget);
      expect(cardText(partial, 'RM 200.00'), findsNothing);
      await t.tap(cardText(partial, 'Details'));
      await t.pumpAndSettle();
      expect(cardText(partial, 'RM 200.00'), findsOneWidget);
      expect(cardText(partial, 'RM 100.00'), findsOneWidget);
      expect(
        find.textContaining('Refundable after return inspection'),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('Refresh invoices'));
      await t.pumpAndSettle();
      expect(cardText(partial, 'RM 200.00'), findsOneWidget);
      expect(api.writes, 0);
    },
  );
  testWidgets(
    'status count stays accurate for all filters and only builds visible records',
    (t) async {
      final api = SearchPayments()
        ..rows = [
          record(1),
          record(2, state: 'SandboxPaid'),
          record(3, state: 'Pending'),
          record(4, blocked: true),
          record(5, state: 'ReviewRequired'),
          for (var i = 6; i <= 60; i++)
            record(i, state: 'SandboxPaid', title: 'Gown payment $i'),
        ];
      await render(t, api);
      expect(find.text('60 payments'), findsOneWidget);
      expect(find.byType(CheckoutInvoiceCard).evaluate().length, lessThan(60));
      expect(historyCard(api.rows.last), findsNothing);
      for (final (label, count) in [
        ('To pay', '1 payment'),
        ('Paid receipts', '56 payments'),
        ('Processing', '1 payment'),
        ('Expired / cancelled', '1 payment'),
        ('Needs review', '1 payment'),
        ('All', '60 payments'),
      ]) {
        final chip = find.widgetWithText(ChoiceChip, label);
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(find.text(count), findsOneWidget);
      }
      await t.scrollUntilVisible(
        historyCard(api.rows.last),
        520,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      await t.pumpAndSettle();
      expect(historyCard(api.rows.last).hitTestable(), findsOneWidget);
      expect(historyCard(api.rows.first), findsNothing);
      expect(api.reads, 1);
      expect(api.writes, 0);
    },
  );
  testWidgets('initial loading, readable error, retry and empty history', (
    t,
  ) async {
    final api = SearchPayments()..waiting = Completer<void>();
    await render(t, api, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No payments yet'), findsNothing);
    api.fail = true;
    api.waiting!.complete();
    await t.pumpAndSettle();
    expect(
      find.text('Could not load your payments. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Internal error text'), findsNothing);
    api.fail = false;
    api.rows.clear();
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('No payments yet'), findsOneWidget);
    expect(find.text('0 payments'), findsOneWidget);
  });
  testWidgets(
    'ringgit amounts keep exact cents, grouping, signs and a single spoken value',
    (t) async {
      final due = record(1, amount: 129900);
      final paid = record(2, state: 'SandboxPaid', amount: 1250001);
      final negative = record(3, state: 'ReviewRequired', amount: -37450);
      final api = SearchPayments()..rows = [due, paid, negative];
      await render(t, api);
      expect(cardText(paid, 'RM 12,500.01'), findsOneWidget);
      expect(cardText(negative, 'RM -374.50'), findsOneWidget);
      expect(cardText(negative, 'Amount'), findsOneWidget);
      final text = t.widget<Text>(cardText(due, 'RM 1,299.00'));
      expect(text.semanticsLabel, 'RM 1,299.00');
      expect(text.style!.fontFamily, 'LuvlySans');
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans.first.text, 'RM ');
      expect(spans.first.style!.fontSize, lessThan(text.style!.fontSize!));
      expect(spans.last.text, '1,299.00');
    },
  );
  testWidgets(
    'large-font history keeps a large amount and pickup deadline visible',
    (t) async {
      final invoice = record(
        1,
        purpose: 'SecurityDeposit',
        amount: 100000000,
        due: '2027-01-27',
        title:
            'Refundable gown security deposit: ${'Long bridal collection ' * 7}',
      );
      final api = SearchPayments()..rows = [invoice];
      await render(t, api, width: 320, scale: 2, reduceMotion: true);
      final amount = cardText(invoice, 'RM 1,000,000.00');
      expect(amount, findsOneWidget);
      expect(t.getSize(amount).width, greaterThan(0));
      expect(
        cardText(invoice, 'Payment due · Before pickup · 27 Jan 2027'),
        findsOneWidget,
      );
      expect(
        t.getTopLeft(find.textContaining('Payment due')).dy,
        lessThan(t.getTopLeft(cardText(invoice, 'Pay now')).dy),
      );
      await t.ensureVisible(cardText(invoice, 'Details'));
      final expander = t.widget<Expansible>(
        find.descendant(
          of: historyCard(invoice),
          matching: find.byType(Expansible),
        ),
      );
      expect(expander.duration, Duration.zero);
      await t.tap(cardText(invoice, 'Details'));
      await t.pumpAndSettle();
      expect(expander.controller.isExpanded, isTrue);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'search narrows records, survives refresh and reset restores records without writes',
    (t) async {
      final api = SearchPayments();
      await render(t, api);
      expect(find.byType(CheckoutInvoiceCard), findsNWidgets(2));
      await t.enterText(find.byType(TextField), 'Luxe');
      await t.pumpAndSettle();
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      await t.tap(find.byTooltip('Refresh invoices'));
      await t.pumpAndSettle();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Luxe',
      );
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      expect(api.reads, 2);
      await t.enterText(find.byType(TextField), 'no-match');
      await t.pumpAndSettle();
      expect(find.text('No matching payments'), findsOneWidget);
      await t.tap(find.text('Reset search & filters'));
      await t.pumpAndSettle();
      expect(find.byType(CheckoutInvoiceCard), findsNWidgets(2));
      expect(api.writes, 0);
    },
  );
  testWidgets(
    'status chips and filter-sheet apply/cancel are separate from payment actions',
    (t) async {
      final api = SearchPayments();
      await render(t, api);
      await t.ensureVisible(find.text('Paid receipts'));
      await t.tap(find.text('Paid receipts'));
      await t.pumpAndSettle();
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      expect(
        t
            .widget<CheckoutInvoiceCard>(find.byType(CheckoutInvoiceCard))
            .invoice
            .state,
        'SandboxPaid',
      );
      await t.tap(find.byTooltip('Filter payments'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Close filters'));
      await t.pumpAndSettle();
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      await t.tap(find.byTooltip('Filter payments'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('payment-filter-type-security')),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('payment-filter-options')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('payment-filter-type-security')));
      await t.pumpAndSettle();
      await t.tap(find.text('Apply filters'));
      await t.pumpAndSettle();
      expect(find.text('No matching payments'), findsOneWidget);
      await t.tap(find.text('Reset search & filters'));
      await t.pumpAndSettle();
      expect(find.byType(CheckoutInvoiceCard), findsNWidgets(2));
      expect(api.writes, 0);
    },
  );
  testWidgets(
    'focused invoice bypasses list filtering, then offers searchable full history',
    (t) async {
      final api = SearchPayments();
      await render(t, api, focused: api.rows.last.id);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CheckoutInvoiceCard), findsOneWidget);
      await t.ensureVisible(find.text('View all payments & receipts'));
      await t.tap(find.text('View all payments & receipts'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(CheckoutInvoiceCard), findsNWidgets(2));
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('filters fit $width text $scale', (t) async {
        await render(t, SearchPayments(), width: width, scale: scale);
        await t.enterText(find.byType(TextField), 'no-match');
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Filter payments'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('payment search visual', (t) async {
    t.view.physicalSize = const Size(390, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(fonts);
    const key = ValueKey('search-visual');
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: luvlyTheme,
          home: LivePaymentsScreen(api: SearchPayments()),
        ),
      ),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('previews/payment-search.png'),
    );
    await t.tap(find.byTooltip('Filter payments'));
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('previews/payment-search-filters.png'),
    );
  });
}
