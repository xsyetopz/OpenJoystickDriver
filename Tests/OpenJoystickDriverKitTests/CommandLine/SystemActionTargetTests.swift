import Testing

@testable import OpenJoystickDriverKit

/// The system action targets of `ojd binding set`.
@Suite
struct SystemActionTargetTests {
  @Test
  func eachTargetParsesToItsDestinationAndKeepsColonsInItsValue() throws {
    let cases: [(String, RemappingDestination)] = [
      ("system-key:volume-up", .systemKey(.volumeUp)),
      ("system:mission-control", .systemAction(.missionControl)),
      ("system:launchpad", .systemAction(.launchpad)),
      ("system:screenshot", .systemAction(.screenshot)),
      ("open-app:com.apple.TextEdit", .openApplication(bundleIdentifier: "com.apple.TextEdit")),
      ("open-url:https://example.com:8080/a", .openURL("https://example.com:8080/a")),
      ("shortcut:Dim: Lights", .runShortcut("Dim: Lights")),
      ("text:a:b", .typeText("a:b")),
    ]
    for (text, destination) in cases {
      #expect(try RemappingCommandValueParser.destination(text) == destination, "\(text)")
    }
  }

  @Test
  func unknownSystemKeyOrActionIsRejected() {
    for text in ["system-key:nope", "system:nope"] {
      #expect(throws: RemappingCommandValueError.self) {
        try RemappingCommandValueParser.destination(text)
      }
    }
  }
}
