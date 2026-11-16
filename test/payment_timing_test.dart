import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_timing.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'checkout_redesign_test.dart' show fonts, viewport;

final clock = DateTime.utc(2026, 10, 18, 15, 24);
SandboxInvoice payment({
  String purpose = 'PackageBalance',
  String state = 'Quoted',
  String? due = '2026-10-23',
  int? expiry,
  int? paidAt,
  bool blocked = false,
  String? review,
}) => SandboxInvoice(
  id: 'a' * 32,
  title: 'Remaining balance: Bridal Essentials',
  appointmentId: 'visit',
  amountCents: 42450,
  purpose: purpose,
  state: state,
  pickupDueDate: due,
  holdExpiresAt: expiry,
  paidAt: paidAt,
  paymentBlocked: blocked,
  reviewReason: review,
);
Future<void> render(WidgetTester t, Widget child, {double scale = 1}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test(
    'pickup due parser rejects invalid dates and never assumes a clock time',
    () {
      expect(
        parsePickupDueDate({'kind': 'BeforePickup', 'date': '2026-10-23'}),
        '2026-10-23',
      );
      for (final d in [
        null,
        {'kind': 'Expiry', 'date': '2026-10-23'},
        {'kind': 'BeforePickup', 'date': '2026-02-30'},
        {'kind': 'BeforePickup', 'date': 123},
        {'kind': 'BeforePickup', 'date': '2026-10-23T23:59:00Z'},
      ]) {
        expect(parsePickupDueDate(d), isNull);
      }
    },
  );
  testWidgets(
    'balance and security show the actual pickup date without a false countdown',
    (t) async {
      for (final purpose in ['PackageBalance', 'SecurityDeposit']) {
        await render(
          t,
          PaymentTiming(
            invoice: payment(purpose: purpose),
            now: clock,
          ),
        );
        expect(find.text('Before pickup · 23 Oct 2026'), findsOneWidget);
        expect(find.textContaining('Time left'), findsNothing);
        expect(find.textContaining('23:59'), findsNothing);
      }
    },
  );
  testWidgets('missing pickup date uses an honest generic instruction', (
    t,
  ) async {
    await render(t, PaymentTiming(invoice: payment(due: null), now: clock));
    expect(find.text('Before pickup'), findsOneWidget);
    expect(find.textContaining('See your agreed pickup date'), findsOneWidget);
  });
  testWidgets(
    'real reservation hold shows absolute MYT deadline and remaining time',
    (t) async {
      for (final purpose in [
        'FittingFee',
        'BookingDeposit',
        'RentalExtension',
      ]) {
        await render(
          t,
          PaymentTiming(
            invoice: payment(
              purpose: purpose,
              expiry: clock
                  .add(const Duration(minutes: 15))
                  .millisecondsSinceEpoch,
            ),
            now: clock,
          ),
        );
        expect(find.text('18 Oct 2026 · 23:39 MYT'), findsOneWidget);
        expect(find.text('Time left · 15:00'), findsOneWidget);
      }
    },
  );
  testWidgets(
    'MYT rollover uses calendar days; past pickup is not a failed payment',
    (t) async {
      await render(
        t,
        PaymentTiming(
          invoice: payment(due: '2026-10-19'),
          now: DateTime.utc(2026, 10, 18, 16, 1),
        ),
      );
      expect(
        find.textContaining('collecting your items today'),
        findsOneWidget,
      );
      await render(
        t,
        PaymentTiming(
          invoice: payment(due: '2026-10-18'),
          now: DateTime.utc(2026, 10, 18, 16, 1),
        ),
      );
      expect(
        find.text('Pickup date has passed. Contact our team.'),
        findsOneWidget,
      );
      expect(find.text('Failed'), findsNothing);
    },
  );
  testWidgets(
    'paid dates replace deadline; review/blocked states never show reassuring timing',
    (t) async {
      await render(
        t,
        PaymentTiming(
          invoice: payment(
            state: 'SandboxPaid',
            paidAt: clock.millisecondsSinceEpoch,
            expiry: 1,
          ),
          now: clock,
        ),
      );
      expect(find.text('Paid on'), findsOneWidget);
      expect(find.text('18 Oct 2026 · 23:24 MYT'), findsOneWidget);
      expect(find.text('Payment due'), findsNothing);
      for (final p in [
        payment(blocked: true),
        payment(review: 'Needs review'),
        payment(state: 'ReviewRequired'),
        payment(state: 'SandboxPaid'),
      ]) {
        await render(t, PaymentTiming(invoice: p, now: clock));
        expect(find.byKey(const Key('payment-timing')), findsNothing);
      }
    },
  );
  testWidgets('expiry does not imply order cancellation or trigger a payment', (
    t,
  ) async {
    await render(
      t,
      PaymentTiming(
        invoice: payment(
          purpose: 'Other',
          expiry: clock.millisecondsSinceEpoch - 1,
        ),
        now: clock,
      ),
    );
    expect(find.text('Payment link expiry'), findsOneWidget);
    expect(find.textContaining('Payment window ended'), findsOneWidget);
    expect(find.textContaining('cancelled'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('deadline card fits 320px at text $scale', (t) async {
      viewport(t, const Size(320, 1100));
      await render(
        t,
        CheckoutInvoiceCard(
          invoice: payment(),
          staff: false,
          busy: false,
          now: clock,
          onPay: () {},
        ),
        scale: scale,
      );
      expect(t.takeException(), isNull);
      expect(
        t.getTopLeft(find.text('Payment due')).dy,
        lessThan(t.getTopLeft(find.text('Pay now')).dy),
      );
    });
  }
  testWidgets('payment due card visual', (t) async {
    viewport(t, const Size(390, 844));
    await fonts();
    await render(
      t,
      CheckoutInvoiceCard(
        invoice: payment(),
        staff: false,
        busy: false,
        now: clock,
        onPay: () {},
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/payment-due-card.png'),
    );
  });
}
