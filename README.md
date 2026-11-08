# Tower

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=wilsonfaustino_tower&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=wilsonfaustino_tower)

A macOS menu bar app that shows one queue of the GitHub pull requests and Jira tickets that need you now, sorted by urgency. Open the panel, see what to do, and click through to the item.

Tower is a sibling of [Copilot Runway](https://github.com/wilsonfaustino/copilot-runway). Both apps use aviation names.

## Status

MVP, in daily use by the author. Builds are ad-hoc signed. Notarized releases come later.

## What Tower shows

The panel has six sections in a fixed urgency order. Tower hides a section that has no items.

| Section | Items |
|---|---|
| Fix | Your open PRs with failing checks, and your failed CircleCI pipelines that have no PR |
| Review | PRs that ask for your review. Bot PRs (Dependabot, Renovate) collapse into one row per bot. Only direct requests older than 24 hours are urgent. |
| Merge | Your approved PRs with no failing checks |
| Tidy | Your in-progress Jira tickets with no PR, or whose PR has no reviewer |
| Watch | Your running CircleCI pipelines that have no PR. Pipelines on hold for approval are urgent. |
| Waiting | Your other open PRs: drafts, and PRs that wait for review. PRs with changes requested are urgent. Merged PRs leave the list. |

The menu bar icon changes shape, not color: a beacon and a count for urgent items, a filled cab and a count for items to fix.

Tower refreshes every 5 minutes, and every 2 minutes when all sources are offline. It keeps the last good result of each source on disk, so it shows stale data instead of an empty panel when a source fails.

## Requirements

- macOS 26 or later
- Xcode 27 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [GitHub CLI](https://cli.github.com), signed in: `gh auth login`
- Optional: a Jira Cloud account and an [API token](https://id.atlassian.com/manage-profile/security/api-tokens)

## Build and run

```bash
xcodegen generate
open Tower.xcodeproj
```

Run the `Tower` scheme. The cab icon appears in the menu bar. Tower has no Dock icon. Click the icon to open the panel. Right-click or Control-click it for Settings and Quit Tower.

`project.yml` is the source of the Xcode project. Do not edit `Tower.xcodeproj` by hand; it is generated and gitignored.

## Set up

- **GitHub:** Tower reads your token from `gh auth token` and keeps it in memory only. If the sign-in expires, click "Reconnect" in the panel. Terminal opens and runs `gh auth login`.
- **Jira:** open Settings from the gear button in the panel or from the right-click menu. Enter the site URL (for example `https://acme.atlassian.net`), your email and the API token, then click "Test connection". Tower keeps the token in the Keychain.

## Test

```bash
xcodegen generate
xcodebuild -scheme Tower -destination 'platform=macOS' test
```

The tests use Swift Testing. `CoreTests` covers the `Core` framework: queue rules, clients (with a stub transport and fixture JSON), cache, refresh timing and panel state. `AppTests` covers the store refresh and cache load (with the same stub transport), the settings loaders, the menu bar icon, its right-click menu, the panel close rules and placement, the banner and Settings text, and the Settings window. The tests do not call the network, and they do not touch the real Jira and CircleCI Keychain items, the owner's defaults or the real cache folder.

GitHub Actions runs the same tests on each PR to `main` and each push to `main` (`.github/workflows/ci.yml`). The `build-and-test` job uses the `xcode-27` runner image and converts the code coverage with `scripts/xccov-to-sonarqube-generic.sh` (copied from Copilot Runway). The `sonarqube` job sends the code and the `App` and `Core` coverage to SonarQube Cloud. Only three layout-only views are excluded from coverage (`sonar-project.properties`). It needs the `SONAR_TOKEN` repo secret, so it does not run on PRs from forks.

## Release

```bash
scripts/release.sh
```

The script builds `dist/Tower-<version>.zip`, ad-hoc signed. With `DEVELOPER_ID_IDENTITY` and `NOTARY_KEYCHAIN_PROFILE` set, it signs with a Developer ID, notarizes, staples and checks the result with `spctl`.

## Project layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI and AppKit app: status item, panel window, store, panel views, settings, theme tokens, assets |
| `Core/` | Framework with no SwiftUI: models, GitHub and Jira clients, queue rules, cache, refresh policy, panel state |
| `CoreTests/` | Unit tests and fixtures for `Core` |
| `AppTests/` | Unit tests for the store, status item, panel and Settings logic, hosted by the app |
| `scripts/` | Release script, coverage conversion for SonarQube |
| `docs/superpowers/` | Specs and implementation plans |

## Next steps

1. **Open Settings when Tower is launched again** ([#14](https://github.com/wilsonfaustino/tower/issues/14)), so Tower stays reachable when its menu bar icon is hidden.
2. **Small fixes from the MVP review** ([#10](https://github.com/wilsonfaustino/tower/issues/10)): hover layout, copy details, VoiceOver selection, Jira paging, partial GitHub errors.
3. **Later:** GitHub sign-in without `gh`, launch at login, notarized releases.

Update this list when an item ships or changes.

## Documents

- MVP spec: [`docs/superpowers/specs/2026-11-05-tower-mvp-design.md`](docs/superpowers/specs/2026-11-05-tower-mvp-design.md)
- MVP plan: [`docs/superpowers/plans/2026-11-05-tower-mvp.md`](docs/superpowers/plans/2026-11-05-tower-mvp.md)
