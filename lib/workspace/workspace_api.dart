import '../payments/payment_api.dart';

/// Existing authenticated transport; never accepts an actor UID in request bodies.
class WorkspaceApi {
  WorkspaceApi({HttpPaymentApi? transport})
    : _transport = transport ?? HttpPaymentApi(),
      _owns = transport == null;
  final HttpPaymentApi _transport;
  final bool _owns;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final value = await _transport.businessRequest(path, body: body);
    if (value is! Map) {
      throw const PaymentFailure(
        'Could not verify the server response. Please retry.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  void close() {
    if (_owns) _transport.close();
  }
}

String workspaceError(Object e) => e is PaymentFailure
    ? e.message
    : 'Could not complete this request. Check your connection and retry.';

String workDay(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime workToday() {
  final d = DateTime.now().toUtc().add(const Duration(hours: 8));
  return DateTime(d.year, d.month, d.day);
}
