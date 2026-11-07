/// Intensity for every rumble channel a `set-rumble` command can name; `.min` is off.
public struct RumbleIntensities: Equatable, Hashable, Sendable {
  /// Intensity of the low-frequency (main) motor.
  public var lowFrequency: UnipolarValue
  /// Intensity of the high-frequency (main) motor.
  public var highFrequency: UnipolarValue
  /// Intensity of the left trigger motor.
  public var leftTrigger: UnipolarValue
  /// Intensity of the right trigger motor.
  public var rightTrigger: UnipolarValue
  /// Steam Controller trackpad haptics.
  public var leftHaptic: UnipolarValue
  /// Intensity of the right trackpad haptic.
  public var rightHaptic: UnipolarValue

  /// Creates intensities; every channel not given is off.
  public init(
    lowFrequency: UnipolarValue = .min,
    highFrequency: UnipolarValue = .min,
    leftTrigger: UnipolarValue = .min,
    rightTrigger: UnipolarValue = .min,
    leftHaptic: UnipolarValue = .min,
    rightHaptic: UnipolarValue = .min
  ) {
    self.lowFrequency = lowFrequency
    self.highFrequency = highFrequency
    self.leftTrigger = leftTrigger
    self.rightTrigger = rightTrigger
    self.leftHaptic = leftHaptic
    self.rightHaptic = rightHaptic
  }

  /// Intensities with every channel off.
  public static let off = Self()

  /// The intensity of one rumble channel.
  public subscript(motor: PhysicalRumbleMotor) -> UnipolarValue {
    get {
      switch motor {
      case .lowFrequency: lowFrequency
      case .highFrequency: highFrequency
      case .leftTrigger: leftTrigger
      case .rightTrigger: rightTrigger
      case .leftHaptic: leftHaptic
      case .rightHaptic: rightHaptic
      }
    }
    set {
      switch motor {
      case .lowFrequency: lowFrequency = newValue
      case .highFrequency: highFrequency = newValue
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
    lowFrequency: UInt8?,
    highFrequency: UInt8?,
    leftTrigger: UInt8?,
    rightTrigger: UInt8?
  ) -> Self {
    let noneGiven = [lowFrequency, highFrequency, leftTrigger, rightTrigger].allSatisfy {
      $0 == nil
    }
    let fallback: UInt8 = noneGiven ? 180 : 0
    return Self(
      lowFrequency: UnipolarValue(byte: lowFrequency ?? fallback),
      highFrequency: UnipolarValue(byte: highFrequency ?? fallback),
      leftTrigger: UnipolarValue(byte: leftTrigger ?? 0),
      rightTrigger: UnipolarValue(byte: rightTrigger ?? 0)
    )
  }
}

/// How long a `set-rumble` command runs: a bounded number of milliseconds, or until the next
/// rumble command.
public enum RumbleDuration: Equatable, Hashable, Sendable {
  /// The command runs for the given number of milliseconds.
  case milliseconds(Int)
  /// The command runs until the next rumble command.
  case held

  /// The duration of a manual rumble test that names none.
  public static let manualTestSeconds = 0.45
  /// The longest bounded duration, `maxRumbleDurationMs`, in seconds.
  public static let maximumSeconds = Double(maxRumbleDurationMs) / 1_000
}

/// One step of speaker playback.
public enum SpeakerOutput: Equatable, Hashable, Sendable {
  /// Sets the speaker up and unmutes it for audio of `seconds`; a controller refuses a longer
  /// clip than its `speakerMaxSeconds`.
  case start(seconds: Double)
  /// Plays encoded audio bytes of the speaker's format; one packet holds at most 20.
  case data([UInt8])
  /// Mutes and disables the speaker.
  case stop
}

/// One normalized physical output command.
public enum ControllerOutputCommand: Equatable, Hashable, Sendable {
  /// Drives the rumble channels at the given intensities for the given duration.
  case setRumble(RumbleIntensities, duration: RumbleDuration)
  /// Stops all rumble.
  case stopRumble
  /// Selects the player indicator the controller shows.
  case setPlayerIndicator(PhysicalPlayerIndicator)
  /// Sets the controller light to a colour.
  case setRGB(ControllerColor)
  /// Sets the brightness of the controller light.
  case setLightBrightness(UnipolarValue)
  /// Applies an effect to one adaptive trigger.
  case setAdaptiveTrigger(PhysicalAdaptiveTrigger, PhysicalAdaptiveTriggerEffect)
  /// Plays audio on the controller's speaker.
  case speaker(SpeakerOutput)

  /// The capability a controller needs to carry out this command; a rumble command names its
  /// first active channel, or the low-frequency motor when none is active.
  public var capability: ControllerOutputCapability {
    switch self {
    case .setRumble(let intensities, _): .rumble(intensities.activeMotors.first ?? .lowFrequency)
    case .stopRumble: .rumble(.lowFrequency)
    case .setPlayerIndicator: .playerIndicator
    case .setRGB: .rgb
    case .setLightBrightness: .lightBrightness
    case .setAdaptiveTrigger(let trigger, _): .adaptiveTrigger(trigger)
    case .speaker: .speaker
    }
  }
}

/// A physical output capability an output command can require.
public enum ControllerOutputCapability: Equatable, Hashable, Sendable {
  /// Rumble on the given channel.
  case rumble(PhysicalRumbleMotor)
  /// The player indicator.
  case playerIndicator
  /// The programmable light colour.
  case rgb
  /// The programmable light brightness.
  case lightBrightness
  /// The given adaptive trigger.
  case adaptiveTrigger(PhysicalAdaptiveTrigger)
  /// The speaker.
  case speaker
}

/// Why a controller did not accept or encode an output command.
public enum ControllerOutputError: Error, Equatable, Hashable, Sendable {
  /// The controller lacks the capability the command requires.
  case unsupportedCapability(ControllerOutputCapability)
  /// The protocol session cannot carry the command yet.
  case notReady
  /// The command carries a value the protocol cannot encode.
  case invalidValue
}

extension PhysicalControllerOutputCapabilities {
  /// The command this controller can carry, with the rumble channels it lacks set to zero, and
  /// those channels.
  ///
  /// A rumble command is unsupported only when the controller has no rumble motor.
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
    case .speaker: supported = supportsSpeaker
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
