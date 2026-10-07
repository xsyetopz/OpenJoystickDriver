import Foundation

/// What became of one output command sent with `DeviceManager.sendControllerOutput`.
///
/// JSON: `{"outcome":"delivered","droppedRumbleChannels":["leftTrigger"]}`. A partially supported
/// `set-rumble` is `delivered` on the channels the controller has and lists the rest in
/// `droppedRumbleChannels`.
public struct ControllerOutputResult: Codable, Equatable, Hashable, Sendable {
  public enum Outcome: String, Codable, CaseIterable, Hashable, Sendable {
    case delivered
    /// No connected controller matches the selector exactly once.
    case notFound
    case unsupportedCapability
    /// The protocol session cannot carry the command yet.
    case notReady
    case invalidValue
    case writeFailed
    /// The controller disconnected or was replaced before the command was written.
    case cancelled

    init(_ error: ControllerOutputError) {
      switch error {
      case .unsupportedCapability: self = .unsupportedCapability
      case .notReady: self = .notReady
      case .invalidValue: self = .invalidValue
      }
    }
  }

  public var outcome: Outcome
  /// The requested rumble channels the controller lacks, which were not driven.
  public var droppedRumbleChannels: [PhysicalRumbleMotor]

  public init(_ outcome: Outcome, droppedRumbleChannels: [PhysicalRumbleMotor] = []) {
    self.outcome = outcome
    self.droppedRumbleChannels = droppedRumbleChannels
  }

  public var isDelivered: Bool { outcome == .delivered }
}

/// JSON: every channel as a `UnipolarValue` number, keyed by its `PhysicalRumbleMotor` name, for
/// example `{"leftMain":65535,"rightMain":0,...}`. A missing channel decodes as off; a key that
/// names no motor fails decoding.
extension RumbleIntensities: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: PhysicalRumbleMotorKey.self)
    if let unknown = container.allKeys.first(where: {
      PhysicalRumbleMotor(rawValue: $0.stringValue) == nil
    }) {
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

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: PhysicalRumbleMotorKey.self)
    for motor in PhysicalRumbleMotor.allCases {
      try container.encode(self[motor], forKey: PhysicalRumbleMotorKey(motor))
    }
  }

  private struct PhysicalRumbleMotorKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ motor: PhysicalRumbleMotor) { stringValue = motor.rawValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }
}

/// JSON: `"held"`, or `{"milliseconds":450}` with milliseconds in `0...5000`
/// (`maxRumbleDurationMs`).
extension RumbleDuration: Codable {
  private enum CodingKeys: String, CodingKey { case milliseconds }
  private static let heldName = "held"

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
/// - `{"type":"set-adaptive-trigger","trigger":"left","effect":{"kind":"resistance",...}}`
extension ControllerOutputCommand: Codable {
  private enum Kind: String, Codable {
    case setRumble = "set-rumble"
    case stopRumble = "stop-rumble"
    case setPlayerIndicator = "set-player-indicator"
    case setRGB = "set-rgb"
    case setLightBrightness = "set-light-brightness"
    case setAdaptiveTrigger = "set-adaptive-trigger"
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case intensities
    case duration
    case player
    case red
    case green
    case blue
    case brightness
    case trigger
    case effect
  }

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
  /// These intensities with the main motors mirrored onto the trackpad haptics, so a Steam
  /// Controller answers a main-motor request.
  public func mirroringMainOntoHaptics() -> Self {
    var mirrored = self
    mirrored.leftHaptic = leftMain
    mirrored.rightHaptic = rightMain
    return mirrored
  }
}
