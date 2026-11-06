import Foundation

/// What became of one output command sent with `DeviceManager.sendControllerOutput`.
///
/// JSON: `{"outcome":"Delivered","droppedRumbleChannels":["LeftTrigger"]}`. A partially supported
/// `set-rumble` is `Delivered` on the channels the controller has and lists the rest in
/// `droppedRumbleChannels`.
public struct ControllerOutputResult: Codable, Equatable, Hashable, Sendable {
  /// The outcome of an output command.
  public enum Outcome: String, Codable, CaseIterable, Hashable, Sendable {
    /// The command was written to the controller.
    case delivered = "Delivered"
    /// No connected controller matches the selector exactly once.
    case notFound = "NotFound"
    /// The controller lacks the capability the command requires.
    case unsupportedCapability = "UnsupportedCapability"
    /// The protocol session cannot carry the command yet.
    case notReady = "NotReady"
    /// The command carries a value the protocol cannot encode.
    case invalidValue = "InvalidValue"
    /// The write to the controller failed.
    case writeFailed = "WriteFailed"
    /// The controller disconnected or was replaced before the command was written.
    case cancelled = "Cancelled"

    /// Maps an encoding error to the outcome that reports it.
    init(_ error: ControllerOutputError) {
      switch error {
      case .unsupportedCapability: self = .unsupportedCapability
      case .notReady: self = .notReady
      case .invalidValue: self = .invalidValue
      }
    }
  }

  /// The outcome of the command.
  public var outcome: Outcome
  /// The requested rumble channels the controller lacks, which were not driven.
  public var droppedRumbleChannels: [PhysicalRumbleMotor]

  /// Creates a result from an outcome and the rumble channels that were not driven.
  public init(_ outcome: Outcome, droppedRumbleChannels: [PhysicalRumbleMotor] = []) {
    self.outcome = outcome
    self.droppedRumbleChannels = droppedRumbleChannels
  }

  /// Whether the command was delivered.
  public var isDelivered: Bool { outcome == .delivered }
}

/// JSON: every channel as a `UnipolarValue` number, keyed by its `PhysicalRumbleMotor` name, for
/// example `{"lowFrequency":65535,"highFrequency":0,...}`. A missing channel decodes as off; a key
/// that names no motor fails decoding.
extension RumbleIntensities: Codable {
  /// Decodes a channel-keyed intensity object; a key that names no motor is rejected and a missing
  /// channel is off.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: PhysicalRumbleMotorKey.self)
    let names = Set(PhysicalRumbleMotor.allCases.map(\.recordKey))
    if let unknown = container.allKeys.first(where: { !names.contains($0.stringValue) }) {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: container.codingPath + [unknown],
          debugDescription: "Unknown rumble motor"
        )
      )
    }
    self = .off
    for motor in PhysicalRumbleMotor.allCases {
      self[motor] =
        try container.decodeIfPresent(UnipolarValue.self, forKey: PhysicalRumbleMotorKey(motor))
        ?? .min
    }
  }

  /// Encodes every channel, keyed by its motor name.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: PhysicalRumbleMotorKey.self)
    for motor in PhysicalRumbleMotor.allCases {
      try container.encode(self[motor], forKey: PhysicalRumbleMotorKey(motor))
    }
  }

  /// A coding key that is a motor's record key.
  private struct PhysicalRumbleMotorKey: CodingKey {
    /// The motor's record key.
    let stringValue: String
    /// Always `nil`, because the keys are strings.
    var intValue: Int? { nil }
    /// Creates the key of a motor.
    init(_ motor: PhysicalRumbleMotor) { stringValue = motor.recordKey }
    /// Creates a key from any string; `init(from:)` rejects names that are no motor.
    init?(stringValue: String) { self.stringValue = stringValue }
    /// Always fails, because the keys are strings.
    init?(intValue: Int) { nil }
  }
}

/// JSON: `"held"`, or `{"milliseconds":450}` with milliseconds in `0...5000`
/// (`maxRumbleDurationMs`).
extension RumbleDuration: Codable {
  /// The JSON key of `milliseconds`.
  private enum CodingKeys: String, CodingKey {
    /// The key of the duration in milliseconds.
    case milliseconds
  }
  /// The JSON string that encodes a held duration.
  private static let heldName = "held"

  /// Decodes `"held"` or a `milliseconds` object; any other string or a value outside
  /// `0...maxRumbleDurationMs` is rejected.
  public init(from decoder: any Decoder) throws {
    if let name = try? decoder.singleValueContainer().decode(String.self) {
      guard name == Self.heldName else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "Unknown rumble duration")
        )
      }
      self = .held
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let milliseconds = try container.decode(Int.self, forKey: .milliseconds)
    guard 0...maxRumbleDurationMs ~= milliseconds else {
      throw DecodingError.dataCorruptedError(
        forKey: .milliseconds,
        in: container,
        debugDescription: "Rumble duration is outside 0...\(maxRumbleDurationMs) ms"
      )
    }
    self = .milliseconds(milliseconds)
  }

  /// Encodes a held duration as `"held"` and a bounded one as a `milliseconds` object.
  public func encode(to encoder: any Encoder) throws {
    switch self {
    case .held:
      var container = encoder.singleValueContainer()
      try container.encode(Self.heldName)
    case .milliseconds(let milliseconds):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(milliseconds, forKey: .milliseconds)
    }
  }
}

