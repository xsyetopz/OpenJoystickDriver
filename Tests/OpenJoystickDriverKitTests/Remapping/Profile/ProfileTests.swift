import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingProfileTests {
  @Test func codableRoundTripPreservesRepresentativeControllerSources() throws {
    let profile = RemappingProfile(
      id: fixedUUID(10),
      name: "Adventure",
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA),
      applicationScope: .application(bundleIdentifier: "com.example.Adventure"),
      bindings: [
        binding(
          id: fixedUUID(1),
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [.shift])
        ),
        binding(id: fixedUUID(2), source: .button(.touchpad), destination: .mouseButton(.middle)),
        binding(
          id: fixedUUID(3),
          source: .button(.auxiliary1),
          destination: .keyboard(key: .escape, modifiers: [])
        ),
        RemappingBinding(
          id: fixedUUID(4),
          source: .axis(.rightStickX),
          destination: .mouseMovement(.x),
          axisTuning: RemappingAxisTuning(
            deadzone: 0.15,
            gain: 1.75,
            inverted: true,
            responseCurve: .smoothStep,
            digitalActivationThreshold: 0.6
          )
        )
      ]
    )

    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(RemappingProfile.self, from: data)

    #expect(decoded == profile)
    try decoded.validate()
  }

  @Test func encodedProfileUsesStableExplicitKeysAndSymbolicDestinations() throws {
    let profile = RemappingProfile(
      id: fixedUUID(10),
      name: "Keyboard",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .application(bundleIdentifier: "com.example.Game"),
      bindings: [
        binding(
          id: fixedUUID(1),
          source: .dpad(.up),
          destination: .keyboard(key: .w, modifiers: [.command, .shift])
        )
      ]
    )

    let data = try JSONEncoder().encode(profile)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(root.keys) == [
        "schema_version", "id", "name", "device", "application_scope", "bindings", "chords",
        "sequences", "layers"
      ]
    )

    let device = try #require(root["device"] as? [String: Any])
    #expect(Set(device.keys) == ["vendor_id", "product_id"])
    let scope = try #require(root["application_scope"] as? [String: Any])
    #expect(scope["type"] as? String == "application")
    #expect(scope["bundle_id"] as? String == "com.example.Game")

    let bindings = try #require(root["bindings"] as? [[String: Any]])
    let firstBinding = try #require(bindings.first)
    let destination = try #require(firstBinding["destination"] as? [String: Any])
    #expect(destination["type"] as? String == "keyboard")
    #expect(destination["key"] as? String == "w")
    #expect(destination["modifiers"] as? [String] == ["command", "shift"])
    #expect(destination["key_code"] == nil)
  }

  @Test func globalScopeIsExplicitInEncodedProfile() throws {
    let profile = RemappingProfile(
      name: "Global",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )

    let data = try JSONEncoder().encode(profile)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let scope = try #require(root["application_scope"] as? [String: Any])
    #expect(scope["type"] as? String == "global")
    #expect(scope["bundle_id"] == nil)
    try profile.validate()
  }

  @Test func symbolicKeyboardSurfaceHasStableExtendedAndKeypadValues() throws {
    let keys: [RemappingKeyboardKey] = [
      .capsLock, .help, .insert, .f13, .f20, .keypad0, .keypad9, .keypadDecimal, .keypadMultiply,
      .keypadPlus, .keypadClear, .keypadDivide, .keypadEnter, .keypadMinus, .keypadEqual
    ]
    let data = try JSONEncoder().encode(keys)
    let rawValues = try JSONDecoder().decode([String].self, from: data)

    #expect(
      rawValues == [
        "caps_lock", "help", "insert", "f13", "f20", "keypad_0", "keypad_9", "keypad_decimal",
        "keypad_multiply", "keypad_plus", "keypad_clear", "keypad_divide", "keypad_enter",
        "keypad_minus", "keypad_equal"
      ]
    )
    #expect(Set(RemappingKeyboardKey.allCases).isSuperset(of: keys))
  }

  private func binding(id: UUID, source: RemappingSource, destination: RemappingDestination)
    -> RemappingBinding
  { RemappingBinding(id: id, source: source, destination: destination) }

  private func fixedUUID(_ finalByte: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
  }
}
