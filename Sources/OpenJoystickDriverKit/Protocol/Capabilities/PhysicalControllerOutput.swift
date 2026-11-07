/// A physical rumble actuator that the active protocol implementation can address.
public enum PhysicalRumbleMotor: String, Codable, CaseIterable, Hashable, Sendable {
  /// The low-frequency (heavy) motor.
  case lowFrequency = "LowFrequency"
  /// The high-frequency (light) motor.
  case highFrequency = "HighFrequency"
  /// The motor in the left trigger.
  case leftTrigger = "LeftTrigger"
  /// The motor in the right trigger.
  case rightTrigger = "RightTrigger"
  /// The haptic actuator on the left.
  case leftHaptic = "LeftHaptic"
  /// The haptic actuator on the right.
  case rightHaptic = "RightHaptic"

  /// Lists of motors are in declaration order.
  static func isDeclaredBefore(_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.declarationIndex < rhs.declarationIndex
  }

  /// The position of this motor in `allCases`.
  private var declarationIndex: Int {
    guard let index = Self.allCases.firstIndex(of: self) else {
      preconditionFailure("every case of a CaseIterable enum is in allCases")
    }
    return index
  }

  /// The key that names this motor in controller records, protocol descriptions and endpoint
  /// rumble intensities: the lowerCamelCase form of its actuator name.
  public var recordKey: String { rawValue.prefix(1).lowercased() + rawValue.dropFirst() }
}

/// A physical lighting feature with a source-backed output implementation.
public enum PhysicalLightingFeature: String, Codable, CaseIterable, Hashable, Sendable {
  /// The controller shows which player it is.
  case playerIndicator = "PlayerIndicator"
  /// The controller has a color that the host sets.
  case programmableColor = "ProgrammableColor"
  /// The controller has a brightness that the host sets.
  case programmableBrightness = "ProgrammableBrightness"
}

/// Generic player indicator selection for protocols with numbered controller LEDs.
public enum PhysicalPlayerIndicator: Int, Codable, CaseIterable, Hashable, Sendable {
  /// No player.
  case off = 0
  /// Player 1.
  case player1 = 1
  /// Player 2.
  case player2 = 2
  /// Player 3.
  case player3 = 3
  /// Player 4.
  case player4 = 4
}

/// A trigger that has an adaptive effect.
public enum PhysicalAdaptiveTrigger: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left trigger.
  case left = "Left"
  /// The right trigger.
  case right = "Right"
}

/// The kind of an adaptive trigger effect.
public enum PhysicalAdaptiveTriggerEffectKind: String, Codable, CaseIterable, Hashable, Sendable {
  /// No effect.
  case off = "Off"
  /// A resistance that starts at a position.
  case resistance = "Resistance"
}

/// A bounded DualSense-style trigger effect.
///
/// Positions and strength are normalized to `0...1`.
public struct PhysicalAdaptiveTriggerEffect: Codable, Equatable, Hashable, Sendable {
  /// The kind of the effect.
  public let kind: PhysicalAdaptiveTriggerEffectKind
  /// The normalized trigger position where the effect starts.
  public let startPosition: Double
  /// The normalized strength of the effect.
  public let strength: Double

  /// Creates an effect; `validate()` checks the values.
  public init(
    kind: PhysicalAdaptiveTriggerEffectKind,
    startPosition: Double = 0,
    strength: Double = 0
  ) {
    self.kind = kind
    self.startPosition = startPosition
    self.strength = strength
  }

  /// The effect that switches an adaptive trigger off.
  public static let off = Self(kind: .off)

  /// Checks that the position and the strength are finite values in `0...1`, and that the off
  /// effect has both at zero.
  public func validate() throws {
    guard startPosition.isFinite, (0...1).contains(startPosition), strength.isFinite,
      (0...1).contains(strength)
    else { throw PhysicalAdaptiveTriggerEffectError.invalidValue }
    if kind == .off, startPosition != 0 || strength != 0 {
      throw PhysicalAdaptiveTriggerEffectError.invalidValue
    }
  }

  /// The keys of an effect.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The key of the effect kind.
    case kind
    /// The key of the start position.
    case startPosition
    /// The key of the strength.
    case strength
  }

  /// Decodes an effect with all three keys; an unknown key or a missing key is rejected.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    kind = try values.decode(PhysicalAdaptiveTriggerEffectKind.self, forKey: .kind)
    startPosition = try values.decode(Double.self, forKey: .startPosition)
    strength = try values.decode(Double.self, forKey: .strength)
  }
}

