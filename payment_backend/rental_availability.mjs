import {HttpError} from './payment_service.mjs';
import {peakUsage, rentalResources, variantId} from './rental_service.mjs';

// Read-only stock snapshot. Never expose allocations or another customer's data.
export function stockStatus(variant, dates, now) {
  if (!Number.isSafeInteger(variant?.quantity) || variant.quantity < 0) return 'Unconfirmed';
  return variant.quantity > peakUsage(variant.allocations, dates.startDay, dates.endDay, now)
    ? 'Available' : 'Unavailable';
}

export async function selectedAvailability(tx, selection, dates, now) {
  const rows = [];
  for (const g of selection.selectedGowns ?? []) {
    const d = await tx.get(`dresses/${g.dressId}`);
    const v = await tx.get(`rentalVariants/${variantId(g.dressId,g.size)}`);
    const status = d?.published === true && d.availability === 'Available' &&
      typeof d.sizes === 'string' && d.sizes.split(', ').includes(g.size)
      ? stockStatus(v, dates, now) : 'Unavailable';
    rows.push({name:g.name ?? d?.name ?? 'Gown', dressId:g.dressId, size:g.size, status});
  }
  for (const resource of rentalResources({accessories:selection.selectedAccessories})) {
    rows.push({name:resource.name, status:stockStatus(await tx.get(resource.path), dates, now)});
  }
  return rows;
}

export async function requireSelectedAvailability(tx, selection, dates, now) {
  const rows = await selectedAvailability(tx, selection, dates, now);
  if (rows.some(r => r.status === 'Unconfirmed')) throw new HttpError(409,'INVENTORY_NOT_CONFIGURED');
  if (rows.some(r => r.status !== 'Available')) throw new HttpError(409,'RENTAL_STOCK_UNAVAILABLE');
}
