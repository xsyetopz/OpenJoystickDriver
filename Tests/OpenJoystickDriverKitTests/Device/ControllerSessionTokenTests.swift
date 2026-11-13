import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerSessionTokenTests {
  @Test
  func everyIssuedTokenIsNewAndWellFormed() {
    let tokens = (0..<1000).map { _ in ControllerSessionToken.issue() }
    #expect(Set(tokens).count == tokens.count)
    #expect(tokens.allSatisfy { ControllerSessionToken(rawValue: $0.rawValue) == $0 })
  }

  @Test
  func tokensWithSameTextAreEqual() throws {
    let token = try #require(ControllerSessionToken(rawValue: "E-AbCd_123-xyzW09q"))
    #expect(ControllerSessionToken(rawValue: token.rawValue) == token)
    #expect(
      token
        != ControllerSessionToken(rawValue: "E-AbCd_123-xyzW09r")
    )
  }

  @Test(arguments: [
    ("E-AbCd_123-xyzW09q", true), ("E-AbCd_123-xyzW09", false), ("E-AbCd/123-xyzW09q", false),
    ("U-AbCd_123-xyzW09q", false), ("M-054C-0CE6", false), ("", false),
  ])
  func tokensAreEAnd16Base64URLCharacters(text: String, valid: Bool) {
    #expect((ControllerSessionToken(rawValue: text) != nil) == valid)
  }

  @Test
  func encodesAsItsTextAndRejectsOtherText() throws {
    let token = ControllerSessionToken.issue()
    let data = try JSONEncoder().encode(token)
    #expect(String(bytes: data, encoding: .utf8) == "\"\(token.rawValue)\"")
    #expect(try JSONDecoder().decode(ControllerSessionToken.self, from: data) == token)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        ControllerSessionToken.self,
        from: Data("\"U-AbCd_123-xyzW09q\"".utf8)
      )
    }
  }
}
