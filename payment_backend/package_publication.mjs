import {createHash} from 'node:crypto';
import {approvedPackageTarget} from './approved_package_pricing.mjs';
import { applyBundleDiscount, checkPricing, isPricingId, requirePricingManager,
  resolvePackagePricing } from './bridal_service_pricing.mjs';

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
}

const packagePath = id => `servicePackages/${id}`;
const draftPath = id => `servicePackageDrafts/${id}`;

export class PackagePublication {
  constructor(store, now, validate, validateStock) {
    Object.assign(this, {store, now, validate, validateStock});
  }

  async get(uid, id) {
    await requirePricingManager(this.store, uid);
    const [published, draft] = await Promise.all([
      this.store.get(packagePath(id)), this.store.get(draftPath(id)),
    ]);
    return {published: published ?? null, draft: draft ?? null};
  }

  async version(uid, id, revision) {
    await requirePricingManager(this.store, uid);
    const version = await this.store.get(`${packagePath(id)}/versions/${revision}`);
    checkPricing(version, 'PACKAGE_VERSION_NOT_FOUND', 404);
    return version;
  }

  async save(uid, id, input, action) {
    checkPricing(id !== 'custom-bridal' && input && Number.isSafeInteger(input.draftRevision) && input.draftRevision >= 0 &&
      Number.isSafeInteger(input.publishedRevision) && input.publishedRevision >= 0, 'INVALID_PACKAGE_DRAFT');
    return this.store.atomic(async tx => {
      await requirePricingManager(tx, uid);
      const current = await tx.get(packagePath(id));
      const draft = await tx.get(draftPath(id));
      checkPricing((current?.revision ?? 0) === input.publishedRevision &&
        (draft?.revision ?? 0) === input.draftRevision, 'PACKAGE_CHANGED', 409);
      if (action === 'publish') {
        checkPricing(input.confirmed === true && draft && draft.publishedRevision === input.publishedRevision,
          'PACKAGE_PUBLISH_CONFIRMATION_REQUIRED', 409);
      }
      const configuration = action === 'publish' ? draft.configuration : input.configuration;
      checkPricing(configuration && configuration.id === id && Array.isArray(configuration.services) &&
        configuration.services.length <= 12 && configuration.services.every(s => s && isPricingId(s.id)) &&
        configuration.pricing && typeof configuration.pricing === 'object', 'INVALID_PACKAGE_DRAFT');
      if (action === 'draft') {
        const next = {id, revision: input.draftRevision + 1, publishedRevision: input.publishedRevision,
          configuration, updatedAt: this.now(), updatedBy: uid};
        tx.set(draftPath(id), next);
        return next;
      }

      const {pricing, ...fields} = configuration;
      const {pricingSnapshot, ...resolved} = await resolvePackagePricing(tx, configuration);
      if (pricing.matchApprovedPrice === true) {
        const target = approvedPackageTarget(id);
        checkPricing(target !== undefined && pricingSnapshot.subtotalCents >= target,
          'APPROVED_PACKAGE_SUBTOTAL_TOO_LOW', 409);
        checkPricing(resolved.services.some(service => service.serviceType === 'package-veil' &&
          service.standardVeilId === 'veil-short' && service.kind === 'Optional' && service.priceCents === 8000),
          'INVALID_PACKAGE_ACCESSORY_PRICING');
        const bundleDiscount = {kind: 'fixed', value: pricingSnapshot.subtotalCents - target};
        Object.assign(pricingSnapshot, applyBundleDiscount(pricingSnapshot.subtotalCents, bundleDiscount), {bundleDiscount});
        resolved.basePriceCents = target;
      }
      const proposed = {...fields, ...resolved, revision: input.publishedRevision};
      this.validate(proposed);
      await this.validateStock(tx, proposed, current);
      const reviewId = createHash('sha256').update(JSON.stringify(canonical([proposed, pricingSnapshot]))).digest('hex');
      if (action === 'preview') return {configuration: proposed, pricingSnapshot, reviewId, published: current ?? null};
      checkPricing(typeof input.reviewedSnapshot === 'string' &&
        input.reviewedSnapshot === reviewId, 'PACKAGE_REVIEW_CHANGED', 409);
      const {accessoryPricingApproved, ...publicFields} = proposed;
      const now = this.now();
      const next = {...publicFields, pricing, pricingSnapshot, pricingModel: 'service-based', draft: false,
        revision: proposed.revision + 1, createdAt: current?.createdAt ?? now,
        createdBy: current?.createdBy ?? uid, updatedAt: now, updatedBy: uid,
        publishedAt: now, publishedBy: uid,
        versionRevisions: [...(current?.versionRevisions ?? (current?.revision && !current.draft ? [current.revision] : [])),
          proposed.revision + 1]};
      if (current?.revision && !current.draft && !current.versionRevisions) {
        tx.set(`${packagePath(id)}/versions/${current.revision}`, current);
      }
      tx.set(packagePath(id), next);
      tx.set(`${packagePath(id)}/versions/${next.revision}`, next);
      tx.delete(draftPath(id));
      return next;
    });
  }
}

export function selectionPricingSnapshot(pkg, priced, accessories, totalCents = priced.totalCents) {
  if (!pkg.pricingSnapshot) return {};
  const selectedIds = new Set(priced.services.map(service => service.id));
  const removed = pkg.services.filter(service => service.kind === 'Optional' && !selectedIds.has(service.id));
  const addOns = priced.services.filter(service => service.kind === 'Add-on');
  return {pricingSnapshot: {...pkg.pricingSnapshot, packageRevision: pkg.revision,
    removalCents: removed.reduce((total, service) => total + service.priceCents, 0),
    addOnCents: addOns.reduce((total, service) => total + service.priceCents, 0),
    veilUpgradeCents: accessories.accessoryCharges.filter(charge => charge.pricing === 'package').reduce((total, charge) => total + charge.extraCents, 0), selectedAccessories: accessories.selectedAccessories,
    accessoryAdjustmentCents: accessories.accessoryExtraCents, totalCents}};
}
