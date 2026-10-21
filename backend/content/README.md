# Over-the-air content (#583)

Data the app picks up without a new build. Code can't ship this way (App Review 2.5.2): only flags, values and content.

Publish: edit here → PR (CI checks it, `test/remote.test.ts`) → squash-merge (staging) → check on a TestFlight build → **Promote to production**.
The app fetches `/v1/app-config` at launch and when it comes back to the foreground (at most every 5 min).

## config.json

| Key | What it does |
| --- | --- |
| `minimumBuild` | Builds below it show **Update needed** (full screen, needs `update`). |
| `recommendedBuild` | Builds below it show the **update banner** on Train (dismissable per build). |
| `update` | `{ "title", "body", "url" }` for the banner and screen. `url` defaults to TestFlight (`itms-beta://`); set `itms-apps://apps.apple.com/app/id6819971090` after the App Store launch. |
| `flags.<name>` | `{ "on", "minBuild", "maxBuild", "percent", "message" }`. Off → the feature shows the **paused** card with `message`. `percent` rolls out to that share of installs. Known: `foodScan`, `gymScan`, `askCoach`. Unknown flags in older builds are ignored; a flag missing from the file is on. |
| `values.<key>` | Any JSON, read in the app with `Remote.shared.value(...)`. |
| `packs.<name>` | `{ "minBuild", "maxBuild" }`: serves `packs/<name>.json` to those builds. |

## Packs

Same format as the bundled file. Applied on the **next launch**, dropped when the app updates (the new build has its own copy), ignored when it doesn't decode.

| Pack | Replaces |
| --- | --- |
| `recipes` | `ios/Packages/GymCore/Sources/WorkoutEngine/Resources/Recipes.json` |
| `foods` | `…/Resources/Foods.json` |
| `whats-new` | `ios/MonkeyWorkout/Resources/WhatsNew.json` (new `id` → shown once) |
| `coach-tips` | adds tips to Coach Monkey: `[{ "id", "text", "tint": ["3D5AFF","1E9BFF"], "cta", "action": "progress\|calendar\|levels", "minBuild", "maxBuild" }]` |

Fix a recipe: copy `Recipes.json` to `packs/recipes.json`, edit, add `"recipes": { "minBuild": 60, "maxBuild": 60 }` so the next build (which bundles the fix) doesn't take it.

## Signing

`CONTENT_SIGNING_KEY` (Fly secret, base64 Ed25519 PKCS#8 DER) signs `/v1/app-config` (`X-Content-Signature`); the config lists each pack's SHA-256, so packs are covered too.
Make it with the **Content signing key** workflow; it prints the public key for `CONTENT_PUBLIC_KEY` in `ios/Config/*.xcconfig` (write `//` as `/$()/` there, xcconfig reads `//` as a comment). Builds with a public key reject unsigned or tampered config.
