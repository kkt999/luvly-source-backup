import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/bookings/booking_repository.dart';

void main() {
  test('MYT appointments are timezone-independent and future-only', () {
    final start = appointmentUtc(DateTime(2026, 10, 10), 10);
    expect(start, DateTime.utc(2026, 10, 10, 2));
    expect(appointmentLabel(start), '10/10/2026 · 10:00 MYT');
    expect(
      validAppointmentTime(start, start.subtract(const Duration(days: 1))),
      isTrue,
    );
    expect(validAppointmentTime(start, start), isFalse);
    expect(
      validAppointmentTime(
        start.add(const Duration(minutes: 1)),
        start.subtract(const Duration(days: 1)),
      ),
      isFalse,
    );
    expect(
      validAppointmentTime(start, start.subtract(const Duration(days: 181))),
      isFalse,
    );
  });
  test('brides cancel; staff process valid transitions only', () {
    expect(canMoveBooking('Requested', 'Confirmed', staff: false), isFalse);
    expect(canMoveBooking('Confirmed', 'Completed', staff: false), isFalse);
    expect(canMoveBooking('Requested', 'Cancelled', staff: false), isTrue);
    expect(canMoveBooking('Confirmed', 'Cancelled', staff: false), isTrue);
    expect(canMoveBooking('Requested', 'Confirmed', staff: true), isFalse);
    expect(canMoveBooking('Confirmed', 'Completed', staff: true), isTrue);
    expect(canMoveBooking('Requested', 'Completed', staff: true), isFalse);
    expect(canMoveBooking('Cancelled', 'Confirmed', staff: true), isFalse);
  });
}
