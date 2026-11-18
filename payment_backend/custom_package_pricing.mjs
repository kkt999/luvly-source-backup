import {canOfferStandalone} from './package_service_types.mjs';
import {malaysiaDay} from './booking_dates.mjs';
import { accessoryCatalogue } from './accessory_catalogue.mjs';
import { applyBundleDiscount, checkPricing, isMoney, isPricingId } from './bridal_service_pricing.mjs';
import { MAX_PACKAGE_GOWNS } from './package_gown_catalogue.mjs';

export const customPackageId = 'custom-bridal';
const catalogueProductServices = [
  {id: 'custom-veil', name: 'Veil Rental', description: '', serviceType: 'item-priced-veil'},
  {id: 'custom-accessories', name: 'Bridal Accessories', description: '', serviceType: 'item-priced-accessories'},
];

export function standaloneAppointmentType(services) {
  if (services.length !== 1 || services[0].quantity !== 1) return null;
  const service = services[0];
  if (service.serviceType === 'makeup-trial') return 'Makeup Trial';
  if (service.id === 'consultation' && service.serviceType === 'custom') return 'Bridal Consultation';
  return null;
}

export function validateCustomEventPlan(plan, now) {
  const day = plan?.eventDate;
  const time = typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day) ? Date.parse(day+'T00:00:00Z') : NaN;
  checkPricing(plan && Object.keys(plan).length === 1 && Number.isFinite(time) &&
    new Date(time).toISOString().slice(0,10) === day &&
    day >= malaysiaDay(now) && day <= malaysiaDay(now + 365 * 86400000), 'INVALID_CUSTOM_EVENT_DATE');
}
export async function customPackageOptions(store, uid) {
  const [staff, bride] = await Promise.all([store.get(`staff/${uid}`), store.get(`brides/${uid}`)]);
  checkPricing(!staff && bride, 'BRIDE_REQUIRED', 403);
  const services = (await store.list('bridalServicePrices')).filter(entry => entry.active && entry.customEligible !== false)
    .map(entry => {
      const {id, name, description, priceCents, revision, serviceType, method} = entry;
      return {id, name, description, priceCents, revision, serviceType, method,
        standaloneEligible: entry.standaloneEligible === true && canOfferStandalone(entry)};
    });
  return {maxGowns: MAX_PACKAGE_GOWNS, services, accessoryCatalogueVersion: accessoryCatalogue.version};
}

export async function resolveCustomPackage(tx, gowns, options) {
  checkPricing(Array.isArray(options) && options.length <= 10 && (gowns.length > 0 || options.length > 0), 'INVALID_CUSTOM_PACKAGE');
  const services = [];
  const lines = [];
  const gownLines = [];
  for (const g of gowns) {
    const dress = await tx.get(`dresses/${g.dressId}`);
    checkPricing(dress?.published && dress.availability === 'Available' &&
      dress.revision === g.revision, 'PACKAGE_GOWN_CHANGED', 409);
    checkPricing(isMoney(dress.priceCents) && dress.priceCents > 0, 'PACKAGE_GOWN_PRICE_REQUIRED', 409);
    gownLines.push({itemId: g.dressId, revision: dress.revision, name: dress.name,
      size: g.size, quantity: 1, unitPriceCents: dress.priceCents, amountCents: dress.priceCents});
  }
  for (const option of options) {
    checkPricing(isPricingId(option?.id) && !services.some(s => s.id === option.id) &&
      !catalogueProductServices.some(s => s.id === option.id) &&
      Number.isSafeInteger(option.revision) && Number.isSafeInteger(option.quantity) &&
      option.quantity >= 1 && option.quantity <= 12, 'INVALID_CUSTOM_PACKAGE_SERVICE');
    const entry = await tx.get(`bridalServicePrices/${option.id}`);
    checkPricing(entry?.active && entry.customEligible !== false && entry.revision === option.revision, 'BRIDAL_SERVICE_PRICE_CHANGED', 409);
    checkPricing(gowns.length > 0 || entry.standaloneEligible === true && canOfferStandalone(entry),
      'CUSTOM_SERVICE_REQUIRES_GOWN', 409);
    checkPricing(entry.method === 'per-session' || option.quantity === 1, 'INVALID_CUSTOM_PACKAGE_SERVICE');
    const quantity = entry.method === 'per-gown' ? gowns.length : option.quantity;
    const amountCents = quantity * entry.priceCents;
    checkPricing(isMoney(amountCents), 'PACKAGE_PRICE_LIMIT');
    services.push({id: entry.id, name: entry.name, description: entry.description,
      serviceType: entry.serviceType, kind: 'Required', priceCents: 0, quantity});
    lines.push({serviceId: entry.id, revision: entry.revision, name: entry.name, quantity,
      unitPriceCents: entry.priceCents, amountCents});
  }
  services.push(...catalogueProductServices.map(service => ({...service, kind: 'Add-on', priceCents: 0})));
  const subtotal = [...lines, ...gownLines].reduce((sum, row) => sum + row.amountCents, 0);
  const breakdown = applyBundleDiscount(subtotal);
  return {id: customPackageId, revision: 1, name: 'Custom bridal package',
    description: 'Your selection of gowns, services and rental accessories.',
    active: true, includedGownCount: gowns.length, allCatalogueGowns: true,
    pricingModel: 'custom', basePriceCents: subtotal, services,
    pricingSnapshot: {...breakdown, gownLines, lines}};
}
