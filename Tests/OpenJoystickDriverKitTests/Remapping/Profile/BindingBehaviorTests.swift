import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingBindingBehaviorTests {
  @Test func omittedBehaviorInCurrentSchemaDecodesAsHold() throws {
    let binding = RemappingBinding(
      source: .button(.south), destination: .keyboard(key: .a, modifiers: [])
    )
    let original = profile(binding)
    let data = try JSONEncoder().encode(original)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let bindings = try #require(object["bindings"] as? [[String: Any]])
    #expect(bindings.first?["behavior"] == nil)
    let decoded = try JSONDecoder().decode(RemappingProfile.self, from: data)
    try decoded.validate()
    #expect(decoded.bindings.first?.behavior == .hold)
    #expect(decoded == original)
  }

  @Test func olderSchemaIsRejectedBeforeBindingPayloadIsDecoded() throws {
    let data = Data(#"{"schema_version":2,"bindings":"not an array"}"#.utf8)
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try JSONDecoder().decode(RemappingProfile.self, from: data)
    }
  }

  @Test(arguments: 0..<4)
  func toggleRejectsConflictingOutputAndActivation(configuration: Int) {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: configuration == 0 ? .mouseMovement(.x) : .keyboard(key: .a, modifiers: []),
      behavior: .toggle,
      turbo: configuration == 1 ? RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5) : nil,
      longHold: configuration == 2
        ? RemappingLongHold(durationMs: 500, destination: .keyboard(key: .b, modifiers: [])) : nil,
      doubleTap: configuration == 3
        ? RemappingDoubleTap(windowMs: 200, destination: .keyboard(key: .b, modifiers: [])) : nil
    )
    #expect(throws: RemappingValidationError.bindingBehaviorConflict(index: 0)) {
      try profile(binding).validate()
    }
  }

  private func profile(_ binding: RemappingBinding) -> RemappingProfile {
    RemappingProfile(
      name: "Behavior validation",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [binding]
    )
  }
}
