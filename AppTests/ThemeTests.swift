import AppKit
import Core
import SwiftUI
import Testing

@testable import Tower

private func resolved(_ color: NSColor, in appearanceName: NSAppearance.Name) -> NSColor? {
  var resolvedColor: NSColor?
  NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
    resolvedColor = color.usingColorSpace(.sRGB)
  }
  return resolvedColor
}

// WCAG relative luminance and contrast ratio, computed here so the test does not reuse Theme code.
private func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
  func luminance(_ color: NSColor) -> CGFloat {
    let srgb = color.usingColorSpace(.sRGB)!
    func linear(_ channel: CGFloat) -> CGFloat {
      channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(srgb.redComponent) + 0.7152 * linear(srgb.greenComponent) + 0.0722 * linear(srgb.blueComponent)
  }
  let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
  return (lighter + 0.05) / (darker + 0.05)
}

private let light = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
private let dark = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
private let highContrastLight = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
private let highContrastDark = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)

@MainActor struct ThemeColorTests {
  @Test func hexSplitsRedGreenAndBlue() throws {
    let color = try #require(Theme.hex(0xB3261E).usingColorSpace(.sRGB))
    #expect(color.redComponent == CGFloat(0xB3) / 255)
    #expect(color.greenComponent == CGFloat(0x26) / 255)
    #expect(color.blueComponent == CGFloat(0x1E) / 255)
    #expect(color.alphaComponent == 1)
  }

  // NSAppearance(named:) gives the plain appearance for the high contrast names, so only light and dark are testable.
  @Test func dynamicColorPicksLightOrDark() {
    let color = Theme.dynamicColor(
      light: light, dark: dark, highContrastLight: highContrastLight, highContrastDark: highContrastDark)
    #expect(resolved(color, in: .aqua) == light)
    #expect(resolved(color, in: .darkAqua) == dark)
  }

  @Test func neutralUsesTheSecondaryTextAndNeutralFill() {
    #expect(Theme.statusText(.neutral) == Theme.textSecondary)
    #expect(Theme.badgeFill(.neutral) == Theme.neutralBadgeFill)
  }

  @Test(arguments: [BadgeVariant.failing, .urgent, .ready])
  func statusVariantsHaveTheirOwnColors(variant: BadgeVariant) {
    #expect(Theme.statusText(variant) != Theme.textSecondary)
    #expect(Theme.badgeFill(variant) != Theme.neutralBadgeFill)
  }

  @Test(arguments: [BadgeVariant.failing, .ready])
  func increaseContrastValuesHaveMoreContrastThanTheStandardValues(variant: BadgeVariant) throws {
    let colors = try #require(Theme.statusColors(variant))
    #expect(contrastRatio(colors.highContrastLight, .white) > contrastRatio(colors.light, .white))
    #expect(contrastRatio(colors.highContrastDark, .black) > contrastRatio(colors.dark, .black))
  }
}
