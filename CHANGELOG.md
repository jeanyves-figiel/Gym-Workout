# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Adaptive session generator (#1): warm-up → explosive → strength → climber mobility → cardio → cool-down.
- Session length derived from goal, sessions/week, experience, climbing load and optional cap.
- Weekly splits for 2–6 sessions; A/B variants; exercise variety across the week.
- Six goals: balanced, build & define, max strength, climbing, endurance, explosive.
- Climber logic: shoulder-health and forearm-antagonist prehab, reduced pull/grip volume with ≥2 climbing days.
- Cool-down built from the session's most-loaded muscles; post-interval flush; breathing finish.
- 4-week mesocycle with deload.
- Fitnesspark Puls 5 equipment profile (editable); ~150 exercises, drills and stretches.
- Mobile-first PWA UI: profile setup, week view, session view with tick-off, swap, rest timer, weight log with last-used weight.
- Dockerfile (nginx, `/healthz`), CI, staging auto-deploy and manual "Promote to production" (same image) workflows.
- Repository bootstrap (README, CHANGELOG, .gitignore).
