import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/packages/rental_date_change_screen.dart';
import 'package:luvly_app/packages/rental_extension_status.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_method_dialog.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/payments/receipt_document.dart';
import 'rental_date_change_test.dart' show rental, preview, visualRentalNow;
import 'fitting_workflow_test.dart' show show, scrollTo;
import 'checkout_redesign_test.dart' show fonts, viewport;

const details = {
  'pickupDate': '2026-10-27',
  'eventDate': '2026-10-29',
  'returnDate': '2026-10-30',
  'oldPickupDate': '2026-10-28',
  'oldReturnDate': '2026-10-30',
  'extraDays': 1,
  'dayRateCents': 10000,
};
Map<String, dynamic> invoiceJson() => {
  'id': 'e' * 32,
  'title': 'Additional rental days: Bridal Essentials',
  'appointmentId': 'visit',
  'packageSelectionId': 'b' * 32,
  'purpose': 'RentalExtension',
  'paymentPhase': 'Extension',
  'amountCents': 10000,
  'state': 'Quoted',
  'environment': 'sandbox',
  'extensionDetails': details,
};
Map<String, dynamic> pendingRental({DateTime? at}) => {
  ...rental(at: at),
  'pendingExtension': {
    'id': 'd' * 32,
    'invoiceId': 'e' * 32,
    'amountCents': 10000,
    'expiresAt': (at ?? DateTime.now()).millisecondsSinceEpoch + 900000,
    ...details,
  },
};
HttpPaymentApi apiFor(List<http.Request> calls) => HttpPaymentApi(
  baseUrl: 'https://example.com',
  token: () async => 'token',
  client: MockClient((r) async {
    calls.add(r);
    if (r.url.path.endsWith('/change-dates')) {
      final body = jsonDecode(r.body);
      return http.Response(
        jsonEncode(
          body['previewOnly'] == true
              ? {
                  'canConfirm': true,
                  'requiresPayment': true,
                  'rentalDays': 4,
                  'allowedRentalDays': 3,
                  'extraDaysRequired': 1,
                  'additionalChargeCents': 10000,
                  'dayRateCents': 10000,
                  'quotePackageRevision': 3,
                  'availableAgain': '2026-11-03',
                }
              : pendingRental(),
        ),
        200,
      );
    }
    if (r.url.path.endsWith('/cancel-extension')) {
      return http.Response(
        jsonEncode({
          ...rental(),
          'pendingExtension': null,
          'lastExtensionOutcome': 'Cancelled',
        }),
        200,
      );
    }
    if (r.url.path == '/v1/invoices') {
      return http.Response(
        jsonEncode({
          'invoices': [
            {
              ...invoiceJson(),
              'id': 'c' * 32,
              'purpose': 'SecurityDeposit',
              'state': 'SandboxPaid',
              'invoiceNo': 'SB-paid',
              'amountCents': 30000,
              'extensionDetails': null,
            },
            invoiceJson(),
          ],
        }),
        200,
      );
    }
    return http.Response('{}', 200);
  }),
);
Future<void> previewQuote(WidgetTester t, {DateTime? at}) async {
  await scrollTo(t, 'New pickup date');
  await t.tap(find.text('New pickup date'));
  await t.pumpAndSettle();
  t
      .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
      .onDateChanged(
        DateTime.parse(
          rental(at: at)['pickupDate'],
        ).subtract(const Duration(days: 1)),
      );
  await t.pump();
  await t.tap(find.text('OK'));
  await t.pumpAndSettle();
  await preview(t);
}

