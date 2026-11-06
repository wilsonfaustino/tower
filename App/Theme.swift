import AppKit
import Core
import SwiftUI

// Tokens from the design canvas, board "1 · Design tokens". Color only means urgency.
enum Theme {
  enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
  }

  enum Radius {
    static let row: CGFloat = 8
    static let banner: CGFloat = 10
  }

  enum Metrics {
    static let panelWidth: CGFloat = 380
    static let panelMaxHeight: CGFloat = 560
    static let rowMinHeight: CGFloat = 40
    static let rowInset: CGFloat = 6
    static let iconColumn: CGFloat = 20
    static let symbolSize: CGFloat = 15
    static let openArrowSize: CGFloat = 11
  }

  enum Fonts {
    static let stateTitle = Font.title3.weight(.semibold)
    static let panelTitle = Font.headline
    static let rowTitle = Font.body
    static let stateBody = Font.callout
    static let section = Font.subheadline.weight(.semibold)
    static let sectionCount = Font.subheadline.monospacedDigit()
    static let rowMeta = Font.subheadline.monospacedDigit()
    static let badge = Font.caption.weight(.semibold)
  }

  static let textPrimary = Color(nsColor: .labelColor)
  // System secondary label fails AA on the light panel (3.8:1), so use these values instead.
  static let textSecondary = Color(nsColor: dynamicColor(light: .black.withAlphaComponent(0.60), dark: .white.withAlphaComponent(0.62)))
  static let surfaceHover = Color(nsColor: dynamicColor(light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.08)))
  static let neutralBadgeFill = Color(nsColor: dynamicColor(light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.10)))

  static func statusText(_ variant: BadgeVariant) -> Color {
    switch variant {
    case .failing: Color(nsColor: dynamicColor(light: hex(0xB3261E), dark: hex(0xFF8A80)))
    case .urgent: Color(nsColor: dynamicColor(light: hex(0x934600), dark: hex(0xFFB84D)))
    case .ready: Color(nsColor: dynamicColor(light: hex(0x146B2B), dark: hex(0x5BE07A)))
    case .neutral: textSecondary
    }
  }

  // System colors stay only as badge tints: 12% light, 18% dark.
  static func badgeFill(_ variant: BadgeVariant) -> Color {
    let systemColor: NSColor
    switch variant {
    case .failing: systemColor = .systemRed
    case .urgent: systemColor = .systemOrange
    case .ready: systemColor = .systemGreen
    case .neutral: return neutralBadgeFill
    }
    return Color(nsColor: dynamicColor(light: systemColor.withAlphaComponent(0.12), dark: systemColor.withAlphaComponent(0.18)))
  }

  private static func hex(_ value: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }

  private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
  }
}
