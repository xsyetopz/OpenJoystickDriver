import Testing

@testable import OpenJoystickDriverKit

struct GyroStickTemplateTests {
  private static let model = ControllerModelID(vendorID: 0x054C, productID: 0x0CE6)
  private static let device = RemappingDeviceScope(vendorID: 0x054C, productID: 0x0CE6)

  private static func capabilities(motion: Bool) -> ControllerProfileCapabilities {
    ControllerProfileCapabilities(
      physicalInput: ControllerCapabilities(controls: [.leftShoulder], motion: motion),
      physicalOutput: .none
    )
  }

  @Test
  func theRightStickTemplateHoldsToActivateAndPassesEveryControlThrough() throws {
    let profile = try RemappingGyroStickTemplate.profile(
      name: "Gyro",
      device: Self.device,
      applicationScope: .global,
      stick: .right,
      activation: .button(.leftShoulder),
      capabilities: Self.capabilities(motion: true)
    )

    let expected = RemappingProfile(
      id: profile.id,
      name: "Gyro",
      device: Self.device,
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared),
      gyroOutput: RemappingGyroOutput(
        mode: .rightStick,
        activationMode: .whileHeld,
        activationSource: .button(.leftShoulder)
      ),
      bindings: []
    )
    #expect(profile == expected)
    try profile.validate()
  }

  @Test
  func theLeftStickTemplateWithoutActivationIsAlwaysOn() throws {
    let profile = try RemappingGyroStickTemplate.profile(
      name: "Gyro",
      device: Self.device,
      applicationScope: .global,
      stick: .left,
      activation: nil,
      capabilities: Self.capabilities(motion: true)
    )

    #expect(profile.gyroOutput.mode == .leftStick)
    #expect(profile.gyroOutput.activationMode == .always)
    #expect(profile.gyroOutput.activationSource == nil)
    try profile.validate()
  }

  @Test
  func aModelWithoutAMotionSensorFailsNamingTheModel() {
    #expect(throws: RemappingGyroStickTemplate.Failure.noMotionSensor(Self.model)) {
      try RemappingGyroStickTemplate.profile(
        name: "Gyro",
        device: Self.device,
        applicationScope: .global,
        stick: .right,
        activation: nil,
        capabilities: Self.capabilities(motion: false)
      )
    }
  }
}
