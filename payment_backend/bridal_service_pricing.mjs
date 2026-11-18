import { HttpError } from './payment_service.mjs';
import { accessoryCatalogue, standardVeilFor } from './accessory_catalogue.mjs';
import { packageServiceTypes, canOfferStandalone } from './package_service_types.mjs';
import { MAX_PACKAGE_GOWNS } from './package_gown_catalogue.mjs';

export const isMoney = value => Number.isSafeInteger(value) && value >= 0 && value <= 100000000;
export const isPricingId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(value);
export const checkPricing = (condition, code, status = 400) => {
  if (!condition) throw new HttpError(status, code);
};
export const standardGownAllowanceId = 'standard-gown-allowance';
const methods = new Set(['fixed', 'per-session', 'per-day', 'per-gown']);
const validText = (value, min, max) => typeof value === 'string' &&
  value.length >= min && value.length <= max && value.trim() === value && !/[\x00-\x1f\x7f]/.test(value);

export async function requirePricingManager(reader, uid) {
  const actor = await reader.get(`staff/${uid}`);
  checkPricing(actor?.active === true && actor.role === 'manager', 'MANAGER_REQUIRED', 403);
}

export class BridalServiceCatalogue {
  constructor(store, now = Date.now) {
    Object.assign(this, {store, now});
  }

  async list(uid) {
    await requirePricingManager(this.store, uid);
    const services = await this.store.list('bridalServicePrices');
    return {services: services.sort((a, b) => a.name.localeCompare(b.name)), limited: services.length >= 100};
  }

  async save(uid, input) {
    return this.store.atomic(async tx => {
      await requirePricingManager(tx, uid);
      const {id, revision, name, description, serviceType, method, priceCents, active, customEligible = true, standaloneEligible: requestedStandalone} = input ?? {};
      checkPricing(isPricingId(id) && Number.isSafeInteger(revision) && revision >= 0 &&
        validText(name, 2, 100) && validText(description, 0, 300) &&
        packageServiceTypes.has(serviceType) &&
        !['package-veil', 'item-priced-accessories', 'item-priced-veil', 'veil-rental', 'accessory-rental', 'veil-accessories'].includes(serviceType) &&
        methods.has(method) && (serviceType === 'extra-rental-day') === (method === 'per-day') &&
        isMoney(priceCents) && typeof active === 'boolean' && typeof customEligible === 'boolean', 'INVALID_BRIDAL_SERVICE_PRICE');
      checkPricing(id !== standardGownAllowanceId || (serviceType === 'custom' && method === 'per-gown' &&
        customEligible === false && priceCents > 0), 'INVALID_BRIDAL_SERVICE_PRICE');
      const path = `bridalServicePrices/${id}`;
      const previous = await tx.get(path);
      checkPricing((previous?.revision ?? 0) === revision, 'BRIDAL_SERVICE_PRICE_CHANGED', 409);
      const standaloneEligible = requestedStandalone === undefined
        ? previous?.standaloneEligible === true : requestedStandalone;
      checkPricing(typeof standaloneEligible === 'boolean' && (!standaloneEligible ||
        (id !== standardGownAllowanceId && customEligible && canOfferStandalone({serviceType, method}))),
        'INVALID_STANDALONE_ELIGIBILITY');
      const updatedAt = this.now();
      const next = {id, name, description, serviceType, method, priceCents, active, customEligible, standaloneEligible,
        revision: revision + 1, createdAt: previous?.createdAt ?? updatedAt,
        createdBy: previous?.createdBy ?? uid, updatedAt, updatedBy: uid};
      tx.set(path, next);
      tx.set(`${path}/revisions/${next.revision}`, next);
      return next;
    });
  }
}

export function applyBundleDiscount(subtotalCents, discount) {
  checkPricing(isMoney(subtotalCents), 'PACKAGE_PRICE_LIMIT');
  const {kind, value} = discount ?? {kind: 'fixed', value: 0};
  checkPricing(isMoney(value) && (kind === 'fixed' || kind === 'percent' && value <= 10000),
    'INVALID_BUNDLE_DISCOUNT');
  const discountCents = kind === 'fixed' ? value : Math.round(subtotalCents * value / 10000);
  checkPricing(discountCents <= subtotalCents, 'INVALID_BUNDLE_DISCOUNT');
  return {subtotalCents, discountCents, sellingPriceCents: subtotalCents - discountCents};
}

