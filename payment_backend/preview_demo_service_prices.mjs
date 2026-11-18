import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { standardVeilFor } from './accessory_catalogue.mjs';

const standard = [
  { id: 'consultation', name: 'Bridal Consultation', priceCents: 10000, serviceType: 'custom', method: 'fixed',
    description: 'One bridal planning consultation.',
    aliases: ['bridal consultation', 'consultation', 'styling consultation', 'bridal styling consultation'] },
  { id: 'extra-fitting', name: 'Additional Fitting Session', priceCents: 8000, serviceType: 'extra-fitting', method: 'per-session',
    description: 'An additional fitting session. The standard fitting booking fee is handled separately.',
    aliases: ['fitting session', 'additional fitting session', 'additional fitting', 'extra fitting session', 'extra fitting'] },
  { id: 'makeup-hair', name: 'Bridal Makeup & Hairstyling', priceCents: 50000, serviceType: 'makeup-hair', method: 'fixed',
    description: 'One complete wedding-day makeup and hairstyling look.',
    aliases: ['bridal makeup and hairstyling', 'bridal makeup and hair', 'bridal makeup and hair styling',
      'wedding day makeup and hair', 'wedding day makeup and hairstyling'] },
  { id: 'makeup-trial', name: 'Makeup & Hairstyle Trial', priceCents: 20000, serviceType: 'makeup-trial', method: 'fixed',
    description: 'One pre-wedding makeup and hairstyle trial.',
    aliases: ['makeup and hairstyle trial', 'makeup and hairstyling trial', 'makeup and hair trial',
      'makeup trial', 'bridal makeup trial', 'pre wedding makeup and hair trial'] },
  { id: 'extra-rental-day', name: 'Additional Rental Day', priceCents: 10000, serviceType: 'extra-rental-day', method: 'per-day',
    description: 'One additional rental day.',
    aliases: ['additional rental day', 'one additional rental day', 'extra rental day'] },
];

const normalize = text => String(text ?? '').toLowerCase().replace(/&/g, ' and ')
  .replace(/[^a-z0-9]+/g, ' ').trim();

export function previewDemoServicePrices(existing) {
  if (!Array.isArray(existing) || existing.some(row => typeof row?.id !== 'string' ||
      typeof row?.name !== 'string' || !Number.isSafeInteger(row.priceCents))) {
    throw new Error('Provide a Manager catalogue export with service IDs, names and prices in cents.');
  }
  const recommendations = standard.map(({aliases, ...service}) => {
    const matches = existing.filter(row => row.id === service.id || aliases.includes(normalize(row.name)) ||
      service.serviceType !== 'custom' && row.serviceType === service.serviceType);
    if (matches.length) return {
      action: 'keep-existing', name: service.name,
      existing: matches.map(({id, name, priceCents, active}) => ({id, name, priceCents, active})),
    };
    return {action: 'propose-create', service: {...service, revision: 0, active: true, customEligible: true}};
  });
  const veil = standardVeilFor({standardVeilId: 'veil-short'});
  return {
    scope: 'Development or staging review only. Preview generates no writes.',
    recommendations,
    standaloneVeil: {
      action: 'keep-existing-item',
      itemId: 'veil-short',
      currentPriceCents: veil?.priceCents ?? null,
      proposedPriceCents: 8000,
    },
    requiresBusinessDecision: [
      'Bridal Makeup Only (RM350) and Bridal Hairstyling Only (RM200) were not proposed as separate entries. Existing scheduled categories support the combined look and trial.',
      'The standard gown allowance requires an approved amount. No gown or accessory charge was proposed.',
      'The trial booking flow continues to collect its existing RM50 fitting fee. The RM80 recommendation is for an additional fitting service.',
    ],
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [, , flag, filename, ...rest] = process.argv;
  if (flag !== '--catalogue' || !filename || rest.length) {
    throw new Error('Usage: node payment_backend/preview_demo_service_prices.mjs --catalogue <development-catalogue.json>');
  }
  const data = JSON.parse(readFileSync(filename, 'utf8'));
  console.log(JSON.stringify(previewDemoServicePrices(data.services ?? data), null, 2));
}
