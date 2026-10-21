# Contributing conventions

## Every change

1. **GitHub issue** first: all bugs, features and tasks live in GitHub issues.
2. **Branch off `main`**, open a PR that references the issue. Squash-merge only.
3. **`CHANGELOG.md` entry** under `[Unreleased]` (Keep a Changelog: Added / Changed / Fixed), naming the issue and the user-visible effect.
4. **Docs**: update the matching page in `docs/` (new route → [api/endpoints.md](api/endpoints.md) + `npm run docs`; new table, workflow, secret name, screen or device feature → its page). CI fails on undocumented routes.
5. **Tests**: backend `npm test` + `npm run typecheck`; engine `swift test --package-path ios/Packages/GymCore`; UI changes get demo screens for CI screenshots.
6. **What's new**: feature PRs suggest a card line in the PR body; the release owner writes `WhatsNew.json` once per release ([ci-cd.md](ci-cd.md#whats-new-every-release)).

## UI changes

Any visible change starts with 2–3 mockups (images ≤ 800 px) for the owner to pick. Follow the design rules in [ios/app.md](ios/app.md#design-rules).

## Code style

- Match the surrounding code: comment density, naming, idiom. Comments say why, with the issue number (`(#432)`).
- Backend: zod for every input, `ApiError(status, code, message)` for errors, member-scoped queries, a test per route.
- iOS: features in `AppModel+<Feature>.swift` and `Views/<Area>/`; engine logic in `GymCore` (pure, testable); local-first writes then sync.
- API changes are additive; older app builds must keep working.

## Security

- Never commit secrets, tokens, keys, bucket names, member data or personal emails (public repository). Secrets are entered by the owner in GitHub / Fly only.
- Shared infrastructure (Cloudflare DNS, AWS SES) also serves other apps: add only, never modify or delete existing records without the owner's OK.
- Production promotes need the owner's explicit OK per change.
