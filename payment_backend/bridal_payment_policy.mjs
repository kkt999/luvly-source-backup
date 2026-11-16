import { MAX_PACKAGE_GOWNS } from './package_gown_catalogue.mjs';

// Integer cents only. This policy applies to NEW bookings/rentals, never old invoices.
export const POLICY_VERSION = 1;
export const FITTING_FEE = 5000;
export const SECURITY_PER_GOWN = 30000;
export function packagePaymentQuote(totalCents, gownCount, creditCents = 0) {
  if (!Number.isSafeInteger(totalCents) || totalCents < 200 ||
      !Number.isInteger(gownCount) || gownCount < 0 || gownCount > MAX_PACKAGE_GOWNS ||
      ![0, FITTING_FEE].includes(creditCents)) throw Error('INVALID_POLICY_QUOTE');
  const depositTargetCents = Math.round(totalCents / 2);
  // Never create a zero/negative gateway bill or silently discard unused credit.
  if (depositTargetCents - creditCents < 100) throw Error('PACKAGE_PRICE_REVIEW_REQUIRED');
  return {policyVersion: POLICY_VERSION, depositTargetCents, fittingCreditCents: creditCents,
    depositCents: depositTargetCents - creditCents, balanceCents: totalCents - depositTargetCents,
    securityCents: gownCount * SECURITY_PER_GOWN};
}
