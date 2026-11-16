import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/payments/receipt_document.dart';
import 'package:luvly_app/payments/receipt_screen.dart';
import 'package:image/image.dart' as img;

SandboxInvoice paid() => const SandboxInvoice(
  id: '0123456789abcdef0123456789abcdef',
  title: 'Bridal Essentials - Booking Deposit',
  appointmentId: 'appointment-demo-01',
  amountCents: 10000,
  state: 'SandboxPaid',
  invoiceNo: 'TP2610174143190014',
  customerName: 'Alyssa Tan',
  purpose: 'BookingDeposit',
  paymentChannel: 'FPX B2C',
  paidAt: 1792026000000,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unpaid or missing transaction reference cannot be exported', () {
    expect(
      () => ReceiptDocument(
        const SandboxInvoice(
          id: 'id',
          title: 'Invoice',
          appointmentId: 'appointment',
          amountCents: 100,
          state: 'Pending',
        ),
      ),
      throwsA(isA<PaymentFailure>()),
    );
    expect(
      receiptPaidDate(
        const SandboxInvoice(
          id: 'id',
          title: 'Invoice',
          appointmentId: 'a',
          amountCents: 100,
          state: 'SandboxPaid',
          invoiceNo: 'ref',
        ),
      ),
      'Not available',
    );
  });
  testWidgets(
    'receipt exports high-resolution PNG and one-page PDF from identical verified data',
    (t) async {
      await (FontLoader('LuvlySans')
            ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
          .load();
      await t.runAsync(() async {
        final doc = ReceiptDocument(paid()),
            png = await doc.png(),
            pdf = await doc.pdf(image: png);
        final image = img.decodePng(png)!;
        expect(image.width, 1520);
        expect(image.height, greaterThan(1200));
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        final dir = Directory('test/payments/previews')
          ..createSync(recursive: true);
        await File('${dir.path}/receipt-sandbox-sample.png').writeAsBytes(png);
        await File('${dir.path}/receipt-sandbox-sample.pdf').writeAsBytes(pdf);
      });
    },
  );
  testWidgets(
    'receipt download offers PDF and PNG; cancelled save is not reported successful',
    (t) async {
      final formats = <bool>[];
      await t.pumpWidget(
        MaterialApp(
          home: VerifiedReceiptScreen(
            invoice: paid(),
            saveBytes: (name, bytes, pdf) async {
              formats.add(pdf);
              expect(bytes, isNotEmpty);
              return false;
            },
          ),
        ),
      );
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pumpAndSettle();
      await t.tap(find.text('Download PDF'));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(formats, [true]);
      expect(find.text('Save cancelled.'), findsOneWidget);
      await t.tap(find.text('Download image'));
      await t.pumpAndSettle();
      expect(formats, [true, false]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'security receipt explicitly separates refundable money from the package',
    (t) async {
      await (FontLoader('LuvlySans')
            ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
          .load();
      const invoice = SandboxInvoice(
        id: '11111111111111111111111111111111',
        title: 'Refundable gown security deposit: Bridal Essentials',
        appointmentId: 'fitting-demo',
        amountCents: 30000,
        state: 'SandboxPaid',
        invoiceNo: 'TP2610174143190015',
        customerName: 'Alyssa Tan',
        purpose: 'SecurityDeposit',
        paymentChannel: 'FPX B2C',
        paidAt: 1792026000000,
      );
      expect(receiptPurpose(invoice), contains('separate from package price'));
      await t.runAsync(() async {
        final doc = ReceiptDocument(invoice),
            png = await doc.png(),
            pdf = await doc.pdf(image: png);
        await File(
          'test/payments/previews/receipt-security-sample.png',
        ).writeAsBytes(png);
        await File(
          'test/payments/previews/receipt-security-sample.pdf',
        ).writeAsBytes(pdf);
      });
    },
  );
}
