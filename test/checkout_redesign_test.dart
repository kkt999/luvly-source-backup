import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'package:luvly_app/bookings/appointment_payment_summary.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/bookings/booking_screens.dart';
import 'package:luvly_app/payments/checkout_invoice_card.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/payment_method_dialog.dart';
import 'package:luvly_app/payments/payment_screen.dart';
import 'booking_flow_test.dart' show MemoryBookings;

SandboxInvoice invoice(String state, {String? reviewReason}) => SandboxInvoice(
  id: '0123456789abcdef0123456789abcdef',
  title: 'First gown fitting · 60 minutes',
  appointmentId: 'a' * 32,
  amountCents: 5000,
  state: state,
  purpose: 'FittingFee',
  invoiceNo: state == 'SandboxPaid' ? 'TP2610174143190014' : null,
  appointment: PaymentAppointment(
    startAt: DateTime.utc(2026, 10, 24, 6).millisecondsSinceEpoch,
    type: 'Dress Trial',
    durationMinutes: 60,
  ),
  reviewReason: reviewReason,
);
Future<void> fonts() async {
  await (FontLoader('LuvlySans')
        ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/roboto-medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
      .load();
  await (FontLoader(
    'LuvlySerif',
  )..addFont(rootBundle.load('assets/fonts/CormorantGaramond.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

void viewport(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

FilledButton payButton(WidgetTester t) =>
    t.widget(find.widgetWithText(FilledButton, 'Continue to payment'));

Future<void> tapBookingText(
  WidgetTester t,
  String label, {
  double scroll = 200,
}) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      target,
      scroll,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(target.first);
  await t.pumpAndSettle();
  await t.tap(target.first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'sticky payment action stays visible and requires acceptance without creating a booking',
    (t) async {
      viewport(t, const Size(360, 800));
      final repo = MemoryBookings();
      var times = [10, 11];
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        BookingScope(
          repository: repo,
          availableHours: (_) async => times,
          child: MaterialApp(
            theme: luvlyTheme,
            home: const BookingRequestForm(
              uid: 'bride',
              name: 'Demo Bride',
              phone: '0123456789',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Continue to payment').hitTestable(), findsOneWidget);
      expect(payButton(t).onPressed, isNull);
      expect(
        find.text('Choose an available time to continue.'),
        findsOneWidget,
      );
      expect(find.textContaining(' MYT').hitTestable(), findsNothing);
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '12:00'))
            .onSelected,
        isNull,
      );
      await tapBookingText(t, '10:00');
      await tapBookingText(t, '11:00');
      final chips = t.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(
        chips
            .where((chip) => chip.selected)
            .map((chip) => (chip.label as Text).data),
        ['11:00'],
      );
      expect(
        find.text('Agree to the booking terms to continue.').hitTestable(),
        findsOneWidget,
      );
      expect(payButton(t).onPressed, isNull);
      await tapBookingText(t, 'I agree to the booking terms.');
      expect(payButton(t).onPressed, isNotNull);
      await tapBookingText(t, 'Refresh available times', scroll: -120);
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '11:00')).selected,
        isTrue,
      );
      expect(payButton(t).onPressed, isNotNull);
      times = [10];
      await tapBookingText(t, 'Refresh available times');
      expect(
        t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '11:00')).selected,
        isFalse,
      );
      expect(payButton(t).onPressed, isNull);
      await tapBookingText(t, '10:00');
      await tapBookingText(t, 'I agree to the booking terms.');
      expect(payButton(t).onPressed, isNull);
      expect(repo.rows, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'changing date or service clears the summary and reloads matching times',
    (t) async {
      viewport(t, const Size(390, 844));
      final repo = MemoryBookings();
      final loaded = <(DateTime, String)>[];
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        BookingScope(
          repository: repo,
          availableHoursForType: (day, type) async {
            loaded.add((day, type));
            return type == 'Dress Trial' ? [15] : [11];
          },
          child: MaterialApp(
            theme: luvlyTheme,
            home: const BookingRequestForm(
              uid: 'bride',
              name: 'Jane Lim',
              phone: '+60123456789',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final (initial, _) = loaded.single;
      await tapBookingText(t, '15:00');
      expect(find.textContaining('3:00 PM MYT'), findsOneWidget);
      await tapBookingText(t, 'I agree to the booking terms.');
      expect(payButton(t).onPressed, isNotNull);
      final later = DateUtils.addDaysToDate(initial, 2);
      await tapBookingText(
        t,
        '${initial.day}/${initial.month}/${initial.year}',
        scroll: -200,
      );
      t
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .onDateChanged(later);
      await t.pumpAndSettle();
      await tapBookingText(t, 'OK');
      expect(loaded.last, (later, 'Dress Trial'));
      expect(find.textContaining('3:00 PM MYT'), findsNothing);
      expect(payButton(t).onPressed, isNull);
      await tapBookingText(t, '15:00');
      expect(payButton(t).onPressed, isNotNull);
      final service = find.byType(DropdownButtonFormField<String>);
      await t.scrollUntilVisible(
        service,
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(service);
      await t.pumpAndSettle();
      await t.tap(find.text('Bridal Consultation').last);
      await t.pumpAndSettle();
      expect(loaded.last, (later, 'Bridal Consultation'));
      expect(
        t
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '15:00'))
            .onSelected,
        isNull,
      );
      expect(find.text('Continue to payment'), findsNothing);
      expect(find.text('RM 0.00'), findsOneWidget);
      await tapBookingText(t, '11:00');
      final book = find.widgetWithText(FilledButton, 'Book appointment');
      expect(t.widget<FilledButton>(book).onPressed, isNull);
      expect(find.textContaining('11:00 AM MYT'), findsOneWidget);
      expect(repo.rows, isEmpty);
    },
  );
  testWidgets(
    'taken slot refreshes availability and a successful retry opens the returned invoice',
    (t) async {
      viewport(t, const Size(390, 844));
      final repo = MemoryBookings();
      addTearDown(repo.changes.close);
      final submitted = <(String, DateTime, String)>[];
      final pending = Completer<BookingOutcome>();
      final returned = 'invoice-from-server';
      DateTime? loadedDate;
      var loads = 0;
      await t.pumpWidget(
        BookingScope(
          repository: repo,
          availableHoursForType: (day, _) async {
            loadedDate = day;
            return ++loads == 1 ? [14, 15] : [15];
          },
          child: MaterialApp(
            theme: luvlyTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open booking'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BookingRequestForm(
                        uid: 'bride',
                        name: 'Jane Lim',
                        phone: '+60123456789',
                        packageName: 'Bridal Essentials',
                        submitRequest: (type, start, notes) async {
                          submitted.add((type, start, notes));
                          if (submitted.length == 1) {
                            throw const PaymentFailure(
                              'Slot already taken',
                              code: 'SLOT_UNAVAILABLE',
                            );
                          }
                          return pending.future;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tapBookingText(t, 'Open booking');
      expect(submitted, isEmpty);
      await tapBookingText(t, '14:00');
      await t.ensureVisible(find.byType(TextFormField));
      await t.enterText(
        find.byType(TextFormField),
        'Please prepare an ivory gown.',
      );
      await tapBookingText(t, 'I agree to the booking terms.');
      expect(find.text('Selected package: Bridal Essentials'), findsOneWidget);
      expect(find.textContaining('eligible paid fitting'), findsOneWidget);
      await tapBookingText(t, 'Continue to payment');
      expect(submitted.single, (
        'Dress Trial',
        appointmentUtc(loadedDate!, 14),
        'Please prepare an ivory gown.',
      ));
      expect(loads, 2);
      expect(
        find
            .text('This time is no longer available. Choose another time.')
            .hitTestable(),
        findsOneWidget,
      );
      expect(payButton(t).onPressed, isNull);
      expect(find.byType(LivePaymentsScreen), findsNothing);
      await tapBookingText(t, '15:00', scroll: -200);
      expect(find.textContaining('3:00 PM MYT'), findsOneWidget);
      final submit = payButton(t).onPressed!;
      submit();
      submit();
      await t.pump();
      expect(submitted, hasLength(2));
      expect(submitted.last, (
        'Dress Trial',
        appointmentUtc(loadedDate!, 15),
        'Please prepare an ivory gown.',
      ));
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Preparing…'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(
        BookingOutcome(
          appointmentId: 'visit',
          status: 'AwaitingPayment',
          invoiceId: returned,
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<LivePaymentsScreen>(find.byType(LivePaymentsScreen))
            .initialInvoiceId,
        returned,
      );
      expect(t.takeException(), isNull);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(BookingRequestForm), findsNothing);
      expect(
        find.text('View your appointment and payment status under Bookings.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow booking and terms remain scrollable at double text and with the keyboard',
    (t) async {
      viewport(t, const Size(320, 720));
      t.view.padding = const FakeViewPadding(bottom: 22);
      t.view.viewPadding = const FakeViewPadding(bottom: 22);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      final repo = MemoryBookings();
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        BookingScope(
          repository: repo,
          availableHours: (_) async => [15],
          child: MaterialApp(
            theme: luvlyTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const BookingRequestForm(
              uid: 'bride',
              name: 'Jane Lim',
              phone: '+60123456789',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tapBookingText(t, '15:00');
      final notes = find.byType(TextFormField);
      await t.scrollUntilVisible(
        notes,
        140,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(notes);
      t.view.viewInsets = const FakeViewPadding(bottom: 290);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.ensureVisible(notes);
      await t.enterText(notes, 'Optional notes');
      await t.pumpAndSettle();
      expect(notes.hitTestable(), findsOneWidget);
      expect(find.text('Continue to payment'), findsNothing);
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, -280));
      await t.pumpAndSettle();
      await tapBookingText(t, 'Booking & cancellation');
      await tapBookingText(t, 'Package payment details');
      final terms = find.byType(CheckboxListTile);
      await t.scrollUntilVisible(
        terms.hitTestable(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(terms.hitTestable());
      await t.pumpAndSettle();
      final payment = find.widgetWithText(FilledButton, 'Continue to payment');
      expect(payment.hitTestable(), findsOneWidget);
      expect(t.getBottomLeft(payment).dy, lessThan(698));
      expect(payButton(t).onPressed, isNotNull);
      expect(t.takeException(), isNull);
      expect(repo.rows, isEmpty);
    },
  );
  testWidgets(
    'success is never presented for pending or paid-but-review transactions',
    (t) async {
      for (final i in [
        invoice('Pending'),
        invoice('ReviewRequired'),
        invoice(
          'SandboxPaid',
          reviewReason: 'Payment verified after expiry; staff review required',
        ),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CheckoutInvoiceCard(
                  invoice: i,
                  staff: false,
                  busy: false,
                  focused: true,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Payment successful'), findsNothing);
        expect(find.text('Success'), findsNothing);
        expect(find.text('Failed'), findsNothing);
        expect(t.takeException(), isNull);
      }
    },
  );
  testWidgets('payment method chooser shows only the connected option', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PaymentMethodDialog(invoice: invoice('Quoted'))),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('FPX online banking'), findsOneWidget);
    expect(find.text('Credit / debit card'), findsNothing);
    expect(find.textContaining('Not connected'), findsNothing);
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
  });
  for (final scene in [
    'booking',
    'booking-large-text',
    'payment',
    'success',
    'review',
    'desktop-success',
    'payment-details',
    'payment-method',
  ]) {
    testWidgets('checkout visual $scene', (t) async {
      final booking = scene.startsWith('booking'),
          large = scene == 'booking-large-text';
      viewport(
        t,
        scene.startsWith('desktop')
            ? const Size(1100, 900)
            : Size(large ? 360 : 390, large ? 950 : 844),
      );
      await t.runAsync(fonts);
      const key = ValueKey('checkout-capture');
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: luvlyTheme,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(
                title: Text(booking ? 'Book an appointment' : 'Your payment'),
              ),
              bottomNavigationBar: booking
                  ? AppointmentBookingFooter(
                      chargeable: true,
                      included: false,
                      busy: false,
                      onContinue: () {},
                    )
                  : null,
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: booking
                        ? [
                            Text(
                              'Review your visit',
                              style: luvlyTheme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 16),
                            AppointmentPaymentSummary(
                              chargeable: true,
                              included: false,
                              linkedToPackage: true,
                              visitStart: DateTime.utc(2026, 11, 19, 7),
                              packageName: 'Bridal Essentials',
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'I agree to the booking terms.',
                              ),
                              value: true,
                              onChanged: (_) {},
                            ),
                          ]
                        : [
                            if (scene == 'payment-method')
                              PaymentMethodDialog(invoice: invoice('Quoted'))
                            else
                              CheckoutInvoiceCard(
                                invoice: invoice(
                                  scene == 'review'
                                      ? 'SandboxPaid'
                                      : scene.contains('success')
                                      ? 'SandboxPaid'
                                      : 'Quoted',
                                  reviewReason: scene == 'review'
                                      ? 'Payment verified after expiry; staff review required'
                                      : null,
                                ),
                                staff: false,
                                busy: false,
                                focused: true,
                                onPay: () {},
                                onReceipt: () {},
                                onDone: () {},
                              ),
                          ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      if (scene == 'payment-details') {
        await t.tap(find.text('Payment details'));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('previews/checkout-$scene.png'),
      );
    });
  }
}
