import 'dart:js_interop';
import 'package:web/web.dart' as web;

bool downloadCsv(String filename, String csv) {
  final blob = web.Blob(
    ['\uFEFF$csv'.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