void main() {
  testWidgets(
    'paid quote displays rate and total, issues separate invoice only after staff agreement',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      await show(t, RentalDateChangeScreen(rental: rental(), api: api));
      await t.pumpAndSettle();
      await previewQuote(t);
      await scrollTo(t, 'Create extension invoice & hold');
      expect(find.text('Additional payment: RM 100.00'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Create extension invoice & hold',
              ),
            )
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await scrollTo(t, 'Create extension invoice & hold');
      await t.tap(find.text('Create extension invoice & hold'));
      await t.pumpAndSettle();
      final body = jsonDecode(calls.last.body);
      expect(body['quoteRateCents'], 10000);
      expect(body['quotePackageRevision'], 3);
      expect(body.containsKey('amountCents'), false);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'customer must select FPX and explicitly agree to extension dates and fee',
    (t) async {
      viewport(t, const Size(390, 844));
      await show(
        t,
        Scaffold(
          body: PaymentMethodDialog(
            invoice: SandboxInvoice.fromJson(invoiceJson()),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('FPX online banking'));
      await t.pumpAndSettle();
      await t.tap(find.text('FPX online banking'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNotNull,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('pending invoice is sorted ahead of previously paid receipts', (
    t,
  ) async {
    viewport(t, const Size(390, 844));
    final calls = <http.Request>[], api = apiFor(calls);
    addTearDown(api.close);
    await show(t, LivePaymentsScreen(api: api));
    await t.pumpAndSettle();
    expect(
      t
          .widget<CheckoutInvoiceCard>(find.byType(CheckoutInvoiceCard).first)
          .invoice
          .id,
      'e' * 32,
    );
    expect(t.takeException(), isNull);
  });
  test(
    'extension invoice metadata cannot hide a mismatched amount; receipt has its own stage',
    () {
      expect(
        () => SandboxInvoice.fromJson({...invoiceJson(), 'amountCents': 1}),
        throwsA(isA<PaymentFailure>()),
      );
      expect(
        receiptPurpose(SandboxInvoice.fromJson(invoiceJson())),
        'Additional rental days',
      );
    },
  );
  testWidgets(
    'staff cancellation closes extra hold only and never calls rental cancellation',
    (t) async {
      viewport(t, const Size(390, 844));
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      Map<String, dynamic>? result;
      await show(
        t,
        Scaffold(
          body: ListView(
            children: [
              RentalExtensionStatus(
                rental: pendingRental(),
                api: api,
                staff: true,
                onChanged: (r) => result = r,
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel pending extension'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel extension'));
      await t.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single.url.path, endsWith('/cancel-extension'));
      expect(result!['pendingExtension'], null);
      expect(t.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('extension quote layout $width / $scale', (t) async {
        viewport(t, Size(width, 900));
        await fonts();
        final calls = <http.Request>[], api = apiFor(calls);
        addTearDown(api.close);
        await show(
          t,
          RepaintBoundary(
            key: const ValueKey('extension-quote'),
            child: RentalDateChangeScreen(
              rental: rental(at: visualRentalNow()),
              api: api,
              now: visualRentalNow,
            ),
          ),
          scale: scale,
        );
        await t.pumpAndSettle();
        await previewQuote(t, at: visualRentalNow());
        await scrollTo(t, 'Create extension invoice & hold');
        expect(t.takeException(), isNull);
        if (width == 390 && scale == 1) {
          await expectLater(
            find.byKey(const ValueKey('extension-quote')),
            matchesGoldenFile('goldens/rental-paid-extension.png'),
          );
        }
      });
    }
  }
  testWidgets(
    'pending extension status fits small screen and shows both original and requested dates',
    (t) async {
      viewport(t, const Size(390, 844));
      await fonts();
      final calls = <http.Request>[], api = apiFor(calls);
      addTearDown(api.close);
      await show(
        t,
        RepaintBoundary(
          key: const ValueKey('extension-pending'),
          child: Scaffold(
            body: ListView(
              children: [
                RentalExtensionStatus(
                  rental: pendingRental(at: visualRentalNow()),
                  now: visualRentalNow,
                  api: api,
                  staff: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('until payment is verified'), findsOneWidget);
      expect(find.text('Cancel pending extension'), findsNothing);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('extension-pending')),
        matchesGoldenFile('goldens/rental-extension-pending.png'),
      );
    },
  );
  testWidgets(
    'verified extension receipt exports PNG and PDF from the same amount and dates',
    (t) async {
      await fonts();
      await t.runAsync(() async {
        final invoice = SandboxInvoice.fromJson({
          ...invoiceJson(),
          'state': 'SandboxPaid',
          'invoiceNo': 'SB-extension-verified',
          'paidAt': 1792202400000,
        });
        final doc = ReceiptDocument(invoice),
            png = await doc.png(),
            pdf = await doc.pdf(image: png);
        expect(png.length, greaterThan(10000));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        await File(
          'test/payments/previews/receipt-extension.png',
        ).writeAsBytes(png);
      });
    },
  );
}
