import { HttpError } from './payment_service.mjs';
export function validateMeasurements(value) {
  if (value === null) return null;
  const fields = ['bustMin', 'bustMax', 'waistMin', 'waistMax', 'hipMin', 'hipMax', 'lengthCm'];
  const valid = value && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === fields.length && fields.every(k => Object.hasOwn(value, k)) &&
    fields.every(k => typeof value[k] === 'number' && Number.isFinite(value[k]) &&
      value[k] >= 20 && value[k] <= 300 && Math.abs(value[k] * 10 - Math.round(value[k] * 10)) < 0.00001) &&
    ['bust', 'waist', 'hip'].every(k => value[k + 'Min'] <= value[k + 'Max']);
  if (!valid) throw new HttpError(400, 'INVALID_GOWN_MEASUREMENTS');
  return Object.fromEntries(fields.map(k => [k, value[k]]));
}
