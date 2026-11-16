import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../src/ar_preview.dart';
import '../src/design.dart';
import '../src/gown_viewer.dart';
import '../src/model.dart' show Dress;

class BridalMakeupButton extends StatelessWidget {
  const BridalMakeupButton({super.key});

  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.palette_outlined, size: 18),
    label: const Text('Preview bridal makeup'),
    onPressed: () async {
      try {
        await const MethodChannel('luvly/makeup').invokeMethod<void>('open');
        return;
      } on PlatformException {
        // The native screen may be unavailable on this device.
      } on MissingPluginException {
        // An older Android build may not include the preview.
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open bridal makeup preview.')),
      );
    },
  );
}

/// One preview group beneath the photo; booking remains the primary action.
class GownPreviewTools extends StatelessWidget {
  const GownPreviewTools({
    super.key,
    required this.model,
    required this.catalogueName,
  });
  final Dress model;
  final String catalogueName;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, box) {
          final hasOrbit = supportsGownViewer(model);
          final stacked =
              box.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final width = stacked || !hasOrbit
              ? box.maxWidth
              : (box.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              SizedBox(
                width: width,
                child: OutlinedButton.icon(
                  key: const Key('product-ar-preview'),
                  onPressed: () => go(
                    context,
                    ArTryOnGuideScreen(
                      dress: model,
                      catalogueName: catalogueName,
                    ),
                  ),
                  icon: const Icon(Icons.view_in_ar_outlined, size: 18),
                  label: const Text('AR try-on'),
                ),
              ),
              if (hasOrbit)
                SizedBox(
                  width: width,
                  child: GownViewerButton(dress: model),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      const Text(
        'Appearance preview · Confirm fit at a fitting.',
        style: TextStyle(fontSize: 11, color: muted),
      ),
      ExpansionTile(
        key: const Key('product-about-preview'),
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'About preview',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The preview uses a prepared 3D model. Lighting, colour and shape may differ from the actual gown. It does not measure your body or confirm garment fit.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 8),
                Text(
                  'Model: ${model.name}',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                if (model.credits != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    model.credits!,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
                if (model.referenceUrl != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    model.referenceUrl!,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ],
  );
}
