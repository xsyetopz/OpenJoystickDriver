import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct TouchOptionsTests {
  @Test func partialUpdatePreservesOtherSurfaceAndProfileSettings() throws {
    let right = RemappingTouchMapping(surface: .right, mode: .rightStick)
    let left = RemappingTouchMapping(surface: .left, mode: .pointer, pointerSensitivity: 500)
    let original = RemappingProfile(
      name: "Touch",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      touchMappings: [right, left],
      bindings: []
    )
    let updated = try MappingProfileEditor.updating(original, options: MappingOptions([
      "--touch-surface", "left", "--touch-pointer-sensitivity", "750"
    ]))

    #expect(updated.id == original.id)
    #expect(updated.touchMappings[0] == right)
    #expect(updated.touchMappings[1].id == left.id)
    #expect(updated.touchMappings[1].pointerSensitivity == 750)
    let removed = try MappingProfileEditor.updating(updated, options: MappingOptions([
      "--touch-surface", "left", "--touch-mode", "none"
    ]))
    #expect(removed.touchMappings == [right])
  }

  @Test func createsTypedMappingWithDefaults() throws {
    let mappings = try MappingProfileEditor.touchMappings(MappingOptions([
      "--touch-surface", "primary", "--touch-mode", "pointer"
    ]))
    #expect(mappings.count == 1)
    #expect(mappings[0].surface == .primary)
    #expect(mappings[0].mode == .pointer)
  }

  @Test(arguments: [
    ["--touch-mode", "pointer"],
    ["--touch-surface", "unknown"],
    ["--touch-surface", "left", "--touch-mode", "unknown"],
    ["--touch-surface", "left", "--touch-mode", "none", "--touch-deadzone", "0.1"],
    ["--touch-surface", "left", "--touch-pointer-sensitivity", "nan"],
    ["--touch-surface", "left", "--touch-stick-radius", "0"]
  ])
  func rejectsInvalidOptions(arguments: [String]) throws {
    let options = try MappingOptions(arguments)
    #expect(throws: (any Error).self) {
      let profile = RemappingProfile(
        name: "Touch",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        touchMappings: try MappingProfileEditor.touchMappings(options),
        bindings: []
      )
      try profile.validate()
    }
  }
}
