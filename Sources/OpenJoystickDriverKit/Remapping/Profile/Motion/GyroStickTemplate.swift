/// The `gyro-stick` profile template: gyro motion drives a stick of the virtual gamepad.
public enum RemappingGyroStickTemplate {
  /// The stick that gyro motion drives.
  public enum Stick: String, CaseIterable, Sendable {
    /// The left stick.
    case left
    /// The right stick.
    case right
  }

  /// Why a template profile cannot be made.
  public enum Failure: Error, Equatable, Sendable {
    /// The controller model reports no motion sensor.
    case noMotionSensor(ControllerModelID)
  }

  /// Makes a profile that drives `stick` from gyro motion and passes every other control through.
  ///
  /// Gyro output is active while `activation` is held, or always when it is nil.
  /// - Throws: ``Failure/noMotionSensor(_:)`` when `capabilities` report no motion.
  public static func profile(
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope,
    stick: Stick,
    activation: RemappingSource?,
    capabilities: ControllerProfileCapabilities
  ) throws -> RemappingProfile {
    guard capabilities.physicalInput.motion else {
      throw Failure.noMotionSensor(
        ControllerModelID(vendorID: device.vendorID, productID: device.productID)
      )
    }
    return RemappingProfile(
      name: name,
      device: device,
      applicationScope: applicationScope,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .shared),
      gyroOutput: RemappingGyroOutput(
        mode: stick == .left ? .leftStick : .rightStick,
        activationMode: activation == nil ? .always : .whileHeld,
        activationSource: activation
      ),
      bindings: []
    )
  }
}
