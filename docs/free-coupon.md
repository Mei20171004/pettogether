# Free coupon setup

The app and Security Rules use the default Firestore database in project
`pettogether-76452`. Create this document in the Firebase console or with an
administrator account:

| Path | Field | Firestore type | Value |
| --- | --- | --- | --- |
| `/aiUsage/freecoupon` | `coupon` | string | `petlove2026` |
| `/aiUsage/freecoupon` | `enddate` | timestamp | `2026-11-08 00:00:00 Asia/Tokyo` (`2026-11-07T15:00:00Z`) |

Deploy both `firestore.rules` and `storage.rules` before demonstrating the
coupon. The app checks the definition and the signed-in user's redemption in
Firestore on launch, after sign-in, and when returning to the foreground. A
successful redemption creates `/freeCouponRedemptions/{uid}`; the client cannot
write it unless the submitted code matches the unexpired definition. The
server-side rules use the configured `enddate`, so access ends at that instant
even if a device's clock is wrong. An offline demo has no Firestore connection
and cannot redeem this coupon.

The coupon unlocks the existing Pro, multi-pet, and AI feature gates. AI keeps
its existing monthly fair-use limit of 100 parses. Redeeming does not alter
RevenueCat subscriptions or charge the user.

After signing back in to Firebase CLI, deploy the rules with:

```sh
firebase deploy --only firestore:rules,storage --project pettogether-76452
```
