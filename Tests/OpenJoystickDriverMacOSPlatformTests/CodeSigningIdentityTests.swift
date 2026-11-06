import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct CodeSigningIdentityTests {
  @Test
  func theProcessAtTheOtherEndOfASocketResolvesToCode() throws {
    var descriptors: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    defer { for descriptor in descriptors { close(descriptor) } }

    let peer = try #require(LocalSocketPeer.authenticated(descriptors[0]))
    #expect(peer.processIdentifier == getpid())
    #expect(peer.code() != nil)
    #expect(peer.satisfies(nil))
  }

  @Test
  func systemToolIsSignedByApple() throws {
    let identity = try #require(CodeSigningIdentity.of(path: URL(fileURLWithPath: "/usr/bin/true")))

    #expect(identity.kind == .platform)
    #expect(identity.identifier == "com.apple.true")
    #expect(identity.requirementText == "identifier \"com.apple.true\" and anchor apple")
    #expect(identity.requirement != nil)
  }

  @Test
  func teamRequirementPinsTheTeam() {
    let identity = CodeSigningIdentity(
      kind: .signed,
      identifier: "com.example.\"tool\"",
      publisherID: "ABCDE12345"
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
    let identity = CodeSigningIdentity(kind: .adHoc, identifier: "tool", publisherID: nil)

    #expect(identity.requirementText == nil)
    #expect(identity.requirement == nil)
  }

  @Test
  func pathWithoutCodeHasNoIdentity() {
    #expect(CodeSigningIdentity.of(path: URL(fileURLWithPath: "/etc/hosts")) == nil)
  }
}
