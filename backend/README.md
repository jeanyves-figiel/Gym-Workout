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
| `HIBP_CHECK` | on (off when `NODE_ENV=test`) | `0` disables the breached-password check |
| `PURGE_INTERVAL_MIN` | `60` | purge of expired codes / refresh tokens (also runs at startup; `0` = startup only) |

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

App name taken → change it in the `fly.*.toml`, `deploy-staging.yml` / `promote.yml` and `fly-setup.yml`.
Sender: `MAIL_FROM` in `fly.*.toml` (`no-reply@monkeygrade.cloud`). Console mode: email codes appear in the app's logs (Fly dashboard → Monitoring).

## Endpoints (`/v1`)

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/register` | – | `{email, password, name?, acceptedTerms}` → 202, emails 6-digit code. Enumeration-safe. |
| POST | `/auth/verify-email` | – | `{email, code}` → `{user, tokens}` |
| POST | `/auth/resend-verification` | – | `{email}` → 202 (throttled 1/min) |
| POST | `/auth/login` | – | `{email, password}` → `{user, tokens}`; 403 `email_not_verified`; 429 `account_locked` |
| POST | `/auth/apple` | – | `{identityToken, authorizationCode?, name?}` → `{user, tokens, created}`; links verified email; code exchanged for Apple refresh token (revoked on account deletion) |
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
| GET / POST | `/me/logs` | ✓ | `?since=ISO` delta; upsert ≤500 by client UUID. Entry: `{id, date, exerciseId, sessionId?, weightKg?, reps?, setIndex?, rir?}` |
| DELETE | `/me/logs/:id` | ✓ | |
| GET / POST | `/me/workouts` | ✓ | completed sessions (opaque JSON with `id`, `startedAt`); `?since=ISO` delta; upsert ≤100 |
| DELETE | `/me/workouts/:id` | ✓ | |
| GET / POST | `/me/custom-workouts` | ✓ | user-built workouts (opaque JSON with `id`, `name`, `items[].exerciseId`); `?since=ISO` delta; upsert ≤100 |
| DELETE | `/me/custom-workouts/:id` | ✓ | |
| GET / POST | `/me/pr-attempts` | ✓ | personal-record attempts (JSON with `id`, `exerciseId`, `date`, `kind` 1RM/repMax/maxReps, `kg`, `reps`, `success`, optional `isRecord`); `?since=ISO` delta; upsert ≤200 |
| DELETE | `/me/pr-attempts/:id` | ✓ | |
| GET | `/me/export` | ✓ | full JSON export (nFADP/GDPR) |
| PUT | `/me/push-device` | ✓ | `{token (hex), env: sandbox\|production, topic (bundle id), tz?}`; a token moves to the last account that registers it |
| DELETE | `/me/push-device/:token` | ✓ | 204 (sign-out) |
| GET / PUT | `/me/notification-prefs` | ✓ | `{prefs}`: toggles, reminder/check-in times, quiet hours (minutes after midnight) |
| POST | `/me/achievements` | ✓ | `{achievements: [{id, type, text}]}` ≤30 → pushes each new id once to followers → `{announced}` |
| POST | `/me/push-test` | ✓ | test push to own devices → `{devices, sent, pushConfigured}` |
| GET | `/healthz` | – | |

Errors: `{error: <code>, message}`. Password endpoints (register, reset, change) may return 400 `weak_password` or `breached_password`.

## Security model
- Passwords: scrypt (N=2¹⁵, r=8, p=1), ≥10 chars, common/email-derived rejected; dummy hash for unknown accounts (timing).
- Email codes: 6 digits, HMAC-peppered at rest, 15 min TTL, 5 attempts, previous codes invalidated.
- Access: HS256 JWT, 15 min. Refresh: opaque 256-bit, SHA-256 at rest, 60 days, single-use rotation with family revocation on replay.
- Lockout: 10 failed logins → 15 min. Rate limit: 10 req/min/IP on auth routes.
- Sign in with Apple: identity token verified against Apple JWKS (issuer + bundle-id audience).
- Password change/reset revokes all refresh tokens and notifies by email.
- Breached passwords: Have I Been Pwned range API (k-anonymity: only 5 hex chars of the SHA-1 leave the server, `Add-Padding`), 2 s timeout, fails open.
- Email change: 6-digit code to the new address (same TTL/attempt rules), old address notified, pending codes invalidated.
- Purge job: expired codes / email changes / refresh tokens deleted hourly; revoked refresh tokens kept while their family is live (replay detection), then 24 h grace.
