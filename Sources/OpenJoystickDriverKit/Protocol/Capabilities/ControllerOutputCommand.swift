/// Intensity for every rumble channel a `set-rumble` command can name; `.min` is off.
public struct RumbleIntensities: Equatable, Hashable, Sendable {
  public var leftMain: UnipolarValue
  public var rightMain: UnipolarValue
  public var leftTrigger: UnipolarValue
  public var rightTrigger: UnipolarValue
  /// Steam Controller trackpad haptics.
  public var leftHaptic: UnipolarValue
  public var rightHaptic: UnipolarValue

  public init(
    leftMain: UnipolarValue = .min,
    rightMain: UnipolarValue = .min,
    leftTrigger: UnipolarValue = .min,
    rightTrigger: UnipolarValue = .min,
    leftHaptic: UnipolarValue = .min,
    rightHaptic: UnipolarValue = .min
  ) {
    self.leftMain = leftMain
    self.rightMain = rightMain
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.leftHaptic = leftHaptic
    self.rightHaptic = rightHaptic
  }

  public static let off = Self()

  public subscript(motor: PhysicalRumbleMotor) -> UnipolarValue {
    get {
      switch motor {
      case .leftMain: leftMain
      case .rightMain: rightMain
      case .leftTrigger: leftTrigger
      case .rightTrigger: rightTrigger
      case .leftHaptic: leftHaptic
      case .rightHaptic: rightHaptic
      }
    }
    set {
      switch motor {
      case .leftMain: leftMain = newValue
      case .rightMain: rightMain = newValue
      case .leftTrigger: leftTrigger = newValue
      case .rightTrigger: rightTrigger = newValue
      case .leftHaptic: leftHaptic = newValue
      case .rightHaptic: rightHaptic = newValue
      }
    }
  }

  /// Channels with a nonzero intensity, in declaration order.
  public var activeMotors: [PhysicalRumbleMotor] {
    PhysicalRumbleMotor.allCases.filter { self[$0] != .min }
  }

  /// The intensities of a manual rumble test: each named channel at its byte, and both main
  /// motors at 180 when no channel is named.
  public static func manualTest(
    leftMain: UInt8?,
    rightMain: UInt8?,
    leftTrigger: UInt8?,
    rightTrigger: UInt8?
  ) -> Self {
    let noneGiven = [leftMain, rightMain, leftTrigger, rightTrigger].allSatisfy { $0 == nil }
    let fallback: UInt8 = noneGiven ? 180 : 0
    return Self(
      leftMain: UnipolarValue(byte: leftMain ?? fallback),
      rightMain: UnipolarValue(byte: rightMain ?? fallback),
      leftTrigger: UnipolarValue(byte: leftTrigger ?? 0),
      rightTrigger: UnipolarValue(byte: rightTrigger ?? 0)
    )
  }
}

/// How long a `set-rumble` command runs: a bounded number of milliseconds, or until the next
/// rumble command.
public enum RumbleDuration: Equatable, Hashable, Sendable {
  case milliseconds(Int)
  case held

  /// The duration of a manual rumble test that names none.
  public static let manualTestSeconds = 0.45
  /// The longest bounded duration, `maxRumbleDurationMs`, in seconds.
  public static let maximumSeconds = Double(maxRumbleDurationMs) / 1_000
}

/// One normalized physical output command.
public enum ControllerOutputCommand: Equatable, Hashable, Sendable {
  case setRumble(RumbleIntensities, duration: RumbleDuration)
  case stopRumble
  case setPlayerIndicator(PhysicalPlayerIndicator)
  case setRGB(ControllerColor)
  case setLightBrightness(UnipolarValue)
  case setAdaptiveTrigger(PhysicalAdaptiveTrigger, PhysicalAdaptiveTriggerEffect)

  /// The capability a controller needs to carry out this command; a rumble command names its
  /// first active channel, or the left main motor when none is active.
  public var capability: ControllerOutputCapability {
    switch self {
    case .setRumble(let intensities, _): .rumble(intensities.activeMotors.first ?? .leftMain)
    case .stopRumble: .rumble(.leftMain)
    case .setPlayerIndicator: .playerIndicator
    case .setRGB: .rgb
    case .setLightBrightness: .lightBrightness
    case .setAdaptiveTrigger(let trigger, _): .adaptiveTrigger(trigger)
    }
  }
}

/// A physical output capability an output command can require.
public enum ControllerOutputCapability: Equatable, Hashable, Sendable {
  case rumble(PhysicalRumbleMotor)
  case playerIndicator
  case rgb
  case lightBrightness
  case adaptiveTrigger(PhysicalAdaptiveTrigger)
}

/// Why a controller did not accept or encode an output command.
public enum ControllerOutputError: Error, Equatable, Hashable, Sendable {
  case unsupportedCapability(ControllerOutputCapability)
  /// The protocol session cannot carry the command yet.
  case notReady
  case invalidValue
}

extension PhysicalControllerOutputCapabilities {
  /// The command this controller can carry, with the rumble channels it lacks set to zero, and
  /// those channels. A rumble command is unsupported only when the controller has no rumble motor.
  public func admit(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> (
    command: ControllerOutputCommand, droppedRumbleChannels: [PhysicalRumbleMotor]
  ) {
    let supported: Bool
    switch command {
    case .setRumble(var intensities, let duration):
      guard supportsRumble else { throw .unsupportedCapability(command.capability) }
      let dropped = intensities.activeMotors.filter { !rumbleMotors.contains($0) }
      for motor in dropped { intensities[motor] = .min }
      return (.setRumble(intensities, duration: duration), dropped)
    case .stopRumble: supported = supportsRumble
    case .setPlayerIndicator: supported = supportsPlayerIndicator
    case .setRGB: supported = lightingFeatures.contains(.programmableColor)
    case .setLightBrightness: supported = supportsProgrammableBrightness
    case .setAdaptiveTrigger(let trigger, _): supported = adaptiveTriggers.contains(trigger)
    }
    guard supported else { throw .unsupportedCapability(command.capability) }
    return (command, [])
  }
}

extension UnipolarValue {
  /// The value a protocol byte `0...255` spans; `byte` converts it back exactly.
  public init(byte: UInt8) { self.init(UInt16(byte) * 257) }

  /// The nearest protocol byte `0...255`.
  public var byte: UInt8 { UInt8((Double(rawValue) * 255 / 65_535).rounded()) }

  /// Converts a saved-profile intensity in `0...1`, clamping values outside that range.
  public init(unitInterval: Double) {
    self.init(UInt16((Swift.min(Swift.max(unitInterval, 0), 1) * Double(UInt16.max)).rounded()))
  }

  /// This value as a saved-profile intensity in `0...1`.
  public var unitInterval: Double { Double(rawValue) / Double(UInt16.max) }
}
