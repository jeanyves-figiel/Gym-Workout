# Legal pages

Served by the API (`backend/src/routes/legal.ts`), public HTML, same URLs for App Store Connect (Privacy Policy URL, Support URL, custom EULA) and the app's Settings › Help links.

| Page | Production URL | Sections |
|---|---|---|
| Privacy Policy | https://workout.monkeygrade.cloud/privacy | Who is responsible · What we collect and why (account, training and body data, Apple Health, Garmin, Community, notifications, subscriptions, kept on your device only) · What we do not do · Service providers · How we protect your data · How long we keep data · Your rights · Children · Changes · Contact |
| Terms of Use (EULA) | https://workout.monkeygrade.cloud/terms | Eligibility and account · Health and safety · License · Subscriptions and free trial · Community and your content · Acceptable use · Third-party services · Availability and changes · Liability · Termination · Apple · Governing law · Contact |
| Support | https://workout.monkeygrade.cloud/support | Common questions (delete account, restore data, export, forgotten password, cancel subscription, report a member, missing Health / Watch data), legal links |

- Operator, postal address, contact email, governing law and venue come from `LEGAL_OPERATOR`, `LEGAL_ADDRESS`, `LEGAL_EMAIL`, `LEGAL_LAW`, `LEGAL_VENUE` (`[env]` in `fly.*.toml`); unset values render as a visible placeholder. Swiss law (nFADP) with GDPR rights.
- `LEGAL_UPDATED` in `legal.ts` is the "last updated" date: change it with any wording change.
- Every new kind of personal data, service provider or retention change must update the Privacy Policy in the same PR ([security.md](security.md#member-rights-nfadp--gdpr)).
- Community guidelines are accepted in the app when joining (App Store guideline 1.2); reports go to the moderation mailbox (`MODERATION_EMAIL`).
- App Review specifics: [app-store-review.md](app-store-review.md).
