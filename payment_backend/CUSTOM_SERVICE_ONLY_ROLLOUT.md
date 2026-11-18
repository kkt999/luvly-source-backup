# Custom packages without gown rental

## Catalogue setup

The read-only production check found five active service catalogue records.
All five had customEligible set to false and no standalone eligibility field.
The customer endpoint returned no services. These records were created for
Manager package composition.

The Manager now controls two independent settings in **Manage service prices
→ Edit service → Advanced settings**. Enable **Available for custom packages**
to expose the service in the customer builder. Enable **Available without
gown rental** only for an approved standalone service with a supported unit.
Existing records without the new field remain ineligible for standalone use.
The Manager's save creates a new price revision using the existing review
flow. No production records were changed by this implementation.

| Catalogue entry | Suggested configuration for staging acceptance |
| --- | --- |
| Bridal Consultation | Custom and standalone if approved |
| Makeup & Hairstyle Trial | Custom and standalone if approved |
| Bridal Makeup & Hairstyling | Custom and standalone quote if approved |
| Additional Fitting Session | Custom with gown only if offered |
| Additional Rental Day | Custom with gown only if offered |

## Customer flow

Step 1 collects the wedding or event date. Step 2 allows zero gowns.
Positive gown counts still need pickup and return dates, selected sizes and
stock availability. Step 3 lists active services offered for custom packages
and disables gown-dependent services when no gown is selected. Step 4 offers
veil and accessory items with a gown rental. The server returns the same
itemized pricing snapshot for all custom combinations. The service-only
quote uses the event date and omits gown, accessory and deposit charges.

Saving a service-only package records a quote. A single Bridal Consultation
or Makeup Trial can use the existing type-specific appointment picker.
Booking checks actual staff availability and reserves the accepted slot
through the existing appointment service. The existing package invoice can
be issued after the matching appointment is confirmed. This route does not
create a rental, inventory hold, gown fitting fee or gown security deposit.
The request is limited to the existing booking horizon and the event date.

Wedding-day makeup and other services without an existing matching
appointment type remain saved quotes. The customer sees a message to
contact Luvly. Assembling multi-service or multi-session quotes also uses
staff coordination. An integrated staff scheduling and payment path for
these quotes still needs supported appointment types and allocation rules.
Changing between service-only and gown rental is supported before an
appointment is linked. A linked appointment or invoice locks those changes.

## Release and manual acceptance

This change requires the corresponding backend, Manager Portal and customer
app builds. Start on staging. Use a test Manager account to explicitly enable
one standalone and one gown-dependent service. Run service-only consultation
and makeup trial through selection, quote save, appointment availability,
confirmation and the sandbox package invoice. Verify a wedding-day makeup
quote displays the staff coordination message. Check returning through Step 2
preserves eligible selected services and rechecks stock if a gown is added.
Check a gown-only and a gown-plus-services package through the original
rental and fitting steps, then check one predefined package.

The release does not change any of the three predefined package definitions
or their approved targets. No Firestore migration is needed.
