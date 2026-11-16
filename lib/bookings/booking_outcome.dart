class BookingOutcome {
  const BookingOutcome({
    required this.appointmentId,
    required this.status,
    this.invoiceId,
  });
  final String appointmentId, status;
  final String? invoiceId;
  factory BookingOutcome.fromJson(Map<String, dynamic> data) => BookingOutcome(
    appointmentId: data['appointmentId'] as String,
    status: data['status'] as String? ?? 'Confirmed',
    invoiceId: data['invoiceId'] as String?,
  );
}
