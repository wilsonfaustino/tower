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
    static let panel: CGFloat = 12
  }

  enum Metrics {
    static let panelWidth: CGFloat = 420
    static let panelMaxHeight: CGFloat = 560
    static let panelGap: CGFloat = 4
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
  // Increase Contrast values are stronger so text and fills stay distinct on the panel material.
  static let textSecondary = Color(
    nsColor: dynamicColor(
      light: .black.withAlphaComponent(0.60), dark: .white.withAlphaComponent(0.62),
      highContrastLight: .black.withAlphaComponent(0.80), highContrastDark: .white.withAlphaComponent(0.85)))
  static let surfaceHover = Color(
    nsColor: dynamicColor(
      light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.08),
      highContrastLight: .black.withAlphaComponent(0.14), highContrastDark: .white.withAlphaComponent(0.18)))
  static let neutralBadgeFill = Color(
    nsColor: dynamicColor(
      light: .black.withAlphaComponent(0.06), dark: .white.withAlphaComponent(0.10),
      highContrastLight: .black.withAlphaComponent(0.14), highContrastDark: .white.withAlphaComponent(0.20)))

  // Selection matches menus: the system selection color, not the accent, so any accent keeps contrast.
  static let selectionFill = Color(nsColor: .selectedContentBackgroundColor)
  static let selectionText = Color(nsColor: .alternateSelectedControlTextColor)

  struct StatusColors {
    let light: NSColor
    let dark: NSColor
    let highContrastLight: NSColor
    let highContrastDark: NSColor
  }

  // Only failing and ready have Increase Contrast values, because the PR status strip draws them as thin glyphs.
  static func statusColors(_ variant: BadgeVariant) -> StatusColors? {
    switch variant {
    case .failing:
      StatusColors(light: hex(0xB3261E), dark: hex(0xFF8A80), highContrastLight: hex(0x8C1D18), highContrastDark: hex(0xFFB4AB))
    case .ready:
      StatusColors(light: hex(0x146B2B), dark: hex(0x5BE07A), highContrastLight: hex(0x0D5220), highContrastDark: hex(0x8CF0A0))
    case .urgent, .neutral: nil
    }
  }

  static func statusText(_ variant: BadgeVariant) -> Color {
    if let colors = statusColors(variant) {
      return Color(
        nsColor: dynamicColor(
          light: colors.light, dark: colors.dark, highContrastLight: colors.highContrastLight,
          highContrastDark: colors.highContrastDark))
    }
    return switch variant {
    case .urgent: Color(nsColor: dynamicColor(light: hex(0x934600), dark: hex(0xFFB84D)))
    default: textSecondary
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

  static func hex(_ value: Int) -> NSColor {
    NSColor(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
  }

  static func dynamicColor(
    light: NSColor, dark: NSColor, highContrastLight: NSColor? = nil, highContrastDark: NSColor? = nil
  ) -> NSColor {
    NSColor(name: nil) { appearance in
      switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
      case .darkAqua: dark
      case .accessibilityHighContrastDarkAqua: highContrastDark ?? dark
      case .accessibilityHighContrastAqua: highContrastLight ?? light
      default: light
      }
    }
  }
}
