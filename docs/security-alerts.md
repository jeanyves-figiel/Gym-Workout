# Security alerts: capture and handling

How GitHub security findings are captured, triaged and closed. Controls themselves: [security.md](security.md).

## What is enabled

| Feature | State | Where it shows |
|---|---|---|
| Code scanning, CodeQL **default setup** | on (2026-10-25): `actions`, `javascript-typescript`, `python`, `swift`; suite `default` | Security → Code scanning; a **CodeQL** check on PRs to `main` |
| Secret scanning + push protection | on | Security → Secret scanning; a push holding a known secret is blocked |
| Private vulnerability reporting | on | Security → Advisories |
| Dependabot version updates | on, weekly (`.github/dependabot.yml`: backend npm, GitHub Actions) | Dependabot PRs |
| Dependabot alerts / security updates | **off** | (owner can enable in Settings → Code security) |

Default setup runs on push to `main`, on PRs to `main` and weekly. The Swift job runs on a GitHub-hosted `macos-latest` runner (autobuild), separate from the `xcode-27` runners used by iOS CI and TestFlight. Changing these settings is the owner's call.

## Capture

1. Every PR: the **CodeQL** check flags alerts the PR introduces. A new high or critical alert is fixed in the same PR, or the PR says why not.
2. First scan and weekly scan: new alerts on `main` get one GitHub issue (title `CodeQL: …` or `Secret scanning: …`), with rule, severity, file:line and verdict. Alerts from one scan can share one issue.
3. Local check when the alert list is out of reach (the Claude session token cannot read the alerts API): download the CodeQL bundle and run the same suite, for example
   `codeql database create db --language=javascript --source-root=. && codeql database analyze db --format=csv --output=out.csv codeql/javascript-queries:codeql-suites/javascript-code-scanning.qls`.
   Swift needs macOS and is read from the GitHub run.

## Triage

| Severity | Action |
|---|---|
| Critical / high, reachable | Fix now, in the current bundle if possible; issue + PR + ChangeLog **Security** entry |
| Critical / high, not reachable | Harden when cheap (clears the alert), else dismiss with reason |
| Medium / low | Fix in the next bundle or dismiss with reason |
| Secret detected | Treat as leaked: owner rotates the credential first, then removes it; never only delete the commit |

**Dismissals** always carry a reason (*false positive*, *won't fix*, *used in tests*) and a one-line comment pointing to the code or doc that explains it. Dismissing is done by the owner in the Security tab.

## Log

| Date | Scan | Findings | Outcome |
|---|---|---|---|
| 2026-10-25 | First CodeQL scan, `main` dc1eae64 | `js/insufficient-password-hash` (high) `hibp.ts`: SHA-1 for the Have I Been Pwned range API, not storage | False positive: dismiss (#762) |
| 2026-10-25 | same | `js/incomplete-sanitization` ×2 (high) `community.ts` nickname LIKE escape | Not reachable (input already `[a-z0-9_.]`), hardened: escapes `\ % _` (#762) |
| 2026-10-25 | same | python 0, actions 0; swift pending | |
