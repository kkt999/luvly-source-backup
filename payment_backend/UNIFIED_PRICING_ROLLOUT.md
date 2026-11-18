# Unified bridal package pricing

## Existing workflow and implementation

The Flutter Customer App and Manager Portal use the same package API. The
backend publishes to Firestore's existing servicePackages collection. Saved
selections already carry service, item, and price snapshots and continue
through the existing fitting, proposal, invoice, and rental flows.

- bridal_service_pricing.mjs resolves authoritative minor-unit service and
  gown prices and fixed or percentage bundle discounts. Catalogue price
  revisions are immutable under bridalServicePrices/{id}/revisions.
- package_publication.mjs stores working configurations in servicePackageDrafts
  and published versions under servicePackages/{id}/versions. The first
  service-based publication archives the previous legacy version if present.
  The Manager's reviewed configuration is bound to the publish request.
  Draft revision and live revision must both match. The live document,
  archive and draft cleanup are committed in one Firestore transaction.
- custom_package_pricing.mjs resolves chosen catalogue services and gowns.
  PackageService reuses date validation, selected inventory validation,
  accessory pricing and package selection persistence for preview and save.
  The new custom quote identifier binds the selected financial breakdown
  and dates to the customer. Custom selections are private packageSelections
  records with packageType Custom. They are absent from the template catalogue.
- The Flutter Manager editor supports searchable reusable service prices,
  custom eligibility, inclusion types, gown count, discount
  configuration, draft save, review, customer preview and version history.
  The Customer App reuses the rental date, gown/size and accessory pickers.
  The rental workspace displays custom package type and stored pricing.
- Existing accepted financial records are untouched. New selection snapshots
  retain component price revisions, applied bundle discount, veil and accessory
  adjustments, and the accepted selection total. The RM50 fitting fee, credit,
  deposit, balance, invoice, security deposit, and reservation rules stay in the
  existing services.

## Business configuration before publication

| Package | Prior published base checked on 17 Nov 2026 | Approved target |
| --- | ---: | ---: |
| Bridal Essentials | RM899.00 | RM829.00 |
| Signature Bridal | RM1,799.00 | RM1,729.00 |
| Luxe Bridal | RM2,999.00 | RM2,879.00 |

The approved targets are bundle selling prices. Existing package data
does not supply a separately approved standalone unit price for each legacy
included service. A Manager must link real approved standalone prices and
quantities for those service rows, including consultation, fitting allocations,
makeup/hair and portraits where present in the actual package. For new packages, set the approved standard amount per gown under **Manage
service prices → Standard gown allowance**. The backend multiplies it by
the included gown count and stores the priced allowance with its revision.
Existing complete gown-price references remain effective for the same count.
Customer-selected custom gowns still use their own rental prices. The separate
booking fitting fee is already handled by the existing payment flow.

The approved configuration includes Grace Fingertip Veil by default.
Removing the veil deducts RM80 once. A stocked eligible upgrade uses the
catalogue difference above the standard style. Bridal Accessories uses selected
item prices and starts unchecked. A custom package has no included veil unless
the customer selects and pays for one at its standalone catalogue price.

The editor calculates the bundle discount from the actual subtotal and the
approved target. Missing components and a subtotal below the target block
review and publication. The supplied test fixtures verify all three target
calculations. Production-specific draft totals require approved unit-price inputs.

## Rollout

No Firestore migration is required. Keep the existing restrictive rules for
the new server-managed collections. Maintain the same Cloud Run identity,
environment variables, Firebase project and secret configuration.

1. From the reviewed checkout, follow the **Cloud Run** command block in
   [Approved pricing rollout](APPROVED_PRICING_ROLLOUT.md). Set the release
   prefix and candidate tag to unified-pricing. Use the existing staging project
   or the no-traffic revision. Verify /health, Manager-authenticated service-price
   and draft GET routes, and customer custom options/quote routes. Use staging data
   for write tests. Promote the verified image using that guide's traffic command.
2. Build the Manager web release with flutter build web --release and deploy
   build/web through the existing Portal channel. For Android Studio testing,
   run the updated Portal on Chrome using its configured local port.
3. Build the customer app with a new build number and the existing signing
   setup. For the USB demo, use flutter build apk --debug --target-platform
   android-arm64 --build-number <next-build-number> followed by adb install -r
   build/app/outputs/flutter-apk/app-debug.apk. Release the updated customer app
   before publishing service-based packages. Older customer builds do not list
   service-based versions. Existing supported legacy publications keep their
   prior capability checks.
4. In Service packages, edit one of the three approved packages. Use approved
   package configuration and link actual service price revisions. Confirm the
   standard gown allowance is configured for the included gown count. Check the Standard Veil and Bridal Accessories lines.
   Save unpublished, then Review package, verify the discrepancy list and
   Customer preview, and click Publish package > Confirm and publish only
   when the reviewed amount exactly matches the approved target.
5. Verify the current version in the updated Customer App and the historical
   version in the Manager Portal. Repeat for the other packages.

The earlier rollout document's Manager actions describe the legacy editor.
Use the Manager steps in this document for service-based pricing.

## Manual verification

- Predefined packages: Check eligibility, qty, bundle discount, standard/removal/
  upgrade veil, accessories unchecked and checked with valid stock, and the
  saved quote before and after a subsequent package publication.
- Custom builder: Select dates, try one and multiple gowns and sizes, add a
  service, choose and clear a veil and accessories, navigate back, review
  and save. Reopen the saved selection and revise it before any invoice.
  Verify the correct customer owns the selection and that stock is not held
  just by saving it.
- Manager: Create and find an incomplete draft, edit and review a published
  version's pending changes, check an invalid discount and stale catalogue
  revision, inspect review differences and history, then verify that Staff and
  Customer accounts cannot manage prices or publish.
- Payments: Complete a staging fitting, check the RM50 fee and credit, issue
  the package deposit after customer acceptance, check balance, separately
  refundable security, receipt, callback retry and inventory lock. Confirm a
  historical invoice is identical after a catalogue price update.

## Changed files by area

- Shared pricing and publication: payment_backend/bridal_service_pricing.mjs,
  custom_package_pricing.mjs, package_publication.mjs, package_service.mjs,
  approved_package_pricing.mjs, package_service_types.mjs, accessory_catalogue.mjs,
  and http_app.mjs.
- Manager Portal: lib/packages/service_pricing_editor.dart,
  staff_package_catalogue.dart, staff_rental_workbench.dart, and the shared
  package API, screen and service picker.
- Customer App: lib/packages/custom_package_builder.dart,
  customer_package_details.dart, accessory_catalogue.dart and the shared
  package API and screen.
- Tests: payment_backend/package_service.test.mjs and
  test/packages/package_test.dart. Existing payment and rental regression
  tests remain in place.

## Boundaries to verify on staging

Review calculates the Manager's authoritative amount against present catalogue
revisions. The editor keeps the working form while validation errors are
resolved. The custom builder keeps choices between its pickers and review and
supports editing saved selections in My packages before an invoice or rental
is created. An unfinished selection lives on the open builder screen until
the customer saves a validated selection.

The custom package's standalone rental day can be added while building the
quote when configured by the Manager. The existing paid post-booking date
extension requires a published package extension rate. Custom orders need a
staff review if they later need a paid extension beyond the booked dates.

No customer device, staging appointment, or live payment was used for
this implementation. Perform the manual checklist with a supported
customer build, Manager account and staging payment data before rollout.
