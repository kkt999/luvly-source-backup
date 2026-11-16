import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'payment_api.dart';

String receiptPaidDate(SandboxInvoice i) {
  if (i.paidAt == null) return 'Not available';
  return '${DateTime.fromMillisecondsSinceEpoch(i.paidAt!, isUtc: true).add(const Duration(hours: 8)).toIso8601String().substring(0, 16).replaceFirst('T', ' ')} MYT';
}

String receiptPurpose(SandboxInvoice i) => switch (i.purpose) {
  'FittingFee' =>
    'Gown fitting fee - eligible for one package credit after attendance',
  'SecurityDeposit' => 'Refundable gown security - separate from package price',
  'BookingDeposit' => 'Booking deposit',
  'PackageBalance' => 'Package balance',
  'RentalExtension' => 'Additional rental days',
  'PackagePayment' => 'Package payment',
  'AppointmentDeposit' => 'Appointment deposit',
  'DressPayment' => 'Gown payment',
  _ => 'Payment',
};

class ReceiptDocument {
  ReceiptDocument(this.invoice) {
    if (!canRender(invoice)) {
      throw const PaymentFailure(
        'A receipt is available only for a verified successful payment.',
      );
    }
  }
  static final _receiptNumber = RegExp(r'^[A-Za-z0-9_-]{1,150}$');
  static bool canRender(SandboxInvoice invoice) =>
      invoice.state == 'SandboxPaid' &&
      _receiptNumber.hasMatch(invoice.invoiceNo ?? '') &&
      invoice.title.length <= 500 &&
      (invoice.customerName?.length ?? 0) <= 100;
  final SandboxInvoice invoice;
  String get filename => 'Luvly-test-receipt-${invoice.invoiceNo}';
  // PDF and PNG share the same high-resolution drawing, including platform
  // Unicode font fallback. No client money or guessed payment date is used.
  Future<Uint8List> png() async {
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    const width = 760.0,
        pad = 48.0,
        ink = Color(0xFF332B2D),
        rose = Color(0xFFA34C60),
        muted = Color(0xFF72676B);
    var y = 48.0;
    void text(
      String value, {
      double size = 22,
      Color colour = ink,
      FontWeight weight = FontWeight.normal,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'LuvlySans',
            fontSize: size,
            height: 1.35,
            color: colour,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - pad * 2);
      painter.paint(canvas, Offset(pad, y));
      y += painter.height + 12;
    }

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, 220),
      Paint()..color = const Color(0xFFF9ECEF),
    );
    text('LUVLY', size: 40, colour: rose, weight: FontWeight.bold);
    text(
      'TEST PAYMENT RECEIPT',
      size: 20,
      colour: muted,
      weight: FontWeight.w600,
    );
    y = 246;
    text(invoice.amountLabel, size: 44, weight: FontWeight.bold);
    text(
      'Payment verified',
      size: 20,
      colour: const Color(0xFF386953),
      weight: FontWeight.w600,
    );
    y += 10;
    void row(String label, String value) {
      text(
        label.toUpperCase(),
        size: 15,
        colour: muted,
        weight: FontWeight.w600,
      );
      text(value);
      y += 10;
    }

    row('Payment for', invoice.title);
    row('Payment stage', receiptPurpose(invoice));
    if (invoice.appointment case final a?) {
      row('Appointment', paymentDateLabel(a.startAt));
      row('Duration', '${a.durationMinutes} minutes');
    }
    if (invoice.extensionDetails case final e?) {
      row(
        'Requested rental dates',
        'Pickup ${e['pickupDate']} / Return ${e['returnDate']}',
      );
      row(
        'Additional rental days',
        '${e['extraDays']} x RM ${(e['dayRateCents'] / 100).toStringAsFixed(2)} per package/day',
      );
    }
    if (invoice.customerName != null) row('Customer', invoice.customerName!);
    if (invoice.methodLabel != null) row('Method', invoice.methodLabel!);
    row('Verified at', receiptPaidDate(invoice));
    if (invoice.reviewReason != null) {
      row(
        'Payment review',
        'Please contact Luvly before making another payment.',
      );
    }
    row('ToyyibPay transaction reference', invoice.invoiceNo!);
    canvas.drawLine(
      Offset(pad, y),
      Offset(width - pad, y),
      Paint()..color = const Color(0xFFE4D7DA),
    );
    y += 24;
    text(
      'This receipt records a test payment. No money was transferred.',
      size: 18,
      colour: muted,
    );
    text(
      'For cancellations or refunds, please contact Luvly.',
      size: 18,
      colour: muted,
    );
    y += 24;
    final picture = recorder.endRecording();
    final finalRecorder = ui.PictureRecorder(),
        finalCanvas = Canvas(finalRecorder);
    finalCanvas.scale(2);
    finalCanvas.drawRect(
      Rect.fromLTWH(0, 0, width, y),
      Paint()..color = Colors.white,
    );
    finalCanvas.drawPicture(picture);
    final finalPicture = finalRecorder.endRecording();
    final image = await finalPicture.toImage(
      (width * 2).round(),
      (y * 2).ceil(),
    );
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
      finalPicture.dispose();
    }
  }

  Future<Uint8List> pdf({Uint8List? image}) async {
    final bytes = image ?? await png();
    final document = pw.Document(
      title: 'Luvly payment receipt',
      author: 'Luvly Bridal Boutique',
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
        ),
      ),
    );
    return document.save();
  }
}
