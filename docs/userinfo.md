# User status in Firestore

The default Firestore database in `pettogether-76452` stores one document per
Firebase Auth account at `/userinfo/{uid}`. The document ID and `userId` are
the Auth UID.

| Field | Type | Meaning |
| --- | --- | --- |
| `userId` | string | Firebase Auth UID |
| `userType` | string | `free user`, `pro user`, or `free coupon user` |
| `paidAt` | timestamp or null | Latest Pro purchase date reported by the RevenueCat SDK (informational; a trial may not be a charge) |
| `couponActivatedAt` | timestamp or null | Most recent successful coupon redemption |
| `statusExpiresAt` | timestamp or null | End of the current Pro or coupon access period |
| `createdAt`, `updatedAt` | timestamp | Record creation and last status refresh |

Pro takes priority when both a paid subscription and coupon are active. A
subscription cancellation retains Pro until the paid period ends. At expiry,
the app and Firestore Security Rules stop granting access immediately. The
console summary is refreshed the next time that user opens or resumes the app;
no background status job runs. If a coupon remains active when Pro ends, the
user becomes `free coupon user`; otherwise they become `free user`.

The Flutter app reads the signed-in user's entitlement, coupon redemption, and
coupon definition from Firestore's server on launch, resume, and after a coupon
redemption. It also refreshes after a RevenueCat customer-info change and
after purchase or restore. Only then does it write `userinfo/{uid}`. Security
Rules allow a user to write only their own summary, and verify `userType`,
`statusExpiresAt`, and `couponActivatedAt` against the source documents. Paid
features still rely on the existing entitlement and coupon gates rather than
trusting this summary. `paidAt` is display metadata from the RevenueCat SDK;
it is not a verified billing receipt.

Deploy `firestore.rules` and release the Flutter change. On the reported UID
`KMWKXlpItjVpugWGEOZDBUoetqO2`, the next app launch should replace the
stale `free user` summary with `free coupon user`, provided the coupon remains
valid. Users who do not open the app keep their last summary in the console;
the expiry timestamp is available to interpret it.
