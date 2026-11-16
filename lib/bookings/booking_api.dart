import '../payments/payment_api.dart';

String bookingDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Future<List<int>> loadBookingHours(DateTime day) async {
  return loadBookingHoursForType(day, null);
}

Future<List<int>> loadBookingHoursForType(DateTime day, String? type) async {
  final api = HttpPaymentApi();
  try {
    final data = await api.businessRequest(
      '/v1/appointment-availability?day=${bookingDay(day)}${type == null ? '' : '&type=${Uri.encodeComponent(type)}'}',
    );
    return List<int>.from(data['hours']);
  } finally {
    api.close();
  }
}
