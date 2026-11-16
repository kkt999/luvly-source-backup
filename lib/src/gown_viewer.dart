import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model.dart';
import '../catalogue/ar_models.dart';

bool supportsGownViewer(Dress dress) =>
    dress.arAsset != null && resolveArDress(dress.id)?.arAsset == dress.arAsset;

/// Uses the bundled, attributed model and native Filament; no upload or camera.
Future<void> openGownViewer(BuildContext context, Dress dress) async {
  String? error;
  if (!supportsGownViewer(dress)) {
    error = '360° view is not available for this dress yet.';
  } else if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    error = 'Open the Luvly Android app to explore this dress in 360°.';
  } else {
    try {
      await const MethodChannel('luvly/ar').invokeMethod<void>(
        'openGownViewer',
        {'dressId': dress.id, 'modelAsset': dress.arAsset},
      );
    } on PlatformException catch (e) {
      error = e.code == 'AUTH_REQUIRED'
          ? 'Please sign in to open the 360° view.'
          : 'Could not open the 360° view. Please try again.';
    } on MissingPluginException {
      error = 'Please install the latest Luvly Android app for 360° viewing.';
    }
  }
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}

class GownViewerButton extends StatelessWidget {
  const GownViewerButton({super.key, required this.dress});
  final Dress dress;
  @override
  Widget build(BuildContext context) => supportsGownViewer(dress)
      ? OutlinedButton.icon(
          onPressed: () => openGownViewer(context, dress),
          icon: const Icon(Icons.threesixty),
          label: const Text('360° view'),
        )
      : const SizedBox.shrink();
}
