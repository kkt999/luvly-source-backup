import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model.dart';

/// Native Android tracking stays on-device; web remains the management portal.
Future<void> openLiveTryOn(BuildContext context, {required Dress dress}) async {
  String? error;
  if (dress.id == null || dress.arAsset == null) {
    error =
        'AR preview unavailable for this dress. Please select a dress with an AR model.';
  } else if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    error = 'Live try-on currently requires an Android phone.';
  } else {
    try {
      await const MethodChannel('luvly/ar').invokeMethod<void>('openTryOn', {
        'dressId': dress.id,
        'modelAsset': dress.arAsset,
      });
    } on PlatformException {
      error =
          'Unable to open the camera. Please restart the app and try again.';
    } on MissingPluginException {
      error = 'Fully stop and rebuild the Android app to enable live try-on.';
    }
  }
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
