export const scheduledServiceTypes = new Set([
  'makeup-hair', 'makeup-trial', 'second-beauty-look', 'portrait-session', 'extra-fitting',
]);
const accessoryTypes = new Set(['veil-rental', 'accessory-rental', 'veil-accessories', 'package-veil', 'item-priced-accessories', 'item-priced-veil']);
export const packageServiceTypes = new Set([
  'custom', 'extra-rental-day', ...scheduledServiceTypes, ...accessoryTypes,
]);

export const requiresServiceTiming = service =>
  scheduledServiceTypes.has(service.serviceType ?? service.id);
export const accessoryPricing = service => ({
  'package-veil': 'package',
  'item-priced-accessories': 'per-item',
  'item-priced-veil': 'per-item',
})[service.serviceType] ?? 'allowance';
export const requiresAccessorySelection = service =>
  accessoryTypes.has(service.serviceType ?? service.id);
export const addsRentalDay = service => service.serviceType === undefined
  ? /extra.*rental.*day|additional.*rental.*day/i.test(service.name)
  : service.serviceType === 'extra-rental-day';

export function accessoryCategories(service) {
  if (service.serviceType === undefined) {
    return { veils: /veil/i.test(service.name), jewellery: /accessor|jewel|tiara/i.test(service.name) };
  }
  return {
    veils: ['veil-rental', 'veil-accessories', 'package-veil', 'item-priced-veil'].includes(service.serviceType),
    jewellery: ['accessory-rental', 'veil-accessories', 'item-priced-accessories'].includes(service.serviceType),
  };
}

export function canOfferStandalone(entry) {
  return ['custom', 'makeup-hair', 'makeup-trial', 'portrait-session'].includes(entry.serviceType) &&
    ['fixed', 'per-session'].includes(entry.method);
}
