import '../src/model.dart';
import 'package:flutter/foundation.dart';

const elegantLocalReview = Dress(
  'Elegant Bridal Gown',
  0,
  'A-Line',
  'elegant_bridal',
  'An A-line wedding gown with sheer tulle layers and a long train.',
  id: 'elegant-local-review',
  arAsset: 'local_review/elegant_bridal.glb',
  referenceUrl: 'https://www.turbosquid.com/3d-models/2434090',
  credits:
      'Elegant Bridal Gown by Fashionart3d, TurboSquid 2434090. Standard License. Local review only; model redistribution is restricted. Adapted materials and 1K textures.',
  previewNote:
      'Use the virtual try-on to compare the silhouette. Confirm fit in store.',
);

// Model metadata may be linked to a demo product on every platform. Its private
// GLB remains playable only in the Android debug build; a catalogue link never
// grants permission to distribute or load the asset elsewhere.
List<Dress> get browseArDresses => [
  ...preparedArDresses,
  if (kDebugMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.android)
    elegantLocalReview,
];

// IDs must also be allowlisted by Android ArDressCatalogue and Firestore rules.
// Never infer an AR model from a dress name, style, image or inventory position.
final preparedArDresses = List<Dress>.unmodifiable(
  dresses.where(
    (d) => d.id == 'princess-wedding' || d.id == 'francine-reference',
  ),
);

Dress? resolveArDress(String? id) {
  for (final dress in browseArDresses) {
    if (dress.id == id) return dress;
  }
  return null;
}

List<Dress> get catalogueArModels => [...preparedArDresses, elegantLocalReview];

Dress? resolveCatalogueArDress(String? id) {
  for (final dress in catalogueArModels) {
    if (dress.id == id) return dress;
  }
  return null;
}
