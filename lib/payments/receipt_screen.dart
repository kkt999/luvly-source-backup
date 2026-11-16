import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../support/assistant_launcher.dart';
import 'receipt_save.dart';
import 'payment_api.dart';
import 'receipt_document.dart';

class VerifiedReceiptScreen extends StatefulWidget {
  const VerifiedReceiptScreen({
    super.key,
    required this.invoice,
    this.saveBytes,
  });
  final SandboxInvoice invoice;
  final Future<bool> Function(String name, Uint8List bytes, bool pdf)?
  saveBytes;
  @override
  State<VerifiedReceiptScreen> createState() => _ReceiptState();
}

class _ReceiptState extends State<VerifiedReceiptScreen> {
  late final document = ReceiptDocument(widget.invoice);
  late Future<Uint8List> preview;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    preview = document.png();
  }

  Future<void> save(bool pdf) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final image = await preview,
          bytes = pdf ? await document.pdf(image: image) : image;
      bool saved;
      if (widget.saveBytes != null) {
        saved = await widget.saveBytes!(document.filename, bytes, pdf);
      } else {
        saved = await saveReceipt(document.filename, bytes, pdf);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? (kIsWeb
                        ? 'Download started.'
                        : 'Receipt saved to your selected location.')
                  : 'Save cancelled.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              'Could not save the receipt. Try another location; your payment is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AssistantExclusion(child: Text('Receipt'))),
    body: FutureBuilder<Uint8List>(
      future: preview,
      builder: (c, s) {
        if (s.hasError) {
          return const Center(
            child: Text(
              'Could not prepare this receipt. Return to Payments and refresh.',
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : () => save(true),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Download PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => save(false),
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Download image'),
                        ),
                      ],
                    ),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 20),
                    Image.memory(
                      s.data!,
                      semanticLabel:
                          'Payment receipt for ${widget.invoice.amountLabel}',
                      filterQuality: FilterQuality.high,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
