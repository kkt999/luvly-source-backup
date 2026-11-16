import 'package:flutter_test/flutter_test.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/recommendations/recommendation_engine.dart';

CatalogueDress gown(
  String id,
  String style, {
  String colour = 'White',
  int price = 50000,
  bool published = true,
  String availability = 'Available',
}) => CatalogueDress(
  id: id,
  name: 'Gown $id',
  category: style,
  description: 'A bridal gown for testing.',
  colour: colour,
  sizes: 'S, M, L',
  priceCents: price,
  imageUrl: '',
  published: published,
  availability: availability,
);
BridalPreferences body(double b, double w, double h) => BridalPreferences(
  measurements: {'Bust': b, 'Waist': w, 'Hips': h},
  useProportions: true,
);
void main() {
  test(
    'report sharing is opt-in, survives serialization and withdraws when measurements are cleared',
    () {
      final p = BridalPreferences(
        measurements: const {'Bust': 90, 'Waist': 65, 'Hips': 92},
        useProportions: true,
        shareProportionStats: true,
      );
      expect(
        BridalPreferences.fromJson(p.toJson()).shareProportionStats,
        isTrue,
      );
      expect(p.withMeasurements({}).shareProportionStats, isFalse);
      final old = p.toJson()..remove('shareProportionStats');
      expect(BridalPreferences.fromJson(old).shareProportionStats, isFalse);
      expect(
        const BridalPreferences(shareProportionStats: true).valid,
        isFalse,
      );
    },
  );
  test('five proportion guides use bust waist and hip circumferences', () {
    expect(proportionGuide(body(90, 65, 92)), ProportionGuide.hourglass);
    expect(proportionGuide(body(85, 70, 100)), ProportionGuide.pear);
    expect(proportionGuide(body(100, 70, 85)), ProportionGuide.inverted);
    expect(proportionGuide(body(90, 80, 92)), ProportionGuide.rectangle);
    expect(proportionGuide(body(95, 95, 100)), ProportionGuide.oval);
    expect(proportionGuide(const BridalPreferences()), isNull);
  });
  test(
    'ratios have defined boundaries and are invariant to uniform scaling',
    () {
      expect(proportionGuide(body(100, 75, 105)), ProportionGuide.hourglass);
      expect(proportionGuide(body(100, 75, 105.01)), ProportionGuide.pear);
      expect(proportionGuide(body(100, 90, 100)), ProportionGuide.oval);
      for (final b in [
        body(90, 65, 92),
        body(85, 70, 100),
        body(100, 70, 85),
        body(90, 80, 92),
        body(95, 95, 100),
      ]) {
        expect(
          proportionGuide(
            BridalPreferences(
              measurements: b.measurements.map((k, v) => MapEntry(k, v * 1.1)),
              useProportions: true,
            ),
          ),
          proportionGuide(b),
        );
      }
    },
  );
  test(
    'missing nonfinite out-of-range and forged measurements are invalid',
    () {
      for (final p in [
        const BridalPreferences(
          measurements: {'Bust': 90},
          useProportions: true,
        ),
        BridalPreferences(measurements: {'Bust': double.nan}),
        const BridalPreferences(measurements: {'Waist': 0}),
        const BridalPreferences(measurements: {'Shoulder': 101}),
        const BridalPreferences(styles: ['Fake']),
        const BridalPreferences(maxPriceCents: 0),
      ]) {
        expect(p.valid, isFalse);
        expect(() => recommendGowns([], p), throwsFormatException);
      }
    },
  );
  test('shoulder width and unrelated fields never alter proportion result', () {
    final p = body(90, 65, 92);
    expect(
      proportionGuide(
        BridalPreferences(
          measurements: {...p.measurements, 'Shoulder': 30, 'Height': 150},
          useProportions: true,
        ),
      ),
      proportionGuide(p),
    );
  });
  test('only published available gowns within exact budget remain', () {
    final result = recommendGowns([
      gown('a', 'A-Line'),
      gown('b', 'Mermaid', price: 50001),
      gown('c', 'Ball Gown', published: false),
      gown('d', 'Sheath', availability: 'Unavailable'),
    ], const BridalPreferences(maxPriceCents: 50000));
    expect(result.map((r) => r.dress.id), ['a']);
    expect(result.single.score, isNull);
  });
  test('weighted score is calculated and explains each active criterion', () {
    final p = BridalPreferences(
      measurements: body(90, 65, 92).measurements,
      styles: ['A-Line'],
      colours: ['Ivory'],
      useProportions: true,
    );
    final result = recommendGowns([
      gown('a', 'A-Line', colour: 'Ivory'),
      gown('b', 'Mermaid'),
    ], p);
    expect(result.first.dress.id, 'a');
    expect(result.first.score, 96); // 60 + 25.5 + 10
    expect(result.last.score, 48); // 15 + 30 + 2.5
    expect(result.first.components.map((r) => r.weight), [60, 30, 10]);
    expect(result.first.components.first.reason, contains('preferred'));
  });
  test(
    'turning guide off ignores measurements and renormalizes active criteria',
    () {
      final result = recommendGowns(
        [gown('a', 'Mermaid')],
        BridalPreferences(
          measurements: body(85, 70, 100).measurements,
          styles: ['Mermaid'],
        ),
      );
      expect(result.single.score, 100);
      expect(result.single.components.length, 1);
    },
  );
  test(
    'preferences can outweigh body guide and multiple liked styles are equal',
    () {
      final p = BridalPreferences(
        measurements: body(85, 70, 100).measurements,
        useProportions: true,
        styles: ['Sheath', 'Mermaid'],
      );
      final result = recommendGowns([
        gown('a', 'A-Line'),
        gown('b', 'Mermaid'),
      ], p);
      expect(result.first.dress.id, 'b');
      expect(result.first.score, 92);
    },
  );
  test('empty profile has no invented scores and ties are deterministic', () {
    final list = [
      gown('z', 'Mermaid'),
      gown('a', 'A-Line'),
      gown('c', 'Sheath', price: 49000),
    ];
    final r = recommendGowns(list, const BridalPreferences());
    expect(r.map((v) => v.dress.id), ['c', 'a', 'z']);
    expect(r.every((v) => v.score == null), isTrue);
    expect(
      recommendGowns(
        list.reversed,
        const BridalPreferences(),
      ).map((v) => v.dress.id),
      r.map((v) => v.dress.id),
    );
  });
  test(
    'body information edit preserves preferences and clears guide if required fields removed',
    () {
      final p = BridalPreferences(
        measurements: body(90, 65, 92).measurements,
        useProportions: true,
        styles: ['A-Line'],
        maxPriceCents: 60000,
      );
      final changed = p.withMeasurements({'Height': 165});
      expect(changed.styles, ['A-Line']);
      expect(changed.useProportions, isFalse);
      expect(changed.maxPriceCents, 60000);
      expect(BridalPreferences.fromJson(p.toJson()).toJson(), p.toJson());
    },
  );
}
