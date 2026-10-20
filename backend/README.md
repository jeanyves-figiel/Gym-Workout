# MonkeyWorkout API

Accounts + data sync for the iOS app. Single-user-scale: SQLite (`node:sqlite`) on a volume.

## Run

| Env | How |
|---|---|
| DEV | `npm run dev` → `http://localhost:7443`, DB `./data/dev.db`, emails logged to console |
| Container | `docker build -t gym-api . && docker run -p 8080:8080 -v gym-data:/data --env-file .env gym-api` |

Production env: see `.env.example` (`JWT_SECRET`, `CODE_PEPPER`, and either `SES_ACCESS_KEY_ID`+`SES_SECRET_ACCESS_KEY` (+`SES_REGION`, default `eu-central-2`) or `SMTP_URL`).

Optional env:

| Env | Default | Purpose |
|---|---|---|
| `APPLE_TEAM_ID` | – | Sign in with Apple server-to-server: team id (`fly.*.toml`) |
| `APPLE_KEY_ID` | – | Key ID of the Sign in with Apple key (Fly secret) |
| `APPLE_PRIVATE_KEY` | – | `.p8` contents, real newlines or `\n` (Fly secret) |
| `APPLE_CLIENT_ID` | first `APPLE_BUNDLE_IDS` | client_id fallback; the identity token's audience (bundle id) is preferred |
| `APPLE_TWO_STEP` | off | `on`: Sign in with Apple also asks for the authenticator code when 2-step is on (needs an app that handles `mfa_required` there) |
| `AI_DAILY_LIMIT` | `500` | paid model calls (coach chat, gym scan, food scan) across all members per UTC day; over it they answer 429 `daily_limit` |
| `HIBP_CHECK` | on (off when `NODE_ENV=test`) | `0` disables the breached-password check |
| `PURGE_INTERVAL_MIN` | `60` | purge of expired codes / refresh tokens (also runs at startup; `0` = startup only) |
| `MODERATION_EMAIL` | – | receives community reports (unset → stored only) |
| `LEGAL_OPERATOR` / `LEGAL_ADDRESS` | – | operator name and postal address on `/privacy`, `/terms`, `/support` (unset → visible placeholder) |
| `LEGAL_EMAIL` | `MODERATION_EMAIL` | contact email on the legal and support pages |
| `LEGAL_LAW` | `Switzerland` | governing law in the Terms of Use |
| `LEGAL_VENUE` | – | place of jurisdiction in the Terms of Use |

Without the three `APPLE_*` key settings the Apple code exchange and token revocation are skipped (logged once).
With them: `/auth/apple` exchanges `authorizationCode` at `appleid.apple.com/auth/token` (ES256 client-secret JWT, 5 min)
and stores the Apple refresh token AES-256-GCM encrypted (key derived from `CODE_PEPPER`; rotating it makes stored tokens unrevocable);
`DELETE /me` revokes it at `appleid.apple.com/auth/revoke`. Apple errors never block sign-in or deletion.
Container starts as root only to `chown` the `/data` mount, then runs as `node` (`docker-entrypoint.sh`).

## Hosting (Fly.io)

| Env | Fly app | Config | URL | Deployed by |
|---|---|---|---|---|
| staging | `monkeyworkout-staging` | `fly.staging.toml` | `https://workout-staging.monkeygrade.cloud` | **Deploy staging**, every merge to `main` |
| production | `monkeyworkout-prod` | `fly.production.toml` | `https://workout.monkeygrade.cloud` | **Promote to production**, manual, same digest |

Each: region `fra`, 1 machine + 1 GB volume (`/data`, SQLite), `/healthz` check. One-time setup, no local tools:

1. fly.io dashboard → **Tokens** → create org token. GitHub → Settings → Secrets → Actions: repo secret `FLY_API_TOKEN`.
   Email (Amazon SES Zurich, domain `monkeygrade.cloud` verified): IAM user `monkeyworkout-ses-smtp` (only `ses:SendRawEmail` on that identity) → access key → repo secrets `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY`. **Fly setup** passes them to the app, which sends via the SES HTTPS API (`SendRawEmail`, SigV4; Zurich has no SES SMTP endpoint). Or set `SMTP_URL` directly. Without either, email codes go to the app logs.
