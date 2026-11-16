# Free connection recovery — 16 October 2026, evening MYT

Owner supplied a live Home screenshot with both customer planning and offers
unavailable. Actual customer acceptance had therefore not passed, despite the
earlier successful code tests/build and afternoon health checks.

## Verified cause

- Local backend PID 34760 still listened on loopback 8787 and returned health200.
- The former public hostname `muze-restrict-whats-grocery.trycloudflare.com`
  returned NXDOMAIN from the system resolver and independent 1.1.1.1 resolver.
- The existing cloudflared PID 38680 log recorded DNS/edge loss at 11:08 UTC,
  followed by repeated `Unauthorized: Tunnel not found`. This was not an empty
  package catalogue or evidence of deleted customer records.

## Recovery

- Verified the exact old tunnel executable/arguments before replacing only that
  failed process. New hidden HTTP2 tunnel PID 17460 still forwards only the
  existing backend at 127.0.0.1:8787.
- New verified origin:
  `https://pulling-untitled-simplified-pure.trycloudflare.com`.
- Ran the existing health-gated configure_endpoint script to rotate local
  return/callback and Calendar redirect configuration. Restarted only the
  verified backend listener, 34760 → 43072, with hidden window/log redirection.
- Ran the existing publish_endpoint command and read back
  `runtimeConfig/backend`. Public health200 and unauthenticated planning,
  promotions and packages401 verified. No weakened authentication, billing,
  hosting purchase, Firestore rule change or APK rebuild.
- Read-only aggregate customer-planning probe: three bridal profiles,
  11 selections, 11 visits, six dated plans, one plan needing review, zero
  reserved rentals. Recovery did not modify customer, order, payment, appointment
  or stock records. Only the established runtime endpoint/config changed.
- Port5000 / the owner's Chrome development runner was not touched.

## Owner acceptance / remaining limitations

- Installed Android2041 discovers the endpoint afresh on Reload/Retry. Owner
  should tap Reload my plan and revisit Home/offers. An authenticated phone UI
  success has not been asserted based only on unauthenticated health checks.
- This remains the owner-requested free temporary setup, without a stable URL
  or uptime promise. No unsolicited monitoring service/task was installed.
- For NEW or reconnected Calendar authorisation, the existing Google Web OAuth
  client also needs the following authorised redirect URI, retaining existing
  entries:
  `https://pulling-untitled-simplified-pure.trycloudflare.com/oauth/google/calendar/callback`.
  Existing refresh-token sync is separate; Home loading does not depend on this
  manual Google Cloud change.
- Existing ToyyibPay bills retain the old gateway-side callback/return addresses.
  Use the existing Check status/reconciliation path for a payment already
  attempted; do not recreate bills or pay again solely because a redirect failed.

Logs: `logs/tunnel-planning-recovery-20261016.*.log` and
`logs/planning-recovery-20261016.*.log`.
