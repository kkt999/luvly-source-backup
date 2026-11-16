# University demonstration sizing

User approved illustrative measurements on 2026-10-14. These are not measurements of physical Luvly gowns and not guaranteed fit ranges. No inventory quantities or prices are invented.

The internally consistent Luvly demo grading uses centimetres. XXS/XS/S/M/L/XL/2XL/3XL/4XL/5XL centre bust values are 78/82/86/92/98/104/112/120/128/136; waist 60/64/68/74/80/86/94/102/110/118; hip 86/90/94/100/106/112/120/128/136/144. Each illustrative range is centre +/-2 cm. Narrow ranges intentionally do not promise adjustment or stretch. Gaps may return no match and require a fitting; do not force a recommendation.

General magnitude was checked against https://www.azazie.com/size-chart (2026-10-14), but the letter-size mapping and ranges above are original demo assumptions, NOT that supplier's chart and NOT a universal standard. All demo lengths use a 150 cm hollow-to-hem reference excluding train; this is not the length measured from a strapless neckline or a verified garment length. Actual length, fabric, fastening and alteration allowance remain unknown.

`seed_demo_measurements.mjs` defaults to dry run. `--apply` fills only missing measurements on sizes already present on dresses, transactionally rechecking size membership. Existing measurements, quantities, prices and allocations are preserved. Missing physical quantity stays unknown. Made-to-measure/unknown sizes are skipped. Repeat runs do not overwrite prior data.

Records carry measurementSource=demo-reference. Customer fit dialogs, size cards, package selection and staff stock show explicit demo labels in build 2024. Staff replacement measurements become staff-entered, not automatically verified. Old app/web versions must be updated before viewing seeded demo values because they do not understand source metadata.

Execution: build 2024 installed with adb install -r and versionCode verified. Backend restarted. Filled XXS, XS and 5XL on dress CRSQVMlGpVqIscfXfTJd only; repeat dry run found zero missing records. Thirteen Flutter checks passed and scoped analyzer clean; demo/measurement validation and rental regression tests passed. Actual phone interaction remains for user acceptance.
