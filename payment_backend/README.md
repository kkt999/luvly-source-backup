# Luvly local ToyyibPay sandbox backend — 10 October 2026

Category supplied by the user: `w8n5i4lf` (verified against the locally supplied
Sandbox key using the read-only category API on 10 October 2026).

Local backend, bride checkout screen and manager invoice screen are implemented.
They were configured and started for the approved temporary test on 10 October
2026. No bills have been created by the setup checks. No Firebase rules or billing
have changed. Packages remain deferred. The user's first payment was later
verified through gateway-query reconciliation (see compatibility correction below).
Receipt UI confirmation and independent callback-delivery testing remain.
Official contract: https://toyyibpay.com/apireference/

## Run offline tests (Node 22 or newer)

From the Flutter project root:

```powershell
node --test payment_backend/*.test.mjs
```

All gateway calls in these tests are mocked; no payment account is contacted.

## Credentials

A local `.env` has been prepared and configured for this test. Do not paste
credentials in chat, Dart source, Flutter assets, screenshots or public repositories.
`.env`, `.env.local`, `node_modules/` and `secrets/` are ignored.

1. ToyyibPay **Sandbox** dashboard: copy User Secret Key into
   `TOYYIBPAY_SECRET_KEY` in `.env`. Category `w8n5i4lf` must belong to this key.
2. Firebase Console > Project settings > Service accounts > Firebase Admin SDK:
   generate a private key **yourself**, then save the JSON as
   `payment_backend/secrets/firebase-admin.json`. This is a privileged key;
   never send it in chat or ship it with the mobile app. If you do not want a
   service-account key, stop here and choose an alternative credential method.
3. The user approved a temporary HTTPS tunnel forwarding ONLY port 8787.
   Set `PAYMENT_RETURN_URL=https://YOUR-HOST/return` and
   `PAYMENT_CALLBACK_URL=https://YOUR-HOST/callback`. No trailing extra paths.
4. For portal testing, use a fixed local origin such as `http://localhost:5000`
   in `PAYMENT_ALLOWED_ORIGINS`. Multiple exact origins may be comma-separated.

Sandbox credentials must match a Sandbox category. Live endpoints are disabled.
The adapter requires public HTTPS return/callback endpoints for checkout.
ToyyibPay cannot send callbacks to localhost. Running a local server alone does
not solve this: a separately approved public HTTPS endpoint/tunnel is needed.
A temporary tunnel was started after approval. No payment account or permanent
hosting was created. The Firebase key was supplied locally by the user, never
included in the app. The portable Cloudflare tool is described below.
Official Firebase Admin SDK dependencies have been installed locally.

## Approved temporary tunnel

Cloudflare Quick Tunnels are for development/testing, not permanent hosting.
Traffic passes through Cloudflare; anyone with the URL can reach the HTTP service,
but invoice endpoints still require Firebase authentication and authorization.
Only the payment HTTP service is forwarded, not a directory or the web portal.
Do not enable email gating: ToyyibPay callbacks are non-interactive.
Official guide: https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/

A portable Windows x64 `cloudflared` 2026.10.0 was downloaded from Cloudflare's
official GitHub release. SHA256 matches the release digest and its Windows
Authenticode signature is valid. No Windows service or global installation added.

After BOTH credentials are filled locally, start the following in a separate
terminal (the backend starts after the new public URL is configured):

```powershell
& 'C:\Users\User\Documents\Codex\2026-08-18\referenced-chatgpt-conversation-this-is-an\work\tools\cloudflared.exe' tunnel --no-autoupdate --url http://127.0.0.1:8787
```

Copy the printed `https://...trycloudflare.com` origin into the two `.env` URLs
(`/return` and `/callback` respectively), then start the backend below. Until the
backend starts, this URL will return an origin connection error, not a working
payment endpoint. Check `/health` before rebuilding apps with this origin.
Never paste keys into the tunnel command or use debug logging.

Keep the tunnel terminal open only during the approved test. Press **Ctrl+C** in
the tunnel terminal and backend terminal after testing. The temporary URL stops
working when the tunnel closes and changes on the next tunnel run; do not reuse
old bills after changing the callback URL. Resolve pending tests before closing.

## Start (only after configuration is complete)

From this `payment_backend` directory:

```powershell
npm.cmd start
```

The server binds **127.0.0.1 only**, never all network interfaces. It refuses to
start without sandbox configuration and credentials for `luvly-44c77`.
Node reads `.env` automatically; do not put these secrets in Flutter build flags.

From the Flutter project root, build/run the bride app using the approved public
backend origin (NO secret in the command):

