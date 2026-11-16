# Luvly cloud backend

Project: `luvly-44c77`; service: `luvly-api`; region: `asia-southeast1`.

Stable API: https://luvly-api-127519727979.asia-southeast1.run.app

The Cloud Run URL is public ingress, while business endpoints still require a
valid Firebase ID token and the existing owner/staff/manager checks. Only the
previously public health, payment and OAuth routes remain public. The scheduled
maintenance route additionally verifies Google's OIDC signature, audience,
expiry, verified email and exact dedicated scheduler service account.

Cloud Run uses request billing, 0 minimum / 1 maximum instance, 1 vCPU, 512 MiB,
20 concurrent requests and a 120-second timeout. Cloud Scheduler invokes awaited
maintenance every minute. Do not enable the local timer workers in cloud mode:
idle Cloud Run CPUs do not reliably execute background intervals.

## Runtime configuration

Secret Manager secret `luvly-backend-config` version 1 stores a JSON bundle:
`projectId`, `paymentSecret`, `categoryCode`, optional base64 `calendarKey`, and
`files` containing the existing Calendar OAuth/config, Gmail and Gemini JSON
configuration. Never log, commit or upload this JSON in the build context. The
existing Calendar encryption key must be retained to decrypt saved connections.
The runtime uses Application Default Credentials, not a downloaded administrator
key. Secret configuration is materialised with private permissions in ephemeral
storage at startup.

Non-secret environment variables:

- `PAYMENT_RETURN_URL`: stable API + `/return`
- `PAYMENT_CALLBACK_URL`: stable API + `/callback`
- `PAYMENT_ALLOWED_ORIGINS`: explicit approved portal origins
- `MAINTENANCE_AUDIENCE`: stable API origin
- `MAINTENANCE_EMAIL`: `luvly-api-scheduler@luvly-44c77.iam.gserviceaccount.com`
- `LUVLY_CONFIG_BUNDLE`: Secret Manager version reference

Dedicated runtime identity: `luvly-api-runtime`. It has Firestore data and
Firebase Auth administration access required by the existing application; object
access is limited to the Luvly media bucket; secret access is limited to this
secret. Signing access is limited to itself for private media download URLs.
Build identity `luvly-api-build` has access only to build sources, the image
repository and build logging. No user-managed service-account key is deployed.

## Rebuild / redeploy

From the source root, create a NEW staging directory outside the app source:

```powershell
node payment_backend/prepare_cloud_source.mjs C:/path/to/new-cloud-stage
gcloud builds submit C:/path/to/new-cloud-stage --project=luvly-44c77 --region=asia-southeast1 --tag=asia-southeast1-docker.pkg.dev/luvly-44c77/luvly-backend/api:NEW_VERSION
```

Use the dedicated build identity with Cloud Logging when configuring a build.
Deploy the resulting immutable image/digest to the existing `luvly-api` service,
preserving its runtime identity, secret reference, environment and resource
limits. Do not build the entire Flutter directory or use `COPY . .`.

The portable staging command follows only relative runtime imports from
`server.mjs`, adds the two required static policy/catalogue files, and refuses
an existing output directory. It excludes administration scripts, all local
credentials, business backups, tests, models and media. Docker expects this
staged build context.

Calendar redirect registration (one stable entry):
https://luvly-api-127519727979.asia-southeast1.run.app/oauth/google/calendar/callback

The App resolves the administrator-only Firestore `runtimeConfig/backend`
document. Its validator allows this exact stable origin and legacy temporary
tunnels for rollback. It never accepts arbitrary Cloud Run tenants. Local API
development requires explicit `--dart-define=LUVLY_LOCAL_BACKEND=true`; normal
Staff web builds and mobile builds use the cloud configuration.

## Operations and verification

- Run backend regression tests with `node --test *.test.mjs`.
- `node check_readiness.mjs` checks portal/HTTPS/auth/CORS/maintenance protection.
- `node verify_cloud_runtime.mjs` performs read-only role checks using existing
  administrator credentials locally. It never prints ID tokens or identities.
- Scheduler job: `luvly-api-maintenance`, every minute, MYT, dedicated OIDC identity.
- `serviceMaintenance/worker` records completion and failed queue names; Firestore
  leases prevent overlapping workers. Calendar state and per-user locks are
  durable across restarts and revision changes.
- Media remains private in the existing Storage bucket. No inventory, customer
  measurements, invoice amounts or verified payment states are migrated/rewritten.
- Existing sandbox payment configuration is unchanged apart from callback origin.

Cloud usage, builds, image storage, secrets and scheduler usage are charged under
the project's existing Blaze/free-trial billing. Scale-to-zero and maximum
instances reduce idle/resource use; they are not a total spending cap. Review
billing before the existing trial ends. No billing account or plan was changed.

Known limits: payments remain in ToyyibPay sandbox; external Gmail/Google APIs
still depend on their grants/quotas. Cold starts can add latency. A working cloud
backend does not publish the localhost Staff frontend automatically.
