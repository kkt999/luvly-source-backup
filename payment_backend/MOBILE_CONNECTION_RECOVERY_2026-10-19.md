# Mobile connection recovery — 19 October 2026

## Cause

The local backend was healthy, but the mobile runtime configuration still pointed to an expired temporary Cloudflare hostname. No cloudflared process was running. The old hostname returned DNS ENOTFOUND, preventing both planning and offers from loading.

## Approved recovery

- User explicitly approved replacing the free public tunnel.
- New public origin: https://mills-relocation-cats-shall.trycloudflare.com
- Tunnel process at recovery: 34176; HTTP/2; loopback upstream 127.0.0.1:8787.
- Existing configure_endpoint.mjs updated payment return/callback URLs and the local Calendar redirect URI.
- Verified old backend process 31668 identity before restarting. Replacement backend process: 13320.
- Existing publish_endpoint.mjs updated and read back only runtimeConfig/backend.
- No manual customer, rental, promotion, or payment record edits were made. Normal existing background workers resume with the backend.

## Verification

- Public GET /health: 200; expected environment and promotions enabled.
- Anonymous GET /v1/my-planning: 401 SIGN_IN_REQUIRED.
- Anonymous GET /v1/promotions: 401 SIGN_IN_REQUIRED.
- Anonymous GET /v1/dashboard: 401 SIGN_IN_REQUIRED.
- Backend startup stderr empty at verification.
- HttpPaymentApi resolves the admin-managed endpoint on each request/retry, so this change requires no APK rebuild.
- Authenticated phone display still requires the user's retry; no phone session was impersonated.

## Calendar and lifecycle

Register https://mills-relocation-cats-shall.trycloudflare.com/oauth/google/calendar/callback in the existing Google Cloud Web client's authorized redirect URIs before reconnecting Calendar. Existing Calendar connections were not disconnected or replaced.

This is a temporary development tunnel, not durable hosting. The backend and tunnel must remain running; restarting the tunnel can change its hostname. No Windows startup task or security configuration was changed.

Logs: logs/mobile-recovery-20261019-2055-{tunnel,server}.{stdout,stderr}.log
