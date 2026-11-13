import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingProfileTests {
  @Test
  func optionalPhysicalColorIsBackwardCompatibleAndRoundTripsBlack() throws {
    let oldData = try JSONEncoder().encode(
      RemappingProfile(
        id: fixedUUID(1),
        name: "Old",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        bindings: []
      )
    )
    let oldProfile = try JSONDecoder().decode(RemappingProfile.self, from: oldData)
    #expect(oldProfile.physicalColor == nil)

    let selectedBlack = RemappingProfile(
      id: fixedUUID(2),
      name: "Black",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      physicalColor: ControllerColor(red: 0, green: 0, blue: 0),
      bindings: []
    )
    let roundTrip = try JSONDecoder().decode(
      RemappingProfile.self,
      from: JSONEncoder().encode(selectedBlack)
    )
    #expect(roundTrip.physicalColor == ControllerColor(red: 0, green: 0, blue: 0))
  }

  @Test
  func codableRoundTripPreservesRepresentativeControllerSources() throws {
    let profile = RemappingProfile(
      id: fixedUUID(10),
      name: "Adventure",
      device: RemappingDeviceScope(vendorID: 0x045E, productID: 0x02EA),
      applicationScope: .application(appIDs: ["com.example.Adventure"]),
      bindings: [
        binding(
          id: fixedUUID(1),
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [.shift])
        ),
        binding(
          id: fixedUUID(2),
          source: .button(.touchpadClick),
          destination: .mouseButton(.middle)
        ),
        binding(
          id: fixedUUID(3),
          source: .button(.capture),
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
        ),
      ]
    )

    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(RemappingProfile.self, from: data)

    #expect(decoded == profile)
    try decoded.validate()
  }

  @Test
  func encodedProfileUsesStableExplicitKeysAndSymbolicDestinations() throws {
    let profile = RemappingProfile(
      id: fixedUUID(10),
      name: "Keyboard",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .application(appIDs: ["com.example.Game"]),
      bindings: [
        binding(
          id: fixedUUID(1),
          source: .dpad(.up),
          destination: .keyboard(key: .w, modifiers: [.meta, .shift])
        )
      ]
    )

    let data = try JSONEncoder().encode(profile)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(root.keys) == [
        "apiVersion", "kind", "id", "name", "device", "applicationScope", "bindings", "chords",
        "sequences", "layers", "outputPolicy",
      ]
    )

    let device = try #require(root["device"] as? [String: Any])
    #expect(Set(device.keys) == ["vendorID", "productID"])
    let scope = try #require(root["applicationScope"] as? [String: Any])
    #expect(scope["type"] as? String == "Application")
    #expect(scope["appIDs"] as? [String] == ["com.example.Game"])
    #expect(scope["appID"] == nil)

    let bindings = try #require(root["bindings"] as? [[String: Any]])
    let firstBinding = try #require(bindings.first)
    let destination = try #require(firstBinding["destination"] as? [String: Any])
    #expect(destination["type"] as? String == "Keyboard")
    #expect(destination["key"] as? String == "KeyW")
    #expect(destination["modifiers"] as? [String] == ["Meta", "Shift"])
    #expect(destination["key_code"] == nil)
  }

  @Test
  func globalScopeIsExplicitInEncodedProfile() throws {
    let profile = RemappingProfile(
      name: "Global",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )

    let data = try JSONEncoder().encode(profile)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let scope = try #require(root["applicationScope"] as? [String: Any])
    #expect(scope["type"] as? String == "Global")
    #expect(scope["appID"] == nil)
    try profile.validate()
  }

  @Test
  func missingOrUnsupportedHeaderIsRejectedAndNamed() throws {
    let profile = RemappingProfile(
      name: "Current",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    let supported = "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    let cases: [(member: String, value: String?, code: ErrorCode?, message: String)] = [
      ("apiVersion", nil, .unsupportedAPIVersion, "no apiVersion found; \(supported)"),
      (
        "apiVersion", "unsupported.example/v9", .unsupportedAPIVersion,
        "apiVersion unsupported.example/v9 is not supported; \(supported)"
      ),
      ("kind", nil, nil, "no kind found; expected Profile"),
      ("kind", "Controller", nil, "expected Profile, found Controller"),
    ]
    for item in cases {
      var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
      )
      object[item.member] = item.value
      let data = try JSONSerialization.data(withJSONObject: object)
      do {
        _ = try JSONDecoder().decode(RemappingProfile.self, from: data)
        Issue.record("\(item.member) \(item.value ?? "nil") was accepted")
      } catch let problem as DocumentHeaderProblem {
        #expect(item.code != nil)
        #expect(problem.code == item.code)
        #expect(problem.message == item.message)
      } catch let DecodingError.dataCorrupted(context) {
        #expect(item.code == nil)
        #expect(context.debugDescription == item.message)
      }
    }
  }

  @Test
  func versionTaggedProfilesAreRejected() throws {
    let profile = RemappingProfile(
      name: "Current",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: []
    )
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any]
    )
    object["schemaVersion"] = 3
    let tagged = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingProfile.self, from: tagged)
    }
  }

  @Test
  func symbolicKeyboardSurfaceHasStableExtendedAndKeypadValues() throws {
    let keys: [RemappingKeyboardKey] = [
      .capsLock, .help, .insert, .f13, .f20, .keypad0, .keypad9, .keypadDecimal, .keypadMultiply,
      .keypadPlus, .keypadClear, .keypadDivide, .keypadEnter, .keypadMinus, .keypadEqual,
    ]
    let data = try JSONEncoder().encode(keys)
    let rawValues = try JSONDecoder().decode([String].self, from: data)

    #expect(
      rawValues == [
        "CapsLock", "Help", "Insert", "F13", "F20", "Numpad0", "Numpad9", "NumpadDecimal",
        "NumpadMultiply", "NumpadAdd", "NumLock", "NumpadDivide", "NumpadEnter",
        "NumpadSubtract", "NumpadEqual",
      ]
    )
    #expect(Set(RemappingKeyboardKey.allCases).isSuperset(of: keys))
  }

  private func binding(
    id: UUID,
    source: RemappingSource,
    destination: RemappingDestination
  ) -> RemappingBinding { RemappingBinding(id: id, source: source, destination: destination) }

  private func fixedUUID(_ finalByte: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, finalByte))
  }
}
