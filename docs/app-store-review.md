# App Store review: what MonkeyWorkout provides (#125)

## App Store Connect fields

| Field | Value |
|---|---|
| Privacy Policy URL | https://workout.monkeygrade.cloud/privacy |
| Support URL | https://workout.monkeygrade.cloud/support |
| License Agreement (EULA) | Custom: paste or link https://workout.monkeygrade.cloud/terms (or keep Apple standard EULA and add the Terms link to the description) |
| App description | Must end with links to Terms of Use and Privacy Policy once subscriptions ship (3.1.2) |
| Age rating | Answers in `listing.json`. Terms require 16+: set **Age Rating Override → 16+** in App Store Connect so the store rating matches (#975) |
| Sign-in required | Yes: give App Review a demo account (email + password) in App Review Information |

Staging copies for checking: https://workout-staging.monkeygrade.cloud/privacy, `/terms`, `/support`.

## Listing workflow (#882)

Store text lives in `ios/AppStore/listing.json` (name, subtitle, categories, description, keywords, promo text, URLs, age rating answers, App Review notes). Edit it there, then run **App Store listing** (`asc-listing.yml`): dry run first, then `apply`. It writes to the editable iOS version, so create the version in App Store Connect first (+ Version). Secrets read for App Review Information: `REVIEW_DEMO_EMAIL`, `REVIEW_DEMO_PASSWORD` (a production account with a gym, a plan and past workouts), `REVIEW_CONTACT_PHONE`; unset → fill those fields by hand.

Still by hand (no API): App Privacy labels (table below) and screenshots (`app-store-screenshots` branch).

## Operator details (`[env]` in `backend/fly.*.toml`)

| Env | Used for |
|---|---|
| `LEGAL_OPERATOR` | Legal name of the person or company offering the app (seller name in App Store Connect) |
| `LEGAL_ADDRESS` | Postal address (required under FADP/GDPR for the controller) |
| `LEGAL_EMAIL` | Contact for privacy and support (falls back to `MODERATION_EMAIL`) |
| `LEGAL_LAW` | Governing law of the Terms (default `Switzerland`) |
| `LEGAL_VENUE` | Place of jurisdiction |

Set for staging and prod: MonkeyWorkout by Figiel, Schlieren, contact@monkeygrade.cloud, Swiss law, Zurich courts. Unset → yellow `[… to be completed]` placeholder.

## Guideline coverage

| Guideline | How |
|---|---|
| 5.1.1(i) privacy policy in app + ASC | Account → Legal & support → Privacy policy; sign-up and Sign in with Apple link it |
| 5.1.1(v) account deletion | Account → Delete account (server delete + Sign in with Apple revoke) |
| 5.1.2 data use | No tracking, no ads, no third-party SDKs (`NSPrivacyTracking` false) |
| 5.1.2(i) third-party AI | Privacy policy § AI features names Anthropic and what each feature sends (#973); explicit in-app consent before first AI use: #972 |
| 5.1.1 purpose strings | Every `NS…UsageDescription` in `ios/project.yml` says what is sent where (camera: scans go to Anthropic, #974) |
| 5.1.3 health | HealthKit data not used for ads, not sold, not in iCloud; sleep, HRV and mood go to Anthropic only for Coach's week review (health management, disclosed in policy); usage strings in `ios/project.yml` |
| 1.2 user-generated content | Terms (zero tolerance), guidelines accepted on join, word filter + AI check refuse objectionable text and photos, report, block, auto-hide after 3 reports |
| 1.4.1 physical harm | Terms § Health and safety (not medical advice) |
| 1.5 developer contact | Support page |
| 3.1.2 subscriptions | Terms § Subscriptions (auto-renew, trial, cancel); paywall must show price, period, Terms + Privacy links (In-app subscriptions work) |
| Privacy manifest | App `ios/MonkeyWorkout/Resources/PrivacyInfo.xcprivacy`, Watch `ios/MonkeyWorkoutWatch/PrivacyInfo.xcprivacy`, widgets `ios/MonkeyWorkoutWidgets/PrivacyInfo.xcprivacy` (App Group UserDefaults: reason `1C8F.1`, #975) |

## App Privacy labels (ASC questionnaire)

Data used to track you: **none**. All below: linked to the user, purpose App Functionality only.

| Category | Type | Collected because |
|---|---|---|
| Contact Info | Email Address, Name | Account |
| Health & Fitness | Health, Fitness | Body metrics, sessions incl. avg/max heart rate, logged sets; sleep, HRV and mood sent for Coach's week review |
| User Content | Photos or Videos, Other User Content | Exercise photos, profile photo; community captions, bio, shared workouts |
| Identifiers | User ID | Account ID, community nickname |
| Purchases | Purchase History | Subscription status (already in the privacy manifest) |

Not collected (device only): precise/coarse location (gym search via Apple Maps), biometrics, MonkeyGrade token.

AI features send data to Anthropic as a service provider (processing for app functionality, not tracking); the labels above already cover those data types.

## Audit 2026-10-30 (#971)

Checked against the App Review Guidelines: privacy policy, labels and manifests, account creation and deletion, Sign in with Apple, HealthKit, camera and AI, subscriptions, UGC moderation and purpose strings. Gaps found: #972 (AI consent, in progress), #973 (policy AI section), #974 (camera string), #975 (listing text, widget manifest, age override, this doc). Still by hand: App Privacy labels, age rating override, review demo account (#882).
