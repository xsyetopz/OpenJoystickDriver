import Foundation

/// An unsigned control value, such as a trigger; `0` is released or minimum and `65535` is fully
/// actuated.
public struct UnipolarValue: Hashable, Codable, Sendable {
  /// The released, minimum value, `0`.
  public static let min = Self(0)
  /// The fully actuated, maximum value, `65535`.
  public static let max = Self(UInt16.max)

  /// The value from `0` to `65535`.
  public let rawValue: UInt16

  /// Creates a value from its raw representation.
  public init(_ rawValue: UInt16) { self.rawValue = rawValue }

  /// Decodes an unsigned control value from a single `UInt16`.
  ///
  /// - Throws: `DecodingError` when the stored value is not a `UInt16`.
  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(UInt16.self))
  }

  /// Encodes the raw value as a single `UInt16`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A signed control value, such as a stick axis, centered on `0` with the symmetric magnitude
/// `-32767...32767`.
public struct BipolarValue: Hashable, Codable, Sendable {
  /// The lowest value, `-32767`.
  public static let min = Self(-Int16.max)
  /// The centered value, `0`.
  public static let center = Self(0)
  /// The highest value, `32767`.
  public static let max = Self(Int16.max)

  /// The value from `-32767` to `32767`.
  public let rawValue: Int16

  /// Creates a value from `rawValue`, clamping `-32768` to `-32767` so both directions have the
  /// same magnitude.
  public init(_ rawValue: Int16) { self.rawValue = Swift.max(rawValue, -Int16.max) }

  /// Decodes a signed control value from a single `Int16`, clamping `-32768` to `-32767`.
  ///
  /// - Throws: `DecodingError` when the stored value is not an `Int16`.
  public init(from decoder: any Decoder) throws {
    self.init(try decoder.singleValueContainer().decode(Int16.self))
  }

  /// Encodes the raw value as a single `Int16`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Nanoseconds from one process-local monotonic clock.
public struct MonotonicTimestamp: Hashable, Comparable, Codable, Sendable {
  /// The nanosecond count of the clock.
  public let nanoseconds: UInt64

  /// Creates a timestamp from a nanosecond count.
  public init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }

  /// Orders timestamps by their nanosecond counts.
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.nanoseconds < rhs.nanoseconds }
}

