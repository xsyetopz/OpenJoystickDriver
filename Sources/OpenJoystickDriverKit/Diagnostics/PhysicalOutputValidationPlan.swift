import Foundation

/// Redacted, capability-driven manual validation instructions for physical controller output.
public struct PhysicalOutputValidationPlan: Codable, Equatable, Sendable {
  public struct Step: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let command: String
    public let expectedObservation: String

    public init(id: String, command: String, expectedObservation: String) {
      self.id = id
      self.command = command
      self.expectedObservation = expectedObservation
    }
  }

  public let vendorID: UInt16
  public let productID: UInt16
  public let parser: String
  public let evidence: PhysicalOutputEvidence
  public let steps: [Step]
  public let notes: [String]

  public init(device: ApplicationServiceDeviceDescription) {
    self.init(
      vendorID: device.vendorID,
      productID: device.productID,
      parser: device.parser,
      capabilities: device.physicalOutputCapabilities
    )
  }

  public init(
    vendorID: UInt16,
    productID: UInt16,
    parser: String,
    capabilities: PhysicalControllerOutputCapabilities
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.parser = parser
    evidence = capabilities.evidence
    steps = Self.steps(
      vendorID: vendorID,
      productID: productID,
      capabilities: capabilities
    )
    notes = [
      "Record pass/fail separately; generating this plan does not verify hardware.",
      "Stop testing and disconnect the controller if output behaves unexpectedly.",
      "Serial values, HID locations, packet payloads, and filesystem paths are excluded.",
    ]
  }

  public func encodedJSON() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  private static func steps(
    vendorID: UInt16,
    productID: UInt16,
    capabilities: PhysicalControllerOutputCapabilities
  ) -> [Step] {
    let prefix = "OpenJoystickDriver --headless controller output"
    let identity = "\(vendorID) \(productID)"
    var result: [Step] = []
    let motors = Set(capabilities.rumbleMotors)
    if motors.contains(.leftMain) || motors.contains(.leftHaptic) {
      result.append(Step(
        id: motors.contains(.leftHaptic) ? "left-haptic" : "left-main",
        command: "\(prefix) rumble \(identity) --left 160 --right 0 --duration-ms 300",
        expectedObservation: motors.contains(.leftHaptic)
          ? "Only the left trackpad haptic actuator pulses."
          : "Only the left main actuator runs."
      ))
    }
    if motors.contains(.rightMain) || motors.contains(.rightHaptic) {
      result.append(Step(
        id: motors.contains(.rightHaptic) ? "right-haptic" : "right-main",
        command: "\(prefix) rumble \(identity) --left 0 --right 160 --duration-ms 300",
        expectedObservation: motors.contains(.rightHaptic)
          ? "Only the right trackpad haptic actuator pulses."
          : "Only the right main actuator runs."
      ))
    }
    if motors.contains(.leftTrigger) {
      result.append(Step(
        id: "left-trigger",
        command: "\(prefix) rumble \(identity) --left 0 --right 0 --lt 160 --duration-ms 300",
        expectedObservation: "Only the left trigger actuator runs."
      ))
    }
    if motors.contains(.rightTrigger) {
      result.append(Step(
        id: "right-trigger",
        command: "\(prefix) rumble \(identity) --left 0 --right 0 --rt 160 --duration-ms 300",
        expectedObservation: "Only the right trigger actuator runs."
      ))
    }
    if capabilities.supportsPlayerIndicator {
      result.append(Step(
        id: "player-indicators",
        command: "\(prefix) player \(identity) 1",
        expectedObservation: "The controller displays the player-one indicator pattern."
      ))
      result.append(Step(
        id: "player-indicators-off",
        command: "\(prefix) player \(identity) off",
        expectedObservation: "The numbered player indicators turn off."
      ))
    }
    if capabilities.lightingFeatures.contains(.programmableColor) {
      for (id, color, values) in [
        ("color-red", "red", "255 0 0"),
        ("color-green", "green", "0 255 0"),
        ("color-blue", "blue", "0 0 255"),
      ] {
        result.append(Step(
          id: id,
          command: "\(prefix) color \(identity) \(values)",
          expectedObservation: "The lightbar becomes \(color)."
        ))
      }
    }
    if capabilities.supportsProgrammableBrightness {
      result.append(Step(
        id: "brightness-low",
        command: "\(prefix) brightness \(identity) 32",
        expectedObservation: "The controller LED becomes dim."
      ))
      result.append(Step(
        id: "brightness-high",
        command: "\(prefix) brightness \(identity) 224",
        expectedObservation: "The controller LED becomes bright."
      ))
    }
    return result
  }
}