// Resolve current catalogue values only for draft calculation or publication.
// Published packages retain this priced snapshot.
export async function resolvePackagePricing(reader, config) {
  const {components, bundleDiscount, gownPrices = [], useStandardGownAllowance} = config.pricing;
  const count = config.includedGownCount ?? 0;
  const useAllowance = useStandardGownAllowance === true;
  checkPricing(Number.isSafeInteger(count) && count >= 0 && count <= MAX_PACKAGE_GOWNS &&
    (useStandardGownAllowance === undefined || useAllowance), 'INVALID_PACKAGE_GOWN_PRICING');
  checkPricing(Array.isArray(components) && components.length <= 12 &&
    Array.isArray(gownPrices) && gownPrices.length === (useAllowance ? 0 : count),
    'PACKAGE_PRICING_CONFIGURATION_REQUIRED');
  const services = [...config.services];
  const covered = new Set();
  const pricedIds = new Set();
  const lines = [];
  for (const component of components) {
    const {serviceId, catalogueId, revision, quantity} = component ?? {};
    const index = services.findIndex(service => service.id === serviceId);
    const service = services[index];
    checkPricing(service && !covered.has(serviceId) && !pricedIds.has(catalogueId) && isPricingId(catalogueId) && catalogueId !== standardGownAllowanceId &&
      Number.isSafeInteger(quantity) && quantity >= 1 && quantity <= 12, 'INVALID_PACKAGE_COMPONENT');
    const entry = await reader.get(`bridalServicePrices/${catalogueId}`);
    checkPricing(entry?.active && entry.revision === revision, 'BRIDAL_SERVICE_PRICE_CHANGED', 409);
    checkPricing(service.serviceType === entry.serviceType &&
      (entry.method === 'per-session' || quantity === 1) &&
      (entry.method !== 'per-gown' || config.includedGownCount > 0), 'INVALID_PACKAGE_COMPONENT');
    const units = entry.method === 'per-gown' ? config.includedGownCount : quantity;
    const amountCents = units * entry.priceCents;
    checkPricing(isMoney(amountCents), 'PACKAGE_PRICE_LIMIT');
    covered.add(serviceId);
    pricedIds.add(catalogueId);
    lines.push({serviceId, catalogueId, revision, quantity: units, kind: service.kind,
      name: entry.name, unitPriceCents: entry.priceCents, amountCents});
    services[index] = {...service, name: entry.name, description: entry.description,
      ...(service.kind === 'Add-on' ? {priceCents: amountCents} : {})};
  }
  for (const service of services) {
    if (covered.has(service.id)) continue;
    if (service.serviceType === 'item-priced-accessories') continue;
    checkPricing(service.serviceType !== 'item-priced-veil', 'INVALID_PACKAGE_COMPONENT');
    const item = standardVeilFor(service);
    checkPricing(item, 'PACKAGE_PRICING_CONFIGURATION_REQUIRED', 409);
    lines.push({serviceId: service.id, itemId: item.id, revision: accessoryCatalogue.version,
      name: item.name, quantity: 1, kind: service.kind, unitPriceCents: item.priceCents,
      amountCents: item.priceCents});
  }
  const gownLines = [];
  if (useAllowance && count > 0) {
    const allowance = await reader.get(`bridalServicePrices/${standardGownAllowanceId}`);
    checkPricing(allowance?.active === true && allowance.method === 'per-gown' &&
      isMoney(allowance.priceCents) && allowance.priceCents > 0, 'PACKAGE_GOWN_ALLOWANCE_REQUIRED', 409);
    gownLines.push({catalogueId: standardGownAllowanceId, revision: allowance.revision,
      name: allowance.name, quantity: count, unitPriceCents: allowance.priceCents,
      amountCents: count * allowance.priceCents});
  }
  for (const gown of gownPrices) {
    checkPricing(isPricingId(gown?.dressId) &&
      (config.allCatalogueGowns || config.eligibleDressIds?.includes(gown.dressId)) &&
      !gownLines.some(line => line.itemId === gown.dressId), 'INVALID_PACKAGE_GOWN_PRICING');
    const dress = await reader.get(`dresses/${gown.dressId}`);
    checkPricing(dress?.published === true && dress.availability === 'Available' &&
      dress.revision === gown.revision, 'PACKAGE_GOWN_CHANGED', 409);
    checkPricing(isMoney(dress.priceCents) && dress.priceCents > 0, 'PACKAGE_GOWN_PRICE_REQUIRED', 409);
    gownLines.push({itemId: gown.dressId, revision: dress.revision, name: dress.name,
      quantity: 1, unitPriceCents: dress.priceCents, amountCents: dress.priceCents});
  }
  const subtotal = [...lines.filter(line => line.kind !== 'Add-on'), ...gownLines]
    .reduce((sum, line) => sum + line.amountCents, 0);
  const breakdown = applyBundleDiscount(subtotal, bundleDiscount);
  return {services, basePriceCents: breakdown.sellingPriceCents,
    pricingSnapshot: {...breakdown, lines, gownLines, bundleDiscount: bundleDiscount ?? {kind: 'fixed', value: 0}}};
}
