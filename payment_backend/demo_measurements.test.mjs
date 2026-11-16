import test from 'node:test';
import assert from 'node:assert/strict';
import { demoMeasurements, withDemoMeasurements } from './demo_measurements.mjs';
test('demo grading is monotonic, valid and excludes custom sizes', () => {
  let last = 0;
  for (const size of ['XXS','XS','S','M','L','XL','2XL','3XL','4XL','5XL']) {
    const m = demoMeasurements(size);
    assert.ok(m.bustMin > last); last = m.bustMin;
    assert.equal(m.bustMax - m.bustMin, 4);
    assert.ok(m.waistMin < m.bustMin && m.hipMin > m.bustMin);
  }
  assert.equal(demoMeasurements('Made to measure'), null);
  assert.equal(demoMeasurements('bogus'), null);
});
test('seeding preserves physical inventory and never overwrites existing measurements', () => {
  const old = { quantity: 2, allocations: { held: { state: 'Held' } }, revision: 4, updatedBy: 'staff' };
  const next = withDemoMeasurements(old, 'M');
  assert.equal(next.quantity, 2);
  assert.deepEqual(next.allocations, old.allocations);
  assert.equal(next.updatedBy, 'staff');
  assert.equal(next.revision, 5);
  assert.equal(next.measurementSource, 'demo-reference');
  assert.equal(withDemoMeasurements(next, 'M'), null);
  assert.equal(Object.hasOwn(withDemoMeasurements(undefined, 'M'), 'quantity'), false);
  assert.equal(Object.hasOwn(old, 'measurements'), false);
});
