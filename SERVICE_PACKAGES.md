# Connected service packages — 10 October 2026

## Staff package invoicing — 11 October 2026

Active staff and managers may issue a package invoice from Customer selections
or the appointment's Review package link. The linked appointment must be
Confirmed. Amounts come from the immutable saved selection; extra amount/state
fields are rejected. The issuing UID is recorded as createdBy, and repeated
requests return the same invoice. Brides, inactive staff and unknown accounts
cannot issue invoices. Standalone manual-amount invoice permissions are unchanged.
Confirmation and invoice creation do not mark a payment Paid.

## Connection recovery update — 11 October 2026

Android build 2008 and newer source use authenticated Firestore document
`runtimeConfig/backend` for the shared package/payment API origin. Every action
reads from the server, including Retry; an old compiled `PAYMENT_BACKEND_URL` is
no longer the default. No automatic replay of payment POST requests is performed.
The config accepts only enabled schema-1 sandbox HTTPS trycloudflare origins.
Anonymous reads, collection listing, other config documents, and all client
writes (including staff/manager writes) remain forbidden. Admin SDK maintains it.

This removes the need to rebuild/reinstall after each tunnel renewal, but does
NOT provide always-on hosting. The computer, backend and temporary tunnel must
remain running and online. Firebase billing is unchanged.

Recovery for an administrator:
1. Start a new temporary tunnel forwarding only `http://127.0.0.1:8787`.
2. Update `.env` return/callback URLs to that origin and restart the local backend.
3. Run `node payment_backend/publish_endpoint.mjs https://NEW.trycloudflare.com`
   from the project root. This checks public health and URL consistency before
   updating Firebase. It contains no credential arguments or logging.
4. Tap Retry in the updated app. Do not pay an old bill again just because its
   return link fails: use Check status to reconcile it first. Previously created
   bills keep their original gateway return/callback links.

The rules migration was checked against the deployed rules and changes only the
single config document's get permission. Offline rule tests cover every client
role; Flutter tests cover fresh discovery, failed discovery and no POST replay.

Implements the package-selection and package-management requirements in
BACS3403_FinalDoc__Khoo Khai Ther_.pdf (FR-M3-01–31 and FR-M8-01–23;
PDF pages 103–104, 116–118, 313–314).

## Customer flow

Home → Packages (or Profile → My packages) → search and review → keep the
standard package or customize → review the final total → Confirm package.
Mandatory services stay included. Optional included services may be removed
for their specified deduction. Add-ons are included once, with confirmation.
Selections persist in the customer's Firebase account and keep their price
and service snapshot even if the catalogue is later edited or deactivated.

My packages → Book an appointment → submit preferred time → staff confirms
in Appointments → manager opens Service packages → Customer selections →
Issue package invoice → customer opens Payments & receipts → Pay now →
gateway verification → receipt. Payment remains ToyyibPay sandbox. A package
selection is not a reservation or an appointment confirmation.

## Staff/manager flow

Both active staff and managers can create, edit, activate and deactivate
packages, as specified by the package-management requirements. Create a
package with its name, description, standard price and up to 12 service rows.
Each service has a stable ID, description and one of these types:

- Mandatory: included, cannot be removed, no separate deduction.
- Optional: included, with a configured deduction if removed.
- Add-on: excluded by default, with a configured extra charge.

Validation rejects duplicate services, missing mandatory services, invalid
money precision, totals below RM 1 after deductions, stale catalogue edits,
and selection of inactive or changed packages. New packages start Active.
Deactivation retains existing selections. Only managers issue invoices;
only the owning bride can pay. Package invoices use the stored total and a
linked confirmed appointment; separate dress/deposit invoices are blocked
for package-linked appointments to avoid overlapping charges.

## Persistence and runtime

The existing local backend verifies Firebase ID tokens and performs all
package writes using Firebase Admin transactions. Collections:
`servicePackages`, `packageSelections`, and `packageAppointments`.
Existing `appointments` and `sandboxInvoices` hold the linked records.
Direct client access to the new collections remains denied by existing
Firestore rules; no rules deployment or new storage/billing service is needed.
The existing PAYMENT_BACKEND_URL and temporary HTTPS tunnel serve the app
and portal. The computer/backend/tunnel must remain available for these
features, just as for payments. No private keys are included in Flutter.

No catalogue packages or customer orders are seeded in the live database.
The boutique's first package, services and prices must be entered through
Create package. Test fixtures exist only in automated tests.

## Scope still separate

Package invoices currently collect the full confirmed package total. Separate
package deposit/balance instalments, promo codes, refunds, Google Calendar
synchronization, and a synchronized per-service preparation timeline are
not implemented by this change. Existing appointment completion remains
separate from payment and service fulfilment.

## Verification

- Backend tests cover standard/customized totals, invalid payloads, mandatory
  service protection, duplicates, stale prices, deactivation, owner isolation,
  staff roles, idempotent selection/booking, appointment link checks, manager
  invoice creation and verified payment/receipt integration.
- Flutter tests cover phone layout, search, standard/customized review,
  server errors, role controls, validation and unchanged payment/booking flows.
- Visual captures cover customer catalogue, customization, editor and portal.

98 backend tests and 30 focused Flutter tests passed; Flutter analysis reports
no issues. Live read-only Firebase verification confirmed manager access and
an empty package catalogue. No live package, booking or invoice was created
by verification. Android build 2005 was installed successfully on the connected
phone on 11 October, preserving app data. A real-account customer/staff package
test remains necessary; enter the first actual offering through the portal.

The previous quick tunnel expired after a network interruption. Its replacement
was renewed again on 11 October after the overnight network interruption:
`https://philip-conjunction-cars-findarticles.trycloudflare.com`. The backend return
and callback URLs, portal launch and Android build 2005 use this replacement.

## Included inventory gowns — 11 October 2026

Packages now declare an explicit `includedGownCount` (0–3) and an
`eligibleDressIds` allowlist. Staff/managers maintain both in the package editor.
Customers choose the exact number of distinct published, available gowns and
a listed size for each before reviewing and confirming the package. Photos use
the existing authenticated catalogue photo component. Insufficient inventory
blocks confirmation with an explanation; no stock or alternative sizes are invented.

The backend rechecks package eligibility, dress publication, availability,
revision and sizes in the selection transaction. Names, colours and sizes are
snapshotted in `selectedGowns`, visible to the owner and authorized staff.
Standalone dress prices are not added. Existing package-appointment safeguards
continue to prevent a second standalone dress/deposit invoice on that appointment.
Selections express gown preferences, not a dated inventory reservation or a
guarantee of fit. Staff still confirms fitting and rental availability.

Existing saved customer selections are unchanged. The three initial packages
are linked to the one currently published/available inventory gown, preserving
current prices and services. Essentials and Signature require one gown; Luxe
requires two. Add and explicitly link a second available gown before customers
can complete a new Luxe selection. Historical selections remain visible as saved.

Verification: 102 backend tests, 36 focused Flutter tests and clean Flutter
analysis. New tests cover forged IDs/sizes/prices, unavailable and stale gowns,
duplicate choices, immutable historical details, repeat submissions, insufficient
inventory and photo-picker layout. Android build 2006 contains this update.
