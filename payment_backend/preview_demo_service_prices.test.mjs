import test from 'node:test';
import assert from 'node:assert/strict';
import { previewDemoServicePrices } from './preview_demo_service_prices.mjs';

test('empty demo preview proposes only supported inventory-independent rates', () => {
  const preview = previewDemoServicePrices([]);
  const services = preview.recommendations.map(row => row.service);
  assert.deepEqual(services.map(row => [row.id, row.priceCents, row.method]), [
    ['consultation', 10000, 'fixed'], ['extra-fitting', 8000, 'per-session'],
    ['makeup-hair', 50000, 'fixed'], ['makeup-trial', 20000, 'fixed'],
    ['extra-rental-day', 10000, 'per-day'],
  ]);
  assert.equal(preview.standaloneVeil.currentPriceCents, 8000);
  assert.equal(preview.standaloneVeil.action, 'keep-existing-item');
});

test('existing IDs, aliases and supported categories are preserved without duplicate or price changes', () => {
  const original = [
    {id:'personal-planning', name:'Bridal styling consultation', serviceType:'custom', priceCents:13000},
    {id:'makeup-hair', name:'Wedding makeup', serviceType:'makeup-hair', priceCents:42500},
    {id:'artist-preview', name:'Artist preview', serviceType:'makeup-trial', priceCents:22000, active:false},
  ];
  const rows = previewDemoServicePrices(original).recommendations;
  assert.deepEqual(rows.filter(row => row.action === 'keep-existing').map(row => row.existing[0].priceCents),
    [13000, 42500, 22000]);
  const first = previewDemoServicePrices([]);
  assert.ok(previewDemoServicePrices(first.recommendations.map(row => row.service))
    .recommendations.every(row => row.action === 'keep-existing'));
});
