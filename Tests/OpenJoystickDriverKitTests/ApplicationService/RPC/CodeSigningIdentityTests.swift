import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct CodeSigningIdentityTests {
  @Test
  func systemToolIsSignedByApple() throws {
    let identity = try #require(CodeSigningIdentity.of(path: URL(fileURLWithPath: "/usr/bin/true")))

    #expect(identity.kind == .apple)
    #expect(identity.identifier == "com.apple.true")
    #expect(identity.requirementText == "identifier \"com.apple.true\" and anchor apple")
    #expect(identity.requirement != nil)
  }

  @Test
  func teamRequirementPinsTheTeam() {
    let identity = CodeSigningIdentity(
      kind: .team,
      identifier: "com.example.\"tool\"",
      teamIdentifier: "ABCDE12345"
    )

    #expect(
      identity.requirementText
        == "identifier \"com.example.\\\"tool\\\"\" and anchor apple generic and "
        + "certificate leaf[subject.OU] = \"ABCDE12345\""
    )
    #expect(identity.requirement != nil)
  }

  @Test
  func adHocCodeHasNoRequirement() {
    let identity = CodeSigningIdentity(kind: .adHoc, identifier: "tool", teamIdentifier: nil)

    #expect(identity.requirementText == nil)
    #expect(identity.requirement == nil)
  }

  @Test
  func pathWithoutCodeHasNoIdentity() {
    #expect(CodeSigningIdentity.of(path: URL(fileURLWithPath: "/etc/hosts")) == nil)
  }
}
