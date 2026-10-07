# Gym-Workout

Personal **iOS app** (SwiftUI) generating adaptive gym sessions for a large, fully equipped gym (reference: Fitnesspark Puls 5, Zürich):
strength + definition, climber mobility, cardio, explosiveness, and cool-downs derived from what each session loaded.

| Part | Path | Stack |
|---|---|---|
| iOS app | `ios/` | SwiftUI, iOS 17+, on-device workout engine |
| API | `backend/` | Node 22 (TS type-stripping), Fastify, SQLite, JWT — accounts + sync |

## API (backend)

```bash
cd backend
npm ci
npm run dev      # http://localhost:7443  (emails printed to console)
npm test
npm run typecheck
```

See [`backend/README.md`](backend/README.md) for endpoints and security model.

## Delivery (trunk-based)

1. Branch off `main` → PR → CI.
2. Squash-merge → **Deploy staging**: builds `ghcr.io/jeanyves-figiel/gym-workout-api:sha-<sha>` (+ `:staging`), calls `STAGING_DEPLOY_HOOK`.
3. Validate staging.
4. **Promote to production** (manual): re-tags the same digest as `:prod`, calls `PROD_DEPLOY_HOOK`. No rebuild.

Repo settings needed: environments `staging` / `production`, secrets `STAGING_DEPLOY_HOOK`, `PROD_DEPLOY_HOOK`, vars `STAGING_URL`, `PROD_URL` (#3).
