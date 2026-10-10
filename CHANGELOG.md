# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Log climbs** (#44): Train tab card for climbers (goal climbing or climbing days set) with climbs this week; log sheet with type (boulder, lead, top rope, outdoor), start, duration, effort 1–10, optional top grade and notes. Stored on device and written to Apple Health as a Climbing workout (estimated kcal) when Health is connected. Recent climbs strip merges in-app climbs with Health climbs from other apps (e.g. MonkeyGrade), long-press deletes in-app ones (and their Health workout). A hard climb yesterday or today shows a keep-grip-light note before the next session.
- **TestFlight distribute** workflow: waits for Apple processing, then adds the newest build to the internal TestFlight group "Workout" via the App Store Connect API. Runs after each TestFlight upload; also manual (group name input).
- Manual **Fly logs** workflow: prints recent staging/production API logs (errors by default) without local tools.
- Custom workouts (#28): build your own (name, catalog exercises with search + category/muscle filters, sets × reps, rest, optional kcal, reorder), edit/duplicate/delete, "Duplicate & edit" on example workouts; "My workouts" on Train, played and recorded like examples, synced with offline queue. API `/v1/me/custom-workouts` (upsert, `since`, delete; in export and account deletion).
- Per-set logging in the workout player (kg × reps, optional RIR), prefilled from a load suggestion; synced (`setIndex`/`rir` on logs, backward compatible; backend migration adds nullable columns) (#5).
- Load suggestions: double progression within the prescribed rep range, equipment-aware increments/rounding, −5 % below range, −10 % deload week; shown in player and on exercise page (#5).
- Per-exercise history (best e1RM trend, sessions with sets) from the exercise page (#5).
- Exercise illustrations from free-exercise-db (public domain, pinned commit) for 113 exercises: thumbnails on session cards, animated header with credit on exercise page, animated image in the player; disk-cached for offline use (#27).
- Sign in with Apple credential check on launch/foreground; signs out when the Apple ID link is revoked (#12).
- Account deletion revokes the Sign in with Apple token: server exchanges the authorization code at sign-in (refresh token stored encrypted) and calls Apple's revoke endpoint on deletion. Needs GitHub secrets `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, pushed to Fly by the **Fly setup** workflow; skipped until set (#12).
- Change email: Account → Change email, 6-digit code to new address, old address notified (`POST /v1/me/email`, `/v1/me/email/confirm`) (#13).
- Breached-password check (Have I Been Pwned, k-anonymity, fail-open, 2 s timeout) at sign-up, reset and change; `HIBP_CHECK=0` disables (#13).
- Purge job for expired codes, pending email changes and expired/revoked refresh tokens (`PURGE_INTERVAL_MIN`, default 60) (#13).
- Climbing schedule (#6): pick climbing weekdays (and optionally gym days) in the training profile; sessions are placed on weekdays around climbing: no heavy pull/grip or explosive block the day before climbing, push and leg days adjacent to climbing. Session cards, next-up card and session screen show weekday + "climbing tomorrow / day after climbing" hint. Climbing days/week follows picked weekdays; Health climbing hint hidden then. Profiles without weekdays generate unchanged plans.
- **Staging smoke test** workflow (#26): after each staging deploy, checks `/healthz`, that mail goes via SMTP, sign-up email accepted by SES (mailbox simulator), unverified-login refusal, forgot-password and auth guards. `/healthz` now reports the mail transport.
- Example workouts on the Train tab: **Arms + Shoulder** (10 exercises) and **Lowerbody** (10 exercises), 3 × 10 each, with source-plan calories and activity points; open, tick off and play like any session, recorded to history. 12 new exercises with full setup/technique (barbell split squat, barbell & incline curls, lying barbell/dumbbell French press, standing reverse fly, diamond push-up, seated calf raise, hip adduction/abduction, seated crunch, torso rotation) and 4 new machines; example-only exercises are never picked by the generator.
- **TestFlight (Staging)** workflow (#12): archives the Staging scheme on macOS and uploads to App Store Connect using an App Store Connect API key (cloud signing); skips until `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_KEY_P8` are set. Setup steps in `ios/README.md`.
- Staging + production hosted on Fly.io (#3): apps `monkeyworkout-staging` → `https://workout-staging.monkeygrade.cloud`, `monkeyworkout-prod` → `https://workout.monkeygrade.cloud` (`backend/fly.*.toml`, region `fra`, 1 machine + `/data` volume, `/healthz` check). **Deploy staging** deploys the CI-built image on every merge to `main`; **Promote to production** (manual) deploys the same digest to prod. Both skip with a warning until `FLY_API_TOKEN` is set. Manual **Fly setup** workflow bootstraps app, volume, secrets and TLS cert per environment without local tools. Email via Amazon SES SMTP (eu-central-2, dedicated send-only IAM user; SMTP password derived in CI) from `no-reply@monkeygrade.cloud` when repo secrets `SES_ACCESS_KEY_ID`/`SES_SECRET_ACCESS_KEY` (or `SMTP_URL`) are set, else codes logged. iOS Staging build → staging host, Release → prod host.

### Fixed
- **TestFlight distribute** no longer fails on internal groups with automatic distribution (Apple rejects manual assignment there; those groups already get every build).
- TestFlight uploads after the first failed ("bundle version must be higher than 1"): generated Info.plist hard-coded version 1.0 build 1. It now uses `MARKETING_VERSION` (set to 1.0, matching App Store Connect) and `CURRENT_PROJECT_VERSION` (CI run number).
- Email on staging/prod: SES Zurich (eu-central-2) has no SMTP endpoint, so sign-up failed with 500 (`ENOTFOUND email-smtp.eu-central-2.amazonaws.com`). API now sends via the SES HTTPS API (`SendRawEmail`, SigV4, same send-only IAM user); **Fly setup** pushes `SES_*` secrets and drops the old `SMTP_URL`. Smoke test accepts `ses` (#26).
- iOS local state decodes leniently: state saved by older builds no longer resets to empty when new fields are missing.
- API container: entrypoint fixes ownership of root-owned `/data` mounts (Fly volumes) before dropping to the `node` user (#3).

### Changed
- App renamed **MonkeyWorkout** (#21): Xcode project/target/schemes, display names, bundle IDs `Com.app.MonkeyWorkout` (Release + TestFlight staging) and `Com.app.MonkeyWorkout.dev` (DEV); App Store Connect SKU `Monkeyworkout`, Apple ID `6819971090` documented; signing team `U7VAR53G86` set.
- API: Sign in with Apple accepts the new bundle IDs, matched case-insensitively; emails sent as MonkeyWorkout (#21).

### Added
- Progress tab (#18): totals, week streak vs target, 12-week consistency calendar, sessions-per-week chart, estimated-1RM trend per lift, 28-day muscle balance map, personal records, 22 achievements (bronze/silver/gold with progress), full session history with per-exercise sets/weights, heart rate, kcal and muscle map.
- Apple Health (#18): writes each session as a workout (energy estimate + metadata) and reads weight, height, age, sex, resting HR, HRV, VO₂max, sleep, in-session heart rate and climbing workouts; readiness card (sleep, HRV and resting HR vs 30-day baseline); climbing-days suggestion from Health; body weight & VO₂max trends. Health data stays on device.
- Body & Health screen (#18): height, weight, birth year entered in-app when Health lacks them, optional write-back to Health; prompt on Train tab until known. Inclusive, optional identity: gender (woman, man, non-binary, genderfluid, agender, Two-Spirit, questioning, self-describe, prefer not to say) kept separate from optional sex for estimates (female, male, intersex, other, prefer not to say).
- API: workout history sync `/v1/me/workouts` (upsert, `since` delta, delete; included in export and account deletion) (#18).
- Equipment & correct positioning for every exercise (#16): equipment cards (icon, Puls 5 zone, adjustment advice), and per-exercise technique — numbered set-up steps (machine settings + start position), head-to-feet body-position checkpoints, common mistakes, breathing. Shown on exercise pages, as a "Setup & technique" sheet and inline checkpoints in the workout player, and as an equipment line on exercise cards. Covered for all 151 exercises by tests.
- Muscle visibility (#14): front/back body heat maps per session, per exercise and for the week; primary/assist muscle chips on every exercise; per-part "session flow" showing which muscles each category targets.
- Explore tab (#14): browse by muscle (tappable body map, muscle groups, weekly sets) or by category; muscle pages list related exercises grouped by category (main vs assist); exercise pages with map, cues, equipment and swap.
- Workout player (#14): full-screen step-through with category progress bar, set tracking, auto rest countdown (+15 s / skip), weight logging, next-up preview and a finish summary of muscles hit.
- DEBUG demo mode + CI screenshot job (≤ 800 px, branch `screenshots/pr-<n>`) for visual review (#14).
- Bold dark design system (#14): heavy rounded type, lime accent, gradient per category, progress rings, animated welcome screen.

### Changed
- Every session now ends with mandatory static stretching (≥ 3 stretches + breathing, never dropped by the time budget); block renamed "Stretching & cool-down" (#14).
- Climber prehab (shoulder + forearm antagonist) both supersetted into long main-lift rests (#14).
- Added side-delt stretch so every muscle has at least one stretch (#14).
- iOS app (SwiftUI, iOS 17+, #9): welcome + Sign in with Apple, email sign-up with 6-digit verification, sign in, forgot/reset password, privacy notice; account screen with name, change/set password, signed-in devices, Face ID app lock, data export, sign out / sign out all devices, account deletion.
- On-device workout engine (`GymCore/WorkoutEngine`, Swift port of the validated generator, #1): session length from goal × frequency, weekly splits, warm-up → explosive → strength (supersets, paired mobility) → climber mobility → cardio → load-derived cool-down, 4-week mesocycle, Puls 5 equipment profile, 150 exercises.
- Plan UI: training profile, week view with mesocycle navigation and variations, session view with tick-off, swap, rest timer with haptics, weight logging with last weight.
- `GymCore/APIClient`: Keychain token storage, single-flight token refresh, profile + log sync with offline queue.
- XcodeGen project with Debug/Staging/Release configs, privacy manifest, macOS CI (package tests + simulator builds).
- Auth & sync API (`backend/`, #8): email/password registration with emailed 6-digit verification, login with lockout, Sign in with Apple, rotating refresh tokens with replay detection, forgot/reset & change password, logout / logout all devices, account deletion, data export, profile + workout-log sync, per-IP rate limiting.
- API Docker image, CI (typecheck, tests, image build), staging auto-deploy and manual "Promote to production" (same image) workflows.
- Repository bootstrap (README, CHANGELOG, .gitignore).
