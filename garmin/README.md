# MonkeyWorkout for Garmin (#550)

Connect IQ watch app (Monkey C). Design B from `other-watches/garmin-proposals.png`: Garmin's black data-field look.

**How it talks to us.** No phone link of its own: `Communications.makeWebRequest` reaches our server through the
Garmin Connect app (works with an iPhone).

1. Watch: `POST /v1/garmin/pair` → token + 6-letter code, shown on the watch.
2. iPhone: Settings › Watches › Garmin watch → type the code (`POST /v1/me/garmin/claim`).
3. iPhone publishes what the watch shows (`PUT /v1/me/garmin/snapshot`, `GarminSync`): this week's sessions, next
   session in full, water. Watch reads it with `GET /v1/garmin/snapshot` (`X-Garmin-Token`).
4. Watch queues sets, done exercises, finished workouts and water (`POST /v1/garmin/events`); the iPhone picks them
   up when it opens (`GET /v1/me/garmin/inbox`, then ack) and records them like Apple Watch events.

The watch records a Garmin strength activity (heart rate, calories, a lap per set). Garmin Connect adds it to Apple
Health; the phone does not save another one.

**Screens.** Home: next session, START, water. Set: kg x reps (Up/Down change reps, menu → Change kg), LOG SET.
Rest: green ring around the bezel, Up = +15 s, Start = skip, buzz at the end. Menu: next exercise, finish, discard.
Glance: next session and water. Home menu: Water +1, Refresh, Unpair.

**Build.** `monkey.jungle` = production (workout.monkeygrade.cloud), `staging.jungle` = staging. CI
(`.github/workflows/garmin.yml`) needs `GARMIN_USERNAME`, `GARMIN_PASSWORD` (Garmin developer account, for the SDK and
device files) and `GARMIN_DEVELOPER_KEY` (base64 of the `.der` signing key, keep a copy: the Store app is tied to it).
Side-load `MonkeyWorkout-staging-fr265.prg` from the workflow artifact by copying it to `GARMIN/APPS` over USB.
