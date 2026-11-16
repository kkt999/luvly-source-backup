import 'dart:typed_data';
import '../payments/payment_api.dart';
import '../packages/package_api.dart' show packageRequestId;

class ReviewApi {
  ReviewApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi(),
      owns = transport == null;
  final HttpPaymentApi transport;
  final bool owns;
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
  }) async => Map<String, dynamic>.from(
    await transport.businessRequest(path, body: body),
  );
  Future<Map<String, dynamic>> upload(
    String rentalId,
    String uploadId,
    Uint8List bytes,
    String mime,
  ) async => Map<String, dynamic>.from(
    (await transport.uploadBusinessFile(
      '/v1/reviews/$rentalId/upload/$uploadId',
      bytes,
      mime,
    ))['media'],
  );
  String requestId() => packageRequestId();
  void close() {
    if (owns) transport.close();
  }
}

String reviewError(Object e) => e is PaymentFailure
    ? e.message
    : 'Could not verify this review. Check your connection and retry.';
