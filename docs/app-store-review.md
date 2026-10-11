# App Store review: what MonkeyWorkout provides (#125)

## App Store Connect fields

| Field | Value |
|---|---|
| Privacy Policy URL | https://workout.monkeygrade.cloud/privacy |
| Support URL | https://workout.monkeygrade.cloud/support |
| License Agreement (EULA) | Custom: paste or link https://workout.monkeygrade.cloud/terms (or keep Apple standard EULA and add the Terms link to the description) |
| App description | Must end with links to Terms of Use and Privacy Policy once subscriptions ship (3.1.2) |
| Age rating | 12+ suggested (user-generated content with moderation; no unrestricted web access) |
| Sign-in required | Yes: give App Review a demo account (email + password) in App Review Information |

Staging copies for checking: https://workout-staging.monkeygrade.cloud/privacy, `/terms`, `/support`.

## Owner must fill (Fly secrets / env, both apps)

| Env | Used for |
|---|---|
| `LEGAL_OPERATOR` | Legal name of the person or company offering the app (seller name in App Store Connect) |
| `LEGAL_ADDRESS` | Postal address (required under FADP/GDPR for the controller) |
| `LEGAL_EMAIL` | Contact for privacy and support (falls back to `MODERATION_EMAIL`) |
| `LEGAL_LAW` | Governing law of the Terms (default `Switzerland`) |

Until set, the pages show a yellow `[… to be completed]` placeholder. Review should not be submitted with placeholders.

## Guideline coverage

| Guideline | How |
|---|---|
| 5.1.1(i) privacy policy in app + ASC | Account → Legal & support → Privacy policy; sign-up and Sign in with Apple link it |
| 5.1.1(v) account deletion | Account → Delete account (server delete + Sign in with Apple revoke) |
| 5.1.2 data use | No tracking, no ads, no third-party SDKs (`NSPrivacyTracking` false) |
| 5.1.3 health | HealthKit data not used for ads, not shared, not in iCloud; disclosed in policy; usage strings in `ios/project.yml` |
| 1.2 user-generated content | Terms (zero tolerance), guidelines accepted on join, text filter, report, block, auto-hide after 3 reports |
| 1.4.1 physical harm | Terms § Health and safety (not medical advice) |
| 1.5 developer contact | Support page |
| 3.1.2 subscriptions | Terms § Subscriptions (auto-renew, trial, cancel); paywall must show price, period, Terms + Privacy links (In-app subscriptions work) |
| Privacy manifest | `ios/MonkeyWorkout/Resources/PrivacyInfo.xcprivacy` |

## App Privacy labels (ASC questionnaire)

Data used to track you: **none**. All below: linked to the user, purpose App Functionality only.

| Category | Type | Collected because |
|---|---|---|
| Contact Info | Email Address, Name | Account |
| Health & Fitness | Health, Fitness | Body metrics, sessions incl. avg/max heart rate, logged sets |
| User Content | Photos or Videos, Other User Content | Exercise photos, profile photo; community captions, bio, shared workouts |
| Identifiers | User ID | Account ID, community nickname |
| Purchases | Purchase History | Add when subscriptions ship |

Not collected (device only): precise/coarse location (gym search via Apple Maps), biometrics, MonkeyGrade token.
