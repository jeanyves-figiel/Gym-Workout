# Security and data protection

Design and controls. The repository is public: no secret values, keys, bucket names or member data belong here or anywhere in the repo. Report a vulnerability privately to the contact on [`/support`](https://workout.monkeygrade.cloud/support), not in a public issue.

## Authentication

| Method | How it works |
|---|---|
| Email + password | Password ≥ 10 chars, common and email-derived passwords rejected, checked against Have I Been Pwned (k-anonymity range API: only 5 hex chars of the SHA-1 leave the server, padded, 2 s timeout, fails open). Hashed with scrypt (N=2¹⁵, r=8, p=1, random salt), at most a few hashes at once. Unknown accounts hash a dummy to keep timing equal. Email verified by a 6-digit code before first sign-in. |
| Sign in with Apple | Identity token verified against Apple's JWKS (issuer, bundle-id audience, expiry). The raw `nonce` must match the token's SHA-256 `nonce` claim and is accepted once (replay). The authorization code is exchanged for an Apple refresh token (stored AES-256-GCM encrypted) so account deletion can revoke it at Apple. A verified Apple email links to an existing account. |
| Passkeys | WebAuthn via SimpleWebAuthn; relying party per environment (`WEBAUTHN_RP_ID`), associated domains served from `/.well-known/apple-app-site-association`. Up to 20 per account; challenges single use, 5 min. |
| 2-step (optional) | TOTP (RFC 6238) with 10 single-use recovery codes. Password sign-in then answers 403 `mfa_required` with a short-lived `mfaToken`. Apple and passkey sign-ins skip it unless `APPLE_TWO_STEP=on` (Apple). |

**Email codes:** 6 digits, HMAC with a server pepper at rest, 15 min, 5 attempts, a new code voids older ones, resend once a minute, per-address hourly caps.

**Lockout:** 10 failed logins from one IP lock that IP out of the account for 15 min; 100 failures a day across IPs lock password sign-in for the day (a reset reopens it). IPs come from Fly's proxy (`Fly-Client-IP`), never the client-supplied `X-Forwarded-For`.

**Enumeration:** register, resend, forgot password and email change answer the same whether or not the account exists.

## Sessions and tokens

- **Access token:** HS256 JWT, 15 min, algorithm pinned, signed with `JWT_SECRET`. Every authenticated route checks the account still exists and that the token was issued after the account's `tokens_valid_after` (ms precision), so a password change or reset and sign out everywhere end open access tokens too, not only refresh tokens.
- **Refresh token:** opaque 256-bit random, stored as SHA-256, 60 days, **single use with rotation**. Each sign-in starts a token family. Replaying a spent token whose replacement was never used is treated as a lost response (reissue); replaying after the replacement was used revokes the whole family.
- **Re-auth grant:** changing password or email, deleting the account, 2-step and passkey changes need `X-Reauth-Token` from `POST /v1/me/reauth` (password, Apple, email code, TOTP or passkey), valid 5 min, hashed at rest. A password change, email change or account delete spends the grant (given back if the change is refused); 2-step and passkey changes may reuse it for their two calls. Password change or reset and sign out everywhere drop every open grant.
- Password change or reset revokes every refresh token and access token (the change keeps only the tokens it returns) and emails a notice. Members see their devices and can sign out everywhere.
- **On the device:** tokens live in the Keychain, `AfterFirstUnlockThisDeviceOnly` (no iCloud sync, not restored to other devices). Optional Face ID app lock (`App/AppLock.swift`).

## Authorization and isolation

- Every query is scoped by the `user_id` from the verified token; upserts check ownership (`WHERE <table>.user_id = excluded.user_id`), so a client id belonging to another account is skipped. Tests cover cross-account access.
- Community: visibility per post (`private`, `members`, `public`), blocks applied both ways, reported content auto-hidden after 3 distinct reporters, word filter on nicknames and text, moderation mailbox.
- Machine-note photos and problem reports are owner-only; gym data is shared only as counts.
- Watch and Garmin tokens can reach only their narrow routes (sport upload; snapshot and events).
- Ops actions (restore, member delete, free access, undo workout) are not HTTP endpoints: they run on the machine from manual GitHub workflows with typed confirmations.

## Input handling

- zod schemas on every body, query and path (unknown fields dropped); 1 MB default body limit; per-item size caps; row quotas per table and a 50 MiB byte quota per member; full pulls stream or page instead of building the answer in memory.
- Text members share with others (nicknames, captions, gym map zone names) goes through the word filter. Custom exercise photos are re-checked as JPEG and stripped like every other upload.
- Images: JPEG only, size and dimension checks, APPn/comment segments (EXIF, GPS, XMP) stripped before storage.
- HTML pages (legal, share card) escape every interpolated value.
- Request logs never include bodies or tokens; the member's call name is redacted from URLs; emails are masked in ops logs. Problem reports filed as GitHub issues redact emails, tokens and other secrets in the title, text and every attached fact.
- The member's call name is never written to disk: its recording is kept in memory for an hour and dropped when the account is deleted.
- Staging-only subscription test routes (`SUBSCRIPTION_TESTS=on`) refuse to start when the server's passkey host is the production host.

## Encryption

| Where | Control |
|---|---|
| In transit | HTTPS only (`force_https`), TLS at Fly's edge. iOS ATS without exceptions except local networking for DEV. No certificate pinning (deliberate: rotation risk). |
| Server at rest | Fly volume encrypted. Secrets inside the DB: password hashes (scrypt), codes and tokens hashed (HMAC/SHA-256), TOTP secrets and Apple refresh tokens AES-256-GCM (key derived from `CODE_PEPPER`). Training data is plain inside the encrypted volume (needed for Community and levels). |
| Backups off-site | Gzipped and encrypted on the server (AES-256-GCM, key derived from `BACKUP_KEY` via scrypt) before upload: the storage provider only holds ciphertext. |
| iPhone / Watch | Files written with Data Protection `completeUntilFirstUserAuthentication` (readable by widgets and the Watch after first unlock); export file `complete`. API client keeps no HTTP cache; server sends `Cache-Control: no-store`. |

## Backups

- Fly volume snapshots, daily, kept 14 days, checked daily by the **Fly backups** workflow.
- App backup daily: `VACUUM INTO` a consistent copy on the volume, checked (`quick_check` + row counts) before it is kept, files 0600, 7 kept.
- Encrypted off-site copy daily, kept 30 days.
- Restore: staged copy is checked, then swapped in at the next start; the live DB is kept as `pre-restore-*`. A corrupt copy is refused. `verify` is a read-only drill. Per-member restore and delete exist for support cases.
- Retention fits the privacy policy promise that residual copies of deleted data are gone within 30 days.

## Secrets

Names only. Values are generated in CI runners or pasted by the owner into GitHub / Fly; never in the repo, logs or artifacts.

| Store | Names |
|---|---|
| Fly app secrets | `JWT_SECRET`, `CODE_PEPPER`, `BACKUP_KEY`, `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY`, `SMTP_URL`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `ANTHROPIC_API_KEY`, `ANTHROPIC_WORKSPACE_ID`, `POLLY_ACCESS_KEY_ID`, `POLLY_SECRET_ACCESS_KEY` (optional, else the SES keys), `GITHUB_REPORTS_TOKEN`, storage credentials (`AWS_*`, `BUCKET_NAME`) |
| GitHub Actions secrets | `FLY_API_TOKEN`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `BACKUP_KEY`, the Fly secrets above that **Fly setup** forwards, `GARMIN_DEVELOPER_KEY`, `GARMIN_USERNAME`, `GARMIN_PASSWORD`, `GARMIN_SETUP_TOKEN` |

Rules: each cloud credential has least privilege (the SES IAM user may send mail and synthesize speech, nothing else). Workflows that create credentials hide their output (a public log once exposed storage keys; they were rotated and the workflow now suppresses output). After changing a Fly secret, run **Fly setup** for that environment. Rotating `CODE_PEPPER` invalidates pending codes and makes stored Apple refresh tokens and TOTP secrets unreadable.

## Member rights (nFADP / GDPR)

- Export everything: Settings → Account → Export (`GET /v1/me/export`).
- Delete account in the app (App Store rule): all rows cascade, rate-limit records keyed by the id or email removed, Apple token revoked.
- Leave Community without deleting the account: profile, photo, posts, cheers and the reports the member filed are removed.
- Privacy policy at `/privacy` ([legal.md](legal.md)).

## Supply chain and process

- Dependabot for npm and Actions; `npm ci` with a lockfile; CI typecheck + tests on every PR.
- Staging deploys every merge; production runs the same image digest, promoted manually with the owner's OK.
- No secrets in Xcode project; signing via App Store Connect API key in CI.

## Threat model

| Asset | Threat | Mitigations |
|---|---|---|
| Accounts | Credential stuffing, brute force | HIBP check, scrypt, per-IP rate limit, per-IP and daily lockout, optional 2-step, passkeys |
| Accounts | Account enumeration | Uniform answers on register / reset / email change; dummy hash timing |
| Sessions | Stolen refresh token | Rotation with family revocation on replay, device list, sign out everywhere, Keychain this-device-only |
| Sessions | Stolen access token | 15 min life, ended at once by a password change or sign out everywhere, HTTPS only, no HTTP caching |
| Sensitive changes | Session hijack changes email / deletes | Fresh re-auth grant (5 min, single use) required |
| Sign in with Apple | Token replay | Nonce bound to one sign-in, accepted once |
| Member data | Cross-account access (IDOR) | Owner-scoped queries and upserts, tests |
| Member data | Server or volume loss | Snapshots, daily verified backups, encrypted off-site copy, restore drills |
| Member data | Backup provider breach | Client-side encryption before upload |
| Community | Abuse, harassment, objectionable content | Guidelines acceptance, word filter, reports with auto-hide, blocks, moderation email (App Store 1.2) |
| Paid services | Cost abuse (Claude, Polly) | Pro gating when enforced, per-member daily caps, global daily cap (call-name recordings included), email-verified or aged accounts only for scans |
| API | Request floods, large bodies | Per-IP rate limits keyed on Fly's client IP, body limits, row and byte quotas, daily caps on achievement and buddy pushes |
| Images | Location leak, parser bugs | JPEG only, metadata stripped, size and dimension caps |
| Webhooks | Forged App Store notifications | JWS chain verified to Apple Root CA - G3, bundle id and environment checked |
| Secrets | Leak via public repo or logs | Secrets only in GitHub/Fly stores, workflows suppress credential output, rotation procedure |
| Device | Lost phone | iOS Data Protection, optional Face ID lock, tokens not in backups to other devices |
