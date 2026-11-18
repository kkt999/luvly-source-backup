import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/workspace/workspace_api.dart';
import 'package:luvly_app/recommendations/body_scan.dart';
import 'package:luvly_app/recommendations/measurement_provenance.dart';
import 'package:luvly_app/recommendations/recommendation_api.dart';
import 'package:luvly_app/recommendations/recommendation_engine.dart';
import 'recommendation_engine_test.dart' show gown;

const estimate = BodyMeasurementEstimate(
  measurements: {'Bust': 90, 'Waist': 70, 'Hips': 95},
  heightCm: 168,
  capturedAt: 1793500000000,
  methodVersion: 'two-view-ellipse-v1',
);
const reviewed = ReviewedMeasurements(
  estimate,
  {'Bust': 90, 'Waist': 65, 'Hips': 95},
  1793500002000,
  1793500001000,
);

class AvailableBodyScanner extends BodyScanner {
  const AvailableBodyScanner();
  @override
  bool get available => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy profile remains readable and never claims tape verification',
    () {
      final old = const BridalPreferences(
        measurements: {'Bust': 90, 'Waist': 65, 'Hips': 95},
      ).toJson();
      old.remove('measurementProvenance');
      final profile = BridalPreferences.fromJson(old);
      expect(profile.valid, isTrue);
      expect(profile.measurementProvenance.fields, isEmpty);
      expect(profile.measurementProvenance.summary, contains('not recorded'));
      expect(profile.useProportions, isFalse);
    },
  );

  test(
    'raw estimate and per-field corrections persist without copying final values into metadata',
    () {
      final profile = BridalPreferences(
        measurements: reviewed.measurements,
        measurementProvenance: reviewed.provenance,
        useProportions: true,
      );
      final decoded = BridalPreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(profile.toJson()))),
      );
      expect(decoded.valid, isTrue);
      expect(decoded.measurements['Waist'], 65);
      expect(decoded.measurementProvenance.scan!.measurements['Waist'], 70);
      expect(decoded.measurementProvenance.scan!.heightCm, 168);
      expect(
        decoded.measurementProvenance.fields['Waist']!.source,
        'camera-corrected',
      );
      expect(
        decoded.measurementProvenance.fields['Bust']!.tapeCheckedAt,
        1793500001000,
      );
      expect(
        decoded.measurementProvenance.toJson().containsKey('finalValues'),
        isFalse,
      );
    },
  );

  test(
    'manual edits clear obsolete tape claims while preserving remaining scan evidence',
    () {
      final next = reviewed.provenance.manual(
        'Waist',
        present: true,
        at: 1793500003000,
      );
      expect(next.fields['Waist']!.source, 'user-entered');
      expect(next.fields['Waist']!.tapeCheckedAt, isNull);
      expect(next.scan, isNotNull);
      expect(next.validFor({'Bust': 90, 'Waist': 66, 'Hips': 95}), isTrue);
      var cleared = next;
      for (final label in circumferenceLabels) {
        cleared = cleared.manual(label, present: false, at: 1793500004000);
      }
      expect(cleared.scan, isNull);
      expect(cleared.fields, isEmpty);
    },
  );

  test(
    'contradictory source claims and unsupported estimate metadata are rejected',
    () {
      expect(
        reviewed.provenance.validFor({'Bust': 91, 'Waist': 65, 'Hips': 95}),
        isFalse,
      );
      expect(
        () => BodyMeasurementEstimate.fromJson({
          ...estimate.toJson(),
          'heightCm': double.nan,
        }),
        throwsFormatException,
      );
      expect(
        () => BodyMeasurementEstimate.fromJson({
          ...estimate.toJson(),
          'methodVersion': 'unknown',
        }),
        throwsFormatException,
      );
      expect(
        () => MeasurementEvidence.fromJson({
          'source': 'camera-reviewed',
          'recordedAt': 1793500000000,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'confirmed data keeps opt-out, and enabled analyses recalculate from changed values',
    () {
      final old = BridalPreferences(
        measurements: reviewed.measurements,
        measurementProvenance: reviewed.provenance,
        useProportions: true,
      );
      final before = recommendGowns([
        gown('a', 'A-Line'),
        gown('m', 'Mermaid'),
      ], old);
      expect(before.first.dress.id, 'a');
      final after = old.withMeasurements({
        'Bust': 90,
        'Waist': 65,
        'Hips': 92,
      }, provenance: const MeasurementProvenance());
      expect(proportionGuide(after), ProportionGuide.hourglass);
      expect(
        recommendGowns([
          gown('a', 'A-Line'),
          gown('m', 'Mermaid'),
        ], after).first.dress.id,
        'm',
      );
      final optOut = const BridalPreferences().withMeasurements(
        reviewed.measurements,
      );
      expect(optOut.useProportions, isFalse);
      expect(proportionGuide(optOut), isNull);
    },
  );

  test(
    'supported body guides have neutral descriptions and rule explanations',
    () {
      for (final guide in ProportionGuide.values) {
        expect(guide.description, isNotEmpty);
        expect(guide.explanation, isNotEmpty);
      }
      expect(ProportionGuide.pear.explanation, contains('5%'));
      expect(ProportionGuide.oval.label, 'Oval');
    },
  );

  test(
    'mixed valid and unavailable scores sort deterministically without treating missing as zero',
    () {
      final entries = [
        GownRecommendation(
          gown('missing', 'A-Line', price: 100),
          null,
          [],
          null,
        ),
        GownRecommendation(
          gown('invalid', 'Mermaid', price: 200),
          101,
          [],
          null,
        ),
        GownRecommendation(gown('zero', 'A-Line', price: 500), 0, [], null),
        GownRecommendation(gown('valid', 'Mermaid'), 96, [], null),
      ]..sort(compareGownRecommendations);
      expect(entries.map((entry) => entry.dress.id), [
        'valid',
        'zero',
        'missing',
        'invalid',
      ]);
      expect(entries.last.validScore, isNull);
      for (final guide in ProportionGuide.values) {
        final bodyPoints = silhouettePoints[guide]!;
        expect(
          bodyPoints.values.every((score) => score >= 0 && score <= 100),
          isTrue,
        );
      }
    },
  );

  test(
    'native front/side result mapping preserves captured metadata and rejects incomplete payload',
    () async {
      const channel = MethodChannel('luvly/body-scan');
      final binding =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binding.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'estimateMeasurements');
        expect(call.arguments['heightCm'], 168);
        return {
          ...estimate.measurements,
          'heightCm': estimate.heightCm,
          'capturedAt': estimate.capturedAt,
          'methodVersion': estimate.methodVersion,
        };
      });
      addTearDown(() => binding.setMockMethodCallHandler(channel, null));
      final mapped = await const AvailableBodyScanner().estimateMeasurements(
        168,
      );
      expect(mapped!.toJson(), estimate.toJson());
      binding.setMockMethodCallHandler(channel, (_) async => {'Bust': 90});
      await expectLater(
        const AvailableBodyScanner().estimateMeasurements(168),
        throwsFormatException,
      );
    },
  );

  test(
    'API detects an old server dropping source metadata and retains revision for retry',
    () async {
      final client = MockClient((request) async {
        final sent = jsonDecode(request.body);
        final profile = Map<String, dynamic>.from(sent['profile']);
        profile.remove('measurementProvenance');
        return http.Response(
          jsonEncode({'revision': 2, 'profile': profile}),
          200,
        );
      });
      addTearDown(client.close);
      final transport = HttpPaymentApi(
        baseUrl: 'https://example.com',
        client: client,
        token: () async => 'owner-token',
      );
      final api = RecommendationApi(
        transport: WorkspaceApi(transport: transport),
      );
      final next = BridalPreferences(
        measurements: reviewed.measurements,
        measurementProvenance: reviewed.provenance,
      );
      await expectLater(
        api.save(
          const PreferenceRecord(1, BridalPreferences()),
          next,
          'save-review',
        ),
        throwsA(
          isA<PreferenceSaveFailure>().having(
            (e) => e.saved.revision,
            'saved revision',
            2,
          ),
        ),
      );
    },
  );
}
