import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct ErrorCodeExplanationTests {
  @Test
  func codeMapsToExplanationOjdExplainPrints() throws {
    let code = try #require(ErrorCode(rawValue: "E3029"))
    #expect(ErrorCodeExplanation.lookup("E3029") == .explained(code.facts))
    #expect(code.facts.explanation == code.localizedExplanation)
  }

  @Test
  func factsCarryAreaExitStatusAndWireValueOjdExplainPrints() {
    let cli = ErrorCode.serviceUnavailable.facts
    #expect(cli.exitCode == 69)
    #expect(cli.wire == nil)
    let endpoint = ErrorCode.notGranted.facts
    #expect(endpoint.exitCode == nil && endpoint.wire == nil)
    let remapping = ErrorCode.remappingUnexpected.facts
    #expect(remapping.exitCode == nil)
    #expect(remapping.wire != nil)
  }

  @Test
  func caseAndSurroundingSpaceOfCodeDoNotMatter() {
    #expect(ErrorCodeExplanation.lookup("  e3029\n") == ErrorCodeExplanation.lookup("E3029"))
  }

  @Test
  func textThatIsNoCodeIsUnknown() {
    #expect(ErrorCodeExplanation.lookup("E0000") == .unknown("E0000"))
  }

  @Test
  func blankTextLooksNothingUp() { #expect(ErrorCodeExplanation.lookup(" ") == nil) }
}
