# API conventions

Endpoint list: [endpoints.md](endpoints.md). OpenAPI 3.1: [../reference/openapi.json](../reference/openapi.json).

## Base URLs

| Environment | URL | Used by |
|---|---|---|
| DEV | `http://localhost:7443` | Debug builds, simulator |
| staging | `https://workout-staging.monkeygrade.cloud` | TestFlight builds (scheme MonkeyWorkout Staging) |
| production | `https://workout.monkeygrade.cloud` | App Store builds |

All routes are under `/v1` except `/healthz`, legal pages, `/share/:id` and `/.well-known/apple-app-site-association`. HTTPS only (`force_https`).

## Requests

- JSON bodies (`content-type: application/json`), max **1 MB** (higher limits on photo routes: scans 2.2 MB, problem reports 2.4 MB). Raw `image/jpeg` for avatar and machine-note photo uploads.
- Every body, query and path parameter is validated with zod; an invalid value is rejected with 400 `invalid_request` and the first issue. Unknown fields are ignored (dropped before the route sees them), so an older server accepts a newer app's extra fields.
- Sync ids (path and body) are UUIDs in any letter case; the server stores and returns them in lower case.
- `X-Device-Name` (optional) names the device in the session list.
- Responses over 1 KB are gzip/br compressed when asked.
- Authenticated responses carry `Cache-Control: no-store`.

## Authentication

| Kind | Header | Where it comes from | Lifetime |
|---|---|---|---|
| Access token | `Authorization: Bearer <JWT>` | `/v1/auth/*` sign-in, `/v1/auth/refresh` | 15 min (HS256) |
| Refresh token | body of `/v1/auth/refresh` | sign-in | 60 days, single use, rotated |
| Re-auth grant | `X-Reauth-Token` | `POST /v1/me/reauth` | 5 min; spent by a password change, email change or delete |
| Watch upload key | `X-Watch-Key` | `POST /v1/me/watch-key` | until replaced |
| Garmin token | `X-Garmin-Token` | `POST /v1/garmin/pair`, active once claimed | until unpaired |
| App Store | signed JWS in the body | Apple | per payload |

Sign-in methods: email + password (verified by a 6-digit code), Sign in with Apple, passkeys, optional 2-step (TOTP + recovery codes). Sensitive changes (password, email, delete, 2-step, passkeys) need a fresh re-auth grant. A password change or reset and "sign out everywhere" end every session at once: refresh tokens are revoked and access tokens issued before it answer 401 `invalid_token`. Details: [../security.md](../security.md).

## Errors

```json
{ "error": "invalid_code", "message": "That code is wrong or expired." }
```

`error` is a stable machine code; `message` is user-facing English. Some errors add fields (`lockedUntil`, `mfaToken`, `issues`).

| Status | Common codes |
|---|---|
| 400 | `invalid_request` (validation), `bad_request`, route-specific codes |
| 401 | `invalid_token` (missing, expired or account gone → refresh or sign out) |
| 402 | `pro_required` (Pro feature while subscriptions are enforced) |
| 403 | `reauth_required`, `mfa_required`, `community_profile_required`, `verification_required` |
| 404 | `not_found` |
| 409 | conflicts (`nickname_taken`, `email_taken`, `passkey_exists`…), `quota_exceeded` (per-member row or byte cap) |
| 413 | `too_large` (body or one item over its size limit, with `limit` in bytes when known), `image_too_large` |
| 429 | `rate_limited`, `daily_limit`, `account_locked`, `too_many_attempts`, `busy` |
| 5xx | `internal`, `coach_failed`/`scan_failed`/`voice_failed` (upstream), `*_unavailable` (feature not configured) |

## Rate limits and quotas

- Per client IP (address seen by Fly's proxy, not `X-Forwarded-For`): every public auth route shares a per-minute limit (`AUTH_RATE_LIMIT_PER_MIN`, default 10); `/v1/auth/refresh` 60/min; other per-route limits are listed in [endpoints.md](endpoints.md).
- Per member: data export 3/hour, problem reports 10/hour, reports of posts/workouts 20/hour, coach chat and scans with a daily cap, call names for voices 20/day.
- Global: paid model calls across all members per UTC day (`AI_DAILY_LIMIT`).
- Row quotas per member and table (`ROW_QUOTAS` in `backend/src/quota.ts`): e.g. 100 000 set logs, 10 000 workouts (and PR attempts, body measurements, climbs, sports), 500 custom workouts → 409 `quota_exceeded`.
- Byte quota per member: 50 MiB of synced data in all (`ACCOUNT_BYTES`) → 409 `quota_exceeded`. An upload that doesn't grow the total (an edit, a smaller copy) always passes.
- Per item: a workout or custom workout at most 64 KB of JSON, other synced items smaller → 413 `too_large`.

## Sync protocol

Synced kinds: `logs`, `workouts`, `custom-workouts`, `custom-exercises`, `pr-attempts`, `body-measurements`, `climbs`, `sports`, `machine-notes`. Profile: one opaque JSON blob, last write wins.

- **Upload** `POST /v1/me/<kind>` with an array of items keyed by a client-generated UUID. The server upserts; a retry never duplicates. Rows of another account are never touched. Answer: `{saved, serverTime, conflicts?}`.
- **Optimistic concurrency:** an item may carry `baseUpdatedAt` (the server `updatedAt` its edit started from). If the server row is newer, the item is not written and its server copy comes back in `conflicts` for the app to merge.
- **Pull** `GET /v1/me/<kind>?since=<ISO>` returns rows updated at or after `since` (merge by id) plus `deleted: string[]` (tombstones). Without `since`: full list, no `deleted`. Store `serverTime` as the next `since`.
- **Paged pull:** add `limit` (1–1000) to get one page in update order plus `nextCursor`; pass it back as `cursor` until it is `null`. Keep the first page's `serverTime` as the next `since`. Without `limit` the whole answer comes in one response, streamed as it is read.
- **Deletes** `DELETE /v1/me/<kind>/:id` leave a tombstone for 180 days. Uploading a deleted id again (Undo) restores it. A device offline for longer should do a full pull. Custom exercises are archived (flag), not deleted.
- **Paging** (feed, library, plans): newest first, pass `nextBefore` + `nextBeforeId` back as `before` + `beforeId`. Following lists go by nickname: pass `nextAfter` back as `after`.

## Versioning

One version (`/v1`). Changes are additive: new optional fields, new routes. Older app builds must keep working (e.g. `items` beside `found` in food scan, avatar routes kept under `/community/me/avatar`). A breaking change needs a new route.
