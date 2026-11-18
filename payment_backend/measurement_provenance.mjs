const labels = ['Bust', 'Waist', 'Hips'];
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const only = (value, keys) => object(value) && Object.keys(value).every(key => keys.includes(key));
const time = value => Number.isSafeInteger(value) && value > 0 && value <= 4102444800000;
const number = (value, lo, hi) => typeof value === 'number' && Number.isFinite(value) && value >= lo && value <= hi;

function validEstimate(scan) {
  return only(scan, ['measurements', 'heightCm', 'capturedAt', 'methodVersion']) &&
    only(scan.measurements, labels) && Object.keys(scan.measurements).length === 3 &&
    labels.every(label => number(scan.measurements[label], 30, 300)) &&
    number(scan.heightCm, 120, 220) && time(scan.capturedAt) &&
    scan.methodVersion === 'two-view-ellipse-v1';
}

export function validMeasurementProvenance(provenance, measurements) {
  if (provenance === undefined) return true;
  if (!only(provenance, ['fields', 'scan']) || !only(provenance.fields, labels)) return false;
  const scan = provenance.scan;
  if (scan !== undefined && !validEstimate(scan)) return false;
  let hasCamera = false;
  for (const [label, evidence] of Object.entries(provenance.fields)) {
    if (!(label in measurements) ||
        !only(evidence, ['source', 'recordedAt', 'tapeCheckedAt']) ||
        !['user-entered', 'camera-reviewed', 'camera-corrected'].includes(evidence.source) ||
        !time(evidence.recordedAt) ||
        evidence.tapeCheckedAt !== undefined &&
          (!time(evidence.tapeCheckedAt) || evidence.tapeCheckedAt > evidence.recordedAt)) {
      return false;
    }
    if (evidence.source !== 'user-entered') {
      hasCamera = true;
      if (!scan || !time(evidence.tapeCheckedAt) ||
          evidence.tapeCheckedAt < scan.capturedAt ||
          evidence.recordedAt < scan.capturedAt ||
          (measurements[label] !== scan.measurements[label]) !==
            (evidence.source === 'camera-corrected')) return false;
    }
  }
  return hasCamera === (scan !== undefined);
}

/// An older client may save preferences without understanding source metadata.
/// Retain evidence only for unchanged numbers; changed numbers lose old claims.
export function retainMeasurementProvenance(previous, next) {
  if ('measurementProvenance' in next || !previous?.measurementProvenance) return next;
  const prior = previous.measurementProvenance;
  const fields = Object.fromEntries(Object.entries(prior.fields)
    .filter(([label]) => next.measurements[label] === previous.measurements[label]));
  if (!Object.keys(fields).length) return next;
  const hasCamera = Object.values(fields).some(evidence => evidence.source !== 'user-entered');
  return {...next, measurementProvenance: {
    fields, ...(hasCamera && {scan: prior.scan}),
  }};
}
