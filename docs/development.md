# Run locally (DEV)

Develop on DEV first, then ship through staging ([ci-cd.md](ci-cd.md)).

## API

Node ≥ 24.7 (TypeScript runs through Node's type stripping; no build step).

```bash
cd backend
npm ci
npm run dev        # http://localhost:7443, DB ./data/dev.db, email codes printed to the console
npm test           # vitest (in-memory SQLite, fake Apple / App Store / models)
npm run typecheck
npm run docs       # regenerate docs/reference after changing routes, schema or docs/api/endpoints.md
```

Optional settings for DEV come from the environment (see `backend/.env.example` and `backend/README.md`). Without Anthropic, Polly, APNs or Apple keys those features answer 503 / are skipped, which is fine for most work. `SUBSCRIPTIONS` defaults to `off` (everything open).

Live checks against real services: `scripts/coach-live.ts`, `scripts/voice-live.ts` (need your own keys in the shell; never commit them).

## iPhone app

Mac with Xcode and XcodeGen:

```bash
brew install xcodegen
cd ios && xcodegen generate && open MonkeyWorkout.xcodeproj
```

Scheme **MonkeyWorkout** (Debug) → bundle `Com.app.MonkeyWorkout.dev`, API `http://localhost:7443`. Run the API first; verification codes appear in its console. Scheme **MonkeyWorkout Staging** targets staging.

- Engine and API client tests run anywhere: `swift test --package-path ios/Packages/GymCore` (also on Linux).
- Demo mode without network: launch arguments `-demo -demoScreen <screen>` (screens listed in `Views/RootView.swift` `DemoScreen`).
- StoreKit testing: `ios/Config/MonkeyWorkout.storekit`.
- UI tests: `ios/MonkeyWorkoutUITests`.

## Garmin app

`garmin/` (Connect IQ SDK). CI builds it with `garmin.yml`; a developer key comes from the **Garmin signing key** workflow.

## Useful accounts

Staging has `SUBSCRIPTION_TESTS=on`: Settings › MonkeyWorkout Pro › Staging test fakes purchases without Apple. Never point a DEV build at production.
