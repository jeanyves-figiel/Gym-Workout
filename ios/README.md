# MonkeyWorkout iOS

SwiftUI, iOS 17+, iPhone. Workout engine runs on-device (offline at the gym); account + sync via the API.

## Setup (Mac)

```bash
brew install xcodegen
cd ios && xcodegen generate && open MonkeyWorkout.xcodeproj
```

1. Signing team `U7VAR53G86` is preset (automatic signing). Sign in with Apple + HealthKit are enabled on the App ID.
2. DEV: run the API (`cd backend && npm run dev`, http://localhost:7443), run scheme **MonkeyWorkout** (Debug) on a simulator. Verification codes are printed in the API console.
3. Staging (TestFlight): scheme **MonkeyWorkout Staging**. API `https://workout-staging.monkeygrade.cloud` (prod: `https://workout.monkeygrade.cloud`).

| Config | Bundle id | API |
|---|---|---|
| Debug | `Com.app.MonkeyWorkout.dev` | `http://localhost:7443` |
| Staging (TestFlight) | `Com.app.MonkeyWorkout` | `Config/Staging.xcconfig` |
| Release (App Store) | `Com.app.MonkeyWorkout` | `Config/Release.xcconfig` |

**App Store Connect:** name **MonkeyWorkout** · bundle ID `Com.app.MonkeyWorkout` · SKU `Monkeyworkout` · Apple ID `6819971090`.
Capabilities needed on the App ID(s): Sign in with Apple, HealthKit.

### TestFlight (CI upload)

Workflow **TestFlight (Staging)** (`.github/workflows/testflight.yml`) archives scheme **MonkeyWorkout Staging** (API `workout-staging.monkeygrade.cloud`) on a macOS runner and uploads it to App Store Connect. Manual only (Actions → TestFlight (Staging) → Run workflow); merges to `main` do not upload builds. Build number = workflow run number. Skips with a warning until the secrets below exist.

Signing is Xcode cloud/automatic signing via an App Store Connect API key: no certificates or profiles in the repo.

One-time setup (you, not CI):
1. App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **Generate API Key**. Name `GitHub CI`, access **Admin** (needed for cloud-managed distribution certificates). Download the `.p8` (only downloadable once). Note **Key ID** and **Issuer ID** (top of the page).
2. GitHub → repo → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID` = Key ID
   - `ASC_ISSUER_ID` = Issuer ID
   - `ASC_KEY_P8` = full contents of the `.p8` file (incl. `-----BEGIN PRIVATE KEY-----` lines), or its base64
3. Actions → **TestFlight (Staging)** → Run workflow.
4. App Store Connect → MonkeyWorkout → TestFlight: build appears after Apple processing; add yourself to an internal testing group, then install via the TestFlight app.

## Structure

| Path | Content |
|---|---|
| `Packages/GymCore/Sources/WorkoutEngine` | Plan generator (pure Swift, deterministic per seed), 150-exercise catalog, Puls 5 gym profile |
| `Packages/GymCore/Sources/APIClient` | Typed API client: Keychain tokens, single-flight refresh, sync |
| `MonkeyWorkout/Model` | `AppModel` (auth phase, plan, logs, sync), local JSON store (data protection) |
| `MonkeyWorkout/Views/Auth` | Welcome, Sign in with Apple, sign up, email code, sign in, forgot/reset, privacy notice |
| `MonkeyWorkout/Views/Plan` | Training profile, week, session (tick, swap, rest timer, per-set kg × reps × RIR log with load suggestion) |
| `MonkeyWorkout/Views/Account` | Name, password, devices, Face ID lock, export, sign out (all), delete account |

## Demo mode (DEBUG)

Launch arguments `-demo -demoScreen <welcome|week|session|player|explore|muscle|exercise|technique>` start with sample data, no network.
CI captures each screen (≤ 800 px) and pushes them to branch `screenshots/pr-<n>` + a workflow artifact.

## Tests

```bash
swift test --package-path Packages/GymCore   # engine + API client (also runs on Linux)
```
CI (`.github/workflows/ios.yml`, macOS): package tests + simulator builds for Debug and Staging.
