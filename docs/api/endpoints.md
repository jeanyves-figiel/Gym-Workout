# API endpoints

Every route the API registers, grouped by area. Conventions (base URLs, auth headers, errors, sync protocol, limits): [README.md](README.md).
Machine-readable: [`../reference/openapi.json`](../reference/openapi.json) (generated from this file) and [`../reference/routes.json`](../reference/routes.json) (generated from the code).
`backend/test/docs.test.ts` fails when a route is added, removed or renamed without updating this file (`cd backend && npm run docs`).

Table columns: **Method**, **Path**, **Auth** (`–` public, `Bearer` access token, `Bearer + re-auth` also needs `X-Reauth-Token`, `X-Watch-Key`, `X-Garmin-Token`, `Apple JWS`), **Summary** (body → response), **Errors / limits** (besides the common ones in the README).

## Health and well-known

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/healthz` | – | Liveness for Fly checks → `{ok, mail}` (`mail` = transport: `ses`, `smtp` or `console`) | |
| GET | `/.well-known/apple-app-site-association` | – | AASA JSON for passkeys (`webcredentials`) on this host | 404 `not_found` when not configured |

## Legal pages

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/privacy` | – | Privacy Policy (HTML, operator from `LEGAL_*` env) | |
| GET | `/terms` | – | Terms of Use / EULA (HTML) | |
| GET | `/support` | – | Support page (HTML) | |

## Over-the-air config (#583)

Source: `backend/content/` (see its README). Data only, never code (App Review 2.5.2).

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/app-config` | – | Flags, values, `minimumBuild` / `recommendedBuild`, `update`, packs by SHA-256; `ETag`, `X-Content-Signature` (Ed25519, when `CONTENT_SIGNING_KEY` set) | 304 on `If-None-Match`; 120/min per IP |
| GET | `/v1/packs/:name/:sha` | – | Content pack (`recipes`, `foods`, `whats-new`, `coach-tips`), immutable | 404 `not_found` on unknown name or hash; 120/min per IP |

## Auth

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| POST | `/v1/auth/register` | – | `{email, password, name?, acceptedTerms}` → 202 `verification_required`; 6-digit code emailed. Enumeration-safe | 400 `weak_password`, `breached_password`, `terms_required`; auth rate limit |
| POST | `/v1/auth/verify-email` | – | `{email, code, password?}` → `{user, tokens}` | 400 `invalid_code`, `too_many_attempts`; auth rate limit |
| POST | `/v1/auth/resend-verification` | – | `{email}` → 202 `sent_if_pending` | once per minute per address; auth rate limit |
| POST | `/v1/auth/login` | – | `{email, password}` → `{user, tokens}` or 403 `mfa_required {mfaToken, methods}` when 2-step is on | 401 `invalid_credentials`; 403 `email_not_verified`; 429 `account_locked {lockedUntil}`; auth rate limit |
| POST | `/v1/auth/apple` | – | `{identityToken, authorizationCode?, name?, nonce?}` → `{user, tokens, created}`. Links a verified email; code exchanged for an Apple refresh token (revoked on deletion) | 401 `invalid_apple_token`; auth rate limit |
| POST | `/v1/auth/mfa` | – | Completes 2-step: `{mfaToken, code \| recoveryCode}` → `{user, tokens}` | 401 `mfa_expired`, `invalid_code`; 429 `too_many_attempts`; auth rate limit |
| POST | `/v1/auth/passkey/options` | – | WebAuthn assertion options → `{challengeId, options}` | auth rate limit |
| POST | `/v1/auth/passkey` | – | `{challengeId, response}` (WebAuthn assertion JSON) → `{user, tokens}` | 400 `challenge_expired`; 401 `passkey_invalid`; auth rate limit |
| POST | `/v1/auth/refresh` | – | `{refreshToken}` → a new token pair `{accessToken, refreshToken, ...}` (not wrapped in `tokens`; single-use rotation) | 401 `invalid_refresh_token`; 60/min |
| POST | `/v1/auth/logout` | – | `{refreshToken}` → 204, revokes that session | |
| POST | `/v1/auth/password/forgot` | – | `{email}` → 202 `sent_if_exists` | auth rate limit |
| POST | `/v1/auth/password/reset` | – | `{email, code, newPassword}` → 204; signs out every device (access tokens too) | 400 `invalid_code`, `weak_password`, `breached_password`; auth rate limit |

## Account

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me` | Bearer | → `{user}` (id, email, name, verified, sign-in methods) | |
| PATCH | `/v1/me` | Bearer | `{name: string \| null}` → `{user}` | |
| DELETE | `/v1/me` | Bearer + re-auth | `{confirm: "DELETE", password?}` → 204. Permanent: cascades every row, rate-limit records and call-name recordings, revokes Sign in with Apple; spends the grant | 403 `reauth_required` |
| POST | `/v1/me/password` | Bearer + re-auth | `{currentPassword?, newPassword}` → `{tokens}`; every other session and access token ended, email notice; spends the grant | 403 `reauth_required`; 400 `weak_password`, `breached_password` |
| POST | `/v1/me/email` | Bearer + re-auth | `{newEmail, password?}` → 202; code sent to the new address. Enumeration-safe; spends the grant | 400 `same_email`; auth rate limit |
| POST | `/v1/me/email/confirm` | Bearer | `{code}` → `{user}`; old address notified | 400 `invalid_code`, `too_many_attempts`; 409 `email_taken`; auth rate limit |
| GET | `/v1/me/sessions` | Bearer | → `{sessions: [{device, createdAt, expiresAt}]}` signed-in devices, newest first | |
| POST | `/v1/me/logout-all` | Bearer | → 204, revokes every refresh token, access token and open re-auth grant | |
| GET | `/v1/me/export` | Bearer | Full JSON export of the member's data (nFADP / GDPR), streamed: synced records in time order, machine-note photos, community profile (level, pronouns, photo), reports filed, library saves, plan copies, Garmin watches and inbox, passkeys (id, name, dates), 2-step on/off, watch key set or not | 429 `rate_limited` (3 per hour) |
| POST | `/v1/me/reports` | Bearer | Report a problem: `{kind bug\|broken\|idea, area, text, screen?, error?, via, app{version, build, os, device, locale?}, screenshots[≤3 base64 JPEG]}` → 201 `{id, issueNumber}` | 503 `reports_off`; 10/hour; body ≤ 2.4 MB |

