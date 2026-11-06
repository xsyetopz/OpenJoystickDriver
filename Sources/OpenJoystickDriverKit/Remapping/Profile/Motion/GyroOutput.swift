import Foundation

/// Where gyro motion goes.
public enum RemappingGyroOutputMode: String, Codable, CaseIterable, Sendable {
  /// Gyro motion produces no output.
  case disabled = "Disabled"
  /// Gyro motion moves the pointer.
  case mouse = "Mouse"
  /// Gyro motion drives the left stick of the virtual gamepad.
  case leftStick = "LeftStick"
  /// Gyro motion drives the right stick of the virtual gamepad.
  case rightStick = "RightStick"
}

/// When gyro output is active.
public enum RemappingGyroActivationMode: String, Codable, CaseIterable, Sendable {
  /// Gyro output is always active.
  case always = "Always"
  /// Gyro output is active while the activation source is held.
  case whileHeld = "WhileHeld"
  /// Gyro output is active while the activation source is not held.
  case whileReleased = "WhileReleased"
  /// Each press of the activation source switches gyro output on or off.
  case toggle = "Toggle"
}

/// Converts tuned angular motion to a native output with explicit physical units.
public struct RemappingGyroOutput: Codable, Equatable, Sendable {
  /// Where gyro motion goes.
  public let mode: RemappingGyroOutputMode
  /// Logical screen points of pointer movement per degree of rotation in
  /// ``RemappingGyroOutputMode/mouse``.
  public let pointerPointsPerDegree: Double
  /// Rotation speed that gives full stick deflection, in degrees per second.
  public let fullStickDegreesPerSecond: Double
  /// When gyro output is active.
  public let activationMode: RemappingGyroActivationMode
  /// Source that ``activationMode`` reads; `nil` exactly when the mode is
  /// ``RemappingGyroActivationMode/always``.
  public let activationSource: RemappingSource?
  /// Keeps the activation source out of passthrough output.
  public let consumesActivationSource: Bool
  /// Held-velocity mode that keeps turning after the motion stops, or `nil` for direct motion.
  public let trackball: RemappingGyroTrackball?

  /// Gyro output that is disabled.
  public static let `default` = Self()

  /// Creates a gyro output.
  ///
  /// The initializer does not validate; call ``validate()``.
  public init(
    mode: RemappingGyroOutputMode = .disabled,
    pointerPointsPerDegree: Double = 1,
    fullStickDegreesPerSecond: Double = 360,
    activationMode: RemappingGyroActivationMode = .always,
    activationSource: RemappingSource? = nil,
    consumesActivationSource: Bool = true,
    trackball: RemappingGyroTrackball? = nil
  ) {
    self.mode = mode
    self.pointerPointsPerDegree = pointerPointsPerDegree
    self.fullStickDegreesPerSecond = fullStickDegreesPerSecond
    self.activationMode = activationMode
    self.activationSource = activationSource
    self.consumesActivationSource = consumesActivationSource
    self.trackball = trackball
  }

  /// Checks the trackball, the activation source and the numeric ranges.
  ///
  /// An activation source is required unless the mode is ``RemappingGyroActivationMode/always``,
  /// and it cannot be an analog axis.
  /// - Throws: ``RemappingGyroOutputError/invalidField(_:)`` with the snake_case field name.
  public func validate() throws {
    try trackball?.validate()
    guard (activationMode == .always) == (activationSource == nil) else {
      throw RemappingGyroOutputError.invalidField("activation_source")
    }
    if case .axis = activationSource {
      throw RemappingGyroOutputError.invalidField("activation_source")
    }
    guard pointerPointsPerDegree.isFinite, (0...1000).contains(pointerPointsPerDegree) else {
      throw RemappingGyroOutputError.invalidField("pointer_points_per_degree")
    }
    guard fullStickDegreesPerSecond.isFinite, (1...10000).contains(fullStickDegreesPerSecond) else {
      throw RemappingGyroOutputError.invalidField("full_stick_degrees_per_second")
    }
  }

  /// Profile document keys of a gyro output.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `mode`.
    case mode
    /// The JSON key of `trackball`.
    case trackball
    /// The JSON key of `pointerPointsPerDegree`.
    case pointerPointsPerDegree
    /// The JSON key of `fullStickDegreesPerSecond`.
    case fullStickDegreesPerSecond
    /// The JSON key of `activationMode`.
    case activationMode
    /// The JSON key of `activationSource`.
    case activationSource
    /// The JSON key of `consumesActivationSource`.
    case consumesActivationSource
  }

  /// Decodes a gyro output from a profile document.
  ///
  /// Omitted fields take the initializer defaults.
  /// - Throws: `DecodingError` for an unknown key or a bad value, or the error of ``validate()``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      mode: try values.decodeIfPresent(RemappingGyroOutputMode.self, forKey: .mode) ?? .disabled,
      pointerPointsPerDegree: try values.decodeIfPresent(
        Double.self,
        forKey: .pointerPointsPerDegree
      ) ?? 1,
      fullStickDegreesPerSecond: try values.decodeIfPresent(
        Double.self,
        forKey: .fullStickDegreesPerSecond
      ) ?? 360,
      activationMode: try values.decodeIfPresent(
        RemappingGyroActivationMode.self,
        forKey: .activationMode
      ) ?? .always,
      activationSource: try values.decodeIfPresent(RemappingSource.self, forKey: .activationSource),
      consumesActivationSource: try values.decodeIfPresent(
        Bool.self,
        forKey: .consumesActivationSource
      ) ?? true,
      trackball: try values.decodeIfPresent(RemappingGyroTrackball.self, forKey: .trackball)
    )
    try validate()
  }
}

/// Error for an invalid gyro output or trackball.
public enum RemappingGyroOutputError: Error, Equatable, LocalizedError, Sendable {
  /// A field is outside its valid range or inconsistent with the others.
  case invalidField(String)

  /// Message that names the field that is outside its valid range.
  public var errorDescription: String? {
    switch self {
    case .invalidField(let field): "Gyro output field '\(field)' is outside its valid range."
    }
  }
}