/// The one control vocabulary: position-based ids that physical labels never rename.
///
/// The raw value is the UpperCamelCase id the schemas, records, profiles and the endpoint use.
/// `Resources/Schemas/vocabulary.schema.json` `$defs/control` defines the same set; a test keeps
/// the two equal. A press of a trigger is the `leftTrigger` or `rightTrigger` id, and the D-pad is
/// four ids rather than one hat.
public enum Control: String, CaseIterable, Codable, Sendable {
  /// The south face button.
  case south = "South"
  /// The east face button.
  case east = "East"
  /// The west face button.
  case west = "West"
  /// The north face button.
  case north = "North"
  /// The left shoulder button.
  case leftShoulder = "LeftShoulder"
  /// The right shoulder button.
  case rightShoulder = "RightShoulder"
  /// The digital press of the left trigger.
  case leftTrigger = "LeftTrigger"
  /// The digital press of the right trigger.
  case rightTrigger = "RightTrigger"
  /// The back button.
  case back = "Back"
  /// The start button.
  case start = "Start"
  /// The press of the left stick.
  case leftStickClick = "LeftStickClick"
  /// The press of the right stick.
  case rightStickClick = "RightStickClick"
  /// The D-pad up direction.
  case dpadUp = "DpadUp"
  /// The D-pad down direction.
  case dpadDown = "DpadDown"
  /// The D-pad left direction.
  case dpadLeft = "DpadLeft"
  /// The D-pad right direction.
  case dpadRight = "DpadRight"
  /// The guide button.
  case guide = "Guide"
  /// The capture button.
  case capture = "Capture"
  /// The microphone button.
  case microphone = "Microphone"
  /// The press of the touchpad.
  case touchpadClick = "TouchpadClick"
  /// The first left paddle.
  case leftPaddle1 = "LeftPaddle1"
  /// The second left paddle.
  case leftPaddle2 = "LeftPaddle2"
  /// The first right paddle.
  case rightPaddle1 = "RightPaddle1"
  /// The second right paddle.
  case rightPaddle2 = "RightPaddle2"
  /// The first auxiliary button, for a button that no other id names.
  case auxiliary1 = "Auxiliary1"
  /// The second auxiliary button.
  case auxiliary2 = "Auxiliary2"
  /// The third auxiliary button.
  case auxiliary3 = "Auxiliary3"
  /// The fourth auxiliary button.
  case auxiliary4 = "Auxiliary4"
  /// The fifth auxiliary button.
  case auxiliary5 = "Auxiliary5"
  /// The sixth auxiliary button.
  case auxiliary6 = "Auxiliary6"
  /// The seventh auxiliary button.
  case auxiliary7 = "Auxiliary7"
  /// The eighth auxiliary button.
  case auxiliary8 = "Auxiliary8"
  /// The horizontal axis of the left stick.
  case leftStickX = "LeftStickX"
  /// The vertical axis of the left stick.
  case leftStickY = "LeftStickY"
  /// The horizontal axis of the right stick.
  case rightStickX = "RightStickX"
  /// The vertical axis of the right stick.
  case rightStickY = "RightStickY"
  /// A touch on the left stick.
  case leftStickTouch = "LeftStickTouch"
  /// A touch on the right stick.
  case rightStickTouch = "RightStickTouch"
  /// The press of the left trackpad.
  case leftTrackpadClick = "LeftTrackpadClick"
  /// The press of the right trackpad.
  case rightTrackpadClick = "RightTrackpadClick"
  /// A touch on the left trackpad.
  case leftTrackpadTouch = "LeftTrackpadTouch"
  /// A touch on the right trackpad.
  case rightTrackpadTouch = "RightTrackpadTouch"
  /// The horizontal position a pointing device aims at, from -1 (left) to 1 (right).
  case pointerX = "PointerX"
  /// The vertical position a pointing device aims at, from -1 (top) to 1 (bottom).
  case pointerY = "PointerY"
  /// Whether the pointing device sees its target, so that `pointerX` and `pointerY` are live.
  case pointerTracking = "PointerTracking"
  /// A touch on the left grip.
  case leftGripTouch = "LeftGripTouch"
  /// A touch on the right grip.
  case rightGripTouch = "RightGripTouch"

  /// The four D-pad ids; a controller with a D-pad or hat has all of them.
  public static let dpad: Set<Control> = [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]

  /// The four stick axes.
  public static let stickAxes: [Self] = [.leftStickX, .leftStickY, .rightStickX, .rightStickY]

  /// Controls of the standard Xbox layout, excluding `guide`.
  public static let xboxLayout: Set<Control> = dpad.union([
    .leftStickX, .leftStickY, .rightStickX, .rightStickY, .leftStickClick, .rightStickClick,
    .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
    .back, .start,
  ])

  /// Whether the virtual gamepad report has a button for this control.
  ///
  /// A paddle, an auxiliary button, a trackpad and a stick touch have none.
  public var supportsVirtualOutput: Bool {
    switch self {
    case .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger,
      .back, .start, .leftStickClick, .rightStickClick, .guide, .capture, .dpadUp, .dpadDown,
      .dpadLeft, .dpadRight, .leftStickX, .leftStickY, .rightStickX, .rightStickY:
      return true
    case .microphone, .touchpadClick, .leftPaddle1, .leftPaddle2, .rightPaddle1, .rightPaddle2,
      .auxiliary1, .auxiliary2, .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7,
      .auxiliary8, .leftStickTouch, .rightStickTouch, .leftTrackpadClick, .rightTrackpadClick,
      .leftTrackpadTouch, .rightTrackpadTouch, .pointerX, .pointerY, .pointerTracking,
      .leftGripTouch, .rightGripTouch:
      return false
    }
  }
}

