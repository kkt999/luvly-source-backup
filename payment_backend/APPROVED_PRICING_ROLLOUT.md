# Approved bridal pricing rollout

Read-only production check on 17 November 2026. All three rows are active and
keep their existing Firestore document IDs and linked-gown eligibility.

| Package document | Live revision | Live base | Prepared base with standard veil | Prepared base without veil |
| --- | ---: | ---: | ---: | ---: |
| `bridal-essentials` | 4 | RM 899.00 | RM 829.00 | RM 749.00 |
| `signature-bridal` | 3 | RM 1,799.00 | RM 1,729.00 | RM 1,649.00 |
| `luxe-bridal` | 3 | RM 2,999.00 | RM 2,879.00 | RM 2,799.00 |

Grace Fingertip Veil (`veil-short`) is the default. The catalogue currently
lists it at RM 80.00 and Amara Cathedral Veil at RM 130.00. An eligible,
available upgrade adds the difference between those catalogue prices.
Manager-configured RM 80.00 removal is a separate, one-time deduction.
Bridal Accessories starts unchecked and adds the chosen item prices.

## Cloud Run

Run the following from the Flutter repository root after authenticating the
existing Google Cloud deployment account. This uses the dedicated build
identity and stages only backend runtime files.

```powershell
$project = 'luvly-44c77'
$region = 'asia-southeast1'
$release = 'approved-pricing-' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$stage = Join-Path (Split-Path $PWD.Path -Parent) $release
$image = "$region-docker.pkg.dev/$project/luvly-backend/api:$release"
node payment_backend/prepare_cloud_source.mjs $stage
if ($LASTEXITCODE -ne 0) { throw 'Unable to stage backend' }
$config = "$stage-build.json"
@{
  steps = @(@{ name = 'gcr.io/cloud-builders/docker'; args = @('build', '-t', $image, '.') })
  images = @($image)
  serviceAccount = "projects/$project/serviceAccounts/luvly-api-build@$project.iam.gserviceaccount.com"
  options = @{ logging = 'CLOUD_LOGGING_ONLY' }
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $config -Encoding utf8
gcloud builds submit $stage --config=$config --project=$project --region=$region --gcs-source-staging-dir="gs://$project-backend-build-source/source"
if ($LASTEXITCODE -ne 0) { throw 'Cloud Build failed' }
$digest = gcloud artifacts docker images describe $image --project=$project --format='value(image_summary.digest)'
if ($LASTEXITCODE -ne 0 -or $digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Cloud image digest unavailable' }
$repository = "$region-docker.pkg.dev/$project/luvly-backend/api"
$candidate = gcloud run deploy luvly-api --image="$repository@$digest" --project=$project --region=$region --no-traffic --tag=approved-pricing --format='value(status.latestReadyRevisionName)'
if ($LASTEXITCODE -ne 0 -or !$candidate) { throw 'Candidate deployment failed' }
```

Check `/health` on the tagged candidate URL. As an authenticated Manager,
call `GET /v1/packages/bridal-essentials/approved-pricing` on that URL and
verify the preview base is `82900`, the veil requires `veil-short`, and the
revision matches the live package. Repeat for Signature and Luxe with
`172900` and `287900`. Recheck the existing Cloud Run revision receiving
normal traffic before switching to the verified candidate.

```powershell
gcloud run services update-traffic luvly-api --project=$project --region=$region --to-revisions="$candidate=100"
```

Recheck `/health` and the preview interface on the normal endpoint. This is a
backend release. It does not write package prices or require Firebase rule
changes.

## Customer Android and Manager web

From the same reviewed checkout, run `flutter pub get`. For the project's
existing USB-installed Android demo build, use a build number higher than
the installed version.

```powershell
flutter build apk --debug --target-platform android-arm64 --build-number 2142
adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter build web --release
```

In Android Studio, run the updated Manager Portal on Chrome using the
existing port 5000 configuration. The release web files are in `build/web`.
This repository's Android release configuration uses debug signing. A
store distribution requires the project's release signing configuration.

## Manager publishing

1. Open **Service packages** and edit one of the three existing packages.
2. Click **Load approved pricing** in **Package details**. This loads the
   proposal into the editor. An active package uses one Firestore document,
   so its proposed updates stay in the editor until publication.
3. Compare the base and services against the table. In
   **Services & add-ons**, verify Veil Rental is **Included, removable**
   with a **RM 80.00** deduction. The standard and upgrade prices are shown
   under **View veils**. Bridal Accessories uses catalogue item prices.
4. Choose **Review package → Save changes → Confirm and publish**.
   If the package revision changed, reopen the latest version and repeat.
5. In the updated customer App, open the published package and check the
   standard, removed, and upgraded veil totals. Check both **Bridal
   Accessories** states. Repeat for the remaining packages.

Past selections use their saved quote and accessory snapshots. Revising an
editable plan goes through the existing customer re-quotation flow. The
existing issued-invoice and rental locks still apply.

## Changed source files

- Backend. `approved_package_pricing.mjs`, `accessory_catalogue.mjs`,
  `package_service.mjs` and `http_app.mjs`.
- Flutter package screens. `package_api.dart`, `package_editor.dart`,
  `package_screen.dart`, `accessory_catalogue.dart`,
  `package_presentation.dart`, `customer_package_details.dart` and
  `staff_rental_workbench.dart` in `lib/packages`.
- Regression tests. `payment_backend/package_service.test.mjs`,
  `test/packages/accessory_linkage_test.dart` and
  `test/packages/package_test.dart`.