## Security (re-auth, 2-step, passkeys)

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me/security` | Bearer | → overview: sign-in methods, 2-step on/off, recovery codes left, passkeys | |
| POST | `/v1/me/reauth/email-code` | Bearer | Emails a 6-digit re-auth code → 202 | 400 `no_verified_email`; resend once a minute; auth rate limit |
| POST | `/v1/me/reauth/passkey-options` | Bearer | → `{challengeId, options}` for a passkey re-auth | 400 `no_passkeys` |
| POST | `/v1/me/reauth` | Bearer | One of `{method: password, password}`, `{method: apple, identityToken, nonce?}`, `{method: email_code, code}`, `{method: totp, code}`, `{method: passkey, challengeId, response}` → `{reauthToken, expiresIn: 300}` | 401 `reauth_failed`; 429 `too_many_attempts`; auth rate limit |
| POST | `/v1/me/mfa/totp/setup` | Bearer + re-auth | → `{secret, otpauthUrl}` (pending until enabled) | 409 `mfa_already_enabled` |
| POST | `/v1/me/mfa/totp/enable` | Bearer + re-auth | `{code}` → `{recoveryCodes}` (10, shown once) | 400 `mfa_not_started`, `invalid_code` |
| POST | `/v1/me/mfa/recovery-codes` | Bearer + re-auth | → new `{recoveryCodes}`; old ones void | 400 `mfa_not_enabled` |
| DELETE | `/v1/me/mfa` | Bearer + re-auth | → 204, turns 2-step off | |
| GET | `/v1/me/passkeys` | Bearer | → `{passkeys}` (id, name, created, last used) | |
| POST | `/v1/me/passkeys/options` | Bearer + re-auth | WebAuthn registration options → `{challengeId, options}` | 400 `too_many_passkeys` (20) |
| POST | `/v1/me/passkeys` | Bearer + re-auth | `{challengeId, response, name?}` → `{passkeys}` | 400 `passkey_invalid`, `challenge_expired`; 409 `passkey_exists` |
| PATCH | `/v1/me/passkeys/:id` | Bearer | `{name}` → `{passkeys}` | 404 `not_found` |
| DELETE | `/v1/me/passkeys/:id` | Bearer + re-auth | → `{passkeys}` | 404 `not_found` |

## Sync: profile, logs, workouts

All `GET` pulls take `?since=ISO` (delta + `deleted` ids) and return `serverTime`; with `?limit=1–1000&cursor=` they page and add `nextCursor`. All `POST` uploads upsert by client UUID (any letter case, stored lower case) and may return `conflicts`. Over the row or byte quota → 409 `quota_exceeded`; an item over its size → 413 `too_large`. See [README.md › Sync protocol](README.md#sync-protocol).

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me/profile` | Bearer | → `{data, updatedAt}` opaque app profile JSON | |
| PUT | `/v1/me/profile` | Bearer | `{data}` → `{updatedAt}` (last write wins) | 413 `too_large` (200 KB) |
| GET | `/v1/me/logs` | Bearer | → `{logs, deleted?, serverTime}` set logs `{id, date, exerciseId, sessionId?, weightKg?, reps?, setIndex?, rir?}` | |
| POST | `/v1/me/logs` | Bearer | `{logs[≤500]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded` |
| DELETE | `/v1/me/logs/:id` | Bearer | → 204, tombstoned | |
| GET | `/v1/me/workouts` | Bearer | → `{workouts, deleted?, serverTime}` completed sessions (opaque JSON with `id`, `startedAt`) | |
| POST | `/v1/me/workouts` | Bearer | `{workouts[≤100]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/workouts/:id` | Bearer | → 204 | |