```powershell
flutter run --dart-define=PAYMENT_BACKEND_URL=https://YOUR-HOST
```

Run the web portal at a fixed port for exact CORS matching:

```powershell
flutter run -d chrome --web-port=5000 --dart-define=PAYMENT_BACKEND_URL=https://YOUR-HOST
```

If the tunnel URL changes, update `.env`, restart the backend and rebuild both
apps with the new public origin. An unconfigured build shows a setup message,
not a fake successful checkout. Keep the computer/backend/tunnel running for tests.
Do not use this local demonstration architecture for production.

## Demonstration flow

1. Bride requests an appointment; staff/manager confirms it normally.
2. Manager portal > Payments & receipts > Issue invoice. Choose the confirmed
   appointment, Appointment deposit OR Dress payment, and the explicitly agreed
   RM amount. Dress payments require an available published dress linked to the
   appointment. Catalogue prices do not automatically become appointment fees.
3. Bride phone > Payments & receipts > review invoice > Pay now > Continue.
4. Complete payment through ToyyibPay's sandbox bank simulator, not a real bank.
5. Return to Luvly > Check status. Only a verified gateway transaction produces
   `Paid` and a receipt with a small `Demo receipt` label. The underlying
   state is still `SandboxPaid`, never live money.
6. Manager/staff portal refreshes the invoice list. Staff cannot issue invoices.

The manager chooses a quote rather than this update inventing a fixed fee. One
invoice per purpose per appointment is allowed. Quotes cannot be overwritten;
correcting a quote, refunding, renewing an expired bill or recovering uncertain
creation requires trusted manual review and is not automated in this first version.

## Security implemented and limitations

- Verify Firebase ID tokens and authorize ownership/active manager role.
- Use server-controlled invoices/quotes; never accept a bride's chosen amount.
- Keep sandbox invoices/receipts clearly separate from real money reports.
- Store invoice intent atomically before createBill, preventing concurrent bills.
  On timeout or uncertain response do not automatically create another bill.
- Persist bill/reference/amount/environment binding before returning checkout URL.
- Validate callback hash AND retrieve matching gateway transaction/amount/invoice.
  Return URL status parameters cannot mark a payment as paid.
- Record verified sandbox outcomes atomically and idempotently. Never downgrade
  a settled invoice because a late pending/failed callback arrives.
- Checkout cannot start after appointment cancellation. A verified payment arriving
  after cancellation is recorded with a manager-review note, not hidden/refunded.
- Invoices are stored separately in `sandboxInvoices`; existing Firestore catch-all
  rules deny all client reads/writes. Only the authenticated backend accesses them.
  Admin SDK bypasses rules, so authorization is implemented/tested in the service.
- Both invoice list endpoints and writes verify Firebase ID tokens with revocation
  checks. Inactive staff cannot fall back to bride access. Active staff can read;
  only managers can issue quotes and only the owning bride can enter checkout.
- Exact-origin CORS, JSON/form body limits and basic single-process rate limiting
  are present. These are not production DDoS protection. No wildcard origins.
- Results use integer cents and never trust URL success parameters. Signed callback
  reference is not assumed to equal invoice number; the stored bill is queried.
- Overpayment/ambiguous creation is held for review. No automatic refund or second
  bill. Expired bills remain for audit and must be reviewed, not blindly recreated.
- Lists show at most 100 invoices. No real revenue reports or PDF receipts added.
- Tests use in-memory stores/mocked gateway and loopback HTTP, not live Firebase,
  real ToyyibPay checkout or callback delivery. Live acceptance is still required.

## Before claiming the flow works

Configure credentials/public callback, then test two real signed-in test accounts,
successful/pending/failed sandbox attempts, app restart, callback delivery and
duplicate refreshes. Confirm same Sandbox invoice reference in phone and portal.
Never label sandbox outcomes as real money or enable live mode without a new review.

Local credentials and public callback configuration have been supplied. The first
user-issued Sandbox invoice and checkout now have verified persisted payment data.
Remaining acceptance checks include receipt UI confirmation, callback delivery and
pending/failed attempts. Connectivity checks alone do not prove payment completion.

## Temporary test session started 10 October 2026

- HTTPS origin: `https://reel-paintings-trembl-ctrl.trycloudflare.com`.
- Portal: `http://localhost:5000` (backend CORS allows this exact origin).
- Payment backend: `127.0.0.1:8787`; no directories are served.
- Public `/health` returned 200 with Sandbox environment; unauthenticated invoice
  access returned 401; forged return status only displayed instructions.