/// One of eight compass directions, or neutral (center) for a hat or D-pad.
public enum HatDirection: String, Codable, Sendable {
  /// The hat or D-pad is centered.
  case neutral = "Neutral"
  /// Up.
  case north = "North"
  /// Up and right.
  case northEast = "NorthEast"
  /// Right.
  case east = "East"
  /// Down and right.
  case southEast = "SouthEast"
  /// Down.
  case south = "South"
  /// Down and left.
  case southWest = "SouthWest"
  /// Left.
  case west = "West"
  /// Up and left.
  case northWest = "NorthWest"
}

extension HatDirection {
  /// The D-pad control the hat points at; a diagonal names its vertical id, and neutral the
  /// first D-pad id.
  public var dpadControl: Control {
    switch self {
    case .north, .northEast, .northWest, .neutral: .dpadUp
    case .south, .southEast, .southWest: .dpadDown
    case .east: .dpadRight
    case .west: .dpadLeft
    }
  }
}

/// The battery charge at the precision the device reports, never a synthesized midpoint.
public struct BatteryLevel: Codable, Hashable, Sendable {
  /// The level of a device that reports none.
  public static let unknown = Self(percentage: nil)

  /// The charge within `0...100`.
  ///
  /// One value for an exact reading, the device's bucket otherwise, and `nil` when the device
  /// reports no level.
  public let percentage: ClosedRange<UInt8>?

  /// Creates a level from `percentage`; a bound above 100 is a precondition failure.
  public init(percentage: ClosedRange<UInt8>?) {
    precondition(percentage.map { $0.upperBound <= 100 } ?? true, "Battery charge exceeds 100%")
    self.percentage = percentage
  }

  /// Decodes a battery level from its `percentage` key.
  ///
  /// - Throws: `DecodingError` when `percentage` is a bad value or its upper bound exceeds 100.
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

  /// The locale-independent ASCII charge, `73%` or `0-9%`; `nil` when unknown.
  public var percentageText: String? {
    guard let percentage else { return nil }
    if percentage.lowerBound == percentage.upperBound { return "\(percentage.lowerBound)%" }
    return "\(percentage.lowerBound)-\(percentage.upperBound)%"
  }
}

/// The link and power state of one logical controller.
public struct ControllerConnectionState: Codable, Equatable, Sendable {
  /// Whether and how the controller's battery charges.
  public enum Charging: String, Codable, Sendable {
    /// The device reports no charging state.
    case unknown = "Unknown"
    /// The battery discharges.
    case discharging = "Discharging"
    /// The battery charges.
    case charging = "Charging"
    /// The battery is full.
    case full = "Full"
    /// The controller has no chargeable battery.
    case notChargeable = "NotChargeable"
  }

  /// Power facts a driver decodes from its own reports.
  public struct Power: Codable, Equatable, Sendable {
    /// The power facts of a device that reports none.
    public static let unknown = Self(charging: .unknown, battery: .unknown, wiredPower: nil)

    /// Whether and how the battery charges.
    public let charging: Charging
    /// The battery charge.
    public let battery: BatteryLevel
    /// Whether wired power is available; `nil` when the device does not report it.
    public let wiredPower: Bool?

    /// Creates power facts from the charging state, the battery level and the wired power flag.
    public init(charging: Charging, battery: BatteryLevel, wiredPower: Bool?) {
      self.charging = charging
      self.battery = battery
      self.wiredPower = wiredPower
    }
  }

  /// The controller-side link; `nil` without evidence.
  ///
  /// Wireless is never inferred from absent USB.
  public let transport: PhysicalTransport?
  /// The access path that serves the controller.
  public let backend: DeviceAccessBackend
  /// Whether the controller is linked; a `ProprietaryRadioReceiver` slot can be empty.
  public let isConnected: Bool
  /// The power facts of the controller.
  public let power: Power

  /// Creates a connection state from the link, access path, linked flag and power facts.
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
