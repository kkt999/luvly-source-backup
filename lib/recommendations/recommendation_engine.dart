import '../catalogue/catalogue_repository.dart';
import 'body_scan.dart';

/// Deterministic styling heuristics, not a trained model or fit probability.
const recommendationAlgorithmVersion = 'style-rules-v2';
const measurementLimits = <String, (double, double)>{
  'Height': (50, 250),
  'Weight': (10, 500),
  'Bust': (30, 300),
  'Waist': (30, 300),
  'Hips': (30, 300),
  'Shoulder': (15, 100),
  'Arm length': (15, 120),
};

class BridalPreferences {
  const BridalPreferences({
    this.measurements = const {},
    this.styles = const [],
    this.colours = const [],
    this.maxPriceCents,
    this.useProportions = false,
    this.shareProportionStats = false,
    this.bodyScan,
    this.useScanProportions = false,
  });
  final Map<String, double> measurements;
  final List<String> styles, colours;
  final int? maxPriceCents;
  final bool useProportions;
  final bool shareProportionStats;
  final BodyScan? bodyScan;
  final bool useScanProportions;
  bool get valid =>
      measurements.entries.every((e) {
        final range = measurementLimits[e.key];
        return range != null &&
            e.value.isFinite &&
            e.value >= range.$1 &&
            e.value <= range.$2;
      }) &&
      styles.every(dressCategories.contains) &&
      styles.toSet().length == styles.length &&
      colours.every(dressColours.contains) &&
      colours.toSet().length == colours.length &&
      (maxPriceCents == null ||
          maxPriceCents! >= 1 && maxPriceCents! <= 100000000) &&
      (!shareProportionStats || useProportions) &&
      (bodyScan == null || bodyScan!.valid) &&
      (!useScanProportions || bodyScan != null) &&
      (!useProportions ||
          ['Bust', 'Waist', 'Hips'].every(measurements.containsKey));
  Map<String, dynamic> toJson() => {
    'measurements': measurements,
    'styles': styles,
    'colours': colours,
    'maxPriceCents': maxPriceCents,
    'useProportions': useProportions,
    'shareProportionStats': shareProportionStats,
    'bodyScan': bodyScan?.toJson(),
    'useScanProportions': useScanProportions,
  };
  factory BridalPreferences.fromJson(Map<String, dynamic> d) {
    final p = BridalPreferences(
      measurements: (d['measurements'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
      styles: List<String>.from(d['styles']),
      colours: List<String>.from(d['colours']),
      maxPriceCents: d['maxPriceCents'] as int?,
      useProportions: d['useProportions'] as bool,
      shareProportionStats: d['shareProportionStats'] as bool? ?? false,
      bodyScan: d['bodyScan'] == null
          ? null
          : BodyScan.fromJson(Map<String, dynamic>.from(d['bodyScan'])),
      useScanProportions: d['useScanProportions'] as bool? ?? false,
    );
    if (!p.valid) throw const FormatException('Invalid bridal preferences');
    return p;
  }
  BridalPreferences withMeasurements(Map<String, double> values) =>
      BridalPreferences(
        measurements: values,
        styles: styles,
        colours: colours,
        maxPriceCents: maxPriceCents,
        bodyScan: bodyScan,
        useScanProportions: useScanProportions,
        useProportions:
            useProportions &&
            ['Bust', 'Waist', 'Hips'].every(values.containsKey),
        shareProportionStats:
            shareProportionStats &&
            useProportions &&
            ['Bust', 'Waist', 'Hips'].every(values.containsKey),
      );
  BridalPreferences withBodyScan(BodyScan? scan, bool enabled) =>
      BridalPreferences(
        measurements: measurements,
        styles: styles,
        colours: colours,
        maxPriceCents: maxPriceCents,
        useProportions: useProportions,
        shareProportionStats: shareProportionStats,
        bodyScan: scan,
        useScanProportions: scan != null && enabled,
      );
}

enum ProportionGuide {
  hourglass('Hourglass'),
  pear('Pear / triangle'),
  inverted('Inverted triangle'),
  rectangle('Rectangle'),
  oval('Oval');

  const ProportionGuide(this.label);
  final String label;
}

/// Simplified app guide, not FFIT or a body scan. Shoulder width is never
/// compared to circumference. Priority: waist, bust/hip balance, waist definition.
ProportionGuide? proportionGuide(BridalPreferences p) {
  if (!p.valid || !p.useProportions) return null;
  final b = p.measurements['Bust']!,
      w = p.measurements['Waist']!,
      h = p.measurements['Hips']!;
  if (w >= .9 * (b > h ? b : h)) return ProportionGuide.oval;
  if (h > b * 1.05) return ProportionGuide.pear;
  if (b > h * 1.05) return ProportionGuide.inverted;
  if (w <= .75 * (b < h ? b : h)) return ProportionGuide.hourglass;
  return ProportionGuide.rectangle;
}

const silhouettePoints = <ProportionGuide, Map<String, int>>{
  ProportionGuide.hourglass: {
    'A-Line': 85,
    'Ball Gown': 80,
    'Mermaid': 100,
    'Sheath': 95,
  },
  ProportionGuide.pear: {
    'A-Line': 100,
    'Ball Gown': 95,
    'Mermaid': 75,
    'Sheath': 65,
  },
  ProportionGuide.inverted: {
    'A-Line': 95,
    'Ball Gown': 100,
    'Mermaid': 75,
    'Sheath': 70,
  },
  ProportionGuide.rectangle: {
    'A-Line': 90,
    'Ball Gown': 85,
    'Mermaid': 80,
    'Sheath': 100,
  },
  ProportionGuide.oval: {
    'A-Line': 100,
    'Ball Gown': 85,
    'Mermaid': 65,
    'Sheath': 75,
  },
};

class MatchComponent {
  const MatchComponent(this.label, this.value, this.weight, this.reason);
  final String label, reason;
  final int value, weight;
}

class GownRecommendation {
  const GownRecommendation(
    this.dress,
    this.score,
    this.components,
    this.budgetReason,
  );
  final CatalogueDress dress;
  final int? score;
  final List<MatchComponent> components;
  final String? budgetReason;
}

List<GownRecommendation> recommendGowns(
  Iterable<CatalogueDress> dresses,
  BridalPreferences p,
) {
  if (!p.valid) throw const FormatException('Invalid bridal preferences');
  final guide = proportionGuide(p), results = <GownRecommendation>[];
  for (final d in dresses) {
    // Date-specific stock and physical fit remain booking/fitting checks.
    if (!d.published ||
        d.availability != 'Available' ||
        !dressCategories.contains(d.category) ||
        d.priceCents < 1 ||
        p.maxPriceCents != null && d.priceCents > p.maxPriceCents!) {
      continue;
    }
    final parts = <MatchComponent>[
      if (p.styles.isNotEmpty)
        MatchComponent(
          'Your style',
          p.styles.contains(d.category) ? 100 : 25,
          60,
          p.styles.contains(d.category)
              ? '${d.category} is one of your preferred silhouettes.'
              : '${d.category} is an alternative to your preferred silhouettes.',
        ),
      if (guide != null)
        MatchComponent(
          'Proportion guide',
          silhouettePoints[guide]![d.category]!,
          30,
          'The optional ${guide.label.toLowerCase()} guide gives ${d.category} ${silhouettePoints[guide]![d.category]}/100 styling points.',
        ),
      if (guide == null && p.useScanProportions && p.bodyScan != null)
        MatchComponent(
          'Camera proportion ideas',
          scanStylePoints(p.bodyScan!, d.category),
          15,
          'An optional joint-span rule suggests ${d.category} as a style to explore. It is not a body-shape label or size prediction.',
        ),
      if (p.colours.isNotEmpty)
        MatchComponent(
          'Your colour',
          p.colours.contains(d.colour) ? 100 : 25,
          10,
          p.colours.contains(d.colour)
              ? '${d.colour} matches your colour preferences.'
              : '${d.colour} is an alternative colour.',
        ),
    ];
    final weight = parts.fold<int>(0, (n, c) => n + c.weight);
    final score = weight == 0
        ? null
        : (parts.fold<int>(0, (n, c) => n + c.value * c.weight) / weight)
              .round();
    results.add(
      GownRecommendation(
        d,
        score,
        List.unmodifiable(parts),
        p.maxPriceCents == null
            ? null
            : 'Within your RM ${(p.maxPriceCents! / 100).toStringAsFixed(2)} gown-rental budget.',
      ),
    );
  }
  results.sort((a, b) {
    final score = (b.score ?? 0).compareTo(a.score ?? 0);
    if (score != 0) return score;
    final price = a.dress.priceCents.compareTo(b.dress.priceCents);
    if (price != 0) return price;
    final name = a.dress.name.compareTo(b.dress.name);
    return name != 0 ? name : a.dress.id.compareTo(b.dress.id);
  });
  return List.unmodifiable(results);
}

/// App-specific, unvalidated styling heuristics; not anthropometric thresholds.
/// No circumference-derived body-shape label is inferred from joint locations.
int scanStylePoints(BodyScan scan, String category) {
  final points = scan.shoulderHipRatio >= 1.65
      ? const {'A-Line': 95, 'Ball Gown': 100, 'Mermaid': 75, 'Sheath': 75}
      : scan.shoulderHipRatio <= 1.35
      ? const {'A-Line': 100, 'Ball Gown': 95, 'Mermaid': 85, 'Sheath': 80}
      : const {'A-Line': 90, 'Ball Gown': 90, 'Mermaid': 90, 'Sheath': 90};
  return points[category] ?? 0;
}
