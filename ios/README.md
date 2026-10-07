# Gym-Workout iOS

SwiftUI, iOS 17+, iPhone. Workout engine runs on-device (offline at the gym); account + sync via the API.

## Setup (Mac)

```bash
brew install xcodegen
cd ios && xcodegen generate && open GymWorkout.xcodeproj
```

1. Select your team in *Signing & Capabilities* (Sign in with Apple capability is pre-declared).
2. DEV: run the API (`cd backend && npm run dev`, http://localhost:7443), run scheme **GymWorkout** (Debug) on a simulator. Verification codes are printed in the API console.
3. Staging: scheme **GymWorkout Staging**. Set real API hosts in `Config/Staging.xcconfig` / `Config/Release.xcconfig` (#3).

| Config | Bundle id | API |
|---|---|---|
| Debug | `ch.figiel.gymworkout.dev` | `http://localhost:7443` |
| Staging | `ch.figiel.gymworkout.staging` | `Config/Staging.xcconfig` |
| Release | `ch.figiel.gymworkout` | `Config/Release.xcconfig` |

## Structure

| Path | Content |
|---|---|
| `Packages/GymCore/Sources/WorkoutEngine` | Plan generator (pure Swift, deterministic per seed), 150-exercise catalog, Puls 5 gym profile |
| `Packages/GymCore/Sources/APIClient` | Typed API client: Keychain tokens, single-flight refresh, sync |
| `GymWorkout/Model` | `AppModel` (auth phase, plan, logs, sync), local JSON store (data protection) |
| `GymWorkout/Views/Auth` | Welcome, Sign in with Apple, sign up, email code, sign in, forgot/reset, privacy notice |
| `GymWorkout/Views/Plan` | Training profile, week, session (tick, swap, rest timer, kg log) |
| `GymWorkout/Views/Account` | Name, password, devices, Face ID lock, export, sign out (all), delete account |

## Tests

```bash
swift test --package-path Packages/GymCore   # engine + API client (also runs on Linux)
```
CI (`.github/workflows/ios.yml`, macOS): package tests + simulator builds for Debug and Staging.
