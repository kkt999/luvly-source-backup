import { accessoryService } from './accessory_catalogue.mjs';
import { HttpError } from './payment_service.mjs';

const approved = new Map([
  ['bridal-essentials', {
    price: 82900,
    legacy: ['veil-rental', 'accessory-rental'],
    description: 'A wedding gown rental with a personal fitting and standard veil. Choose bridal accessories to complete your look.',
  }],
  ['signature-bridal', {
    price: 172900,
    legacy: ['veil-accessories'],
    description: 'A wedding gown rental with a styling consultation, two fittings and a standard veil. Customize your bridal makeup and accessories.',
  }],
  ['luxe-bridal', {
    price: 287900,
    legacy: ['veil-accessories'],
    description: 'Two wedding gown rentals with styling, three fittings and a standard veil. Customize your bridal makeup, accessories and portrait session.',
  }],
]);

export function approvedPackagePricing(pkg) {
  const plan = approved.get(pkg?.id);
  if (!plan) throw new HttpError(404, 'APPROVED_PACKAGE_PRICING_UNAVAILABLE');
  const replace = new Set([...plan.legacy, 'veil-rental', 'accessory-rental']);
  if (pkg.services.some(service => accessoryService(service) !== replace.has(service.id)))
    throw new HttpError(409, 'APPROVED_PACKAGE_SERVICES_CHANGED');
  return {
    ...pkg,
    description: plan.description,
    basePriceCents: plan.price,
    services: [
      ...pkg.services.filter(service => !replace.has(service.id)),
      { id: 'veil-rental', name: 'Veil Rental', kind: 'Optional', priceCents: 8000,
        serviceType: 'package-veil', standardVeilId: 'veil-short',
        description: 'Standard veil included. Choose an available upgrade or remove the veil.' },
      { id: 'accessory-rental', name: 'Bridal Accessories', kind: 'Add-on', priceCents: 0,
        serviceType: 'item-priced-accessories',
        description: 'Optional. Pay the catalogue rental price for your selected accessories.' },
    ],
  };
}
