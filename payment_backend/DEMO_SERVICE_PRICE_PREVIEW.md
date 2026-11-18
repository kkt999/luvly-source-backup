# Development service price preview

These are suggested FYP demonstration rates. Set them only in a verified
development or staging catalogue after review.

| Supported service or item | Suggested rate | Existing pricing method |
| --- | ---: | --- |
| Bridal Consultation | RM100 | Fixed per consultation |
| Additional Fitting Session | RM80 | Per session |
| Bridal Makeup & Hairstyling | RM500 | Fixed per complete look |
| Makeup & Hairstyle Trial | RM200 | Fixed per trial |
| Additional Rental Day | RM100 | Per day |
| Grace Fingertip Veil | RM80 | Existing standalone catalogue item |

The RM80 fitting suggestion is for an additional fitting session. The existing
RM50 fitting booking fee and its credit rules still apply. The standalone veil
price comes from the item catalogue. The RM80 package removal deduction remains
a separate package rule. The preview does not generate a universal gown price,
a generic accessory charge, or separate makeup-only and hairstyling-only records.

Supply a JSON export of service records from the verified test environment.
The preview accepts an array or an object containing a services array. Each
service must have its existing id, name and priceCents. Include serviceType
and active where available for comparison.

```powershell
node payment_backend/preview_demo_service_prices.mjs --catalogue C:/path/to/development-catalogue.json
```

Rows marked keep-existing retain their current price and active state.
Rows marked propose-create are reviewable suggestions for the Manager to
create in the test catalogue. The command reads only its supplied file and
the bundled accessory catalogue. Re-running it against a catalogue that already
contains the proposed service IDs makes no new proposal for those services.

The three approved bundle targets remain RM829, RM1,729 and RM2,879. A Manager
still needs complete service prices and an approved standard gown allowance,
or the package's existing complete gown-price references, to calculate and
review an eligible package draft. A subtotal below the approved target requires
review of the actual components and prices before publication.
