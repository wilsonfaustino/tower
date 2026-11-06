import Core
import Testing

struct TicketKeyMatcherTests {
  @Test func matchesKeyAtStartOfTitle() {
    #expect(ticketKey("PROJ-14", matches: "PROJ-14 add export"))
  }

  @Test func matchesLowercaseKeyInBranchName() {
    #expect(ticketKey("PROJ-14", matches: "feature/proj-14-export"))
  }

  @Test func rejectsLongerTicketNumber() {
    #expect(!ticketKey("PROJ-14", matches: "proj-143-export"))
  }

  @Test func rejectsLongerProjectPrefix() {
    #expect(!ticketKey("PROJ-14", matches: "XPROJ-14"))
  }
}
