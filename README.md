# MonkeyWorkout

Personal **iOS app** (SwiftUI) generating adaptive gym sessions for a large, fully equipped gym (reference: Fitnesspark Puls 5, Zürich):
strength + definition, climber mobility, cardio, explosiveness, and cool-downs derived from what each session loaded.

| Part | Path | Stack |
|---|---|---|
| iOS app | `ios/` | SwiftUI, iOS 18+, on-device workout engine |
| API | `backend/` | Node 24 (TS type-stripping), Fastify, SQLite, JWT — accounts + sync |
| Watch, widgets, Garmin | `ios/MonkeyWorkoutWatch`, `ios/MonkeyWorkoutWidgets`, `garmin/` | watchOS, WidgetKit, Connect IQ |

**Documentation:** [`docs/`](docs/README.md) — architecture, every screen, every API route, data model, security, infrastructure, CI/CD.

## iOS app

See [`ios/README.md`](ios/README.md): `brew install xcodegen && cd ios && xcodegen generate`.

## API (backend)

```bash
cd backend
npm ci
npm run dev      # http://localhost:7443  (emails printed to console)
npm test
npm run typecheck
```

See [`backend/README.md`](backend/README.md) (env, hosting), [`docs/api/endpoints.md`](docs/api/endpoints.md) (endpoints) and [`docs/security.md`](docs/security.md) (security model).

## Delivery (trunk-based)

1. Branch off `main` → PR → CI.
2. Squash-merge → **Deploy staging**: builds `ghcr.io/jeanyves-figiel/gym-workout-api:sha-<sha>` (+ `:staging`), deploys that image to Fly.io app `monkeyworkout-staging` (`https://workout-staging.monkeygrade.cloud`).
3. Validate staging.
4. **Promote to production** (manual): re-tags the same digest as `:prod`, deploys it to Fly.io app `monkeyworkout-prod` (`https://workout.monkeygrade.cloud`). No rebuild.

Repo settings needed: secret `FLY_API_TOKEN`, environments `staging` / `production` with vars `STAGING_URL`, `PROD_URL`. Setup: [`backend/README.md`](backend/README.md#hosting-flyio) (#3).