## Sync: member content

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me/custom-workouts` | Bearer | → `{workouts, deleted?, serverTime}` member-built workouts (`id`, `name`, `items[].exerciseId`, `visibility`; other app fields kept as sent, e.g. `routine` `{color, symbol}` for own daily routines, #732) | |
| POST | `/v1/me/custom-workouts` | Bearer | `{workouts[≤100]}` → `{saved, serverTime, conflicts?}`; `visibility` members/public shares it to the library | 403 `community_profile_required` to share; 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/custom-workouts/:id` | Bearer | → 204 | |
| GET | `/v1/me/custom-exercises` | Bearer | → `{exercises, deleted: [], serverTime}` (deletion = `archived` flag) | |
| POST | `/v1/me/custom-exercises` | Bearer | `{exercises[≤20]}` (photo base64 JPEG inside, metadata stripped) → `{saved, serverTime, conflicts?}` | 400 `invalid_image`; 409 `quota_exceeded`; 413 `too_large` |
| GET | `/v1/me/pr-attempts` | Bearer | → `{attempts, deleted?, serverTime}` (`exerciseId`, `date`, `kind` oneRepMax\|repMax\|maxReps, `kg`, `reps`, `success`) | |
| POST | `/v1/me/pr-attempts` | Bearer | `{attempts[≤200]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/pr-attempts/:id` | Bearer | → 204 | |
| GET | `/v1/me/body-measurements` | Bearer | → `{measurements, deleted?, serverTime}` (`date`, `girthsCm`, `weightKg`, `bodyFatPct`) | |
| POST | `/v1/me/body-measurements` | Bearer | `{measurements[≤200]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/body-measurements/:id` | Bearer | → 204 | |
| GET | `/v1/me/climbs` | Bearer | → `{climbs, deleted?, serverTime}` climbing sessions | |
| POST | `/v1/me/climbs` | Bearer | `{climbs[≤200]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/climbs/:id` | Bearer | → 204 | |
| GET | `/v1/me/sports` | Bearer | → `{sports, deleted?, serverTime}` other sport sessions (snowboard, MTB, Hyrox…) | |
| POST | `/v1/me/sports` | Bearer | `{sports[≤200]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/sports/:id` | Bearer | → 204 | |
| POST | `/v1/me/watch-key` | Bearer | → `{key}`: upload key for the Apple Watch's direct sport upload (replaces the previous one) | |
| POST | `/v1/watch/sports` | X-Watch-Key | Watch uploads finished sport sessions without the phone: `{sports[≤10]}` → `{saved, serverTime}` | 401 `invalid_token`; 30/min |
| GET | `/v1/me/machine-notes` | Bearer | → `{notes, deleted?, serverTime}` private machine setup notes (gym, exercise, fields, text, `photoId`) | |
| POST | `/v1/me/machine-notes` | Bearer | `{notes[≤200]}` → `{saved, serverTime, conflicts?}` | 409 `quota_exceeded`; 413 `too_large` |
| DELETE | `/v1/me/machine-notes/:id` | Bearer | → 204 (photo removed too) | |
| PUT | `/v1/me/machine-notes/:id/photo` | Bearer | Raw `image/jpeg` body, EXIF stripped → `{photoId, updatedAt}` | 404 `not_found` (sync the note first); 415 `unsupported_media_type`; 400 `invalid_image`; 409 `quota_exceeded` |
| DELETE | `/v1/me/machine-notes/:id/photo` | Bearer | → `{photoId: null, updatedAt}` | 404 `not_found` |
| GET | `/v1/me/machine-notes/photos/:photoId` | Bearer | JPEG, owner only, `Cache-Control: private` | 404 `not_found` |

