import AppKit
import Core
import Testing

@testable import Tower

struct RowSymbolTests {
  @Test(arguments: RowSymbol.allCases)
  func symbolExistsInTheAssetCatalog(symbol: RowSymbol) {
    #expect(NSImage(named: symbol.rawValue) != nil)
  }

  @Test(arguments: PanelSymbol.allCases)
  func panelSymbolExistsInTheAssetCatalog(symbol: PanelSymbol) {
    #expect(NSImage(named: symbol.rawValue) != nil)
  }

  @Test(arguments: MenuSymbol.allCases)
  func menuSymbolExistsInTheAssetCatalog(symbol: MenuSymbol) {
    #expect(NSImage(named: symbol.rawValue) != nil)
  }

  @Test(arguments: SettingsSymbol.allCases)
  func settingsSymbolExistsInTheAssetCatalog(symbol: SettingsSymbol) {
    #expect(NSImage(named: symbol.rawValue) != nil)
  }
}
