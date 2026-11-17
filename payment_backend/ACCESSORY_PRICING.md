# Accessory pricing rollout

The subsequent business-approved amounts and publishing instructions are in
[`APPROVED_PRICING_ROLLOUT.md`](APPROVED_PRICING_ROLLOUT.md).

Live catalogue audit, 17 November 2026

| Package | Base | Existing accessory terms | Manager decision before publishing |
| --- | --- | --- | --- |
| Bridal Essentials | RM 899.00 | RM 80.00 removable veil and RM 70.00 removable accessory service. Under the legacy formula, RM 130.00 veil rental produces a RM 50.00 surcharge. | RM 829.00 is the existing base less the identifiable RM 70.00 accessory allocation. Confirm that this is the intended base and whether both supported veil styles should be included as a single fixed-price service. |
| Signature Bridal | RM 1,799.00 | One combined removable service at RM 150.00. | Confirm the revised base and the standalone veil inclusion or price. There is no recorded split. |
| Luxe Bridal | RM 2,999.00 | One combined removable service at RM 200.00. | Confirm the revised base and the standalone veil inclusion or price. There is no recorded split. |

The existing catalogue charges a three-day rental price per style. The new
service types are `package-veil` and `item-priced-accessories`. The former
requires one available veil and uses the manager's existing Required,
Optional or Add-on service pricing fields. The latter is an opt-in add-on
with a zero service fee. Its amount comes from selected catalogue items,
once per style. The legacy and new accessory types cannot be combined in a
single package. The Manager publishing confirmation explicitly records
approval of the proposed pricing for the request.

Deploy the backend and update the customer and portal builds before changing
the live package configuration. Older customer builds continue to browse
legacy packages. Convert each approved package through Service packages and
publish it through the normal revisioned editor. Rechecking the same saved
package revision and values is safe. Do not republish an active package based
only on the illustrative amount above.

Existing selections keep their service and price snapshots. An editable plan
can be revised through the existing customer review and confirmation flow,
which shows the recalculated amount. An issued invoice or rental continues
to lock revision. Deposit, fitting credit, and refundable security are
calculated through the existing payment policy. The Firestore clients still
cannot write package pricing or financial records directly.

## Source and verification files

- Backend package configuration, catalogue compatibility and selection pricing live in `package_service.mjs`, `package_service_types.mjs`, `accessory_catalogue.mjs` and `http_app.mjs`.
- Flutter configuration and customer selection use `lib/packages/package_api.dart`, `package_editor.dart`, `package_service_picker.dart`, `package_screen.dart`, `rental_availability.dart` and `accessory_catalogue.dart` in the packages directory.
- Package totals and saved plans use `package_presentation.dart`, `customer_package_details.dart` and `staff_rental_workbench.dart`. The shared integer-cents formatter is used by `lib/payments/payment_api.dart` and `checkout_invoice_card.dart`.
- Regression coverage is in `package_service.test.mjs` and the Flutter tests in `test/packages`. Updated visual baselines are in `test/packages/previews`.
