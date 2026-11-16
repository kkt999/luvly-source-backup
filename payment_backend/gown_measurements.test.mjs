import test from 'node:test';
import assert from 'node:assert/strict';
import { validateMeasurements } from './gown_measurements.mjs';
const valid = { bustMin:80, bustMax:90.5, waistMin:60, waistMax:70, hipMin:90, hipMax:100, lengthCm:150 };
test('complete gown size ranges accept one decimal and inclusive equal boundaries', () => {
  assert.deepEqual(validateMeasurements(valid), valid);
  assert.equal(validateMeasurements(null), null);
  assert.equal(validateMeasurements({...valid,bustMin:90.5}).bustMin, 90.5);
});
test('invalid, partial, reversed, non-finite or forged measurement data is rejected', () => {
  for (const x of [{},[],undefined,{...valid, extra:true},{...valid,bustMin:91},{...valid,lengthCm:301},
    {...valid,hipMin:'90'},{...valid,waistMin:NaN},{...valid,waistMax:Infinity},{...valid,lengthCm:140.11},
    {...valid,bustMin:19}]) assert.throws(() => validateMeasurements(x), e => e.code === 'INVALID_GOWN_MEASUREMENTS');
});
