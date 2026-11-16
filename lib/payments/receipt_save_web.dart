import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<bool> saveReceipt(String name, Uint8List bytes, bool pdf) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: pdf ? 'application/pdf' : 'image/png'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = '$name.${pdf ? 'pdf' : 'png'}';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
  return true;
}
