import Foundation

/// Redacted, capability-driven manual validation instructions for physical controller output.
public struct PhysicalOutputValidationPlan: Equatable, Sendable {
  /// One `ojd controller` command to run and what the tester should see.
  public struct Step: Equatable, Sendable, Identifiable {
    /// The name of the step, such as `left-trigger`.
    public let id: String
    /// The `ojd controller` command to run.
    public let command: String
    /// What the controller shows when the command works.
    public let expectedObservation: String

    /// Creates a step from its values.
    public init(id: String, command: String, expectedObservation: String) {
      self.id = id
      self.command = command
      self.expectedObservation = expectedObservation
    }
  }

  /// The USB vendor ID of the controller.
  public let vendorID: UInt16
  /// The USB product ID of the controller.
  public let productID: UInt16
  /// The protocol family bound to the controller.
  public let protocolBinding: ProtocolBindingID
  /// The steps that match the controller's motors, player indicators and lighting, in the order to
  /// run them.
  public let steps: [Step]
  /// The notes to read before testing.
  public let notes: [String]

  /// `selector` names the controller in the commands; it defaults to its `VVVV:PPPP` identity.
  public init(device: ApplicationServiceDeviceDescription, selector: String? = nil) {
    self.init(
      vendorID: device.vendorID,
      productID: device.productID,
      protocolBinding: device.protocolBinding,
      capabilities: device.physicalOutputCapabilities,
      selector: selector
    )
  }

  /// Creates a plan for a controller with `capabilities`.
  ///
  /// `selector` names the controller in the commands; it defaults to its `VVVV:PPPP` identity.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    protocolBinding: ProtocolBindingID,
    capabilities: PhysicalControllerOutputCapabilities,
    selector: String? = nil
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.protocolBinding = protocolBinding
    steps = Self.steps(
      selector: selector ?? String(format: "%04X:%04X", vendorID, productID),
      capabilities: capabilities
    )
    notes = [
      "Record pass/fail separately; generating this plan does not verify hardware.",
      "Stop testing and disconnect the controller if output behaves unexpectedly.",
      "Serial values, HID locations, packet payloads, and filesystem paths are excluded.",
    ]
  }

  /// The steps for `capabilities`; each capability the controller lacks adds none.
  ///
  /// `identity` names the controller in the commands.
  private static func steps(
    selector identity: String,
    capabilities: PhysicalControllerOutputCapabilities
  ) -> [Step] {
    let prefix = "ojd controller"
    var result: [Step] = []
    let motors = Set(capabilities.rumbleMotors)
    if motors.contains(.lowFrequency) || motors.contains(.leftHaptic) {
      result.append(
        Step(
          id: motors.contains(.leftHaptic) ? "left-haptic" : "low-frequency",
          command: "\(prefix) rumble \(identity) --left 160 --duration 0.3",
          expectedObservation: motors.contains(.leftHaptic)
            ? "Only the left trackpad haptic actuator pulses." : "Only the left main actuator runs."
        )
      )
    }
    if motors.contains(.highFrequency) || motors.contains(.rightHaptic) {
      result.append(
        Step(
          id: motors.contains(.rightHaptic) ? "right-haptic" : "high-frequency",
          command: "\(prefix) rumble \(identity) --right 160 --duration 0.3",
          expectedObservation: motors.contains(.rightHaptic)
            ? "Only the right trackpad haptic actuator pulses."
            : "Only the right main actuator runs."
        )
      )
    }
    if motors.contains(.leftTrigger) {
      result.append(
        Step(
          id: "left-trigger",
          command: "\(prefix) rumble \(identity) --left-trigger 160 --duration 0.3",
          expectedObservation: "Only the left trigger actuator runs."
        )
      )
    }
    if motors.contains(.rightTrigger) {
      result.append(
        Step(
          id: "right-trigger",
          command: "\(prefix) rumble \(identity) --right-trigger 160 --duration 0.3",
          expectedObservation: "Only the right trigger actuator runs."
        )
      )
    }
    if capabilities.supportsPlayerIndicator {
      result.append(
        Step(
          id: "player-indicators",
          command: "\(prefix) player \(identity) 1",
          expectedObservation: "The controller displays the player-one indicator pattern."
        )
      )
      result.append(
        Step(
          id: "player-indicators-off",
          command: "\(prefix) player \(identity) off",
          expectedObservation: "The numbered player indicators turn off."
        )
      )
    }
    if capabilities.lightingFeatures.contains(.programmableColor) {
      for (id, color, values) in [
        ("color-red", "red", "FF0000"), ("color-green", "green", "00FF00"),
        ("color-blue", "blue", "0000FF"),
      ] {
        result.append(
          Step(
            id: id,
            command: "\(prefix) light \(identity) --color \(values)",
            expectedObservation: "The lightbar becomes \(color)."
          )
        )
      }
    }
    if capabilities.supportsProgrammableBrightness {
      result.append(
        Step(
          id: "brightness-low",
          command: "\(prefix) light \(identity) --brightness 32",
          expectedObservation: "The controller LED becomes dim."
        )
      )
      result.append(
        Step(
          id: "brightness-high",
          command: "\(prefix) light \(identity) --brightness 224",
          expectedObservation: "The controller LED becomes bright."
        )
      )
    }
    return result
  }
}
