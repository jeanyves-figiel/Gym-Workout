# On-device data

Everything the member sees is cached on the device and drawn on the first frame; the server is the sync target and backup, not the source of the screen. Server tables: [../data-model.md](../data-model.md).

## Files

All in the app's `Application Support` unless noted, written atomically with Data Protection `completeUntilFirstUserAuthentication` (readable after the first unlock, so widgets, the Watch and background sync work).

| File | Owner | Holds | Synced to server |
|---|---|---|---|
| `state.json` | `LocalStore` / `LocalState` | Profile, week plan and seed, done / ticked / skipped, set logs, workout history, custom workouts and exercises, PR attempts, measurements, climbs, sports, machine notes, programme, Train / Progress layouts, taste, growth, paused workout, how each workout felt (`feels`) and its Apple effort 1–10 (`efforts`, local only), **outbox** (pending and deleted id sets, last pull times) | Yes, per kind ([sync protocol](../api/README.md#sync-protocol)); profile as one blob |
| `machine-notes/` | `MachineNote` | One JPEG per machine setup note | Yes (owner-only photo route) |
| `fuel.json` | `FuelStore` | Fuel settings, daily logs, recipes (favourite, own), pantry, meal plans, shopping list, scanned products, supplements, water | **No**: Fuel stays on the device |
| `daily-move.json` | `MoveStore` | Daily steps and stairs | No (from HealthKit) |
| `mind.json` | `MindStore` | Mood check-ins, breathing / relax sessions, daily Mind scores (90 days) | **No**: stays on the device; check-ins and sessions also go to Apple Health (State of Mind, mindful minutes) when connected |
| `me-avatar.jpg`, `me-avatar.json` | `MeAvatar` | Your own profile photo and its URL, so the Me pill shows it at launch (#639); wiped on sign-out | Copy of the server photo |
| `cache/` (`account.json`, `community.json`, `entitlement.json`, `monkeygrade-sessions.json`) | `DeviceCache` | Last server answers per account: account, Community profile and first 30 posts per feed, Pro entitlement, MonkeyGrade sessions; shown at launch and offline (#641); wiped on sign-out and account switch | Copies of server data |
| `lift-sets.json` | `LiftSets` | Watch lift-sensor sets | Via workouts |
| `wod-timers.json` | `WodStore` | Saved WOD and boxing timers | No (sent to the Watch) |
| `swim.json` | `SwimStore` | Swim plan, pool length, gym-day swim blocks, buddy alert minutes | No (today's swim sent to the Watch) |
| `health-snapshot.json` | `HealthManager` | Last HealthKit readings (readiness, steps, gym workouts from other apps) | No |
| `form-reports.json` | `FormReportStore` | Form check reports (#833): reps, scores, faults and the joints of the worst rep (no pictures), last 60; wiped on sign-out | No |
| `tmp/film-clips/*.mp4` | `ClipRecorder` | Film my workout review clip (#952): the last set only (whole session #957: the last set of each move), 2 min max each; deleted on Next / Save / Discard, when the film screen closes and at every launch; never uploaded | No |
| `coach-voices/` | `CoachVoices` | Voice catalog and cached MP3 lines | No (downloaded) |
| `hd-animations/` | `HDAnimations` | HD exercise animation pack (#932): `<id>.mwf` per exercise, its movement clip `<id>.mp4` (#944) + `installed.json`; excluded from backup; kept on sign-out (not account data), deleted by Settings → HD animations off | No (downloaded) |
| `gym-workout-export.json` (temporary directory) | `AccountView` | Data export while it is shared; protection `complete` | n/a |

### App Group (`group.<bundle id>`)

| Item | Writer | Reader |
|---|---|---|
| `home-widgets.json` | app (`HomeWidgetSync`) | Home / Lock Screen widgets |
| Water queue (App Group `UserDefaults`) | Water widget, notification buttons | app, when active |
| Complication snapshot (`SharedSnapshot`) | Watch app | Watch complications |

### Watch

`snapshot.json` in the Watch app's Documents: last snapshot from the phone, so the Watch works with the phone away; logged sets and workouts queue until the phone is reachable.

## Keychain

Access and refresh tokens, the Watch upload key and the MonkeyGrade link sign-in: generic-password items, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not in iCloud Keychain, not restored to another device).

## Settings and preferences

Small UI preferences (style, toggles) live in `UserDefaults` / `@AppStorage`; nothing sensitive. A climbing session tracked live (`climbLive`, #829) stays there until finished, with the last grade scale (`climbLiveScale`). Ring through Silent (`timerAlarms.enabled`, off by default) and whether it was asked (`timerAlarms.asked`). HD animations (#932): `hdAnimations.enabled`, `hdAnimations.wifiOnly` (default on), `hdAnimations.offered`.

## Sign-out and deletion

Sign-out first tries a final sync (5 s at most), then wipes `state.json`, tokens and every account copy outside it (`AppModel.wipeAccountLocalData`): Pro state, lift sets, Health cache, daily move, Mind, timers, swim, Fuel, notification prefs, MonkeyGrade link, Watch upload key, form check reports, the export file and the URL cache; the Watch and widgets get signed-out snapshots. The same runs when another account signs in and after account deletion.
