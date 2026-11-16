import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/payments/payment_method_dialog.dart';

SandboxInvoice invoice({bool paid = false}) => SandboxInvoice.fromJson({
  'id': '0123456789abcdef0123456789abcdef',
  'appointmentId': 'abcdef0123456789abcdef0123456789',
  'title': 'First gown fitting · 60 minutes',
  'purpose': 'FittingFee',
  'amountCents': 5000,
  'environment': 'sandbox',
  'state': paid ? 'SandboxPaid' : 'Quoted',
  if (paid) 'invoiceNo': 'TP2610174143190014',
  if (paid) 'paymentChannel': 'FPX B2C',
  if (paid) 'paidAt': DateTime.utc(2026, 10, 17, 14).millisecondsSinceEpoch,
  'appointmentSummary': {
    'type': 'Dress Trial',
    'durationMinutes': 60,
    'startAt': DateTime.utc(2026, 10, 24, 6).millisecondsSinceEpoch,
  },
});

void main() {
  test(
    'appointment metadata uses Malaysia date and does not invent missing details',
    () {
      expect(
        paymentDateLabel(DateTime.utc(2026, 10, 24, 6).millisecondsSinceEpoch),
        '24 Oct 2026 · 14:00 MYT',
      );
      for (final data in [
        null,
        {},
        {'startAt': 1, 'type': 'Dress Trial', 'durationMinutes': 999},
      ]) {
        expect(PaymentAppointment.parse(data), isNull);
      }
    },
  );
  for (final width in [320.0, 390.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'customer details are readable without internal IDs at $width / $scale',
        (t) async {
          t.view.physicalSize = Size(width, 1600);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          await t.pumpWidget(
            MaterialApp(
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  children: [
                    CheckoutInvoiceCard(
                      invoice: invoice(paid: true),
                      staff: false,
                      busy: false,
                    ),
                  ],
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Payment details'));
          await t.tap(find.text('Payment details'));
          await t.pumpAndSettle();
          expect(find.text('24 Oct 2026 · 14:00 MYT'), findsOneWidget);
          expect(find.text('60 minutes'), findsOneWidget);
          expect(find.text('FPX online banking'), findsOneWidget);
          expect(find.text('TP2610174143190014'), findsOneWidget);
          expect(find.text(invoice().id), findsNothing);
          expect(find.text(invoice().appointmentId), findsNothing);
          expect(find.textContaining('SANDBOX'), findsNothing);
          expect(find.textContaining('test transaction'), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'checkout copy is concise but still requires method selection and does not claim success',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PaymentMethodDialog(invoice: invoice())),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Test checkout with ToyyibPay. No money will be charged.'),
        findsOneWidget,
      );
      expect(find.textContaining('sandbox'), findsNothing);
      expect(find.textContaining('test transaction'), findsNothing);
      expect(find.text('Payment successful'), findsNothing);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      await t.tap(find.text('FPX online banking'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('staff retain internal references for reconciliation', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CheckoutInvoiceCard(invoice: invoice(), staff: true, busy: false),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Payment details'));
    await t.pumpAndSettle();
    expect(find.text(invoice().id), findsOneWidget);
    expect(find.text('Test payment'), findsOneWidget);
  });
}
