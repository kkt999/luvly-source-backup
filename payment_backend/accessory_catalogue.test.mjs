import test from 'node:test';
import assert from 'node:assert/strict';
import { priceAccessories, accessoryCatalogue } from './accessory_catalogue.mjs';
const service = { id: 'accessory', name: 'Bridal accessory rental', priceCents: 7000 };
const veil = { id: 'veil', name: 'Veil rental', priceCents: 8000 };
const pick = itemId => ({ serviceId: 'accessory', itemId });
test('catalogue has distinct product names, pictures, 6 categories and sensible integer prices', () => {
  const items = accessoryCatalogue.items;
  assert.equal(items.length, 11);
  assert.equal(new Set(items.map(i => i.category)).size, 6);
  assert.equal(new Set(items.map(i => i.id)).size, items.length);
  for (const i of items) assert(i.name && i.image && i.description && i.material && i.size && Number.isSafeInteger(i.priceCents) && i.priceCents > 0);
});
test('allowance is charged once; extra = selected value minus included allowance', () => {
  const p = priceAccessories([service], [pick('tiara'), pick('necklace-floral')], 1);
  assert.equal(p.accessoryExtraCents, 4500);
  assert.equal(p.accessoryCharges[0].appliedAllowanceCents, 7000);
  assert.equal(p.selectedAccessories[0].sample, true);
  assert.equal(p.selectedAccessories[0].rentalDays, 3);
  assert.equal(priceAccessories([service], [pick('necklace-pearl')], 1).accessoryExtraCents, 0);
  assert.equal(priceAccessories([service], [], 1).accessoryExtraCents, 0);
});
test('veil allowance does not pay for jewellery; premium veil adds only RM50', () => {
  assert.equal(priceAccessories([veil], [{serviceId: 'veil', itemId: 'veil-long'}], 1).accessoryExtraCents, 5000);
  assert.throws(() => priceAccessories([veil], [{serviceId:'veil', itemId:'ring-halo'}], 1));
  assert.throws(() => priceAccessories([service], [pick('veil-short')], 1));
});

test('customer example: RM35 ring plus RM25 necklace and RM80 veil are included; only excess changes RM899', () => {
  const selected=[pick('ring-halo'),pick('necklace-pearl'),{serviceId:'veil',itemId:'veil-short'}];
  const quote=priceAccessories([service,veil],selected,1);
  assert.equal(quote.accessoryExtraCents,0);
  assert.equal(89900+quote.accessoryExtraCents,89900);
  const upgraded=priceAccessories([service,veil],[...selected,pick('necklace-floral')],1);
  assert.equal(89900+upgraded.accessoryExtraCents,94900);
});
test('removed service, unknown items, duplicates, stale catalogue and forged price rejected', () => {
  assert.throws(() => priceAccessories([], [pick('ring-halo')], 1));
  assert.throws(() => priceAccessories([service], [pick('unknown')], 1));
  assert.throws(() => priceAccessories([service], [pick('ring-halo'),pick('ring-halo')], 1));
  assert.throws(() => priceAccessories([service], [pick('ring-halo')], 2), e => e.code === 'ACCESSORY_CATALOGUE_CHANGED');
  assert.throws(() => priceAccessories([service], [{...pick('ring-halo'), priceCents: 1}], 1));
});

test('a combined allowance covers both veils and jewellery exactly once', () => {
  const combined = { id: 'combined', name: 'Veil and accessory set rental', priceCents: 15000 };
  const pickCombined = itemId => ({ serviceId: combined.id, itemId });
  const picks = [pickCombined('veil-short'), pickCombined('ring-halo')];
  const included = priceAccessories([combined], picks, 1);
  assert.equal(included.selectedAccessories.length, 2);
  assert.equal(included.accessoryExtraCents, 0);
  const premium = priceAccessories([combined], [pickCombined('veil-long'), picks[1]], 1);
  assert.equal(premium.accessoryExtraCents, 1500);
});
