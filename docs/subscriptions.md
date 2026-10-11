# MonkeyWorkout Pro (in-app subscriptions, #126)

One auto-renewable subscription group **MonkeyWorkout Pro**:

| Product id | Period | Price (base CHE) | Intro offer |
|---|---|---|---|
| `monkeyworkout.pro.weekly` | 1 week | CHF 2.00 | 1 week free |
| `monkeyworkout.pro.monthly` | 1 month | CHF 6.00 | 1 week free |
| `monkeyworkout.pro.yearly` | 1 year | CHF 60.00 | 1 week free |

Other territories get Apple's equalized price. The free week is one per Apple ID per group (Apple enforces it).

## How access works

- The app buys with StoreKit 2, passing the account id as `appAccountToken`, and sends every verified transaction (JWS) to
  `POST /v1/me/subscriptions/transactions`. The server checks the x5c chain up to Apple Root CA - G3 (pinned SHA-256),
  Apple's marker OIDs, the bundle id and the product id, then stores the subscription on that account.
- Apple sends renewals, expiry, billing grace, refunds and revocations to `POST /v1/app-store/notifications`
  (App Store Server Notifications V2; production → workout.monkeygrade.cloud, sandbox/TestFlight → workout-staging).
- `GET /v1/me/entitlement` → `{ mode, pro, access, source, productId, expiresAt, trial, willRenew, grant }`.
  `pro` = active subscription (trial and grace period included) or free access from the owner.
- One App Store subscription belongs to one MonkeyWorkout account (restoring it on another account → 409).

## Server switch `SUBSCRIPTIONS` (Fly env, default `off`)

| Value | App |
|---|---|
| `off` | Nothing shown, nothing locked (today). |
| `preview` | Account → MonkeyWorkout Pro and the paywall visible; nothing locked. For testing purchases in TestFlight. |
| `enforced` | Pro features need `pro` (gates still to be wired once the free/Pro split is decided). |

Set it in `backend/fly.staging.toml` / `fly.production.toml` `[env]`, merge, deploy.

## Free access for selected accounts

Actions → **Free access** (manual): environment, `grant` / `revoke` / `list`, email, optional end date and note.
Runs `backend/src/admin.ts` on the Fly machine; no new secret. Granted accounts get `pro: true` (`source: grant`) and
the app shows "Free access". App Store offer codes (Account → Pro → Redeem code) also work for giving free periods.

## App Store Connect setup

Actions → **App Store subscriptions** (manual, dry run by default) creates the group, products, localizations,
CHF prices + equalized territories, availability, the 1-week free trial and the notification URLs with the existing
`ASC_*` key. Run it dry first, then with `apply`.

Needs the owner first (App Store Connect, can't be done by API):
1. Business → **Paid Apps agreement** signed, banking and tax forms complete (status Active).
2. Key behind `ASC_KEY_ID` has the **Admin** or **App Manager** role.
3. After the workflow: each subscription needs a **review screenshot** of the paywall, then submit the subscriptions
   **with the next app version** (first subscriptions can only be reviewed together with a build).
4. App Store listing: privacy policy URL and Terms of Use (EULA) link in the description or the custom EULA field.

Optional later: an In-App Purchase key (App Store Server API) for transaction history lookups and refund requests.
Not needed for the current flow.

## Proposal: free vs Pro (owner to decide; nothing is locked yet)

Free: account, generated weekly plan, workout player and logging, history, Explore library and technique,
Apple Health, reminders, Community.

Pro: New variation and kept swaps, custom exercises and workout builder, PR attempts and share cards,
full progress and muscle heat map, Apple Watch workouts, climbing days and MonkeyGrade.
The paywall lists these (`ProFeature` in `ios/MonkeyWorkout/Views/Account/ProView.swift`).
