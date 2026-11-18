const circumferenceLabels = ['Bust', 'Waist', 'Hips'];

bool measurementTime(Object? value) =>
    value is int && value > 0 && value <= 4102444800000;

/// Values from the existing two-view estimator, before the user edits them.
class BodyMeasurementEstimate {
  const BodyMeasurementEstimate({
    required this.measurements,
    required this.heightCm,
    required this.capturedAt,
    required this.methodVersion,
  });

  final Map<String, double> measurements;
  final double heightCm;
  final int capturedAt;
  final String methodVersion;

  bool get valid =>
      measurements.length == 3 &&
      circumferenceLabels.every((label) {
        final value = measurements[label];
        return value != null && value.isFinite && value >= 30 && value <= 300;
      }) &&
      heightCm.isFinite &&
      heightCm >= 120 &&
      heightCm <= 220 &&
      measurementTime(capturedAt) &&
      methodVersion == 'two-view-ellipse-v1';

  Map<String, dynamic> toJson() => {
    'measurements': {
      for (final label in circumferenceLabels) label: measurements[label],
    },
    'heightCm': heightCm,
    'capturedAt': capturedAt,
    'methodVersion': methodVersion,
  };

  factory BodyMeasurementEstimate.fromJson(Map<String, dynamic> json) {
    final values = json['measurements'];
    if (json.length != 4 ||
        values is! Map ||
        json['heightCm'] is! num ||
        json['capturedAt'] is! int ||
        json['methodVersion'] is! String ||
        values.values.any((value) => value is! num)) {
      throw const FormatException('Invalid measurement estimate');
    }
    final result = BodyMeasurementEstimate(
      measurements: values.map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
      heightCm: (json['heightCm'] as num).toDouble(),
      capturedAt: json['capturedAt'] as int,
      methodVersion: json['methodVersion'] as String,
    );
    if (!result.valid) {
      throw const FormatException('Invalid measurement estimate');
    }
    return result;
  }
}

/// The adopted numbers stay in BridalPreferences.measurements.
class MeasurementEvidence {
  const MeasurementEvidence({
    required this.source,
    required this.recordedAt,
    this.tapeCheckedAt,
  });
  final String source;
  final int recordedAt;
  final int? tapeCheckedAt;
  bool get fromCamera => source != 'user-entered';

  bool get valid =>
      const {
        'user-entered',
        'camera-reviewed',
        'camera-corrected',
      }.contains(source) &&
      measurementTime(recordedAt) &&
      (tapeCheckedAt == null ||
          measurementTime(tapeCheckedAt) && tapeCheckedAt! <= recordedAt) &&
      (!fromCamera || tapeCheckedAt != null);

  Map<String, dynamic> toJson() => {
    'source': source,
    'recordedAt': recordedAt,
    if (tapeCheckedAt != null) 'tapeCheckedAt': tapeCheckedAt,
  };

  factory MeasurementEvidence.fromJson(Map<String, dynamic> json) {
    if (!json.keys.every(
          const {'source', 'recordedAt', 'tapeCheckedAt'}.contains,
        ) ||
        json['source'] is! String ||
        json['recordedAt'] is! int ||
        json['tapeCheckedAt'] != null && json['tapeCheckedAt'] is! int) {
      throw const FormatException('Invalid measurement source');
    }
    final result = MeasurementEvidence(
      source: json['source'],
      recordedAt: json['recordedAt'],
      tapeCheckedAt: json['tapeCheckedAt'],
    );
    if (!result.valid) {
      throw const FormatException('Invalid measurement source');
    }
    return result;
  }
}

class MeasurementProvenance {
  const MeasurementProvenance({this.fields = const {}, this.scan});
  final Map<String, MeasurementEvidence> fields;
  final BodyMeasurementEstimate? scan;

  bool validFor(Map<String, double> measurements) {
    if (fields.length > 3 || scan != null && !scan!.valid) return false;
    for (final entry in fields.entries) {
      if (!circumferenceLabels.contains(entry.key) ||
          !measurements.containsKey(entry.key) ||
          !entry.value.valid) {
        return false;
      }
      if (entry.value.fromCamera) {
        if (scan == null ||
            entry.value.tapeCheckedAt! < scan!.capturedAt ||
            entry.value.recordedAt < scan!.capturedAt) {
          return false;
        }
        final corrected =
            measurements[entry.key] != scan!.measurements[entry.key];
        if (corrected != (entry.value.source == 'camera-corrected')) {
          return false;
        }
      }
    }
    final hasCamera = fields.values.any((entry) => entry.fromCamera);
    return hasCamera == (scan != null);
  }

  Map<String, dynamic> toJson() => {
    'fields': {
      for (final label in circumferenceLabels)
        if (fields.containsKey(label)) label: fields[label]!.toJson(),
    },
    if (scan != null) 'scan': scan!.toJson(),
  };

  factory MeasurementProvenance.fromJson(Map<String, dynamic> json) {
    if (!json.keys.every(const {'fields', 'scan'}.contains) ||
        json['fields'] is! Map) {
      throw const FormatException('Invalid measurement provenance');
    }
    return MeasurementProvenance(
      fields: (json['fields'] as Map).map(
        (key, value) => MapEntry(
          key as String,
          MeasurementEvidence.fromJson(Map<String, dynamic>.from(value)),
        ),
      ),
      scan: json['scan'] == null
          ? null
          : BodyMeasurementEstimate.fromJson(
              Map<String, dynamic>.from(json['scan']),
            ),
    );
  }

  MeasurementProvenance retained(Set<String> labels) {
    final next = Map<String, MeasurementEvidence>.fromEntries(
      fields.entries.where((entry) => labels.contains(entry.key)),
    );
    return MeasurementProvenance(
      fields: next,
      scan: next.values.any((entry) => entry.fromCamera) ? scan : null,
    );
  }

  MeasurementProvenance manual(
    String label, {
    required bool present,
    required int at,
  }) {
    final next = {...fields};
    if (present) {
      next[label] = MeasurementEvidence(source: 'user-entered', recordedAt: at);
    } else {
      next.remove(label);
    }
    return MeasurementProvenance(
      fields: next,
      scan: next.values.any((entry) => entry.fromCamera) ? scan : null,
    );
  }

  String get summary {
    if (fields.isEmpty) {
      return 'Measurement source was not recorded for this profile.';
    }
    final manual = fields.values.where((entry) => !entry.fromCamera).length;
    final camera = fields.length - manual;
    final corrected = fields.values.any(
      (entry) => entry.source == 'camera-corrected',
    );
    return [
      if (manual > 0) 'User-entered measurements',
      if (camera > 0)
        corrected
            ? 'Camera estimates corrected and reported checked with a tape'
            : 'Camera estimates reviewed and reported checked with a tape',
      if (fields.length < 3) 'Some measurement sources were not recorded',
    ].join(' · ');
  }
}

class ReviewedMeasurements {
  const ReviewedMeasurements(
    this.estimate,
    this.measurements,
    this.confirmedAt,
    this.tapeCheckedAt,
  );
  final BodyMeasurementEstimate estimate;
  final Map<String, double> measurements;
  final int confirmedAt, tapeCheckedAt;

  MeasurementProvenance get provenance => MeasurementProvenance(
    scan: estimate,
    fields: {
      for (final label in circumferenceLabels)
        label: MeasurementEvidence(
          source: measurements[label] == estimate.measurements[label]
              ? 'camera-reviewed'
              : 'camera-corrected',
          recordedAt: confirmedAt,
          tapeCheckedAt: tapeCheckedAt,
        ),
    },
  );
}
