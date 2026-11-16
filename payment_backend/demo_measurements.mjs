import { validateMeasurements } from './gown_measurements.mjs';

// Luvly university demo grading, NOT a supplier chart or measured garment.
// Centimetres; each centre has a narrow +/-2 cm illustrative body range.
const centres = {
  XXS: [78, 60, 86], XS: [82, 64, 90], S: [86, 68, 94],
  M: [92, 74, 100], L: [98, 80, 106], XL: [104, 86, 112],
  '2XL': [112, 94, 120], '3XL': [120, 102, 128],
  '4XL': [128, 110, 136], '5XL': [136, 118, 144],
};
export function demoMeasurements(size) {
  const c = centres[size];
  if (!c) return null; // Custom garments require an actual fitting.
  return validateMeasurements({ bustMin: c[0] - 2, bustMax: c[0] + 2,
    waistMin: c[1] - 2, waistMax: c[1] + 2, hipMin: c[2] - 2,
    hipMax: c[2] + 2, lengthCm: 150 });
}
export function withDemoMeasurements(old, size) {
  const measurements = demoMeasurements(size);
  if (old?.measurements != null || !measurements) return null;
  return { ...old, measurements, measurementSource: 'demo-reference',
    measurementNote: 'Illustrative body ranges; not garment measurements. Fitting required. Length is an illustrative hollow-to-hem reference, excluding train.',
    revision: (old?.revision ?? 0) + 1 };
}
