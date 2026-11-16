import { readFileSync } from 'node:fs';
import { HttpError } from './payment_service.mjs';
import { accessoryCategories } from './package_service_types.mjs';
export const accessoryCatalogue = JSON.parse(readFileSync(new URL('../assets/images/accessory-catalogue.json', import.meta.url), 'utf8'));
// Versioned sample catalogue: no assertion of physical stock or precious materials.
export function accessoryService(s) {
  const { veils, jewellery } = accessoryCategories(s);
  return veils || jewellery;
}
export function priceAccessories(services, input = [], version) {
  const fail = (condition, code = 'INVALID_ACCESSORY_SELECTION') => {
    if (!condition) throw new HttpError(409, code);
  };
  fail(Array.isArray(input) && input.length <= 24);
  if (input.length) fail(version === accessoryCatalogue.version, 'ACCESSORY_CATALOGUE_CHANGED');
  const seen = new Set();
  const selectedAccessories = input.map(row => {
    fail(row && typeof row === 'object' && !Array.isArray(row) &&
      Object.keys(row).every(k => ['serviceId', 'itemId'].includes(k)));
    const service = services.find(s => s.id === row.serviceId);
    const item = accessoryCatalogue.items.find(i => i.id === row.itemId);
    fail(service && accessoryService(service) && item && !seen.has(item.id));
    const { veils, jewellery } = accessoryCategories(service);
    fail(item.category === 'Veils' ? veils : jewellery);
    seen.add(item.id);
    return { ...item, serviceId: service.id, serviceName: service.name, sample: true, rentalDays: 3 };
  });
  const accessoryCharges = services.filter(accessoryService).map(service => {
    const items = selectedAccessories.filter(i => i.serviceId === service.id);
    const retailCents = items.reduce((sum, i) => sum + i.priceCents, 0);
    // Service price is already present in the package. Only the excess is extra.
    const allowanceCents = service.accessoryAllowanceCents ?? service.priceCents;
    return { serviceId: service.id, serviceName: service.name, retailCents, allowanceCents,
      appliedAllowanceCents: Math.min(retailCents, allowanceCents),
      extraCents: Math.max(0, retailCents - allowanceCents) };
  });
  return { selectedAccessories, accessoryCharges, accessoryExtraCents: accessoryCharges.reduce((n, c) => n + c.extraCents, 0),
    accessoryCatalogueVersion: accessoryCatalogue.version, accessoryCatalogueSample: true };
}
