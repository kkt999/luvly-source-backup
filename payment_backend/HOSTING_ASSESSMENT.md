# Connectivity incident and hosting assessment — 2026-10-14

## Recovery after 20:59 screenshot

Local port8787 had no listener and the public tunnel returned HTTP530; no cloudflared process remained. Recovered both services with Start-Process -WindowStyle Hidden and explicit safe startup logs, independent of interactive tool sessions. New public origin https://certification-engaging-promises-peripherals.trycloudflare.com; callback configuration rotated, backend restarted, Firebase runtimeConfig/backend published and verified. Public health200; unauthenticated packages401. Package/booking/payment data unchanged. Port5000 remains for Android Studio; no web runner started. New Calendar authorization requires registering this origin's /oauth/google/calendar/callback. Free tunnel availability is still dependent on the computer/network.

## Recovery at 19:15 MYT

User retained the free computer/tunnel setup. Local sandbox health was normal; bedroom-builder-yes-condos.trycloudflare.com failed DNS resolution. Established https://concord-identifies-harry-atmosphere.trycloudflare.com, updated callback/Calendar config, restarted the exact identified backend and published/verified Firebase runtimeConfig/backend. Public health 200; unauthenticated packages 401 as expected. Phone Retry acceptance remains pending. New Google Calendar authorizations require registering https://concord-identifies-harry-atmosphere.trycloudflare.com/oauth/google/calendar/callback in the existing OAuth client. No old bills or payment states changed.

## Verified incident

- Local backend health on 127.0.0.1:8787 returned sandbox successfully.
- Previous public origin realty-retrieval-campaign-kim.trycloudflare.com failed DNS resolution on this machine while its tunnel process still existed. This was not evidence that the package records were deleted.
- Replacement https://bedroom-builder-yes-condos.trycloudflare.com returned /health 200 and unauthenticated /v1/packages 401 (authentication retained).
- Rotated payment return/callback and Calendar redirect configuration, restarted the identified backend, and published/verified Firebase runtimeConfig/backend. Phone Retry should discover it; authenticated phone acceptance still pending.
- New Calendar authorizations require https://bedroom-builder-yes-condos.trycloudflare.com/oauth/google/calendar/callback registered in the existing Google Web OAuth client. Existing callback registrations were not removed. Existing payment bills may retain old callback URLs; do not assume they were migrated or automatically paid.

## Permanent deployment is NOT complete

User authorized evaluation, not a paid purchase. Temporary tunnel still depends on this computer and cannot guarantee uptime.

- Render free sleeps after 15 minutes without inbound traffic and is not suitable for reliable in-process Calendar/hold workers: https://render.com/docs/free
- Render Starter compute is listed as USD7/month; verify checkout, taxes and bandwidth separately: https://render.com/articles/render-vs-railway
- Railway Hobby minimum USD5/month includes USD5 usage; additional usage costs extra. Keep serverless sleeping disabled for the existing workers: https://docs.railway.com/pricing/plans and https://docs.railway.com/deployments/serverless

Before migration: obtain account/budget authorization; configure host PORT and binding (current loopback-only must remain default for local runs); securely provision credentials/token encryption key; include accessory catalogue asset; restrict client discovery to the exact approved hosted origin (current validator only permits temporary tunnel domains); update CORS/payment/Calendar callback URLs; test authenticated catalogue, payment callbacks and Calendar sync. Never commit/upload local .env or secrets as source. Do not change live payment status to make a demo look successful.
