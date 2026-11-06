import AppKit
import Core
import Testing

struct RowSymbolTests {
  @Test(arguments: RowSymbol.allCases)
  func symbolExistsInSFSymbols(symbol: RowSymbol) {
    #expect(NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil) != nil)
  }
}
