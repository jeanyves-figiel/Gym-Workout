# MonkeyWorkout Pro (in-app subscriptions, #126)

One auto-renewable subscription group **MonkeyWorkout Pro** plus a one-time Lifetime purchase:

| Product id | Period | Price (base CHE) | Intro offer |
|---|---|---|---|
| `monkeyworkout.pro.weekly` | 1 week | CHF 2.00 | 1 week free |
| `monkeyworkout.pro.monthly` | 1 month | CHF 6.00 | 1 week free |
| `monkeyworkout.pro.yearly` | 1 year | CHF 60.00 | 1 week free |
| `monkeyworkout.pro.lifetime` | one-time (non-consumable) | CHF 100.00 | none; Pro forever, all future updates and features included |

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
- Production refuses Sandbox / TestFlight purchases (`400 sandbox_transaction`, sandbox notifications ignored) (#432). `SUBSCRIPTION_SANDBOX=on` allows them, e.g. while App Review tests purchases against production; staging and `SUBSCRIPTION_TESTS=on` allow them by default.

## Staging test mode (#154)

`SUBSCRIPTION_TESTS=on` (staging only, in `fly.staging.toml`): no Apple involved. Account → MonkeyWorkout Pro → **Staging test**: pick Server / Off / Preview / Enforced for your account only, then buy any plan (fake, no charge; subscriptions start with the free week, Lifetime never expires), cancel auto-renew or end it now. Entitlement carries `test` when on. Never set on production.

## Server switch `SUBSCRIPTIONS` (Fly env, default `off`)

| Value | App |
|---|---|
| `off` | Nothing shown, nothing locked (today). |
| `preview` | Account → MonkeyWorkout Pro and the paywall visible; nothing locked. For testing purchases in TestFlight. |
| `enforced` | Pro features need `pro`: Ask Coach, Generate & do today, gym and food scan (see Free vs Pro). |

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

## Free vs Pro (decided 2026-10-24, replaces the 2026-10-11 split)

Pro is only the AI and "do it now" features. Everything else is free: variations, kept swaps, workout style, building,
duplicating and sharing workouts, custom exercises, PR attempts, full progress and heat map, starting on Apple Watch,
Wall session, MonkeyGrade, adding a generated workout to a day, HIIT/quick sessions added to a day.

Pro (PRO badge; tap opens the paywall sheet when `enforced`):

| Entry point | Client gate | Server |
|---|---|---|
| Ask Coach: 🐵 bubble, Ask sparks, Ask bar, player voice ask, Siri/Shortcuts "Ask Coach" | `.askCoach` (Siri lands on RootView's chat sheet, gated there) | `POST /v1/me/coach-chat` 402 |
| Generate & do today: builder **Start now**, Coach chat **Start now**, HIIT **Do today** | `.generateWorkout` (Add to a day stays free) | on device |
| Gym scan | `.gymScan` | `POST /v1/me/gym-scan` 402 |
| Fridge / receipt scan | `.foodScan` | `POST /v1/me/food-scan` 402 |
| What can I eat? (meal ideas from the pantry, #869) | `.foodScan` | `POST /v1/me/meal-ideas` 402 |

`ProStore.shared.run(gate, $gate) { … }` + `.proPaywall($gate)` + `ProBadge()`.

Enrollment: after the first plan is generated, one full-screen offer ("Your week is ready", plans, Start free week,
"Not now, train on Free"), only when Pro is switched on. A local reminder fires 2 days before a free week ends.

Existing accounts (testers) at launch: Actions → Free access → `grant-all` with `until` = launch + 1 month.
