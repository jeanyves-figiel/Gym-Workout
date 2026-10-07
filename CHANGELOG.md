# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- iOS app (SwiftUI, iOS 17+, #9): welcome + Sign in with Apple, email sign-up with 6-digit verification, sign in, forgot/reset password, privacy notice; account screen with name, change/set password, signed-in devices, Face ID app lock, data export, sign out / sign out all devices, account deletion.
- On-device workout engine (`GymCore/WorkoutEngine`, Swift port of the validated generator, #1): session length from goal × frequency, weekly splits, warm-up → explosive → strength (supersets, paired mobility) → climber mobility → cardio → load-derived cool-down, 4-week mesocycle, Puls 5 equipment profile, 150 exercises.
- Plan UI: training profile, week view with mesocycle navigation and variations, session view with tick-off, swap, rest timer with haptics, weight logging with last weight.
- `GymCore/APIClient`: Keychain token storage, single-flight token refresh, profile + log sync with offline queue.
- XcodeGen project with Debug/Staging/Release configs, privacy manifest, macOS CI (package tests + simulator builds).
- Auth & sync API (`backend/`, #8): email/password registration with emailed 6-digit verification, login with lockout, Sign in with Apple, rotating refresh tokens with replay detection, forgot/reset & change password, logout / logout all devices, account deletion, data export, profile + workout-log sync, per-IP rate limiting.
- API Docker image, CI (typecheck, tests, image build), staging auto-deploy and manual "Promote to production" (same image) workflows.
- Repository bootstrap (README, CHANGELOG, .gitignore).
