# Tower MVP spec

Date: 2026-11-05
Status: approved by owner, 2026-11-05
Design source: Tower design canvas (https://claude.ai/artifact/8rruisLsnErCnAhAGYDux1), summarized in the Serena memories `design/tokens`, `design/components`, `design/panel-states`, `design/icons`.
Decisions: Serena memory `mvp-decisions`. Post-MVP items: Serena memory `roadmap`.
Reference project: `~/www/dot/copilot-tracker` (Copilot Runway), same owner, same build and release setup.

## Goal

A macOS menu bar app that shows one queue of the GitHub PRs and Jira tickets that need the owner now, sorted by urgency. The owner opens the panel, sees what to do, and clicks through to the item.

## Out of scope for the MVP

- CircleCI pipelines (first item after the MVP, see `roadmap`).
- Paste-a-token or OAuth sign-in for GitHub. The MVP reads the token from the `gh` CLI only.
- Launch at login.
- Notifications, auto-update, Homebrew tap, multiple GitHub hosts (GitHub Enterprise), multiple Jira sites.

## Platform and project

- macOS 26 minimum. Swift 6, SwiftUI, `MenuBarExtra` with `.window` style.
- Agent app (`LSUIElement = YES`): no Dock icon, no main window.
- Bundle ID `dev.wilsonfaustino.Tower`. Display name "Tower".
- XcodeGen (`project.yml`), as in Copilot Runway. Never hand-edit `.pbxproj`. Targets:
  - `Tower` (app): SwiftUI views, the store, `Theme`.
  - `Core` (framework): clients, models, queue rules. No SwiftUI.
  - `CoreTests` (unit tests, Swift Testing): fixtures read by path from `CoreTests/Fixtures`.
- No third-party dependencies.

## Signing and release

- Developer ID of team `PX9G95LY8C`, hardened runtime, notarized. No App Sandbox, so Tower can run `gh`. Copilot Runway ships the same way and runs `gh`, so this setup is proven.
- `scripts/release.sh`: copy from Copilot Runway and rename. Ad-hoc by default. With `DEVELOPER_ID_IDENTITY` and `NOTARY_KEYCHAIN_PROFILE` set, it signs nested code then the app, notarizes, staples, and checks with `spctl`. Output: `dist/Tower-<version>.zip`.
- CI is out of scope for the MVP.

## Data sources

### GitHub

- Token: run `gh auth token` and read stdout. A GUI app does not get the shell PATH, so look for `gh` at `/opt/homebrew/bin/gh` and `/usr/local/bin/gh`.
- Run `gh` with a copy of Copilot Runway's `Core/GhRunner.swift` (30 s timeout, both pipes drained).
- API: GitHub GraphQL `search` queries with the token. One request per refresh if possible.
- The token stays in memory only. Tower does not store it.

### Jira

- Settings: site URL (for example `https://acme.atlassian.net`), account email, API token.
- The site URL and email go to `UserDefaults`. The API token goes to the Keychain.
- API: Jira Cloud REST v3 search with JQL, Basic auth (email + API token).
- Query: `assignee = currentUser() AND statusCategory = "In Progress"`. Status names differ by ticket type, so Tower does not read them for its rules. It shows the status name only in the meta line.

## Queue rules

Sections appear in this fixed order: **Fix, Review, Merge, Tidy**. Tower hides a section that has no items. In a section, the oldest item comes first.

| Section | Item | Source rule | Badge (variant) | Symbol |
|---|---|---|---|---|
| Fix | My PR, CI failing | Open PR, author is me, not draft, check rollup state is `FAILURE` or `ERROR` | "N checks failed" (failing) | `xmark.circle` |
| Review | Review requested of me, waiting 1 day or more | Open PR, review requested of me or of one of my teams, request older than 24 h | "Waiting Nd" (urgent) | `eye` |
| Review | Review requested of me, newer | Same, request newer than 24 h | diff size "+A −D" (neutral) | `eye` |
| Merge | My PR, approved | Open PR, author is me, review decision `APPROVED`, check rollup is not failing | "Approved" (ready) | `arrow.triangle.merge` |
| Tidy | Ticket with no PR | Jira ticket from the query above, and no open PR of mine has the ticket key in its title or branch name | "No PR" (neutral) | `arrow.triangle.branch` |
| Tidy | Ticket whose PR has no reviewer | Jira ticket from the query above, the matched PR has no requested reviewers and no reviews | "No reviewer" (neutral) | `person.badge.questionmark` |

A Jira ticket whose matched PR has a reviewer does not appear. That PR already shows in Fix or Merge, or it waits on someone else.

Key matching: a ticket key matches when it appears in the PR title or head branch name, case-insensitive, as a whole token (`PROJ-14` does not match `PROJ-143`).

Meta line:
- PR: `repo #number · author · age`. Fix and Merge omit the author, because it is me.
- Team review request: add the team after the author: `app-web #2179 · Ana · team web-core · 1d`.
- Jira: `KEY · Status · age`.
- Age: short form (`25m`, `4h`, `1d`). For Review, age counts from the review request. For other rows, from the last update.

Click opens the item URL in the default browser and closes the panel. Cmd-click opens it and keeps the panel open. Up/Down moves the keyboard selection, Return opens.

## Menu bar icon

- Fix has items: `MenuBarCabFailing` + Fix count as text.
- Else, an urgent item exists: `MenuBarCabUrgent` + urgent count as text.
- Else: `MenuBarCab`, no text.
- Counts use tabular digits. All three images are template images.

## Refresh

- Poll every 5 minutes.
- Manual refresh: the header refresh button.
- When all sources fail with a network error, retry every 2 minutes until one succeeds, then go back to 5 minutes.
- The two sources refresh independently. One failure does not block the other.

## Cache

- After each successful fetch, write that source's raw result to a JSON file in Application Support.
- On launch, load the cache first and show it, then refresh.
- On a failed fetch, keep the last cached result for that source on screen.

## Panel states

All copy below is fixed (from the design canvas).

1. **Populated:** sections as above. Header subtitle: "Updated just now" or "Updated 2m ago".
2. **Empty:** `checkmark.seal`, "Clear skies", "Nothing needs you right now.", and the line "Today: N reviews · N merges" (reviews I submitted today, my PRs merged today, both from GitHub search).
3. **Partial error, GitHub auth failed** (`gh` missing, not logged in, or 401): banner with `key`, "GitHub sign-in expired" / "Showing PRs from 18 min ago. Jira is current." and a "Reconnect" button. Header subtitle: "PRs from 18m ago". The same pattern applies to Jira auth failures, with Jira wording, and "Reconnect" opens Settings.
4. **Offline, nothing cached:** `wifi.slash`, "Can't reach GitHub or Jira", "Tower retries every 2 minutes.", "Try now" button. Show this only when no source has a cache. Otherwise show stale data with the subtitle "Offline".

GitHub "Reconnect": write a `.command` file that runs `gh auth login` to a temporary folder and open it, so Terminal runs it. This needs no Automation permission. When Tower becomes active again, it refreshes.

## Settings

A small settings window (opened from the header settings button):
- GitHub: read-only status line ("Signed in as <login> via gh" or the error).
- Jira: site URL, email, API token, and a "Test connection" button.

## Visual design

Use the tokens, type styles, spacing and component specs from the Serena memories `design/tokens` and `design/components` as written. Ship them as one flat `Theme` enum. Panel width 380, max height 560, then scroll.

## Assets

Use `Tower-assets.zip` from the project root:
- `Assets.xcassets` goes into the app target as is (AppIcon + 3 menu bar imagesets).
- `IconComposerLayers/` is the input for the macOS 26 Icon Composer icon (`AppIcon.icon`, as in Copilot Runway).
- `masters/` stays as source SVGs, not in the app bundle.

## Testing

- Queue rules are a pure function in `Core` from source data to sections. Unit test it with fixture JSON for each row in the queue rules table, including the 24 h boundary and team requests.
- Unit tests: menu bar icon state, age format, Jira-to-PR key matching (whole-token rule), retry interval switch.
- Clients take an injected HTTP transport, so tests do not call the network.