/// The failure of an adaptive trigger effect.
public enum PhysicalAdaptiveTriggerEffectError: Error, Equatable, Sendable {
  /// A position or a strength is out of range or not finite, or an off effect has a nonzero value.
  case invalidValue
}

/// The audio format a controller's speaker takes.
public enum PhysicalSpeakerFormat: String, Codable, CaseIterable, Hashable, Sendable {
  /// 4-bit Yamaha ADPCM at the rate of the remote's speaker, which the Wii Remote has.
  case yamahaADPCM4Bit = "YamahaADPCM4Bit"

  /// The samples per second the speaker plays; `nintendo-wii.json` writes the same rate as the
  /// divisor of its speaker configuration, and a test keeps the two equal.
  public var sampleRate: Int {
    switch self {
    case .yamahaADPCM4Bit: 6_000
    }
  }
}

/// Physical output capabilities implemented by the active controller protocol.
public struct PhysicalControllerOutputCapabilities: Codable, Equatable, Hashable, Sendable {
  /// The motors that can rumble, in declaration order.
  public let rumbleMotors: [PhysicalRumbleMotor]
  /// The lighting features of the controller, sorted by name.
  public let lightingFeatures: [PhysicalLightingFeature]
  /// Motors whose hardware accepts only off/on rather than variable intensity.
  public let binaryRumbleMotors: [PhysicalRumbleMotor]
  /// The adaptive triggers, sorted by name.
  public let adaptiveTriggers: [PhysicalAdaptiveTrigger]
  /// The format of the controller's speaker; nil when it has none.
  public let speaker: PhysicalSpeakerFormat?
  /// Creates capabilities; each list drops duplicates, and a binary motor that is not a rumble
  /// motor is dropped.
  public init(
    rumbleMotors: [PhysicalRumbleMotor] = [],
    lightingFeatures: [PhysicalLightingFeature] = [],
    binaryRumbleMotors: [PhysicalRumbleMotor] = [],
    adaptiveTriggers: [PhysicalAdaptiveTrigger] = [],
    speaker: PhysicalSpeakerFormat? = nil
  ) {
    self.rumbleMotors = Set(rumbleMotors).sorted(by: PhysicalRumbleMotor.isDeclaredBefore)
    self.lightingFeatures = Array(Set(lightingFeatures)).sorted { $0.rawValue < $1.rawValue }
    let supportedMotors = Set(self.rumbleMotors)
    self.binaryRumbleMotors = Array(Set(binaryRumbleMotors).intersection(supportedMotors))
      .sorted(by: PhysicalRumbleMotor.isDeclaredBefore)
    self.adaptiveTriggers = Array(Set(adaptiveTriggers)).sorted { $0.rawValue < $1.rawValue }
    self.speaker = speaker
  }

  /// Capabilities with no output.
  public static let none = Self()
  /// Capabilities with the low-frequency and the high-frequency motor.
  public static let dualMainRumble = Self(rumbleMotors: [.lowFrequency, .highFrequency])

  /// Whether any motor can rumble.
  public var supportsRumble: Bool { !rumbleMotors.isEmpty }
  /// Whether a trigger motor can rumble.
  public var supportsTriggerRumble: Bool {
    rumbleMotors.contains(.leftTrigger) || rumbleMotors.contains(.rightTrigger)
  }
  /// Whether the controller has a player indicator.
  public var supportsPlayerIndicator: Bool { lightingFeatures.contains(.playerIndicator) }
  /// Whether the controller has a programmable brightness.
  public var supportsProgrammableBrightness: Bool {
    lightingFeatures.contains(.programmableBrightness)
  }
  /// Whether the controller has an adaptive trigger.
  public var supportsAdaptiveTriggers: Bool { !adaptiveTriggers.isEmpty }
  /// Whether the controller has a speaker.
  public var supportsSpeaker: Bool { speaker != nil }

  /// The keys of the capabilities.
  private enum CodingKeys: String, CodingKey {
    /// The key of the rumble motors.
    case rumbleMotors
    /// The key of the lighting features.
    case lightingFeatures
    /// The key of the binary rumble motors.
    case binaryRumbleMotors
    /// The key of the adaptive triggers.
    case adaptiveTriggers
    /// The key of the speaker format.
    case speaker
  }

