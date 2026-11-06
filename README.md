# Tower

A macOS menu bar app that shows one queue of the GitHub pull requests and Jira tickets that need you now, sorted by urgency. Open the panel, see what to do, and click through to the item.

Tower is a sibling of [Copilot Runway](https://github.com/wilsonfaustino/copilot-runway). Both apps use aviation names.

## Status

MVP, in daily use by the author. Builds are ad-hoc signed. Notarized releases come later.

## What Tower shows

The panel has four sections in a fixed urgency order. Tower hides a section that has no items.

| Section | Items |
|---|---|
| Fix | Your open PRs with failing checks |
| Review | PRs that ask for your review. Bot PRs (Dependabot, Renovate) collapse into one row per bot. Only direct requests older than 24 hours are urgent. |
| Merge | Your approved PRs with no failing checks |
| Tidy | Your in-progress Jira tickets with no PR, or whose PR has no reviewer |

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

Run the `Tower` scheme. The cab icon appears in the menu bar. Tower has no Dock icon.

`project.yml` is the source of the Xcode project. Do not edit `Tower.xcodeproj` by hand; it is generated and gitignored.

## Set up

- **GitHub:** Tower reads your token from `gh auth token` and keeps it in memory only. If the sign-in expires, click "Reconnect" in the panel. Terminal opens and runs `gh auth login`.
- **Jira:** open Settings from the gear button in the panel. Enter the site URL (for example `https://acme.atlassian.net`), your email and the API token, then click "Test connection". Tower keeps the token in the Keychain.

## Test

```bash
xcodegen generate
xcodebuild -scheme Tower -destination 'platform=macOS' test
```

The tests use Swift Testing and cover the `Core` framework: queue rules, clients (with a stub transport and fixture JSON), cache, refresh timing and panel state. They do not call the network.

## Release

```bash
scripts/release.sh
```

The script builds `dist/Tower-<version>.zip`, ad-hoc signed. With `DEVELOPER_ID_IDENTITY` and `NOTARY_KEYCHAIN_PROFILE` set, it signs with a Developer ID, notarizes, staples and checks the result with `spctl`.

## Project layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI app: menu bar scene, store, panel views, settings, theme tokens, assets |
| `Core/` | Framework with no SwiftUI: models, GitHub and Jira clients, queue rules, cache, refresh policy, panel state |
| `CoreTests/` | Unit tests and fixtures |
| `scripts/` | Release script |
| `docs/superpowers/` | Specs and implementation plans |

## Next steps

1. **CircleCI pipelines:** show release pipelines that you started (from scripts or from the CircleCI UI) and that have no PR. The panel placement is still open; the proposal is a "Watch" section for running pipelines.
2. **Small fixes from the MVP review:** hover layout, copy details, VoiceOver selection, Jira paging, partial GitHub errors.
3. **Later:** GitHub sign-in without `gh`, launch at login, notarized releases, CI.

Update this list when an item ships or changes.

## Documents

- MVP spec: [`docs/superpowers/specs/2026-11-05-tower-mvp-design.md`](docs/superpowers/specs/2026-11-05-tower-mvp-design.md)
- MVP plan: [`docs/superpowers/plans/2026-11-05-tower-mvp.md`](docs/superpowers/plans/2026-11-05-tower-mvp.md)
