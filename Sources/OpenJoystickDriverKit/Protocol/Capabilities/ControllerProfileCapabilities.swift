/// Controller features that can be selected safely while editing a remapping profile.
public struct ControllerProfileCapabilities: Equatable, Sendable {
  /// The input controls and sample formats the controller reports.
  public let physicalInput: ControllerCapabilities
  /// The rumble, lighting and adaptive-trigger outputs the controller accepts.
  public let physicalOutput: PhysicalControllerOutputCapabilities

  /// A device OJD cannot describe: every control stays selectable, without
  /// touch, motion or physical output.
  public static let unknown = Self(
    physicalInput: ControllerCapabilities(controls: Set(Control.allCases)),
    physicalOutput: .none
  )

  /// Creates profile capabilities from the controller's input and output capabilities.
  public init(
    physicalInput: ControllerCapabilities,
    physicalOutput: PhysicalControllerOutputCapabilities
  ) {
    self.physicalInput = physicalInput
    self.physicalOutput = physicalOutput
  }

  /// Whether the controller reports at least one stick axis.
  public var supportsStickAxes: Bool {
    !physicalInput.controls.isDisjoint(with: [.leftStickX, .leftStickY, .rightStickX, .rightStickY])
  }

  /// Whether the controller reports at least one analog trigger.
  public var supportsAnalogTriggers: Bool {
    !physicalInput.controls.isDisjoint(with: [.leftTrigger, .rightTrigger])
  }

  /// Returns the capabilities both sides share, for both input and output.
  public func intersecting(_ other: Self) -> Self {
    Self(
      physicalInput: physicalInput.intersecting(other.physicalInput),
      physicalOutput: PhysicalControllerOutputCapabilities(
        rumbleMotors: intersection(physicalOutput.rumbleMotors, other.physicalOutput.rumbleMotors),
        lightingFeatures: intersection(
          physicalOutput.lightingFeatures,
          other.physicalOutput.lightingFeatures
        ),
        binaryRumbleMotors: intersection(
          physicalOutput.binaryRumbleMotors,
          other.physicalOutput.binaryRumbleMotors
        ),
        adaptiveTriggers: intersection(
          physicalOutput.adaptiveTriggers,
          other.physicalOutput.adaptiveTriggers
        )
      )
    )
  }
}

/// The elements of `lhs` that `rhs` also contains, in the order of `lhs`.
private func intersection<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> [Element] {
  lhs.filter(rhs.contains)
}
