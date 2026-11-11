import Foundation

/// Input whose value sets the pointer speed scale.
public struct RemappingPointerSpeedDriver: Codable, Equatable, Hashable, Sendable {
  /// Kind of input that is read.
  public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Pressure of a trigger.
    case trigger = "Trigger"
    /// Deflection of a stick from its center.
    case stickDepth = "StickDepth"
  }

  /// Kind of input that is read.
  public let type: Kind
  /// Trigger or stick that is read.
  public let side: RemappingStickSource

  /// Creates a driver.
  public init(type: Kind, side: RemappingStickSource) {
    self.type = type
    self.side = side
  }

  /// Profile document keys of a driver.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `type`.
    case type
    /// The JSON key of `side`.
    case side
  }

  /// Decodes a driver from a profile document, which must give both fields.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    type = try values.decode(Kind.self, forKey: .type)
    side = try values.decode(RemappingStickSource.self, forKey: .side)
  }
}

/// Scales all pointer movement by the value of a trigger or a stick.
public struct RemappingPointerSpeed: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``minScale`` and ``maxScale``.
  public static let scaleRange = 0.0...10.0

  /// Input that sets the scale.
  public let driver: RemappingPointerSpeedDriver
  /// Scale while the driver is at 0.
  public let minScale: Double
  /// Scale while the driver is at 1.
  public let maxScale: Double
  /// Curve from the driver value to the position between ``minScale`` and ``maxScale``.
  public let curve: RemappingResponseCurve

  /// Creates a pointer speed.
  public init(
    driver: RemappingPointerSpeedDriver,
    minScale: Double,
    maxScale: Double,
    curve: RemappingResponseCurve = .linear
  ) {
    self.driver = driver
    self.minScale = minScale
    self.maxScale = maxScale
    self.curve = curve
  }

  /// Profile document keys of a pointer speed.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `driver`.
    case driver
    /// The JSON key of `minScale`.
    case minScale
    /// The JSON key of `maxScale`.
    case maxScale
    /// The JSON key of `curve`.
    case curve
  }

  /// Decodes a pointer speed from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    driver = try values.decode(RemappingPointerSpeedDriver.self, forKey: .driver)
    minScale = try values.decode(Double.self, forKey: .minScale)
    maxScale = try values.decode(Double.self, forKey: .maxScale)
    curve = try values.decode(RemappingResponseCurve.self, forKey: .curve)
  }

  /// Whether both scales are finite and in ``scaleRange``.
  var isValid: Bool {
    [minScale, maxScale].allSatisfy { $0.isFinite && Self.scaleRange.contains($0) }
  }

  /// Returns the scale for a driver value from 0 to 1.
  public func scale(driverValue: Double) -> Double {
    minScale + (maxScale - minScale) * curve.shaped(min(max(driverValue, 0), 1))
  }

  /// Returns the scale for the controller whose axes `axis` reads, each from its own range: a
  /// trigger from 0 to 1, a stick axis from -1 to 1.
  public func scale(axis: (RemappingAxis) -> Float) -> Double {
    let driverValue: Double
    switch (driver.type, driver.side) {
    case (.trigger, .left): driverValue = Double(axis(.leftTrigger))
    case (.trigger, .right): driverValue = Double(axis(.rightTrigger))
    case (.stickDepth, .left): driverValue = Double(hypot(axis(.leftStickX), axis(.leftStickY)))
    case (.stickDepth, .right): driverValue = Double(hypot(axis(.rightStickX), axis(.rightStickY)))
    }
    return scale(driverValue: driverValue)
  }

  /// Whether the controller reports the trigger or stick the driver reads.
  public func isSupported(by capabilities: ControllerProfileCapabilities) -> Bool {
    let control: Control =
      switch (driver.type, driver.side) {
      case (.trigger, .left): .leftTrigger
      case (.trigger, .right): .rightTrigger
      case (.stickDepth, .left): .leftStickX
      case (.stickDepth, .right): .rightStickX
      }
    return capabilities.physicalInput.controls.contains(control)
  }

  /// Returns the scale for the input `state`.
  public func scale(for state: ControllerState) -> Double {
    scale { axis in
      switch axis {
      case .leftStickX: state.leftStick.x.normalized
      case .leftStickY: state.leftStick.y.normalized
      case .rightStickX: state.rightStick.x.normalized
      case .rightStickY: state.rightStick.y.normalized
      case .leftTrigger: state.leftTrigger.normalized
      case .rightTrigger: state.rightTrigger.normalized
      case .pointerX: state.pointer.x.normalized
      case .pointerY: state.pointer.y.normalized
      }
    }
  }
}
