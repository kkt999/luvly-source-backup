import { variantId } from './rental_service.mjs';

// A request-size ceiling. The catalogue and stock determine the usable limit.
export const MAX_PACKAGE_GOWNS = 100;

export function rentableSizes(dress) {
  if (dress?.published !== true || dress.availability !== 'Available' || typeof dress.sizes !== 'string') return [];
  return dress.sizes.split(', ').filter(size => size && size !== 'Made to measure');
}

export async function packageGownRows(tx, pkg) {
  if (!pkg.includedGownCount) return [];
  if (pkg.allCatalogueGowns) return (await tx.listDresses()).filter(dress => rentableSizes(dress).length > 0);
  const ids = pkg.eligibleDressIds ?? [];
  return (await Promise.all(ids.map(async id => {
    const dress = await tx.get(`dresses/${id}`);
    return dress ? { ...dress, id } : null;
  }))).filter(Boolean);
}

export async function countStockedGowns(tx, gowns, stopAt = MAX_PACKAGE_GOWNS) {
  let count = 0;
  for (let start = 0; start < gowns.length && count < stopAt; start += 20) {
    const stocked = await Promise.all(gowns.slice(start, start + 20).map(async dress => {
      const variants = await Promise.all(rentableSizes(dress)
        .map(size => tx.get(`rentalVariants/${variantId(dress.id, size)}`)));
      return variants.some(variant => Number.isSafeInteger(variant?.quantity) && variant.quantity > 0);
    }));
    count += stocked.filter(Boolean).length;
  }
  return Math.min(count, stopAt);
}
