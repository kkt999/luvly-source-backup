import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

Future<bool> saveReceipt(String name, Uint8List bytes, bool pdf) async {
  final filename = '$name.${pdf ? 'pdf' : 'png'}';
  if (Platform.isAndroid) {
    final result = await const MethodChannel('luvly/receipts')
        .invokeMethod<String>('save', {
          'filename': filename,
          'bytes': bytes,
          'mime': pdf ? 'application/pdf' : 'image/png',
        });
    return result != null;
  }
  final location = await getSaveLocation(suggestedName: filename);
  if (location == null) return false;
  await XFile.fromData(
    bytes,
    name: filename,
    mimeType: pdf ? 'application/pdf' : 'image/png',
  ).saveTo(location.path);
  return true;
}
