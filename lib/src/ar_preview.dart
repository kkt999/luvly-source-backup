import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../catalogue/ar_models.dart';
import 'design.dart';
import 'live_try_on.dart';
import 'gown_viewer.dart';
import 'model.dart';

/// Bundled references remain accessible even when the live catalogue is empty
/// or offline. They are not silently inserted into the boutique's inventory.
class ArDressLibraryScreen extends StatelessWidget {
  const ArDressLibraryScreen({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'AR try-on',
    child: PageList(
      children: [
        Text(
          'See your bridal look',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        gap(8),
        const Text(
          'Try on these 3D gowns with your Android camera. Check the rental catalogue for availability.',
        ),
        gap(20),
        for (final dress in browseArDresses) ...[
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/images/${dress.asset}.jpg',
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    semanticLabel: '${dress.name} model render',
                  ),
                ),
                gap(12),
                Text(dress.name, style: Theme.of(context).textTheme.titleLarge),
                const Text('Virtual try-on', style: TextStyle(color: muted)),
                gap(12),
                FilledButton.icon(
                  onPressed: () =>
                      go(context, ArTryOnGuideScreen(dress: dress)),
                  icon: const Icon(Icons.view_in_ar),
                  label: const Text('Try this dress'),
                ),
                if (supportsGownViewer(dress)) GownViewerButton(dress: dress),
              ],
            ),
          ),
          gap(16),
        ],
      ],
    ),
  );
}

class ArTryOnGuideScreen extends StatelessWidget {
  const ArTryOnGuideScreen({
    super.key,
    required this.dress,
    this.catalogueName,
  });
  final Dress dress;
  final String? catalogueName;
  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return PageFrame(
      title: 'Your try-on moment',
      bottom: FilledButton(
        onPressed: supported
            ? () => openLiveTryOn(context, dress: dress)
            : null,
        child: Text(
          supported ? 'Start live try-on' : 'Use the Android app for AR',
        ),
      ),
      child: PageList(
        children: [
          Text(
            catalogueName ?? dress.name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (catalogueName != null) Text('Linked model: ${dress.name}'),
          gap(12),
          Image.asset(
            'assets/images/${dress.asset}.jpg',
            height: 260,
            fit: BoxFit.contain,
            semanticLabel: 'Preview of the exact 3D model used in try-on',
          ),
          const Section('Before you start'),
          if (supportsGownViewer(dress)) ...[
            GownViewerButton(dress: dress),
            const Text(
              'Explore the dress from every angle without using your camera.',
            ),
            gap(16),
          ],
          for (final instruction in [
            'Use a bright, well-lit space.',
            'Keep your whole body in frame, with arms slightly apart.',
            'Wear fitted clothing and face the camera.',
            'Choose the widest camera view; step back only as needed.',
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline, color: rose),
              title: Text(instruction),
            ),
          const Section('Preview and save'),
          const Text(
            'Place your phone securely and face forward briefly to align. Try-on stays live while you turn slowly left or right. Tap Take photo when ready, then Resume live or Save look. For hands-free photos, choose a 3- or 10-second timer in Camera. Find saved looks under Try-on history in your profile.',
          ),
          gap(16),
          const Text(
            'This is an appearance preview, not a size or fit measurement. Your existing clothes remain visible. Saved looks stay on this device and are removed if you uninstall the app.',
          ),
          if (dress.previewNote != null) ...[gap(12), Text(dress.previewNote!)],
          const Section('About this model'),
          Text(dress.description),
          if (dress.credits != null) ...[
            gap(12),
            SelectableText(dress.credits!),
          ],
        ],
      ),
    );
  }
}