## Push and notifications

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| PUT | `/v1/me/push-device` | Bearer | `{token (hex), env sandbox\|production, topic (bundle id), tz?}` → `{ok, pushConfigured}`; a token moves to the last account registering it | 400 `invalid_topic` |
| DELETE | `/v1/me/push-device/:token` | Bearer | → 204 (sign-out) | |
| GET | `/v1/me/notification-prefs` | Bearer | → `{prefs, pushConfigured}`: toggles, reminder / check-in times, quiet hours (minutes after midnight) | |
| PUT | `/v1/me/notification-prefs` | Bearer | `{prefs}` (any subset; what it leaves out keeps its saved value) → `{prefs}` | |
| POST | `/v1/me/achievements` | Bearer | `{achievements[≤30]: {id, type, text}}` → `{announced}`; each new id pushed once to followers, at most 20 a day per member | 30/min |
| POST | `/v1/me/push-test` | Bearer | Test push to own devices → `{devices, sent, pushConfigured}` | 5/min |

## Community

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me/public-profile` | Bearer | → `{profile}` account profile (nickname, about, photo), joined or not | |
| PUT | `/v1/me/public-profile` | Bearer | `{nickname?, bio?}` → `{profile}` | 409 `nickname_taken`; 400 `objectionable_content` |
| PUT | `/v1/me/public-profile/avatar` | Bearer | Raw `image/jpeg` ≤ 512 KB, 64–1024 px, metadata stripped → `{profile}` | 413 `image_too_large`; 400 `invalid_image`; 415 |
| DELETE | `/v1/me/public-profile/avatar` | Bearer | → `{profile}` | |
| GET | `/v1/community/me` | Bearer | → community profile (`nickname`, `bio`, `defaultVisibility` private\|members\|public, `autoShare`, gym) or null | |
| PUT | `/v1/community/me` | Bearer | Join / update; joining needs `acceptGuidelines: true` → profile | 400 `guidelines_required`, `nickname_required`; 409 `nickname_taken` |
| DELETE | `/v1/community/me` | Bearer | Leave: profile, photo, posts, cheers and the reports you filed removed → 204 | |
| PUT | `/v1/community/me/level` | Bearer | `{level 1–999}` → `{level}` | 404 `not_member` |
| PUT | `/v1/community/me/pronouns` | Bearer | `{pronouns: string \| null}` (≤ 24 chars) → `{pronouns}` | 404 `not_member` |
| PUT | `/v1/community/me/socials` | Bearer | Socials (#745): `{socials: {instagram?, tiktok?, strava?, youtube?}, visibility? everyone\|following\|nobody}`; handles without `@`, empty removes → `{socials, visibility}`. Members see them on `GET /v1/community/members/:userId` per visibility (default following) | 400 invalid handle; 404 `not_member` |
| PUT | `/v1/community/me/avatar` | Bearer | Same as public-profile avatar (older apps) | as above |
| DELETE | `/v1/community/me/avatar` | Bearer | Removes the photo | |
| GET | `/v1/community/avatars/:id` | – | Avatar JPEG; unguessable id, immutable cache | 404 |
| GET | `/v1/community/feed` | Bearer | `?scope=members\|following\|mine&before=ISO&beforeId=&limit=` → `{posts, nextBefore, nextBeforeId}`; blocks applied both ways | 403 `community_profile_required` |
| POST | `/v1/community/posts` | Bearer | Share a win: `{id (client UUID), kind workout\|badge\|record\|climb\|note, refId?, payload, caption?, visibility?}` (`refId` dedupes; an update keeps the caption and visibility it leaves out) → post | 400 `objectionable_content`; 429 `daily_limit` |
| PATCH | `/v1/community/posts/:id` | Bearer | Own post: `{visibility?, caption?}` → post | 404 `not_found` |
| DELETE | `/v1/community/posts/:id` | Bearer | Own post → 204 (also when already gone) | 404 `not_found` (someone else's post) |
| PUT | `/v1/community/posts/:id/reactions/:kind` | Bearer | Cheer (`like`, `strong`, `fire`, `clap`, `beast`, `banana`), not on own posts → `{post}` | 400 `own_post`; 404 |
| DELETE | `/v1/community/posts/:id/reactions/:kind` | Bearer | Remove a cheer → `{post}` | 404 `not_found` (post you can't see) |
| GET | `/v1/community/members` | Bearer | Find members: `?q=` nickname or gym, `?gym=mine`, `?limit≤50`; empty `q` = suggestions → `{members}` | |
| GET | `/v1/community/members/:userId` | Bearer | → `{member, posts, blockedByMe, followedByMe}` | 404 `not_found` (not a member, blocked, or hidden by reports) |
| GET | `/v1/community/follows` | Bearer | Members you follow, by nickname: `?limit=1–500 (default 500)&after=nickname` → `{following, nextAfter}` | |
| PUT | `/v1/community/follows/:userId` | Bearer | Follow → 204 | 400 `own_content`; 404 `not_found` |
| DELETE | `/v1/community/follows/:userId` | Bearer | Unfollow → 204 | |
| POST | `/v1/community/reports` | Bearer | `{postId \| userId, reason spam\|harassment\|hate\|sexual\|violence\|other, details?}` → 202 `{status: received, hidden}`; auto-hidden after 3 distinct reporters, mailed to moderation | 20/hour |
| GET | `/v1/community/blocks` | Bearer | → blocked members | |
| POST | `/v1/community/blocks` | Bearer | `{userId}` → 204; also removes follows both ways | |
| DELETE | `/v1/community/blocks/:userId` | Bearer | Unblock → 204 | |
| GET | `/v1/community/buddies` | Bearer | Gym buddies (#626) → `{buddies: [{userId, nickname, avatarUrl, level, status paired\|invited\|invites_you, live, shareLive}]}`; `shareLive` false when you keep your live set from them (#675); `live` (`title, exercise, detail, state set\|rest\|done, updatedAt`) only when paired and sent in the last 10′ | 403 `community_profile_required` |
| PUT | `/v1/community/buddies/:userId` | Bearer | Invite, or accept an invite → `{status: paired\|invited}`; up to 20; push `buddy_invite` (`actorId`, `actorName`) to the invitee, or to the inviter once paired | 400 `own_content`, `too_many_buddies`; 404 |
| PATCH | `/v1/community/buddies/:userId` | Bearer | `{shareLive}` → `{shareLive}`: keep your live set from this buddy or share it again (#675) | 404 not your buddy |
| DELETE | `/v1/community/buddies/:userId` | Bearer | Unpair, cancel or decline → 204; blocking or leaving the community also unpairs | |
| POST | `/v1/community/buddies/:userId/cheers` | Bearer | `{kind fire\|banana\|beast}` to a paired buddy → 204 | 404 not paired; 60/min |
| PUT | `/v1/community/live` | Bearer | Live set for buddies and the challenge room: `{title, exercise, detail?, state set\|rest\|done, challengeWeek?}` → 204; one row, replaced per set | 400 `objectionable_content`; 403 `community_profile_required` |
| DELETE | `/v1/community/live` | Bearer | Workout ended → 204 | |
| GET | `/v1/community/live/cheers` | Bearer | `?after=` last id seen → `{cheers: [{id, from: {userId, nickname}, kind, at}], last}`; last 10′ only | |
| GET | `/v1/community/challenge` | Bearer | Weekly challenge room: `?week=YYYY-Www` (default this ISO week) → `{week, joined, training, leaderboard[≤20]: {rank, userId, nickname, avatarUrl, level, rounds, reps, live, me}, me}`; blocks and hidden members left out of ranks and counts | 400 `invalid_request` (week that doesn't exist); 403 `community_profile_required` |
| PUT | `/v1/community/challenge/score` | Bearer | `{week, rounds 0–200, reps 0–999}` → `{week, rounds, reps, rank, best}`; the best score stays | 400 `week_closed` |
| GET | `/v1/community/programs` | Bearer | Shared plans (#666), newest first: `?q=` name, `?level=beginner\|intermediate\|advanced`, `?mine=1` your own (private too), `?before=&beforeId=` (creation time), `?limit=` → `{programs: [{id, name, about, level, goal, weeks, sessionsPerWeek, programme, author, mine, visibility, copies, copiedByMe, hidden}], nextBefore, nextBeforeId}`; blocked and auto-hidden left out | 403 `community_profile_required` |
| GET | `/v1/community/programs/:id` | Bearer | One plan → `{program}` | 404 `not_found` |
| PUT | `/v1/community/programs/:id` | Bearer | Create or update your plan: `{name ≤60, about?, level, goal?, weeks, sessionsPerWeek, programme (app record), visibility? (default members)}` → `{program}` | 400 `objectionable_content`, 409 `conflict`, 413, 429 `daily_limit` (20 new/day) |
| DELETE | `/v1/community/programs/:id` | Bearer | Remove your plan → 204 (also when already gone) | 404 `not_found` (someone else's plan) |
| POST | `/v1/community/programs/:id/copy` | Bearer | Counts a copy into My programmes (once per member; the app saves the copy) → `{program}` | 404 |
| POST | `/v1/community/programs/:id/report` | Bearer | `{reason, details?}` → 202 `{status: received, hidden}`; auto-hidden after 3 distinct reporters | 20/hour |
| GET | `/share/:id` | – | Public web card of a `public` post (HTML, Open Graph) | 404 |
| GET | `/i/:code` | – | Invite page (#745): inviter's nickname, code, link to get the app (`INVITE_APP_URL`) | 404 |

## Invite a friend (#745)

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/referrals/me` | Bearer | → `{code, path, joined, subscribed, invitedBy: {nickname, at} \| null, canRedeem}`; `subscribed` = invitees with a paid (non-trial, not revoked) App Store subscription | |
| POST | `/v1/referrals/redeem` | Bearer | `{code}` (case-insensitive), accounts ≤ 14 days old, once → same as GET | 404 `invalid_code`; 400 `own_code`, `account_too_old`, `referral_cycle`; 409 `already_redeemed`; 10/hour |

