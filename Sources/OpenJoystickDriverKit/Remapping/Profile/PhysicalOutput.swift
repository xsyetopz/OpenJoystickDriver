import Foundation

/// A physical-controller channel value owned by one remapping action while that action is active.
public enum RemappingPhysicalOutput: Codable, Equatable, Hashable, Sendable {
  case rumble(motor: PhysicalRumbleMotor, intensity: Double)
  case playerIndicator(PhysicalPlayerIndicator)
  case color(red: UInt8, green: UInt8, blue: UInt8)
  case brightness(Double)
  case adaptiveTrigger(PhysicalAdaptiveTrigger, PhysicalAdaptiveTriggerEffect)

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

  private enum Kind: String, Codable {
    case rumble
    case playerIndicator = "player_indicator"
    case color
    case brightness
    case adaptiveTrigger = "adaptive_trigger"
  }

  private enum CodingKeys: String, CodingKey {
    case type, motor, intensity, indicator, red, green, blue, trigger, effect
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    switch try values.decode(Kind.self, forKey: .type) {
    case .rumble:
      self = .rumble(
        motor: try values.decode(PhysicalRumbleMotor.self, forKey: .motor),
        intensity: try values.decode(Double.self, forKey: .intensity)
      )
    case .playerIndicator:
      self = .playerIndicator(
        try values.decode(PhysicalPlayerIndicator.self, forKey: .indicator)
      )
    case .color:
      self = .color(
        red: try values.decode(UInt8.self, forKey: .red),
        green: try values.decode(UInt8.self, forKey: .green),
        blue: try values.decode(UInt8.self, forKey: .blue)
      )
    case .brightness:
      self = .brightness(try values.decode(Double.self, forKey: .intensity))
    case .adaptiveTrigger:
      self = .adaptiveTrigger(
        try values.decode(PhysicalAdaptiveTrigger.self, forKey: .trigger),
        try values.decode(PhysicalAdaptiveTriggerEffect.self, forKey: .effect)
      )
    }
    try validate()
  }

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
    case .color(let red, let green, let blue):
      try values.encode(Kind.color, forKey: .type)
      try values.encode(red, forKey: .red)
      try values.encode(green, forKey: .green)
      try values.encode(blue, forKey: .blue)
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

public enum RemappingPhysicalOutputError: Error, Equatable, Sendable {
  case invalidValue
}
