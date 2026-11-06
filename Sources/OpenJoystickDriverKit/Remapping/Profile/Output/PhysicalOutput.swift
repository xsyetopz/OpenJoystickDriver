import Foundation

/// A physical-controller channel value owned by one remapping action while that action is active.
public enum RemappingPhysicalOutput: Codable, Equatable, Hashable, Sendable {
  /// Runs one rumble motor at an intensity from 0 to 1.
  case rumble(motor: PhysicalRumbleMotor, intensity: Double)
  /// Lights a player indicator of the controller.
  case playerIndicator(PhysicalPlayerIndicator)
  /// Sets the controller light color.
  case color(ControllerColor)
  /// Sets the controller light brightness from 0 to 1.
  case brightness(Double)
  /// Applies an effect to one adaptive trigger.
  case adaptiveTrigger(PhysicalAdaptiveTrigger, PhysicalAdaptiveTriggerEffect)

  /// Checks that the intensity or brightness is finite and within 0 to 1 and that the adaptive
  /// trigger effect is valid.
  /// - Throws: ``RemappingPhysicalOutputError/invalidValue``.
  public func validate() throws {
    switch self {
    case .rumble(_, let intensity), .brightness(let intensity):
      guard intensity.isFinite, (0...1).contains(intensity) else {
        throw RemappingPhysicalOutputError.invalidValue
      }
    case .adaptiveTrigger(_, let effect):
      do { try effect.validate() } catch { throw RemappingPhysicalOutputError.invalidValue }
    case .playerIndicator, .color: break
    }
  }

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    /// The `Rumble` case.
    case rumble = "Rumble"
    /// The `PlayerIndicator` case.
    case playerIndicator = "PlayerIndicator"
    /// The `Color` case.
    case color = "Color"
    /// The `Brightness` case.
    case brightness = "Brightness"
    /// The `AdaptiveTrigger` case.
    case adaptiveTrigger = "AdaptiveTrigger"

    /// Keys that a profile document may give for this case, which `type` selects.
    var fields: [CodingKeys] {
      switch self {
      case .rumble: [.type, .motor, .intensity]
      case .playerIndicator: [.type, .indicator]
      case .color: [.type, .red, .green, .blue]
      case .brightness: [.type, .intensity]
      case .adaptiveTrigger: [.type, .trigger, .effect]
      }
    }
  }

  /// Profile document keys of a physical output, merged across all cases.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `type`.
    case type
    /// The JSON key of `motor`.
    case motor
    /// The JSON key of `intensity`.
    case intensity
    /// The JSON key of `indicator`.
    case indicator
    /// The JSON key of `red`.
    case red
    /// The JSON key of `green`.
    case green
    /// The JSON key of `blue`.
    case blue
    /// The JSON key of `trigger`.
    case trigger
    /// The JSON key of `effect`.
    case effect
  }

  /// Decodes a physical output from a profile document.
  ///
  /// The `type` field selects the case, and keys that belong to another case are rejected.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value, or
  ///   ``RemappingPhysicalOutputError/invalidValue``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(Kind.self, forKey: .type)
    try values.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .rumble:
      self = .rumble(
        motor: try values.decode(PhysicalRumbleMotor.self, forKey: .motor),
        intensity: try values.decode(Double.self, forKey: .intensity)
      )
    case .playerIndicator:
      self = .playerIndicator(try values.decode(PhysicalPlayerIndicator.self, forKey: .indicator))
    case .color:
      self = .color(
        ControllerColor(
          red: try values.decode(UInt8.self, forKey: .red),
          green: try values.decode(UInt8.self, forKey: .green),
          blue: try values.decode(UInt8.self, forKey: .blue)
        )
      )
    case .brightness: self = .brightness(try values.decode(Double.self, forKey: .intensity))
    case .adaptiveTrigger:
      self = .adaptiveTrigger(
        try values.decode(PhysicalAdaptiveTrigger.self, forKey: .trigger),
        try values.decode(PhysicalAdaptiveTriggerEffect.self, forKey: .effect)
      )
    }
    try validate()
  }

  /// Encodes the case under its `type` value with only its own keys.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .rumble(let motor, let intensity):
      try values.encode(Kind.rumble, forKey: .type)
      try values.encode(motor, forKey: .motor)
      try values.encode(intensity, forKey: .intensity)
    case .playerIndicator(let indicator):
      try values.encode(Kind.playerIndicator, forKey: .type)
      try values.encode(indicator, forKey: .indicator)
    case .color(let color):
      try values.encode(Kind.color, forKey: .type)
      try values.encode(color.red, forKey: .red)
      try values.encode(color.green, forKey: .green)
      try values.encode(color.blue, forKey: .blue)
    case .brightness(let intensity):
      try values.encode(Kind.brightness, forKey: .type)
      try values.encode(intensity, forKey: .intensity)
    case .adaptiveTrigger(let trigger, let effect):
      try values.encode(Kind.adaptiveTrigger, forKey: .type)
      try values.encode(trigger, forKey: .trigger)
      try values.encode(effect, forKey: .effect)
    }
  }
}

/// Error for an invalid physical output.
public enum RemappingPhysicalOutputError: Error, Equatable, Sendable {
  /// An intensity is not finite or is outside 0 to 1, or an adaptive trigger effect is invalid.
  case invalidValue
}