/// JSON, discriminated by `type`:
/// - `{"type":"set-rumble","intensities":{...},"duration":"held"|{"milliseconds":450}}`
/// - `{"type":"stop-rumble"}`
/// - `{"type":"set-player-indicator","player":2}` (`0` is off)
/// - `{"type":"set-rgb","red":17,"green":34,"blue":51}`
/// - `{"type":"set-light-brightness","brightness":32896}`
/// - `{"type":"set-adaptive-trigger","trigger":"Left","effect":{"kind":"Resistance",...}}`
extension ControllerOutputCommand: Codable {
  /// The `type` discriminator of a command in JSON.
  private enum Kind: String, Codable {
    /// The `type` of `setRumble`.
    case setRumble = "set-rumble"
    /// The `type` of `stopRumble`.
    case stopRumble = "stop-rumble"
    /// The `type` of `setPlayerIndicator`.
    case setPlayerIndicator = "set-player-indicator"
    /// The `type` of `setRGB`.
    case setRGB = "set-rgb"
    /// The `type` of `setLightBrightness`.
    case setLightBrightness = "set-light-brightness"
    /// The `type` of `setAdaptiveTrigger`.
    case setAdaptiveTrigger = "set-adaptive-trigger"
  }

  /// The JSON keys of a command.
  private enum CodingKeys: String, CodingKey {
    /// The JSON key of the command type.
    case type
    /// The JSON key of `intensities`.
    case intensities
    /// The JSON key of `duration`.
    case duration
    /// The JSON key of `player`.
    case player
    /// The JSON key of the red channel.
    case red
    /// The JSON key of the green channel.
    case green
    /// The JSON key of the blue channel.
    case blue
    /// The JSON key of `brightness`.
    case brightness
    /// The JSON key of `trigger`.
    case trigger
    /// The JSON key of `effect`.
    case effect
  }

  /// Decodes the command named by `type`; an unknown `type` or a missing or invalid payload key is
  /// rejected.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .setRumble:
      self = .setRumble(
        try container.decode(RumbleIntensities.self, forKey: .intensities),
        duration: try container.decode(RumbleDuration.self, forKey: .duration)
      )
    case .stopRumble: self = .stopRumble
    case .setPlayerIndicator:
      self = .setPlayerIndicator(
        try container.decode(PhysicalPlayerIndicator.self, forKey: .player)
      )
    case .setRGB:
      self = .setRGB(
        ControllerColor(
          red: try container.decode(UInt8.self, forKey: .red),
          green: try container.decode(UInt8.self, forKey: .green),
          blue: try container.decode(UInt8.self, forKey: .blue)
        )
      )
    case .setLightBrightness:
      self = .setLightBrightness(try container.decode(UnipolarValue.self, forKey: .brightness))
    case .setAdaptiveTrigger:
      self = .setAdaptiveTrigger(
        try container.decode(PhysicalAdaptiveTrigger.self, forKey: .trigger),
        try container.decode(PhysicalAdaptiveTriggerEffect.self, forKey: .effect)
      )
    }
  }

  /// Encodes the `type` and the payload keys of the command.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .setRumble(let intensities, let duration):
      try container.encode(Kind.setRumble, forKey: .type)
      try container.encode(intensities, forKey: .intensities)
      try container.encode(duration, forKey: .duration)
    case .stopRumble: try container.encode(Kind.stopRumble, forKey: .type)
    case .setPlayerIndicator(let indicator):
      try container.encode(Kind.setPlayerIndicator, forKey: .type)
      try container.encode(indicator, forKey: .player)
    case .setRGB(let color):
      try container.encode(Kind.setRGB, forKey: .type)
      try container.encode(color.red, forKey: .red)
      try container.encode(color.green, forKey: .green)
      try container.encode(color.blue, forKey: .blue)
    case .setLightBrightness(let brightness):
      try container.encode(Kind.setLightBrightness, forKey: .type)
      try container.encode(brightness, forKey: .brightness)
    case .setAdaptiveTrigger(let trigger, let effect):
      try container.encode(Kind.setAdaptiveTrigger, forKey: .type)
      try container.encode(trigger, forKey: .trigger)
      try container.encode(effect, forKey: .effect)
    }
  }
}

extension RumbleIntensities {
  /// These intensities with the low- and high-frequency motors mirrored onto the trackpad
  /// haptics, so a Steam Controller answers a request for either.
  public func mirroringMainOntoHaptics() -> Self {
    var mirrored = self
    mirrored.leftHaptic = lowFrequency
    mirrored.rightHaptic = highFrequency
    return mirrored
  }
}
