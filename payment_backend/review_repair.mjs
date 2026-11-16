import { HttpError } from './payment_service.mjs';

const requireCheck = (value, code) => { if (!value) throw new HttpError(409, code); };
const eligible = invoice => invoice?.environment === 'sandbox' &&
  invoice.state === 'ReviewRequired' &&
  invoice.reviewReason === 'Transaction requires manager review' &&
  !invoice.invoiceNo && !!invoice.billCode;

// Trusted maintenance only: deliberately NOT exposed through HTTP or client UI.
// Sticky review remains intact for all other cases. Repair one explicitly chosen
// legacy false-positive only after the gateway independently verifies FPX B2C.
export async function repairLegacyFpxB2cReview({ store, gateway, invoiceId, apply = false, now = Date.now }) {
  requireCheck(typeof invoiceId === 'string' && /^[a-f0-9]{32}$/.test(invoiceId), 'INVALID_REPAIR_TARGET');
  const path = `sandboxInvoices/${invoiceId}`;
  const before = await store.get(path);
  requireCheck(eligible(before) && before.id === invoiceId && before.reference === `LV_${invoiceId}`, 'REPAIR_NOT_ELIGIBLE');
  const result = await gateway.reconcile(before); // Read existing bill; NEVER create one.
  requireCheck(result.state === 'SandboxPaid' && result.environment === 'sandbox' &&
    result.paymentChannel === 'FPX B2C' && result.billCode === before.billCode &&
    result.reference === before.reference && result.amountCents === before.amountCents &&
    typeof result.invoiceNo === 'string' && /^[A-Za-z0-9_-]{1,150}$/.test(result.invoiceNo), 'REPAIR_NOT_VERIFIED');
  if (!apply) return { applied: false, verifiedState: result.state, amountCents: result.amountCents };
  await store.atomic(async tx => {
    const current = await tx.get(path);
    requireCheck(eligible(current) && ['id', 'billCode', 'reference', 'amountCents', 'uid', 'appointmentId', 'updatedAt']
      .every(key => current[key] === before[key]), 'REPAIR_TARGET_CHANGED');
    const booking = await tx.get(`appointments/${current.appointmentId}`);
    requireCheck(booking && booking.uid === current.uid, 'REPAIR_BOOKING_MISMATCH');
    const { reviewReason, ...clean } = current;
    const timestamp = now();
    tx.set(path, { ...clean, ...result, updatedAt: timestamp,
      ...(booking.status === 'Cancelled' ? { reviewReason: 'Paid after appointment cancellation; contact manager' } : {}),
      compatibilityRepair: { kind: 'FPX_B2C_LABEL_20261010', previousState: current.state,
        previousReviewReason: reviewReason, verifiedAt: timestamp } });
  });
  return { applied: true, verifiedState: result.state, amountCents: result.amountCents };
}
