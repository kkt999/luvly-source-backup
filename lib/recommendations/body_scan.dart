import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ratios of detected joint spans in a front-facing image. No centimetres,
/// circumferences, body-shape diagnosis, or fitted garment size.
class BodyScan {
  const BodyScan({
    required this.shoulderHipRatio,
    required this.torsoShoulderRatio,
    required this.sampleCount,
    required this.durationMs,
    required this.relativeSpread,
    required this.capturedAt,
    this.algorithmVersion = 'joint-ratios-v1',
  });
  final double shoulderHipRatio, torsoShoulderRatio, relativeSpread;
  final int sampleCount, durationMs, capturedAt;
  final String algorithmVersion;
  bool get valid =>
      (algorithmVersion == 'joint-ratios-v1' ||
          algorithmVersion == 'joint-ratios-v2') &&
      shoulderHipRatio.isFinite &&
      shoulderHipRatio >= .6 &&
      shoulderHipRatio <= 2.4 &&
      torsoShoulderRatio.isFinite &&
      torsoShoulderRatio >= .5 &&
      torsoShoulderRatio <= 2.6 &&
      relativeSpread.isFinite &&
      relativeSpread >= 0 &&
      relativeSpread <= .035 &&
      sampleCount >= (algorithmVersion == 'joint-ratios-v2' ? 15 : 30) &&
      sampleCount <= 90 &&
      durationMs >= (algorithmVersion == 'joint-ratios-v2' ? 3000 : 2000) &&
      durationMs <= (algorithmVersion == 'joint-ratios-v2' ? 15000 : 10000) &&
      capturedAt >= 1 &&
      capturedAt <= 4102444800000;
  Map<String, dynamic> toJson() => {
    'algorithmVersion': algorithmVersion,
    'shoulderHipRatio': shoulderHipRatio,
    'torsoShoulderRatio': torsoShoulderRatio,
    'sampleCount': sampleCount,
    'durationMs': durationMs,
    'relativeSpread': relativeSpread,
    'capturedAt': capturedAt,
  };
  factory BodyScan.fromJson(Map<String, dynamic> d) {
    const keys = {
      'algorithmVersion',
      'shoulderHipRatio',
      'torsoShoulderRatio',
      'sampleCount',
      'durationMs',
      'relativeSpread',
      'capturedAt',
    };
    if (d.length != keys.length ||
        !d.keys.every(keys.contains) ||
        d['algorithmVersion'] is! String ||
        d['shoulderHipRatio'] is! num ||
        d['torsoShoulderRatio'] is! num ||
        d['relativeSpread'] is! num ||
        d['sampleCount'] is! int ||
        d['durationMs'] is! int ||
        d['capturedAt'] is! int) {
      throw const FormatException('Invalid scan result');
    }
    final result = BodyScan(
      algorithmVersion: d['algorithmVersion'],
      shoulderHipRatio: (d['shoulderHipRatio'] as num).toDouble(),
      torsoShoulderRatio: (d['torsoShoulderRatio'] as num).toDouble(),
      relativeSpread: (d['relativeSpread'] as num).toDouble(),
      sampleCount: d['sampleCount'],
      durationMs: d['durationMs'],
      capturedAt: d['capturedAt'],
    );
    if (!result.valid) {
      throw const FormatException('Scan did not meet stability checks');
    }
    return result;
  }
}

class BodyScanner {
  const BodyScanner();
  bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<Map<String, double>?> estimateMeasurements(double heightCm) async {
    if (!available || !heightCm.isFinite || heightCm < 120 || heightCm > 220) {
      throw PlatformException(code: 'SCAN_UNAVAILABLE');
    }
    final raw = await const MethodChannel('luvly/body-scan')
        .invokeMapMethod<String, dynamic>('estimateMeasurements', {
          'heightCm': heightCm,
        });
    if (raw == null) return null;
    const labels = ['Bust', 'Waist', 'Hips'];
    final measurements = <String, double>{};
    for (final label in labels) {
      final n = raw[label];
      if (n is! num || !n.isFinite || n < 30 || n > 300) {
        throw const FormatException('Invalid measurement estimate');
      }
      measurements[label] = n.toDouble();
    }
    return measurements;
  }

  Future<BodyScan?> scan() async {
    if (!available) {
      throw PlatformException(
        code: 'SCAN_UNAVAILABLE',
        message:
            'Body scanning is available in the Android app. You can enter measurements here.',
      );
    }
    final raw = await const MethodChannel(
      'luvly/body-scan',
    ).invokeMapMethod<String, dynamic>('scan');
    return raw == null ? null : BodyScan.fromJson(raw);
  }
}

/// Session-only repeatability information. This is not an accuracy score and
/// neither averages scans nor adds fields to the persisted private profile.
class BodyScanComparison {
  BodyScanComparison(BodyScan previous, BodyScan current)
    : shoulderHipDifference = _difference(
        previous.shoulderHipRatio,
        current.shoulderHipRatio,
      ),
      torsoShoulderDifference = _difference(
        previous.torsoShoulderRatio,
        current.torsoShoulderRatio,
      );
  final double shoulderHipDifference, torsoShoulderDifference;
  static double _difference(double a, double b) =>
      (a - b).abs() / ((a + b) / 2) * 100;
}
