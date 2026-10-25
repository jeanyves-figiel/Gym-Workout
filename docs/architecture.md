# Architecture

## Components

```mermaid
flowchart LR
  subgraph Device["iPhone"]
    App["MonkeyWorkout app<br/>SwiftUI · AppModel"]
    Engine["GymCore / WorkoutEngine<br/>plan generator, catalog, progression"]
    Client["GymCore / APIClient<br/>typed client, Keychain tokens"]
    Widgets["Widget extension<br/>Home/Lock Screen widgets, Live Activity"]
    Group[("App Group container")]
    Health[("HealthKit")]
    App --> Engine
    App --> Client
    App <--> Group
    Widgets <--> Group
    App <--> Health
  end
  subgraph Watch["Apple Watch"]
    WApp["Watch app<br/>player, trackers, lift sensor"]
    Comp["Complications"]
    WApp <--> Comp
  end
  Garmin["Garmin watch<br/>Connect IQ app"]
  subgraph Fly["Fly.io (fra)"]
    API["API<br/>Node 24 · Fastify"]
    DB[("SQLite on volume /data")]
    Voices[("Voice cache /data")]
    API --> DB
    API --> Voices
  end
  App <-- "WatchConnectivity" --> WApp
  WApp -- "X-Watch-Key (sports)" --> API
  Client -- "HTTPS JSON /v1" --> API
  Garmin -- "via Garmin Connect app<br/>X-Garmin-Token" --> API
  API --> SES["Amazon SES<br/>email codes"]
  API --> Polly["Amazon Polly<br/>coach voices"]
  API --> Claude["Anthropic API<br/>coach chat, gym/food scan"]
  API --> APNs["Apple Push"]
  API --> AppleID["Sign in with Apple<br/>token + revoke"]
  AppStore["App Store Server<br/>Notifications V2"] --> API
  API --> HIBP["Have I Been Pwned<br/>k-anonymity range API"]
  API --> Tigris[("Tigris bucket<br/>encrypted backups")]
  API --> GH["GitHub issues<br/>member reports, no personal data"]
```

| Part | Path | Stack |
|---|---|---|
| iPhone app | `ios/MonkeyWorkout` | SwiftUI, iOS 18+, `@Observable` `AppModel` split into `AppModel+<Feature>.swift` |
| Engine | `ios/Packages/GymCore/Sources/WorkoutEngine` | Pure Swift, deterministic per seed, exercise catalog, techniques, food, recipes |
| API client | `ios/Packages/GymCore/Sources/APIClient` | `URLSession` without HTTP cache, Keychain token store, single-flight refresh |
| Widgets + Live Activity | `ios/MonkeyWorkoutWidgets`, `ios/HomeWidgets`, `ios/Shared` | WidgetKit, ActivityKit, App Intents |
| Watch app | `ios/MonkeyWorkoutWatch`, `ios/WatchShared` | SwiftUI, HealthKit workout sessions, Core Motion |
| Watch complications | `ios/MonkeyWorkoutWatchComplications` | WidgetKit on watchOS |
| Garmin app | `garmin/` | Monkey C (Connect IQ) |
| API | `backend/src` | Node 24 (TS type stripping), Fastify 5, `node:sqlite`, zod, jose, SimpleWebAuthn |

## Design principles

- **Offline first.** The plan, the player, logging and Fuel run on the device. Every change is written to the local store first, then queued for sync. The gym may have no signal.
- **Engine on the device.** The server never generates training; it stores the profile and the member's records (see [engine/training-methodology.md](engine/training-methodology.md)).
- **Server = accounts, sync, sharing, paid services.** Anything costing money per call (Claude, Polly) goes through the server with caps.
- **Single SQLite file per environment.** Small scale, one machine, volume snapshots + daily verified backup + encrypted off-site copy.
- **Same image staging → prod.** Prod runs the exact image validated on staging ([ci-cd.md](ci-cd.md)).

## Key flows

### Sign-in

```mermaid
sequenceDiagram
  participant A as App
  participant S as API
  A->>S: POST /v1/auth/login | /apple | /passkey
  alt 2-step on
    S-->>A: 403 mfa_required {mfaToken}
    A->>S: POST /v1/auth/mfa {mfaToken, code}
  end
  S-->>A: {user, tokens: access (15 min) + refresh (60 d)}
  A->>A: tokens → Keychain (this device only)
  A->>S: any /v1 call, Authorization: Bearer
  S-->>A: 401 invalid_token (expired)
  A->>S: POST /v1/auth/refresh (single flight)
  S-->>A: new pair, old refresh token spent
```

### Sync (outbox)

```mermaid
sequenceDiagram
  participant UI
  participant M as AppModel
  participant L as state.json
  participant S as API
  UI->>M: log set / finish workout / edit
  M->>L: persist (pending ids)
  M->>S: POST /v1/me/<kind> (upsert by client UUID)
  S-->>M: {saved, conflicts?}
  M->>L: clear pending ids, merge conflicts
  M->>S: GET /v1/me/<kind>?since=lastPull
  S-->>M: {items, deleted, serverTime}
  Note over M,S: Failures retry silently with backoff and when the network returns
```

### Workout on the Watch

The iPhone sends the session to the Watch over WatchConnectivity; the Watch runs a HealthKit workout session, mirrors heart rate and set events back, and the phone records the workout. Sport sessions recorded on the Watch alone upload directly with an `X-Watch-Key`. Details: [ios/devices.md](ios/devices.md).

### Garmin

The Garmin watch pairs with a 6-letter code, reads a snapshot the phone publishes, and posts events the phone collects from an inbox. The watch never talks to the phone directly. See [ios/devices.md](ios/devices.md#garmin).

### Release

`DEV → branch → PR (CI) → squash-merge to main → staging auto-deploy → validate → Promote to production (manual, same image) → TestFlight (manual)`. See [ci-cd.md](ci-cd.md).
