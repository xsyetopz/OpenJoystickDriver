import Foundation
import Testing
@testable import OpenJoystickDriverKit

struct LayerMotionProfileTests {
  @Test func optionalOverrideRoundTripsAndLegacyLayerDecodes() throws {
    let layer = RemappingLayer(
      name: "Aim",
      activationMode: .hold,
      activator: .button(.east),
      motionTuning: RemappingMotionTuning(yawSensitivity: 0.5)
    )
    let data = try JSONEncoder().encode(layer)
    #expect(try JSONDecoder().decode(RemappingLayer.self, from: data) == layer)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "motion_tuning")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(RemappingLayer.self, from: legacy).motionTuning == nil)
  }

  @Test func profileRejectsInvalidAndLegacyOverrides() {
    func profile(version: Int, tuning: RemappingMotionTuning) -> RemappingProfile {
      RemappingProfile(
        schemaVersion: version,
        name: "Layers",
        device: RemappingDeviceScope(vendorID: 1, productID: 2),
        applicationScope: .global,
        bindings: [],
        layers: [RemappingLayer(
          name: "Aim", activationMode: .hold, activator: .button(.east), motionTuning: tuning
        )]
      )
    }
    #expect(throws: RemappingValidationError.unsupportedSchemaVersion(2)) {
      try profile(version: 2, tuning: .default).validate()
    }
    let error = RemappingValidationError.invalidMotionTuning(.invalidField("yaw_sensitivity"))
    #expect(throws: error) {
      try profile(version: 3, tuning: RemappingMotionTuning(yawSensitivity: -1)).validate()
    }
  }
}
