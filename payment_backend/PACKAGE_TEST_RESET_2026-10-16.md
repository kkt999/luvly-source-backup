# Authorised old package/test-data cleanup — 16 October 2026

The owner asked to delete the crowded saved bridal plans from the database and
reselect packages. After the read-only audit explained the linked appointments
and sandbox payment records, the owner explicitly confirmed their deletion too.

## Exact scope / result

- Uniquely resolved the screenshot's kkt bridal account and froze the 11 exact
  selection document IDs from the pre-confirmation audit. No new selection or
  user-wide deletion was inferred from the account name.
- Deleted 11 packageSelections, 9 linked appointments, 9 packageAppointments,
  3 associated sandboxInvoices, 2 exact appointmentSlots, 5 appointmentMail
  records, and 7 per-event local Calendar sync metadata documents.
- Removed only the target bookings from one shared availability day, preserving
  staff exceptions and unrelated bookings, and incremented its revision.
- Verified the linked Google identity and deterministic private ownership marks;
  removed two corresponding Luvly test events from the app-created Calendar.
  No whole calendar, Google connection/token, account or unrelated event removed.
- No rental records existed for these selections, and no fitting credit was
  consumed or reserved. No gown/accessory stock or promotion configuration was
  changed. Store servicePackages, dresses, staff, customer profiles, support
  conversations and other customer data were not deletion targets.
- Two unrelated appointments and one unrelated sandbox invoice were preserved.
  Post-delete own counts: zero saved packages, two appointments, one invoice.
- Gateway-side ToyyibPay test bills are external to the Firestore cleanup; they
  were not paid, refunded or recreated. Old test checkout links should no longer
  be used. No real-money transaction occurred in this cleanup.

## Backup / safeguards

- Before any database or external event deletion, wrote and checksum-read-back
  a full typed Firestore backup, including exact paths and update timestamps.
  Preserve Timestamp nanoseconds, document references, GeoPoints, bytes, Date,
  maps, arrays and primitives. Remote event content was also saved before its
  individual deletion. Credentials/tokens were never written to this backup.
- Backup is local and excluded by the existing `/payment_backend/secrets/`
  ignore rule:
  `secrets/cleanup-backups/package-reset-1792156157300.json`.
- Deleted/updated database documents in one atomic batch with original
  lastUpdateTime preconditions; no concurrent changes could silently be lost.
  Re-read every deleted target to confirm absence. Existing records are
  recoverable from the backup, but restoration requires explicit owner approval
  and review of shared availability; never overwrite a day's newer bookings.
- The default cleanup command is read-only. Its four unit tests passed for the
  immutable exact allowlist, type-preserving backup and scoped slot removal.
  This is an admin-only local script, not a new HTTP deletion endpoint.

## Service availability / owner refresh

- Verified/stopped only the exact backend PID 43072 during cleanup to prevent
  its Calendar, mail or booking workers from racing the snapshot. Restarted
  hidden as PID 38064 immediately afterwards; existing public tunnel untouched.
- Installed app/data were not reset or reinstalled. Close the plan picker,
  refresh Home and reopen My packages before creating a new selection.
- Recovery backup is not displayed as an active plan and cannot resurrect old
  selections through the customer dashboard.

Tools: `inspect_package_reset.mjs` (read-only),
`reset_selected_test_packages.mjs` (preview by default; explicitly applied once).
Logs: `logs/post-package-reset-20261016.*.log`.