## Workout library

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/library/shared` | Bearer | Members' shared workouts, newest first: `?q=`, `?before=&beforeId=`, `?limit=` → `{workouts, nextBefore, nextBeforeId}`; blocked and auto-hidden left out | 403 `community_profile_required` |
| GET | `/v1/library/shared/:id` | Bearer | One shared workout | 404 `not_found` |
| POST | `/v1/library/shared/:id/save` | Bearer | Counts a copy into My workouts → `{workout}` | 404 |
| POST | `/v1/library/shared/:id/report` | Bearer | `{reason, details?}` → 202 `{status: received, hidden}`; auto-hidden after 3 distinct reporters | 20/hour |

## Gyms

Only counts are shared between members, never who reported.

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| PUT | `/v1/gyms/reports` | Bearer | Your equipment list for a gym `{gym{id, name, lat?, lon?}, equipment[], unsure[]}` (`latitude`/`longitude` also accepted) → `{saved}` (replaces yours, also at the same place under another id) | 409 `quota_exceeded` |
| DELETE | `/v1/gyms/reports` | Bearer | `?id=` → 204 | |
| GET | `/v1/gyms/known` | Bearer | `?id=&name=&lat=&lng=` → what members report, one vote per member: `{place: {members, votes, equipment} \| null, chain: {members, votes, equipment, name, gyms} \| null}` | |
| PUT | `/v1/gyms/maps` | Bearer | Your floor plan `{gym, layout{zones[], door?, sizeM?}}` → `{saved}` (one per place) | 400 `objectionable_content` (zone name); 409 `quota_exceeded` |
| GET | `/v1/gyms/maps` | Bearer | `?id=&name=` → `{map: {layout, members, agreement} \| null}` the plan members agree with most (yours excluded) | |
| POST | `/v1/gyms/busy` | Bearer | "Taken?" tap `{gym{id}, zone}` → `{saved}` (one per member, gym, zone per 5 min; hourly cap) | |
| GET | `/v1/gyms/crowd` | Bearer | `?id=&tz=` → busy zones now and by hour | |

## Coach (AI and voices)

Paid model calls: Pro once subscriptions are enforced, per-member daily caps, global `AI_DAILY_LIMIT` per UTC day.

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me/coach-chat` | Bearer | → `{available, remainingToday}` | |
| POST | `/v1/me/coach-chat` | Bearer | `{turns[1–30]{role member\|coach, text}, context{goal, level, sessionMinutes, equipment, readiness, todayPlanned, method, screen, focus, pronouns, callName, memory}}` → `{reply, workout?, action?, suggestions, remainingToday}` | 402 `pro_required`; 429 `daily_limit`, `busy`; 502 `coach_failed`; 503 `coach_unavailable` |
| POST | `/v1/me/gym-scan` | Bearer | `{photo (base64 JPEG ≤ 1.5 MB), catalog[≤150]{id, label}}` → `{items, remainingToday}` equipment seen | 402; 403 `verification_required`; 429; 502 `scan_failed`; 503 `scan_unavailable` |
| POST | `/v1/me/food-scan` | Bearer | `{photo, catalog[≤400], mode? fridge\|plate\|auto}` → `{items, found[{id \| new food, sure, alcohol, per100}], remainingToday}`; `plate` (#723, a cooked meal) adds `dish` and per food `grams`, `caffeine` (mg/100 g); `auto` (#733, Magic Snap) answers like `plate` plus `kind` meal\|stock (stock: `dish` ""); one daily count for all modes | as gym scan |
| GET | `/v1/me/coach-voices` | Bearer | → `{available, voices, lines[{id, text, hash}]}`; `available: false` (200) when voices aren't configured | |
| GET | `/v1/me/coach-voices/:voice/:line` | Bearer | MP3 of one line (made once with Polly, cached on the volume) | 404; 502 `voice_failed`; 600/min |
| GET | `/v1/me/coach-voices/:voice/call/:style` | Bearer | MP3 of the short call with the member's name (`X-Call-Name` header); kept in memory for an hour, never on disk; a new name counts against `AI_DAILY_LIMIT` | 400 `bad_name`; 429 `daily_limit`, `busy`; 30/min |

## Subscriptions (Pro)

See [`../subscriptions.md`](../subscriptions.md).

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| GET | `/v1/me/entitlement` | Bearer | → `{mode, pro, access, source subscription\|grant\|none, productId, expiresAt, trial, willRenew, grant, products, test?}` | |
| POST | `/v1/me/subscriptions/transactions` | Bearer | `{signedTransaction, signedRenewalInfo?}` StoreKit 2 JWS, verified to Apple Root CA - G3 → entitlement | 400 `invalid_transaction`, `unknown_product`, `sandbox_transaction`; 403/409 `subscription_other_account` |
| PUT | `/v1/me/subscriptions/test` | Bearer | Staging only (`SUBSCRIPTION_TESTS=on`, else 404): `{mode off\|preview\|enforced\|null}` for this account → entitlement | 404 |
| POST | `/v1/me/subscriptions/test/purchase` | Bearer | Staging only: fake purchase `{productId}` → entitlement | 404 |
| POST | `/v1/me/subscriptions/test/cancel` | Bearer | Staging only: `{end?}` → entitlement | 404 |
| POST | `/v1/app-store/notifications` | Apple JWS | App Store Server Notifications V2 `{signedPayload}` → 200 / 400 | 300/min |

## Garmin watches

| Method | Path | Auth | Summary | Errors / limits |
|---|---|---|---|---|
| POST | `/v1/garmin/pair` | – | Watch asks for a pairing code: `{model?}` → `{token, code, expiresAt}` | 5/min |
| GET | `/v1/garmin/snapshot` | X-Garmin-Token | → `{paired: false, code, expiresAt}` while waiting, else `{paired: true, snapshot, updatedAt}` | 401 `invalid_token`; 30/min |
| POST | `/v1/garmin/events` | X-Garmin-Token | `{events[≤50]}` sets, finished workouts, water → `{saved, serverTime}` | 403 `not_paired`; 413 `too_large`; 429 `inbox_full`; 30/min |
| POST | `/v1/me/garmin/claim` | Bearer | `{code}` typed in Settings › Watches → `{id, model, pairedAt}` | 404 `unknown_code`; 409 `too_many_devices`; 10/min |
| GET | `/v1/me/garmin/devices` | Bearer | → paired watches | |
| DELETE | `/v1/me/garmin/devices/:id` | Bearer | Unpair → 204 | |
| PUT | `/v1/me/garmin/snapshot` | Bearer | `{snapshot}` what the watch shows (next session, water) → `{updatedAt}` | 413 `too_large` |
| GET | `/v1/me/garmin/inbox` | Bearer | → `{events}` from the watch, oldest first; `id` is the inbox id to ack, `eventId` the watch's own id | |
| POST | `/v1/me/garmin/inbox/ack` | Bearer | `{ids[≤200]}` → `{removed}` | |
