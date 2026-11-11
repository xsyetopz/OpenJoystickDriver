import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct BindingRemarkTests {
  private static func profile(remark: String?, inLayer: Bool = false) -> RemappingProfile {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: []),
      remark: remark
    )
    return RemappingProfile(
      name: "Remarks",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: inLayer ? [] : [binding],
      layers: inLayer
        ? [RemappingLayer(
            name: "Menus",
            activationMode: .hold,
            activator: .button(.north),
            bindings: [binding]
          )] : []
    )
  }

  @Test
  func aRemarkSurvivesAnEncodeAndDecode() throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .mouseButton(.left),
      remark: "Jump"
    )
    let decoded = try JSONDecoder().decode(
      RemappingBinding.self,
      from: JSONEncoder().encode(binding)
    )
    #expect(decoded.remark == "Jump")
  }

  @Test
  func aBindingWithoutARemarkEncodesNoRemarkKey() throws {
    let binding = RemappingBinding(source: .button(.south), destination: .mouseButton(.left))
    let json = try String(decoding: JSONEncoder().encode(binding), as: UTF8.self)
    #expect(!json.contains("remark"))
  }

  @Test(arguments: ["Jump", "A", String(repeating: "a", count: 200)])
  func aRemarkOfAllowedFormIsAccepted(remark: String) throws {
    try Self.profile(remark: remark).validate()
    try Self.profile(remark: remark, inLayer: true).validate()
  }

  @Test(arguments: [
    "", " Jump", "Jump ", "Ju\nmp", "Ju\u{7f}mp", String(repeating: "a", count: 201),
  ])
  func aRemarkOfBadFormIsRefused(remark: String) {
    #expect(throws: RemappingValidationError.bindingRemarkInvalid(index: 0)) {
      try Self.profile(remark: remark).validate()
    }
    #expect(throws: RemappingValidationError.bindingRemarkInvalid(index: 0)) {
      try Self.profile(remark: remark, inLayer: true).validate()
    }
  }
}
