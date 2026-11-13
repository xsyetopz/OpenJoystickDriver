import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerReferenceTests {
  private let token = ControllerSessionToken(rawValue: "E-AbCd_123-xyzW09q")!
  private let portKey = ControllerPortKey(rawValue: "U-AbCd_123-xyzW09q")!
  private let model = ControllerModelID(vendorID: 0x054C, productID: 0x0268)

  @Test
  func parsesSessionTokenPortKeyOrModel() {
    #expect(ControllerReference("E-AbCd_123-xyzW09q") == .session(token))
    #expect(ControllerReference("U-AbCd_123-xyzW09q") == .port(portKey))
    #expect(ControllerReference("054C:0268") == .model(model))
    #expect(ControllerReference("054c:0268") == .model(model))
  }

  @Test(arguments: ["", "M-054C-0268", "054C-0268", "54C:0268", "054C:0268:00", "E-short", "name"])
  func rejectsTextThatIsNoReference(text: String) {
    #expect(ControllerReference(text) == nil)
  }

  @Test
  func referencesToDifferentTargetsAreDifferent() {
    let references: [ControllerReference] = [
      .session(token), .port(portKey), .model(model),
      .model(ControllerModelID(vendorID: 0x054C, productID: 0x05C4)),
    ]
    #expect(Set(references).count == references.count)
  }

  @Test(arguments: ["E-AbCd_123-xyzW09q", "U-AbCd_123-xyzW09q", "054C:0268"])
  func encodesAsItsTextAndDecodesBack(text: String) throws {
    let reference = try #require(ControllerReference(text))
    let data = try JSONEncoder().encode(reference)
    #expect(String(bytes: data, encoding: .utf8) == "\"\(text)\"")
    #expect(try JSONDecoder().decode(ControllerReference.self, from: data) == reference)
  }

  @Test
  func decodingRejectsTextThatIsNoReference() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ControllerReference.self, from: Data("\"M-054C-0268\"".utf8))
    }
  }
}
