# MonkeyWorkout documentation

MonkeyWorkout is an iPhone + Apple Watch gym app (SwiftUI) with a Node API. The workout engine runs on the device; the API holds accounts, sync, Community and paid services (AI coach, scans, voices, subscriptions).

| Topic | Document |
|---|---|
| Architecture, components, data flows | [architecture.md](architecture.md) |
| iPhone app: tabs, screens, flows | [ios/app.md](ios/app.md) |
| Apple Watch, widgets, Live Activity, complications, Garmin, other watches | [ios/devices.md](ios/devices.md) |
| On-device data (files, Keychain, App Group) | [ios/on-device-data.md](ios/on-device-data.md) |
| Workout engine and training methodology | [engine/training-methodology.md](engine/training-methodology.md) |
| API conventions (auth, errors, sync, limits) | [api/README.md](api/README.md) |
| API endpoint reference (all routes) | [api/endpoints.md](api/endpoints.md) · [OpenAPI](reference/openapi.json) |
| Server data model (SQLite) | [data-model.md](data-model.md) · [schema.sql](reference/schema.sql) |
| Security, data protection, threat model | [security.md](security.md) |
| Security alerts (CodeQL, secret scanning, Dependabot): capture and triage | [security-alerts.md](security-alerts.md) |
| Hosting and third-party services | [infrastructure.md](infrastructure.md) |
| CI/CD, release flow, TestFlight, What's new | [ci-cd.md](ci-cd.md) |
| Subscriptions (MonkeyWorkout Pro) | [subscriptions.md](subscriptions.md) |
| Legal pages | [legal.md](legal.md) |
| App Review notes | [app-store-review.md](app-store-review.md) |
| Run locally (DEV) | [development.md](development.md) |
| Conventions for changes | [contributing.md](contributing.md) |

Also: [`backend/README.md`](../backend/README.md) (server env and Fly setup), [`ios/README.md`](../ios/README.md) (Xcode setup, TestFlight secrets), [`ios/EXERCISE_MEDIA.md`](../ios/EXERCISE_MEDIA.md) (exercise drawings and animations), [`garmin/`](../garmin) (Connect IQ app), [`CHANGELOG.md`](../CHANGELOG.md).

## Keeping it current

- `docs/reference/` is generated: `cd backend && npm run docs`. `backend/test/docs.test.ts` (CI) fails when a route is added or removed without a row in [api/endpoints.md](api/endpoints.md), or when the schema or OpenAPI file is stale.
- A change that adds a screen, route, table, workflow or secret updates the matching page in the same PR.
- The repository is public: these pages describe design and controls only. Never add secret values, tokens, bucket names, member data or personal emails.
