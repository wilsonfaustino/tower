# Panel redesign D: focus tabs with tags

Date: 2026-11-12. Mockup: design canvas https://claude.ai/artifact/9LVWQBmXJpqYwDxBkhZdMK, artboards "D · Needs you tab" and "D · Waiting tab".

## Why

The panel scrolls even when only a few items need the owner. Long repo names truncate in the middle, the team slug gets cut to one letter, and the PR number takes title width. Ten Waiting rows push Review off screen. All icons are gray, so urgent rows do not stand out.

## Goals

- Two tabs in a segmented control: **Needs you** (Fix, Review, Merge, Tidy) and **Waiting** (Waiting). Counts in each tab label.
- Watch rows (running and on-hold pipelines) pinned below the tab content on both tabs. Up to 2 rows, then a "+N more" line. On hold keeps the urgent dot and "Needs approval".
- Each section is an inset grouped card (radius 10, fill white 5% / black 4%, 1px separator stroke). The section header stays above the card.
- Row: symbol, title (full width, no PR number), then a meta line that starts with a **tag chip** (repo, Jira key, or "bot") followed by `#number · author · age · team`.
- The capsule badge becomes **short text plus a status dot** on the right. The dot is `QueueItem.statusDot`. The text is the badge text. Color is never the only signal: the text and the VoiceOver label carry the meaning.
- The status strip keeps threads and approvals. The checks glyph goes away, because the dot shows the checks.
- A **legend** under the list: failing, needs you, ready, pending.
- **Outline groups**: a row with `children` expands in place, with a disclosure chevron. The child rows are indented. Groups are collapsed by default.
  - The Dependabot or Renovate row (one per bot) gets the bot PRs as children.
  - Waiting: 3 or more PRs in the same repo with the same title prefix (the text before the first ":", for example `chore(feature-flags)`) become one group.

## Non-goals

- GitHub sign-in without `gh`.
- Remembering the last tab. The panel always opens on Needs you.
- Hiding the legend after first use.
- Light mode visual polish beyond using the existing dynamic tokens.

## Behavior

- Tabs: click the segment, or Cmd-1 / Cmd-2.
- Up and Down move through the visible rows of the current tab, then the pinned Watch rows. Expanded children count as visible rows.
- On a group row: Right expands, Left collapses, Return and click toggle. On a child row, Left moves the selection to its group.
- Switching tabs clears the selection.
- Empty Needs you tab: the existing "Clear skies" state inside the tab. Empty Waiting tab: "Nothing waiting on others."
- Banners and the offline and failed states stay above the tabs, as today.

## Approaches considered

- A (calm list, Waiting folded into one row): smallest change, but the owner preferred tabs.
- C (dense one-line ledger): fits all rows, but loses the author and makes color the main signal.
- **D (picked)**: B's tabs and cards with C's tags and legend.

## Calls made by Claude

- The tag shows the repo name as given by GitHub (no owner). No prefix stripping.
- The group title is the shared title prefix plus the count, for example `chore(feature-flags) · 4 PRs`. The group URL is a GitHub search for the viewer's open PRs with that prefix in the title.
- Pipeline rows: title is the ref (`main`), tag is the repo.
- Jira rows: tag is the key; the meta line is `status · age`.

## Shared Core API (already on the branch)

`QueueItem.tag`, `QueueItem.children`, `PanelTab` (`title`, `sectionKinds`), `sections(_:in:)`, `StatusDot` (`legendLabel`), `QueueItem.statusDot`.
