# Gym-Workout API

Accounts + data sync for the iOS app. Single-user-scale: SQLite (`node:sqlite`) on a volume.

## Run

| Env | How |
|---|---|
| DEV | `npm run dev` → `http://localhost:7443`, DB `./data/dev.db`, emails logged to console |
| Container | `docker build -t gym-api . && docker run -p 8080:8080 -v gym-data:/data --env-file .env gym-api` |

Production env: see `.env.example` (`JWT_SECRET`, `CODE_PEPPER`, `SMTP_URL` required).

## Endpoints (`/v1`)

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/register` | – | `{email, password, name?, acceptedTerms}` → 202, emails 6-digit code. Enumeration-safe. |
| POST | `/auth/verify-email` | – | `{email, code}` → `{user, tokens}` |
| POST | `/auth/resend-verification` | – | `{email}` → 202 (throttled 1/min) |
| POST | `/auth/login` | – | `{email, password}` → `{user, tokens}`; 403 `email_not_verified`; 429 `account_locked` |
| POST | `/auth/apple` | – | `{identityToken, name?}` → `{user, tokens, created}`; links verified email |
| POST | `/auth/refresh` | – | `{refreshToken}` → new pair (rotation; replay revokes family) |
| POST | `/auth/logout` | – | `{refreshToken}` → 204 |
| POST | `/auth/password/forgot` | – | `{email}` → 202 |
| POST | `/auth/password/reset` | – | `{email, code, newPassword}` → 204, signs out all devices |
| GET / PATCH | `/me` | ✓ | profile of account; PATCH `{name}` |
| POST | `/me/password` | ✓ | `{currentPassword?, newPassword}` → new tokens, other devices signed out |
| GET | `/me/sessions` | ✓ | active devices |
| POST | `/me/logout-all` | ✓ | 204 |
| DELETE | `/me` | ✓ | `{confirm: "DELETE", password?}` — permanent, cascades all data |
| GET / PUT | `/me/profile` | ✓ | opaque app profile JSON |
| GET / POST | `/me/logs` | ✓ | `?since=ISO` delta; upsert ≤500 by client UUID |
| DELETE | `/me/logs/:id` | ✓ | |
| GET | `/me/export` | ✓ | full JSON export (nFADP/GDPR) |
| GET | `/healthz` | – | |

Errors: `{error: <code>, message}`.

## Security model
- Passwords: scrypt (N=2¹⁵, r=8, p=1), ≥10 chars, common/email-derived rejected; dummy hash for unknown accounts (timing).
- Email codes: 6 digits, HMAC-peppered at rest, 15 min TTL, 5 attempts, previous codes invalidated.
- Access: HS256 JWT, 15 min. Refresh: opaque 256-bit, SHA-256 at rest, 60 days, single-use rotation with family revocation on replay.
- Lockout: 10 failed logins → 15 min. Rate limit: 10 req/min/IP on auth routes.
- Sign in with Apple: identity token verified against Apple JWKS (issuer + bundle-id audience).
- Password change/reset revokes all refresh tokens and notifies by email.
