# MonkeyWorkout iOS

SwiftUI, iOS 17+, iPhone. Workout engine runs on-device (offline at the gym); account + sync via the API.

## Setup (Mac)

```bash
brew install xcodegen
cd ios && xcodegen generate && open MonkeyWorkout.xcodeproj
```

1. Select your team in *Signing & Capabilities* (Sign in with Apple capability is pre-declared).
2. DEV: run the API (`cd backend && npm run dev`, http://localhost:7443), run scheme **MonkeyWorkout** (Debug) on a simulator. Verification codes are printed in the API console.
3. Staging (TestFlight): scheme **MonkeyWorkout Staging**. Set real API hosts in `Config/Staging.xcconfig` / `Config/Release.xcconfig` (#3).

| Config | Bundle id | API |
|---|---|---|
| Debug | `Com.app.MonkeyWorkout.dev` | `http://localhost:7443` |
| Staging (TestFlight) | `Com.app.MonkeyWorkout` | `Config/Staging.xcconfig` |
| Release (App Store) | `Com.app.MonkeyWorkout` | `Config/Release.xcconfig` |

**App Store Connect:** name **MonkeyWorkout** · bundle ID `Com.app.MonkeyWorkout` · SKU `Monkeyworkout` · Apple ID `6819971090`.
Capabilities needed on the App ID(s): Sign in with Apple, HealthKit.

## Structure

| Path | Content |
|---|---|
| `Packages/GymCore/Sources/WorkoutEngine` | Plan generator (pure Swift, deterministic per seed), 150-exercise catalog, Puls 5 gym profile |
| `Packages/GymCore/Sources/APIClient` | Typed API client: Keychain tokens, single-flight refresh, sync |
| `MonkeyWorkout/Model` | `AppModel` (auth phase, plan, logs, sync), local JSON store (data protection) |
| `MonkeyWorkout/Views/Auth` | Welcome, Sign in with Apple, sign up, email code, sign in, forgot/reset, privacy notice |
| `MonkeyWorkout/Views/Plan` | Training profile, week, session (tick, swap, rest timer, kg log) |
| `MonkeyWorkout/Views/Account` | Name, password, devices, Face ID lock, export, sign out (all), delete account |

## Demo mode (DEBUG)

Launch arguments `-demo -demoScreen <welcome|week|session|player|explore|muscle|exercise|technique>` start with sample data, no network.
CI captures each screen (≤ 800 px) and pushes them to branch `screenshots/pr-<n>` + a workflow artifact.

## Tests

```bash
swift test --package-path Packages/GymCore   # engine + API client (also runs on Linux)
```
CI (`.github/workflows/ios.yml`, macOS): package tests + simulator builds for Debug and Staging.
