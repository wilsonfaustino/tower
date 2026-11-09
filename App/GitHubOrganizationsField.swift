import SwiftUI

struct GitHubOrganizationsField: View {
  @AppStorage(GitHubSettingsKeys.organizations) private var githubOrganizations = ""

  var body: some View {
    LabeledContent("Organizations") {
      TextEditor(text: $githubOrganizations)
        .font(.body.monospaced())
        .frame(minHeight: 60)
    }
    Text("One per line. Leave empty to show PRs from all organizations.")
      .font(.caption)
      .foregroundStyle(Theme.textSecondary)
  }
}
