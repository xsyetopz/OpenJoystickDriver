import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MotionProfileTests {
  private func profile(version: Int = 3, tuning: RemappingMotionTuning = .default)
    -> RemappingProfile
  {
    RemappingProfile(
      schemaVersion: version,
      name: "Motion",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: tuning,
      bindings: []
    )
  }

  @Test func profileRoundTripPreservesMotionTuning() throws {
    let custom = profile(tuning: RemappingMotionTuning(space: .world, yawSensitivity: 3))
    try custom.validate()
    let data = try JSONEncoder().encode(custom)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == custom)
  }

  @Test func profileValidationRejectsOlderSchemaAndInvalidProgrammaticTuning() {
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try profile(version: 2, tuning: RemappingMotionTuning(invertYaw: true)).validate()
    }
    let expected = RemappingValidationError.invalidMotionTuning(.invalidField("yaw_sensitivity"))
    #expect(throws: expected) {
      try profile(tuning: RemappingMotionTuning(yawSensitivity: .infinity)).validate()
    }
  }
}
