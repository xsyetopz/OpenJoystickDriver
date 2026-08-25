import Testing

@testable import OpenJoystickDriver

@Suite struct ConsoleTests {
  @Test func wrapsConsoleLinesAtEightyColumnsWithoutBreakingWordsWhenPossible() {
    let input = String(repeating: "123456789 ", count: 9) + "tail"

    let lines = ConsoleLineWrapper.wrap(input)

    let firstLine = String(String(repeating: "123456789 ", count: 8).dropLast())
    #expect(lines == [firstLine, "123456789 tail"])
    #expect(lines.allSatisfy { $0.count <= 80 })
  }

  @Test func hardWrapsAnUnbrokenDiagnosticToken() {
    let lines = ConsoleLineWrapper.wrap(String(repeating: "x", count: 161))

    #expect(lines.map(\.count) == [80, 80, 1])
  }
}
