# Tower

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=wilsonfaustino_tower&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=wilsonfaustino_tower)

A macOS menu bar app that shows one queue of the GitHub pull requests and Jira tickets that need you now, sorted by urgency. Open the panel, see what to do, and click through to the item.

Tower is a sibling of [Copilot Runway](https://github.com/wilsonfaustino/copilot-runway). Both apps use aviation names.

## Status

MVP, in daily use by the author. Releases are signed with a Developer ID and notarized by Apple.

## Install

```bash
brew trust wilsonfaustino/tap
brew install --cask wilsonfaustino/tap/tower-menubar
```

Homebrew refuses to load a cask from a third-party tap until you trust the tap, so run `brew trust` once.

The cask is `tower-menubar` because the Homebrew cask `tower` is the Git client of the same name. Both install `Tower.app`, so the cask declares a conflict with it. Tower needs macOS 26 and the GitHub CLI (`gh`), signed in.

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

At launch and then once a day, Tower asks GitHub for its latest release. The request has no token. When a newer version exists, the panel and Settings > About show it with an Update button. Update runs `brew update` and `brew upgrade --cask`, then relaunches Tower. When Homebrew did not install Tower, the button is "Copy brew command". The menu bar icon's context menu has Check for Updates… (Cmd-U).

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

To see the panel with fake data, launch a Debug build with `-demo <scenario>`. Demo data makes no network calls and does not write the cache. Scenarios: `typical` (every section), `long-list` (enough rows to scroll), `clear-skies`, `offline`, `auth-failure`, `notify`, `update` (typical data and a fake newer version, for the update notice; Update shows only "Copy brew command").

```bash
open path/to/Debug/Tower.app --args -demo long-list
```

## Set up

- **GitHub:** Tower reads your token from `gh auth token` and keeps it in memory only. If the sign-in expires, click "Reconnect" in the panel. Terminal opens and runs `gh auth login`.
- **GitHub organizations:** to show PRs from some owners only, enter one organization or user login per line in Settings > GitHub > Organizations. Leave it empty to show PRs from all owners. Tower ignores blank lines and lines that are not valid logins. A change applies at the next refresh.
- **Jira:** open Settings from the gear button in the panel or from the right-click menu. Enter the site URL (for example `https://acme.atlassian.net`), your email and the API token, then click "Test connection". Tower keeps the token in the Keychain.
- **Launch at login:** copy Tower to `/Applications` and open it from there, because a build in DerivedData can be deleted. Then turn on "Launch at login" in Settings > General. It is off by default. If macOS asks for approval, approve Tower in System Settings > General > Login Items.

## Test

```bash
xcodegen generate
xcodebuild -scheme Tower -destination 'platform=macOS' test
```

The tests use Swift Testing. `CoreTests` covers the `Core` framework: queue rules, clients (with a stub transport and fixture JSON), cache, refresh timing and panel state. `AppTests` covers the store refresh and cache load (with the same stub transport), the settings loaders, the menu bar icon, its right-click menu, the panel close rules and placement, the banner and Settings text, the launch at login toggle, and the Settings window. The tests do not call the network, and they do not touch the real Jira and CircleCI Keychain items, the owner's defaults or the real cache folder.

GitHub Actions runs the same tests on each PR to `main` and each push to `main` (`.github/workflows/ci.yml`). The `build-and-test` job uses the `xcode-27` runner image and converts the code coverage with `scripts/xccov-to-sonarqube-generic.sh` (copied from Copilot Runway). The `sonarqube` job sends the code and the `App` and `Core` coverage to SonarQube Cloud. Only four layout-only views are excluded from coverage (`sonar-project.properties`). It needs the `SONAR_TOKEN` repo secret, so it does not run on PRs from forks.

## Release

```bash
scripts/release.sh
```

The script builds `dist/Tower-<version>.zip`, ad-hoc signed. With `DEVELOPER_ID_IDENTITY` and `NOTARY_KEYCHAIN_PROFILE` set, it signs with a Developer ID, notarizes, staples and checks the result with `spctl`. The script reads both values from a gitignored `.env` at the repo root when the environment does not set them:

```bash
DEVELOPER_ID_IDENTITY=<codesign identity name or SHA-1 hash>
NOTARY_KEYCHAIN_PROFILE=<notarytool keychain profile>
```

The script stops when the working tree has uncommitted changes or when `HEAD` has no tag `v<version>`. Use `scripts/release.sh --allow-dirty` to skip both checks for a local test build.

To install the current version on this Mac:

```bash
scripts/install.sh
```

The script runs `release.sh --allow-dirty`, quits a running Tower, replaces `/Applications/Tower.app` with the new build and opens it.

### Publish a release

`.github/workflows/release.yml` and the cask template `packaging/Casks/tower-menubar.rb` publish a version to the Homebrew tap `wilsonfaustino/homebrew-tap`. CI has no Apple credentials, so the maintainer builds the notarized zip on this Mac.

1. Set `MARKETING_VERSION` in `project.yml` to the new version, merge it to `main`, then tag and push: `git tag v<version> && git push origin v<version>`.
2. The `build` job checks that the tag matches `MARKETING_VERSION`, builds an ad-hoc zip and creates a draft release.
3. On `main` at the tag, with `.env` set, run `scripts/release.sh`. Then replace the draft asset: `gh release upload v<version> dist/Tower-<version>.zip --clobber`.
4. Write the release notes and publish the draft.
5. The `verify` job checks the asset: a valid signature from team `PX9G95LY8C`, a stapled ticket, and `spctl` when the runner has Gatekeeper on. If it fails, fix the asset as in step 3 and re-run the workflow.
6. The `tap` job copies the cask template into the tap with the new version and sha256, and pushes. It needs the `HOMEBREW_TAP_TOKEN` repo secret: a fine-grained token with contents read and write on `wilsonfaustino/homebrew-tap`.

## Project layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI and AppKit app: status item, panel window, store, panel views, settings, theme tokens, assets |
| `Core/` | Framework with no SwiftUI: models, GitHub and Jira clients, queue rules, cache, refresh policy, panel state |
| `CoreTests/` | Unit tests and fixtures for `Core` |
| `AppTests/` | Unit tests for the store, status item, panel and Settings logic, hosted by the app |
| `scripts/` | Release and install scripts, coverage conversion for SonarQube |
| `packaging/Casks/` | Homebrew cask template that the release workflow copies into the tap |
| `docs/superpowers/` | Specs and implementation plans |

## Next steps

1. **Next (v0.6.0):** group Waiting PRs by repo ([#90](https://github.com/wilsonfaustino/tower/issues/90)).
2. **Later:** GitHub sign-in without `gh`.

Update this list when an item ships or changes.

## Documents

- MVP spec: [`docs/superpowers/specs/2026-11-05-tower-mvp-design.md`](docs/superpowers/specs/2026-11-05-tower-mvp-design.md)
- MVP plan: [`docs/superpowers/plans/2026-11-05-tower-mvp.md`](docs/superpowers/plans/2026-11-05-tower-mvp.md)
