import AppKit
import SwiftUI

struct LaunchAtLoginSection: View {
  @State private var model = LaunchAtLoginModel()

  var body: some View {
    Section("General") {
      Toggle("Launch at login", isOn: $model.isOn)
      if let caption = model.caption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      model.refresh()
    }
  }
}
