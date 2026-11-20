## Agent skills

### Issue tracker

GitHub Issues on wilsonfaustino/tower, via the gh CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: GLOSSARY.md and docs/adr/ at the repo root. See `docs/agents/domain.md`.

## Running the app

Always launch Tower in demo mode. Demo mode shows fake data, makes no network calls, does not write the cache and does not read or write the Keychain, so it needs no Jira or CircleCI access and shows no Keychain prompt. It works only in Debug builds.

```sh
xcodebuild -scheme Tower -configuration Debug -derivedDataPath build build -quiet
osascript -e 'if application id "dev.wilsonfaustino.Tower" is running then tell application id "dev.wilsonfaustino.Tower" to quit'
open -n build/Build/Products/Debug/Tower.app --args -demo typical
```

Tower is a menu bar app. Quit the running copy first, or `open` reuses it and drops the arguments.

Scenarios: `typical` (every section), `long-list` (enough rows to scroll), `clear-skies`, `offline`, `auth-failure`, `notify` (typical data; the first refresh changes it and posts one real macOS notification of each kind), `update` (typical data and a fake newer version 1.0.0; demo mode never runs brew, so the update notice shows only "Copy brew command").

In demo mode, Settings shows `demo-token` in the token fields, does not save tokens, and turns off "Test connection".

Debug builds sign with the "Apple Development" identity of team PX9G95LY8C, so the Keychain keeps "Always Allow" across rebuilds. CI overrides this with an ad-hoc signature.
