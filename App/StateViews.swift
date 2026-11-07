import SwiftUI

struct StateMessageView: View {
  let symbol: String
  let title: String
  let message: String
  var footnote: String?
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: Theme.Spacing.s) {
      Image(systemName: symbol)
        .font(.system(size: 28))
        .foregroundStyle(Theme.textSecondary)
      Text(title).font(Theme.Fonts.stateTitle).foregroundStyle(Theme.textPrimary)
      Text(message).font(Theme.Fonts.stateBody).foregroundStyle(Theme.textSecondary)
      if let footnote {
        Text(footnote).font(Theme.Fonts.rowMeta).foregroundStyle(Theme.textSecondary)
      }
      if let actionTitle, let action {
        Button(actionTitle, action: action).padding(.top, Theme.Spacing.xs)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.vertical, Theme.Spacing.xl)
  }
}

struct AuthBannerView: View {
  let title: String
  let message: String
  var actionTitle = "Reconnect"
  let reconnect: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Theme.Spacing.s) {
      Image(systemName: "key")
        .font(.system(size: Theme.Metrics.symbolSize))
        .foregroundStyle(Theme.textSecondary)
        .frame(width: Theme.Metrics.iconColumn)
      VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
        Text(title).font(Theme.Fonts.rowTitle.weight(.semibold)).foregroundStyle(Theme.textPrimary)
        Text(message).font(Theme.Fonts.stateBody).foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: Theme.Spacing.s)
      Button(actionTitle, action: reconnect)
    }
    .padding(Theme.Spacing.m)
    .background(Theme.surfaceHover, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
  }
}
