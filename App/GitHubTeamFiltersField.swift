import SwiftUI

struct GitHubTeamFiltersField: View {
  let store: QueueStore
  @State private var addingTeamSlug: String?
  @State private var typedLogin = ""
  @FocusState private var isLoginFieldFocused: Bool

  var body: some View {
    SettingsRow(label: "Team filters") {
      let teamSlugs = store.filterableTeamSlugs
      if teamSlugs.isEmpty {
        SettingsCaption(text: "Tower lists a team here after it sees a review request for that team.")
      } else {
        ForEach(teamSlugs, id: \.self) { teamSlug in
          VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
              Text(teamSlug).fontWeight(.semibold)
              Spacer()
              Picker(teamSlug, selection: isFiltered(teamSlug)) {
                Text("Everyone").tag(false)
                Text("Only these people").tag(true)
              }
              .labelsHidden()
              .fixedSize()
            }
            if let logins = store.teamAuthorLogins[teamSlug] {
              FlowLayout(spacing: Theme.Spacing.xs) {
                ForEach(logins, id: \.self) { login in
                  loginChip(login, teamSlug: teamSlug)
                }
                if addingTeamSlug == teamSlug {
                  loginField(teamSlug: teamSlug)
                } else {
                  addLoginButton(teamSlug: teamSlug)
                }
              }
            }
          }
          .padding(.vertical, Theme.Spacing.xs)
          Divider()
        }
        SettingsCaption(text: "Teams come from review requests Tower has seen. Direct requests always show.")
      }
    }
  }

  private func loginChip(_ login: String, teamSlug: String) -> some View {
    HStack(spacing: Theme.Spacing.xs) {
      Text(login)
      Button {
        store.teamAuthorLogins[teamSlug]?.removeAll { $0 == login }
      } label: {
        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
      }
      .buttonStyle(.plain)
      .foregroundStyle(Theme.textSecondary)
      .accessibilityLabel("Remove \(login)")
    }
    .loginChipPadding()
    .background(Theme.loginChipFill, in: RoundedRectangle(cornerRadius: 4))
  }

  private func addLoginButton(teamSlug: String) -> some View {
    Button {
      typedLogin = ""
      addingTeamSlug = teamSlug
      isLoginFieldFocused = true
    } label: {
      Text("+ Add")
        .foregroundStyle(Theme.textSecondary)
        .loginChipPadding()
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [3])))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // A fixed width, because a text field takes the whole line that the flow layout would offer it.
  private func loginField(teamSlug: String) -> some View {
    TextField("login", text: $typedLogin)
      .textFieldStyle(.plain)
      .focused($isLoginFieldFocused)
      .frame(width: 110)
      .loginChipPadding()
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.cardStroke))
      .onSubmit { addTypedLogin(to: teamSlug) }
      .onExitCommand { addingTeamSlug = nil }
      .onAppear { isLoginFieldFocused = true }
  }

  // An invalid login keeps the field and its text so the user can fix it.
  private func addTypedLogin(to teamSlug: String) {
    if typedLogin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      addingTeamSlug = nil
    } else if let logins = GitHubSettingsKeys.logins(store.teamAuthorLogins[teamSlug] ?? [], adding: typedLogin) {
      store.teamAuthorLogins[teamSlug] = logins
      addingTeamSlug = nil
    }
  }

  private func isFiltered(_ teamSlug: String) -> Binding<Bool> {
    Binding {
      store.teamAuthorLogins[teamSlug] != nil
    } set: { isFiltered in
      if !isFiltered {
        store.teamAuthorLogins[teamSlug] = nil
        if addingTeamSlug == teamSlug { addingTeamSlug = nil }
      } else if store.teamAuthorLogins[teamSlug] == nil {
        store.teamAuthorLogins[teamSlug] = []
      }
    }
  }
}

private extension View {
  func loginChipPadding() -> some View {
    font(Theme.Fonts.tag).padding(.horizontal, 6).padding(.vertical, Theme.Spacing.xxs)
  }
}
