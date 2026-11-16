# Restored AR access — 4 October 2026

## Where to find it

### Unified catalogue follow-up

The bride's **Dresses** tab now includes published boutique dresses and both bundled AR references in the same searchable, style-filtered grid. The former fixed **Explore AR try-on** button was removed; the heading now scrolls with the list. References have explicit **AR preview · Not for sale** labels and AR actions, without invented stock or prices. **Available now** excludes references because availability is unconfirmed.

A published catalogue record linked to a prepared model suppresses that model's standalone reference card to avoid duplication. Draft associations do not affect public reference visibility. An error/loading feed still allows reference previews while clearly reporting boutique-feed status and offering retry after an error. No Firestore data or rules were changed for this follow-up.

Verification: all 104 Flutter tests passed; static analysis was clean; the updated narrow bride catalogue was rendered and visually inspected. Regression coverage includes shared search, style/availability filters, deduplication, exact AR navigation, hidden drafts and empty/error feeds. The Home AR shortcut remains available as an additional route.

The navigation description below records the initial implementation; **Dresses > Explore AR try-on** is superseded by direct dress cards in the Dresses tab.

Restart/rebuild the updated Android bride app. Open **Home > AR Try On** or **Dresses > Explore AR try-on**. The library contains the two existing bundled models: Princess Wedding Dress and Francine reference study. Select **Try this dress > Start live try-on**.

The library remains reachable with an empty or unavailable Firestore catalogue. These models are labelled reference previews, not automatically inserted as boutique inventory. Live camera AR requires Android; web shows the guide with an explicit Android-only action.

## Optional manager links

In **Dress inventory > Add/Edit Dress**, choose **AR model (optional)**. Check the model render against the actual dress and photo, confirm the match, then save. Photo-only dresses require no AR model. Selecting a new model or replacing its photo requires confirmation again.

Linked published dresses offer an AR action that opens exactly the selected prepared model. Missing or unknown IDs do not fall back to an unrelated gown. Removing the link removes the AR action without removing the catalogue dress. Existing records are not migrated or seeded.

The optional `arModelId` is limited to `princess-wedding` and `francine-reference` (or empty/absent). Assets remain bundled with the app; no 3D files are uploaded to Firestore. Adding another model later requires asset preparation, native/Flutter registration, and a corresponding allowlist update.

## Security and deployment

The user approved publishing the AR-link rules. A live-source comparison proved that only the optional field and its value allowlist changed. Existing manager-only catalogue writes, staff read-only access, published-only bride reads, private profiles, role restrictions and default deny remain unchanged.

- Project: `luvly-44c77`.
- Previous release: `projects/luvly-44c77/rulesets/a2a288e9-21db-4329-9f7b-8154f3c18f52`.
- Verified active release: `projects/luvly-44c77/rulesets/11741fc1-e69b-47aa-93a4-60242c437797`.
- Local rule SHA-256: `03f3ce6c72e58297a191718ead583530c52cb19963df75de0665e44c28b71c7a`.
- The first deployment returned an unexpected HTML response; read-back showed the previous release was still active. The retry succeeded and active rules matched the local source.
- The `dressPhotos.data` index exemption remains unchanged.
- No billing, Hosting, live catalogue records, photos, profiles or authentication accounts were changed.

## Verification and remaining check

- Static analysis: no issues.
- Full Flutter suite: 102 tests passed, including exact model routing, empty/error catalogue navigation, unsupported platform behaviour, optional link selection/confirmation/removal and visual regressions.
- Auth/Firestore emulator suite: 130 checks passed, including manager links, malformed model IDs and forbidden staff/bride/revoked-manager changes.
- Android debug APK and web release builds passed. Web retains the pre-existing Cupertino font warning.
- AR library renders were visually checked with both actual bundled thumbnails loaded. The Home shortcut baseline was updated for its new label.

No phone installation or live camera verification was performed in this step. Restart the app and test both models on the phone. Then, if a catalogue dress actually matches a prepared model, save its link as manager and check it from a separate bride session.

This change restores navigation and catalogue linkage; it does not change native pose tracking, mesh fitting or rendering. AR remains an appearance preview, not a body-size measurement or fit guarantee. Saved looks remain local to the device.
