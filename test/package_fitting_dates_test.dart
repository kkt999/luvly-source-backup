import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/bookings/booking_repository.dart';
import 'package:luvly_app/bookings/booking_screens.dart';

void main() {
  testWidgets('package fitting calendar ends before pickup', (tester) async {
    final now = malaysiaNow(),
        today = DateTime(now.year, now.month, now.day),
        cutoff = today.add(const Duration(days: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: BookingRequestForm(
          uid: 'bride',
          name: 'Demo',
          phone: '0123456789',
          packageName: 'Bridal',
          latestAppointmentDay: cutoff,
          submitRequest: (_, _, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final picker = find.byType(OutlinedButton);
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
          .lastDate,
      cutoff,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'no available fitting day disables submission and shows rental-date guidance',
    (tester) async {
      final now = malaysiaNow(), today = DateTime(now.year, now.month, now.day);
      await tester.pumpWidget(
        MaterialApp(
          home: BookingRequestForm(
            uid: 'bride',
            name: 'Demo',
            phone: '0123456789',
            latestAppointmentDay: today.subtract(const Duration(days: 1)),
            submitRequest: (_, _, _) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No fitting date is available before pickup.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Continue to payment'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continue to payment'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