- Firebase read checks succeeded: existing CYJ manager and John staff roles active;
  one confirmed appointment found. No accounts/appointments were modified.
- ToyyibPay category read succeeded (active). Its actual response is an object with
  `CategoryName`, not the documentation's array with `categoryName`.
- Android debug version 2002 built, installed with `adb install -r`, and opened.
  Initial version 1 install was rejected as a downgrade; no uninstall/clear-data
  workaround used. The manager portal is served locally with the same HTTPS origin.
- At initial startup, no bill creation, bank simulator transaction, callback delivery
  or paid receipt had been verified. Subsequent user checkout is recorded below.
- Keep computer/backend/tunnel running during tests. Tell Codex when testing is
  finished to stop the managed processes. This URL is temporary and must not be
  treated as production hosting; changing it requires new app builds/configuration.

## FPX B2C compatibility correction — 10 October 2026

The user's RM100 Sandbox transaction returned one successful gateway transaction
with the expected amount/reference/invoice number but channel `FPX B2C`. The
initial adapter accepted only the API documentation sample's `FPX`, incorrectly
putting that invoice in sticky review. The adapter now accepts exactly `FPX` and
`FPX B2C`; amount/reference/invoice/signature and duplicate-success checks remain.
Unknown/prefixed channels and FPX B2B are NOT enabled by this change.

87 backend tests and 12 Flutter payment UI tests passed, including the observed B2C
transaction contract, rejection cases and targeted repair safety. Normal refresh
still cannot unlock arbitrary
reviews. The server-only `review_repair.mjs` helper is not an HTTP endpoint and
requires explicit target/apply plus an independent gateway query; no new bill is
created. It rejects changed records, wrong ownership and any unverified result.

With the user's fix authorization, a dry-run succeeded and a guarded transaction
repaired ONLY the existing false-positive test invoice, retaining an audit record.
Post-write reads confirmed both authorized manager and customer views return
`SandboxPaid`, RM100, a receipt invoice number and no old review message. The
backend was restarted on the same approved HTTPS tunnel. No app reinstall needed.
No appointment status or booking data was changed. No real money was involved.

This verifies Sandbox gateway-query reconciliation and persisted receipt data;
delivery of a successful signed callback itself has not been independently logged
or proven. User should refresh both screens and inspect `View receipt`.

## Presentation cleanup — 10 October 2026

At the user's request, customer/manager payment copy now uses `Paid`, `Pay now`,
`View receipt`, `Issue invoice` and `Confirm payment`. Large test-only explanatory
banners and the stale portal message claiming payments are disabled were removed.
The receipt retains a small `Demo receipt` label; the browser return page keeps
`Demo mode`. These presentation changes do not enable real money or make unverified
invoices paid. API environment, transaction verification, access rules and stored
Sandbox records remain unchanged. Existing isolated demo routes stay labelled.

13 payment UI tests (including state/receipt gating), 87 backend tests and Flutter
analysis passed. Android build version 2003 compiled, installed as an upgrade and
opened on the connected phone with the same temporary URL; app data preserved.
After the user approved reloading, the old portal session's stdin was found closed.
Only the verified local Flutter portal process was restarted, at the same address
`http://localhost:5000`, with interactive input enabled for subsequent reloads.
The updated source compiled/served successfully and HTTP health checks passed.
Refresh an existing browser tab to load the new UI. Account/payment records were
not cleared, and the existing Sandbox payment backend/tunnel remain unchanged.

## Verification on 10 October 2026

- 61 backend tests passed using mocked gateway, serialized in-memory transactions
  and a loopback HTTP test server; no payment account contacted.
- 12 payment Flutter tests passed, including manager quote validation at 390px,
  confirmation/cancellation, sandbox URL allowlist, read-only staff and receipt gating.
- Flutter static analysis passed with no issues.
- Full Flutter regression run: 124 passed, 1 failed (before adding the extra form
  test). The unrelated existing `test/princess_asset_test.dart` expects old morph
  names `WaistFit`/`ChestFit`, while the existing 7 October Princess GLB contains
  `LuvlyWaist`/`LuvlyChest`/`LuvlyHem`. No AR assets/native sources changed here.
- Android arm64 debug compilation passed. No installation/data clearing performed.
- Web portal compilation passed (not deployed, no backend URL configured yet).
- Missing-configuration startup refused to start, as intended. Admin SDK modules
  load successfully from the backend's installed dependencies.
- Live Firebase read access and Sandbox category validation subsequently passed;
  real checkout and callback delivery remain untested.
