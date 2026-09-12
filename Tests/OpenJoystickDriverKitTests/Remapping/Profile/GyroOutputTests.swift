import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct GyroOutputTests {
  @Test
  func mouseGyroRequiresSystemInputAccessInOtherwiseVirtualOnlyProfiles() throws {
    for mode in RemappingGyroOutputMode.allCases {
      let profile = RemappingProfile(
        name: "Gyro permissions",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
        gyroOutput: RemappingGyroOutput(mode: mode),
        bindings: []
      )
      try profile.validate()
      #expect(profile.requiresSystemInputAccess == (mode == .mouse))
    }
  }

  @Test
  func profilesPersistGyroOutputAndEnforceVirtualOutputPolicy() throws {
    let mouse = profile(output: RemappingGyroOutput(mode: .mouse))
    try mouse.validate()
    let encoded = try JSONEncoder().encode(mouse)
    #expect(String(data: encoded, encoding: .utf8)?.contains("gyro_output") == true)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: encoded) == mouse)
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try profile(output: RemappingGyroOutput(mode: .mouse), schemaVersion: 2).validate()
    }
    for mode in [RemappingGyroOutputMode.leftStick, .rightStick] {
      #expect(throws: RemappingValidationError.virtualOutputRequired) {
        try profile(output: RemappingGyroOutput(mode: mode)).validate()
      }
    }
  }

  private func profile(output: RemappingGyroOutput, schemaVersion: Int = 3) -> RemappingProfile {
    RemappingProfile(
      schemaVersion: schemaVersion,
      name: "Gyro",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      gyroOutput: output,
      bindings: []
    )
  }

  @Test
  func omittedSettingsDisableOutputAndExplicitSettingsRoundTrip() throws {
    let omitted = try JSONDecoder().decode(RemappingGyroOutput.self, from: Data("{}".utf8))
    #expect(omitted == .default)
    #expect(omitted.mode == .disabled)
    for mode in RemappingGyroOutputMode.allCases {
      let settings = RemappingGyroOutput(
        mode: mode,
        pointerPointsPerDegree: 4.5,
        fullStickDegreesPerSecond: 180
      )
      let encoded = try JSONEncoder().encode(settings)
      #expect(try JSONDecoder().decode(RemappingGyroOutput.self, from: encoded) == settings)
    }
    let virtualMotion = RemappingGyroOutput(virtualMotion: true)
    #expect(
      try JSONDecoder().decode(RemappingGyroOutput.self, from: JSONEncoder().encode(virtualMotion))
        == virtualMotion
    )
  }

  @Test
  func invalidUnitsAreRejectedAtValidationAndDecode() throws {
    for value in [-1, 1001, Double.nan, Double.infinity] {
      #expect(throws: RemappingGyroOutputError.invalidField("pointer_points_per_degree")) {
        try RemappingGyroOutput(pointerPointsPerDegree: value).validate()
      }
    }
    for value in [0, 10001, Double.nan, Double.infinity] {
      #expect(throws: RemappingGyroOutputError.invalidField("full_stick_degrees_per_second")) {
        try RemappingGyroOutput(fullStickDegreesPerSecond: value).validate()
      }
    }
    #expect(throws: RemappingGyroOutputError.invalidField("full_stick_degrees_per_second")) {
      try JSONDecoder().decode(
        RemappingGyroOutput.self,
        from: Data(#"{"mode":"right_stick","full_stick_degrees_per_second":0}"#.utf8)
      )
    }
  }
}
