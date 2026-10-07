import Foundation

/// An unsigned control value; `0` is released/minimum and `65535` is fully actuated.
public struct UnipolarValue: Hashable, Codable, Sendable {
  public static let min = Self(0)
  public static let max = Self(UInt16.max)

  public let rawValue: UInt16

  public init(_ rawValue: UInt16) { self.rawValue = rawValue }

  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(UInt16.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A signed control value centered on `0`, with symmetric magnitude `-32767...32767`.
public struct BipolarValue: Hashable, Codable, Sendable {
  public static let min = Self(-Int16.max)
  public static let center = Self(0)
  public static let max = Self(Int16.max)

  public let rawValue: Int16

  /// Clamps a raw `-32768` to `-32767` so both directions have the same magnitude.
  public init(_ rawValue: Int16) { self.rawValue = Swift.max(rawValue, -Int16.max) }

  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(Int16.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Nanoseconds from one process-local monotonic clock.
public struct MonotonicTimestamp: Hashable, Comparable, Codable, Sendable {
  public let nanoseconds: UInt64

  public init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
}

/// Standard semantic control identifiers. Physical labels never rename these IDs.
public enum ControlID: String, CaseIterable, Codable, Sendable {
  case dpad
  case leftStickX = "left-stick-x"
  case leftStickY = "left-stick-y"
  case rightStickX = "right-stick-x"
  case rightStickY = "right-stick-y"
  case leftStickClick = "left-stick-click"
  case rightStickClick = "right-stick-click"
  case faceSouth = "face-south"
  case faceEast = "face-east"
  case faceWest = "face-west"
  case faceNorth = "face-north"
  case leftShoulder = "left-shoulder"
  case rightShoulder = "right-shoulder"
  case leftTrigger = "left-trigger"
  case rightTrigger = "right-trigger"
  case leftTriggerButton = "left-trigger-button"
  case rightTriggerButton = "right-trigger-button"
  case view
  case menu
  case guide
  case share
  case capture
  case touchpadClick = "touchpad-click"
  case microphone
  case paddleLeft1 = "paddle-left-1"
  case paddleLeft2 = "paddle-left-2"
  case paddleRight1 = "paddle-right-1"
  case paddleRight2 = "paddle-right-2"
  case auxiliary1 = "auxiliary-1"
  case auxiliary2 = "auxiliary-2"
  case auxiliary3 = "auxiliary-3"
  case auxiliary4 = "auxiliary-4"
  case auxiliary5 = "auxiliary-5"
  case auxiliary6 = "auxiliary-6"
  case auxiliary7 = "auxiliary-7"
  case auxiliary8 = "auxiliary-8"
  case leftStickTouch = "left-stick-touch"
  case rightStickTouch = "right-stick-touch"
  case leftTrackpadClick = "left-trackpad-click"
  case rightTrackpadClick = "right-trackpad-click"
  case leftTrackpadTouch = "left-trackpad-touch"
  case rightTrackpadTouch = "right-trackpad-touch"

  /// Controls of the standard Xbox layout, excluding `guide`.
  public static let xboxLayout: Set<ControlID> = [
    .dpad, .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftStickClick, .rightStickClick,
    .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .leftTrigger,
    .rightTrigger, .view, .menu,
  ]
}

/// One of eight compass directions, or neutral (center) for a hat or D-pad.
public enum HatDirection: String, Codable, Sendable {
  case neutral
  case north
  case northEast
  case east
  case southEast
  case south
  case southWest
  case west
  case northWest
}

/// Battery charge at the precision the device reports, never a synthesized midpoint.
public struct BatteryLevel: Codable, Hashable, Sendable {
  public static let unknown = Self(percentage: nil)

  /// Charge within `0...100`: one value for an exact reading, the device's bucket otherwise, and
  /// `nil` when the device reports no level.
  public let percentage: ClosedRange<UInt8>?

  public init(percentage: ClosedRange<UInt8>?) {
    precondition(percentage.map { $0.upperBound <= 100 } ?? true, "Battery charge exceeds 100%")
    self.percentage = percentage
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let percentage = try container.decodeIfPresent(ClosedRange<UInt8>.self, forKey: .percentage)
    guard percentage.map({ $0.upperBound <= 100 }) ?? true else {
      throw DecodingError.dataCorruptedError(
        forKey: .percentage,
        in: container,
        debugDescription: "Battery charge exceeds 100%"
      )
    }
    self.percentage = percentage
  }

  /// Locale-independent ASCII charge, `73%` or `0-9%`; `nil` when unknown.
  public var percentageText: String? {
    guard let percentage else { return nil }
    if percentage.lowerBound == percentage.upperBound { return "\(percentage.lowerBound)%" }
    return "\(percentage.lowerBound)-\(percentage.upperBound)%"
  }
}

/// Link and power state of one logical controller.
public struct ControllerConnectionState: Codable, Equatable, Sendable {
  public enum Charging: String, Codable, Sendable {
    case unknown
    case discharging
    case charging
    case full
    case notChargeable
  }

  /// Power facts a driver decodes from its own reports.
  public struct Power: Codable, Equatable, Sendable {
    public static let unknown = Self(charging: .unknown, battery: .unknown, wiredPower: nil)

    public let charging: Charging
    public let battery: BatteryLevel
    /// Whether wired power is available; `nil` when the device does not report it.
    public let wiredPower: Bool?

    public init(charging: Charging, battery: BatteryLevel, wiredPower: Bool?) {
      self.charging = charging
      self.battery = battery
      self.wiredPower = wiredPower
    }
  }

  /// Controller-side link; `nil` without evidence. Wireless is never inferred from absent USB.
  public let transport: PhysicalTransport?
  public let backend: DeviceAccessBackend
  /// Whether the controller is linked; a `proprietary-radio-receiver` slot can be empty.
  public let isConnected: Bool
  public let power: Power

  public init(
    transport: PhysicalTransport?,
    backend: DeviceAccessBackend,
    isConnected: Bool,
    power: Power
  ) {
    self.transport = transport
    self.backend = backend
    self.isConnected = isConnected
    self.power = power
  }
}
