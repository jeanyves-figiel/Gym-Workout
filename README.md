# Gym-Workout

Adaptive workout generator for large, fully equipped gyms (reference: **Fitnesspark Puls 5, Zürich**).
Built for climbers who want strength + definition, mobility, endurance and explosiveness — with cool-downs derived from what each session actually loaded.

## How a session is built

| Block | Purpose | Logic |
|---|---|---|
| Warm-up | Raise HR, open today's ranges | Cardio machine 4–5′ + dynamic drills for the session's regions (hips/ankles on lower days, shoulders/T-spine/wrists on upper days) |
| Explosive | Power, dynos | Jumps / throws / ballistics / upper plyo, done fresh, low reps, full recovery |
| Strength | Build & define | Movement-pattern slots per session focus; first slot = main lift with ramp-up sets; light prehab supersetted into rest; mobility drill paired into long rests |
| Mobility | Climber range | Active end-range: hips (high-step, drop-knee, straddle), shoulders, T-spine, wrists |
| Cardio | Engine | Zone 2 / intervals / threshold / sprints rotated per goal; deload → Zone 2 only |
| Cool-down | Preserve muscles | Greedy stretch selection covering the most-loaded muscles of *this* session, easy flush after hard cardio, ends with down-regulation breathing |

### Session length
`base(goal) × frequency factor + experience ± climbing load`, rounded to 5′, optional hard cap.
Fewer sessions/week → longer sessions; more sessions → shorter, but weekly volume still rises.

| Sessions/week | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|
| Factor | 1.2 | 1.0 | 0.9 | 0.82 | 0.75 |
| Split | Full body ×2 | Full body ×3 (lower / upper / power) | Upper/Lower ×2 | U/L + conditioning + U/L | Push/Pull/Legs ×2 |

### Climber logic
- Shoulder health (face pulls, ER, Y-T-W, push-up plus) right after the main lift.
- Forearm/finger extensor antagonist work.
- ≥2 climbing days: pulling sets −1, grip-heavy lifts avoided, curls dropped.
- Extra mobility share; Zone 2 favours incline walk / stair climber (approach fitness).

### Mesocycle
4 weeks: Base (RPE −1) → Build → Peak (+1 set main lifts) → Deload (−40 % sets, shorter, Zone 2 only).

## Develop

```bash
npm ci
npm run dev        # https://localhost:7443 (self-signed cert)
npm test           # engine unit tests (vitest)
npm run typecheck
npm run build
```

Engine is pure TypeScript (`src/engine`), deterministic per seed. UI is React (`src/ui`), state in `localStorage`.

## Delivery (trunk-based)

1. Branch off `main` → PR → CI (typecheck, tests, build, Docker build).
2. Squash-merge → **Deploy staging** workflow: builds one image `ghcr.io/jeanyves-figiel/gym-workout:sha-<sha>` (+ `:staging`) and calls `STAGING_DEPLOY_HOOK`.
3. Validate staging.
4. Run **Promote to production** (manual `workflow_dispatch`): re-tags the *same* image digest as `:prod` and calls `PROD_DEPLOY_HOOK`. No rebuild.

Required repo settings: environments `staging` / `production` (add required reviewers on production), secrets `STAGING_DEPLOY_HOOK`, `PROD_DEPLOY_HOOK`, vars `STAGING_URL`, `PROD_URL`.
Container listens on `8080`, health check `GET /healthz`.