2. GitHub environments `staging`, `production`: variables `STAGING_URL` / `PROD_URL` (URLs above).
3. Cloudflare DNS (`monkeygrade.cloud`), **DNS only**: `CNAME workout-staging → monkeyworkout-staging.fly.dev`, `CNAME workout → monkeyworkout-prod.fly.dev`.
4. Actions → **Fly setup** → Run for `staging`, then `production`. Creates app, volume, secrets (`JWT_SECRET`, `CODE_PEPPER` random; SES keys, `SMTP_URL` or `MAIL_TRANSPORT=console`), TLS cert. Idempotent; re-run after adding `SMTP_URL`.
5. Re-run latest **Deploy staging**. Prod: **Promote to production** when staging is validated.

Remote push (#69): Apple Developer → Keys → new key with **Apple Push Notifications service (APNs)** → repo secrets `APNS_KEY_ID` (10 chars) and `APNS_PRIVATE_KEY` (.p8 contents), then re-run **Fly setup** per environment. Team id from `APPLE_TEAM_ID`. Without them pushes are skipped (logged once). Quiet hours: pushes still arrive, as passive (silent) notifications. Followers come from `app.push.setFollowersProvider` (Community follow model).

Subscriptions (#126): `SUBSCRIPTIONS=off|preview|enforced` (default off) in `[env]`; free access per account via Actions → **Free access** (`src/admin.ts`). See `docs/subscriptions.md`.

App name taken → change it in the `fly.*.toml`, `deploy-staging.yml` / `promote.yml` and `fly-setup.yml`.
Sender: `MAIL_FROM` in `fly.*.toml` (`no-reply@monkeygrade.cloud`). Console mode: email codes appear in the app's logs (Fly dashboard → Monitoring).

## Endpoints (`/v1`)

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/register` | – | `{email, password, name?, acceptedTerms}` → 202, emails 6-digit code. Enumeration-safe. |
| POST | `/auth/verify-email` | – | `{email, code}` → `{user, tokens}` |
| POST | `/auth/resend-verification` | – | `{email}` → 202 (throttled 1/min) |
| POST | `/auth/login` | – | `{email, password}` → `{user, tokens}`; 403 `email_not_verified`; 429 `account_locked` `{lockedUntil}` |
| POST | `/auth/apple` | – | `{identityToken, authorizationCode?, name?, nonce?}` → `{user, tokens, created}`; `nonce` = raw nonce (16–128 chars) when the token has a `nonce` claim (its SHA-256 hex, single use), else 401 `invalid_apple_token`; links verified email; code exchanged for Apple refresh token (revoked on account deletion) |
| POST | `/auth/refresh` | – | `{refreshToken}` → new pair (rotation; replay revokes family) |
| POST | `/auth/logout` | – | `{refreshToken}` → 204 |
| POST | `/auth/password/forgot` | – | `{email}` → 202 |
| POST | `/auth/password/reset` | – | `{email, code, newPassword}` → 204, signs out all devices |
| GET / PATCH | `/me` | ✓ | profile of account; PATCH `{name}` |
| POST | `/me/password` | ✓ | `{currentPassword?, newPassword}` → new tokens, other devices signed out |
| POST | `/me/email` | ✓ | `{newEmail, password?}` (password required if the account has one) → 202, code emailed to the new address. Enumeration-safe; 400 `same_email` |
| POST | `/me/email/confirm` | ✓ | `{code}` → `{user}`; old address notified; 409 `email_taken` if claimed meanwhile |
| GET | `/me/sessions` | ✓ | active devices |
| POST | `/me/logout-all` | ✓ | 204 |
| DELETE | `/me` | ✓ | `{confirm: "DELETE", password?}` — permanent, cascades all data, revokes Sign in with Apple |
| GET / PUT | `/me/profile` | ✓ | opaque app profile JSON |
| GET / POST | `/me/logs` | ✓ | `?since=ISO` delta (rows updated at or after it; merge by id); upsert ≤500 by client UUID, `saved` = rows written. Entry: `{id, date, exerciseId, sessionId?, weightKg?, reps?, setIndex?, rir?}` |
| DELETE | `/me/logs/:id` | ✓ | |
| GET / POST | `/me/workouts` | ✓ | completed sessions (opaque JSON with `id`, `startedAt`); `?since=ISO` delta; upsert ≤100 |
| DELETE | `/me/workouts/:id` | ✓ | |
| GET / POST | `/me/custom-workouts` | ✓ | user-built workouts (opaque JSON with `id`, `name`, `items[].exerciseId`); `?since=ISO` delta; upsert ≤100 |
| DELETE | `/me/custom-workouts/:id` | ✓ | |
| GET | `/library/shared` | ✓ | workout library (#62): members' shared custom workouts (`visibility` members/public on upsert), newest first; `?q=` name, `?before=` + `beforeId=` (the page's `nextBefore` / `nextBeforeId`), `?limit=`; needs community profile; blocks + auto-hidden excluded |
| GET | `/library/shared/:id` | ✓ | one shared workout |
| POST | `/library/shared/:id/save` | ✓ | count a copy into "My workouts" |
| POST | `/library/shared/:id/report` | ✓ | `{reason, details?}`; auto-hides after 3 distinct reporters |
| GET / PUT / DELETE | `/community/me` | ✓ | community profile (`nickname`, `bio`, `defaultVisibility` private\|members\|public, `autoShare`; joining needs `acceptGuidelines: true`); DELETE = leave (profile, photo, posts, cheers) |
| PUT / DELETE | `/community/me/avatar` | ✓ | raw `image/jpeg` ≤512 KB, 64–1024 px; APPn/comment segments (EXIF, GPS, XMP) stripped |
| GET | `/community/feed?scope=members\|following\|mine&before=ISO&limit=` | ✓ | newest first, `nextBefore` + `nextBeforeId` cursor (pass back as `before` + `beforeId`; `before` alone still works but can skip posts of the same moment); blocks applied both ways |
| POST | `/community/posts` | ✓ | share a win (`kind` workout\|badge\|record\|climb\|note, `refId` dedupes, `payload` card, `caption`, `visibility`) |
| PATCH / DELETE | `/community/posts/:id` | ✓ | own posts: visibility / caption |
| PUT / DELETE | `/community/posts/:id/reactions/:kind` | ✓ | like\|strong\|fire\|clap, not on own posts |
| GET | `/community/members/:userId` | ✓ | member profile + visible posts |
| POST | `/community/reports` | ✓ | `postId` or `userId`, `reason`; post hidden after 3 distinct reporters; mailed to `MODERATION_EMAIL` |
| GET / POST / DELETE | `/community/blocks[/:userId]` | ✓ | block list (blocking also removes follows both ways) |
| GET / PUT / DELETE | `/community/follows[/:userId]` | ✓ | members you follow |
| GET | `/community/avatars/:id` | – | avatar JPEG (unguessable id, immutable cache) |
| GET | `/share/:postId` | – | public web card for `public` posts |
| GET / POST | `/me/pr-attempts` | ✓ | personal-record attempts (JSON with `id`, `exerciseId`, `date`, `kind` 1RM/repMax/maxReps, `kg`, `reps`, `success`, optional `isRecord`); `?since=ISO` delta; upsert ≤200 |
| DELETE | `/me/pr-attempts/:id` | ✓ | |
| GET / POST | `/me/body-measurements` | ✓ | body measurements (#185): JSON with `id`, `date`, optional `girthsCm` (part → cm, e.g. `chest`, `upperArmL`), `weightKg`, `bodyFatPct`; `?since=ISO` delta; upsert ≤200 |
| DELETE | `/me/body-measurements/:id` | ✓ | |
| GET | `/me/export` | ✓ | full JSON export (nFADP/GDPR) |
| PUT | `/me/push-device` | ✓ | `{token (hex), env: sandbox\|production, topic (bundle id), tz?}`; a token moves to the last account that registers it |
| DELETE | `/me/push-device/:token` | ✓ | 204 (sign-out) |
| GET / PUT | `/me/notification-prefs` | ✓ | `{prefs}`: toggles, reminder/check-in times, quiet hours (minutes after midnight) |
| POST | `/me/achievements` | ✓ | `{achievements: [{id, type, text}]}` ≤30 → pushes each new id once to followers → `{announced}` |
| POST | `/me/push-test` | ✓ | test push to own devices → `{devices, sent, pushConfigured}` |
| GET | `/me/entitlement` | ✓ | MonkeyWorkout Pro (#126): `{mode, pro, access, source subscription\|grant\|none, productId, expiresAt, trial, willRenew, grant, products}` |
| PUT / POST | `/me/subscriptions/test`, `/test/purchase`, `/test/cancel` | ✓ | Staging only (`SUBSCRIPTION_TESTS=on`, else 404): per-account Pro mode `{mode: off\|preview\|enforced\|null}`, fake purchase `{productId}`, cancel `{end?}` → entitlement (`test` field present when enabled) |
| POST | `/me/subscriptions/transactions` | ✓ | `{signedTransaction, signedRenewalInfo?}` StoreKit 2 JWS, verified against Apple Root CA - G3 → entitlement; 403/409 `subscription_other_account` |
| POST | `/app-store/notifications` | Apple-signed | App Store Server Notifications V2 `{signedPayload}` |
| GET | `/healthz` | – | |

Sync deletes (#432): every `GET /me/<kind>?since=ISO` pull (`logs`, `workouts`, `custom-workouts`, `custom-exercises`,
`pr-attempts`, `body-measurements`, `climbs`, `sports`, `machine-notes`) also returns `deleted: string[]`, the ids of
items deleted (by any device, or by ops' undo-workout) at or after `since`; drop them locally. Always present on a
`since` pull (`[]` when nothing was deleted; always `[]` for custom exercises, which are archived, not deleted), absent
on a full pull. Uploading a deleted id again (Undo in the app) brings it back and clears its tombstone.
Tombstones are kept 180 days; a device offline for longer should do a full pull.

Errors: `{error: <code>, message}`. Password endpoints (register, reset, change) may return 400 `weak_password` or `breached_password`.

## Security model
- Passwords: scrypt (N=2¹⁵, r=8, p=1), ≥10 chars, common/email-derived rejected; dummy hash for unknown accounts (timing).
- Email codes: 6 digits, HMAC-peppered at rest, 15 min TTL, 5 attempts, previous codes invalidated.
- Access: HS256 JWT, 15 min. Refresh: opaque 256-bit, SHA-256 at rest, 60 days, single-use rotation with family revocation on replay.
- Lockout: 10 failed logins from one IP → that IP locked out of the account for 15 min; 100 a day across IPs → password sign-in locked for a day (a reset reopens it). Rate limit: 10 req/min/IP (`Fly-Client-IP`) on auth routes.
- Sync quotas: 413 `quota_exceeded` past a per-member row cap per table (`ROW_QUOTAS` in `src/quota.ts`).
- Sign in with Apple: identity token verified against Apple JWKS (issuer + bundle-id audience); a `nonce` claim needs the matching raw `nonce` and is accepted once (also for `/me/reauth` `{method: 'apple', identityToken, nonce?}`).
- Password change/reset revokes all refresh tokens and notifies by email.
- Breached passwords: Have I Been Pwned range API (k-anonymity: only 5 hex chars of the SHA-1 leave the server, `Add-Padding`), 2 s timeout, fails open.
- Email change: 6-digit code to the new address (same TTL/attempt rules), old address notified, pending codes invalidated.
- Purge job: expired codes / email changes / refresh tokens deleted hourly; revoked refresh tokens kept while their family is live (replay detection), then 24 h grace.
