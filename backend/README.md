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
| `AI_MODEL_CHAT` / `AI_MODEL_SCAN` | `claude-opus-5-5` / `claude-sonnet-5-5` | model per task (#866): chat plans workouts and answers Coach; scan reads gym, pantry and plate photos against the app's lists. Stable prompt parts (Coach rules, catalogs) are prompt-cached. Every call is counted per day, feature and model (`ai_call_log`, no member ids): Actions → **AI usage** (`admin.ts ai-usage`) shows calls, failures, tokens, cache hit and estimated cost (#877) |
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

## Endpoints and security

- Every route (method, path, auth, body, response, errors, limits): [`docs/api/endpoints.md`](../docs/api/endpoints.md); OpenAPI: [`docs/reference/openapi.json`](../docs/reference/openapi.json).
- Conventions (auth headers, errors, sync protocol, quotas): [`docs/api/README.md`](../docs/api/README.md).
- Security model, data protection, threat model: [`docs/security.md`](../docs/security.md). Schema: [`docs/data-model.md`](../docs/data-model.md).
- After changing routes or schema: `npm run docs` (CI checks `docs/reference/` and the endpoint list against the code).
