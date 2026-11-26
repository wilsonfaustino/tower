import SwiftUI

struct GitHubTeamFiltersField: View {
  let store: QueueStore

  var body: some View {
    SettingsRow(label: "Team filters") {
      let teamSlugs = store.filterableTeamSlugs
      if teamSlugs.isEmpty {
        SettingsCaption(text: "Tower lists a team here after it sees a review request for that team.")
      } else {
        ForEach(teamSlugs, id: \.self) { teamSlug in
          VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
              Text(teamSlug)
              Spacer()
              Picker(teamSlug, selection: isFiltered(teamSlug)) {
                Text("No filter").tag(false)
                Text("Only these people").tag(true)
              }
              .labelsHidden()
              .fixedSize()
            }
            if store.teamAuthorFilterText[teamSlug] != nil {
              SettingsTextEditor(text: allowedLogins(teamSlug))
            }
          }
        }
        SettingsCaption(
          text: "One login per line. A PR that asks several filtered teams shows if any of them allows the author. "
            + "Direct requests always show.")
      }
    }
  }

  private func isFiltered(_ teamSlug: String) -> Binding<Bool> {
    Binding {
      store.teamAuthorFilterText[teamSlug] != nil
    } set: { isFiltered in
      if !isFiltered {
        store.teamAuthorFilterText[teamSlug] = nil
      } else if store.teamAuthorFilterText[teamSlug] == nil {
        store.teamAuthorFilterText[teamSlug] = ""
      }
    }
  }

  private func allowedLogins(_ teamSlug: String) -> Binding<String> {
    Binding {
      store.teamAuthorFilterText[teamSlug] ?? ""
    } set: { text in
      store.teamAuthorFilterText[teamSlug] = text
    }
  }
}