  /// Decodes capabilities; a list that is absent decodes as empty and an absent speaker as none.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      rumbleMotors: try values.decodeIfPresent([PhysicalRumbleMotor].self, forKey: .rumbleMotors)
        ?? [],
      lightingFeatures: try values.decodeIfPresent(
        [PhysicalLightingFeature].self,
        forKey: .lightingFeatures
      ) ?? [],
      binaryRumbleMotors: try values.decodeIfPresent(
        [PhysicalRumbleMotor].self,
        forKey: .binaryRumbleMotors
      ) ?? [],
      adaptiveTriggers: try values.decodeIfPresent(
        [PhysicalAdaptiveTrigger].self,
        forKey: .adaptiveTriggers
      ) ?? [],
      speaker: try values.decodeIfPresent(PhysicalSpeakerFormat.self, forKey: .speaker)
    )
  }
}

/// A raw HID feature-report read request sent through IOKit.
public struct PhysicalHIDFeatureReadRequest: Equatable, Sendable {
  /// The report ID of the feature report.
  public let reportID: UInt8
  /// The length of the read in bytes.
  public let length: Int

  /// Creates a request for a feature report.
  public init(reportID: UInt8, length: Int) {
    self.reportID = reportID
    self.length = length
  }
}

/// A raw HID output report that can be sent through IOKit.
public struct PhysicalHIDOutputReport: Equatable, Sendable {
  /// The report ID of the output report.
  public let reportID: UInt8
  /// The bytes of the report.
  public let bytes: [UInt8]
  /// The wait a startup description asks for before this report, replacing the startup
  /// interval; nil keeps the interval.
  public let startupDelayMilliseconds: Int?

  /// Creates a report with an optional startup delay.
  public init(reportID: UInt8, bytes: [UInt8], startupDelayMilliseconds: Int? = nil) {
    self.reportID = reportID
    self.bytes = bytes
    self.startupDelayMilliseconds = startupDelayMilliseconds
  }
}

/// A raw USB interrupt OUT packet.
public struct PhysicalUSBOutputPacket: Equatable, Sendable {
  /// The OUT endpoint.
  public let endpoint: UInt8
  /// The bytes of the packet.
  public let bytes: [UInt8]
  /// The transfer timeout in milliseconds.
  public let timeoutMilliseconds: UInt32
  /// The wait a startup description asks for before this packet, replacing the startup
  /// interval; nil keeps the interval.
  public let startupDelayMilliseconds: Int?

  /// Creates a packet with an optional startup delay.
  public init(
    endpoint: UInt8,
    bytes: [UInt8],
    timeoutMilliseconds: UInt32,
    startupDelayMilliseconds: Int? = nil
  ) {
    self.endpoint = endpoint
    self.bytes = bytes
    self.timeoutMilliseconds = timeoutMilliseconds
    self.startupDelayMilliseconds = startupDelayMilliseconds
  }
}

/// One write a driver asks its pipeline to perform; each write names its own destination.
public enum PhysicalOutputWrite: Equatable, Sendable {
  /// An interrupt OUT packet. A tolerated rejection (I/O error, timeout, missing or unsupported
  /// endpoint) is logged and does not fail the lifecycle step that produced the write.
  case usb(PhysicalUSBOutputPacket, toleratesRejection: Bool = false)
  /// A HID output report on the bound HID device.
  case hidOutput(PhysicalHIDOutputReport)
  /// A HID feature report on the bound HID device.
  case hidFeature(PhysicalHIDOutputReport)

  /// The wait before this write that a startup description asks for; nil keeps the interval.
  public var startupDelayMilliseconds: Int? {
    switch self {
    case .usb(let packet, _): packet.startupDelayMilliseconds
    case .hidOutput(let report), .hidFeature(let report): report.startupDelayMilliseconds
    }
  }
}

/// Writes that carry one physical output command, sent in order at `intervalNanoseconds`
/// spacing; each write names its own destination.
public struct PhysicalOutputPlan: Equatable, Sendable {
  /// The writes, in the order they are sent.
  public let writes: [PhysicalOutputWrite]
  /// The spacing between the writes in nanoseconds.
  public let intervalNanoseconds: UInt64

  /// Creates a plan; the writes are spaced by `intervalNanoseconds`.
  public init(writes: [PhysicalOutputWrite], intervalNanoseconds: UInt64 = 0) {
    self.writes = writes
    self.intervalNanoseconds = intervalNanoseconds
  }
}
