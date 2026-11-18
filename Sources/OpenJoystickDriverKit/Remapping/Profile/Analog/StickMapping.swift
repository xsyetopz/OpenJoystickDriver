import Foundation

/// Physical stick that feeds a ``RemappingStickMapping``.
public enum RemappingStickSource: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left stick.
  case left = "Left"
  /// The right stick.
  case right = "Right"
}

/// How a ``RemappingStickMapping`` turns stick motion into output.
public enum RemappingStickMode: String, Codable, CaseIterable, Hashable, Sendable {
  /// Deflection turns the pointer continuously, scaled by
  /// ``RemappingStickMapping/aimDegreesPerSecond``.
  case aim = "Aim"
  /// A rim flick turns the pointer by the flick angle, and rotating along the rim keeps turning it.
  case flick = "Flick"
  /// Only the rim flick turns the pointer; rim rotation is ignored.
  case flickOnly = "FlickOnly"
  /// Only rotating along the rim turns the pointer; the flick at the start is ignored.
  case rotateOnly = "RotateOnly"
  /// The pointer sits at the stick deflection scaled to
  /// ``RemappingStickMapping/pointerRadiusPoints``.
  case pointerArea = "PointerArea"
  /// The pointer sits on a ring of ``RemappingStickMapping/pointerRadiusPoints`` in the stick
  /// direction.
  case pointerRing = "PointerRing"
  /// Rotating the stick along the rim emits scroll lines.
  case scrollWheel = "ScrollWheel"
  /// Rotating the stick along the rim accumulates a virtual steering wheel on a virtual gamepad
  /// axis.
  case steering = "Steering"
}

/// Axis along which ``RemappingStickMode/scrollWheel`` scrolls.
public enum RemappingStickScrollAxis: String, Codable, CaseIterable, Hashable, Sendable {
  /// Scrolls sideways.
  case horizontal = "Horizontal"
  /// Scrolls up and down.
  case vertical = "Vertical"
}

/// Rim rotation direction that counts as positive for scrolling and steering.
public enum RemappingStickRotationDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// Clockwise rotation produces positive scroll lines or steering degrees.
  case clockwise = "Clockwise"
  /// Counterclockwise rotation produces positive scroll lines or steering degrees.
  case counterclockwise = "Counterclockwise"

  /// Sign applied to a counterclockwise angle change so the chosen direction is positive.
  var multiplier: Double { self == .clockwise ? -1 : 1 }
}

/// Virtual gamepad axis that ``RemappingStickMode/steering`` drives.
public enum RemappingStickSteeringOutput: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left stick horizontal axis of the virtual gamepad.
  case leftStickX = "LeftStickX"
  /// The right stick horizontal axis of the virtual gamepad.
  case rightStickX = "RightStickX"

  /// Virtual gamepad axis that carries the steering value.
  var axis: RemappingAxis {
    switch self {
    case .leftStickX: .leftStickX
    case .rightStickX: .rightStickX
    }
  }
}

/// Advanced behavior of one physical stick: pointer aim, flick, scroll or steering output.
public struct RemappingStickMapping: Codable, Equatable, Hashable, Sendable {
  /// Physical stick that this mapping reads.
  public let source: RemappingStickSource
  /// How stick motion becomes output.
  public let mode: RemappingStickMode
  /// Deadzone and response calibration applied before the mode runs.
  public let tuning: RemappingStickTuning
  /// Pointer turn rate at full deflection in ``RemappingStickMode/aim``, in degrees per second.
  public let aimDegreesPerSecond: Double
  /// Logical screen points of pointer movement per degree of angular output.
  public let pointerPointsPerDegree: Double
  /// Time over which one flick angle is spread, in milliseconds.
  public let flickDurationMs: Double
  /// Deflection magnitude at which a rim touch starts a flick.
  public let flickThreshold: Double
  /// Margin below ``flickThreshold`` within which rim rotation keeps tracking.
  public let flickHysteresis: Double
  /// Pointer displacement from the activation anchor, in logical screen points.
  public let pointerRadiusPoints: Double
  /// Angular stick travel that emits one logical scroll line, in degrees.
  public let scrollDegreesPerLine: Double
  /// Axis that scroll lines go to.
  public let scrollAxis: RemappingStickScrollAxis
  /// Rim rotation direction that counts as positive.
  public let rotationDirection: RemappingStickRotationDirection
  /// Accumulated wheel rotation that represents full virtual steering output, in degrees.
  public let steeringDegreesAtFullScale: Double
  /// Automatic return speed toward center while the stick is not fully deflected, in degrees per
  /// second.
  public let steeringReturnDegreesPerSecond: Double
  /// Virtual gamepad axis that steering drives.
  public let steeringOutput: RemappingStickSteeringOutput
  /// Keeps the physical stick axes in passthrough output in addition to this mapping.
  public let passthrough: Bool

  /// Creates a stick mapping.
  ///
  /// Defaults match the values a profile document gets when it omits a field. The initializer does
  /// not validate; call ``validate()``.
  public init(
    source: RemappingStickSource,
    mode: RemappingStickMode = .aim,
    tuning: RemappingStickTuning = .default,
    aimDegreesPerSecond: Double = 360,
    pointerPointsPerDegree: Double = 1,
    flickDurationMs: Double = 100,
    flickThreshold: Double = 0.9,
    flickHysteresis: Double = 0.1,
    pointerRadiusPoints: Double = 128,
    scrollDegreesPerLine: Double = 15,
    scrollAxis: RemappingStickScrollAxis = .vertical,
    rotationDirection: RemappingStickRotationDirection = .clockwise,
    steeringDegreesAtFullScale: Double = 360,
    steeringReturnDegreesPerSecond: Double = 360,
    steeringOutput: RemappingStickSteeringOutput = .leftStickX,
    passthrough: Bool = false
  ) {
    self.source = source
    self.mode = mode
    self.tuning = tuning
    self.aimDegreesPerSecond = aimDegreesPerSecond
    self.pointerPointsPerDegree = pointerPointsPerDegree
    self.flickDurationMs = flickDurationMs
    self.flickThreshold = flickThreshold
    self.flickHysteresis = flickHysteresis
    self.pointerRadiusPoints = pointerRadiusPoints
    self.scrollDegreesPerLine = scrollDegreesPerLine
    self.scrollAxis = scrollAxis
    self.rotationDirection = rotationDirection
    self.steeringDegreesAtFullScale = steeringDegreesAtFullScale
    self.steeringReturnDegreesPerSecond = steeringReturnDegreesPerSecond
    self.steeringOutput = steeringOutput
    self.passthrough = passthrough
  }

  /// Checks every field against its allowed range.
  ///
  /// Each numeric field must be finite and inside its range, and ``flickHysteresis`` must be below
  /// ``flickThreshold``.
  /// - Throws: ``RemappingStickMappingError/invalidField(_:)`` with the snake_case field name, or
  ///   the ``RemappingStickTuningError`` of ``tuning``.
  public func validate() throws {
    try tuning.validate()
    let fields: [(String, Double, ClosedRange<Double>)] = [
      ("aim_degrees_per_second", aimDegreesPerSecond, 0...10_000),
      ("pointer_points_per_degree", pointerPointsPerDegree, 0...1000),
      ("flick_duration_ms", flickDurationMs, 0...10_000),
      ("flick_threshold", flickThreshold, 0.1...1), ("flick_hysteresis", flickHysteresis, 0...0.5),
      ("pointer_radius_points", pointerRadiusPoints, 1...10_000),
      ("scroll_degrees_per_line", scrollDegreesPerLine, 1...360),
      ("steering_degrees_at_full_scale", steeringDegreesAtFullScale, 45...1440),
      ("steering_return_degrees_per_second", steeringReturnDegreesPerSecond, 0...10_000),
    ]
    for (field, value, range) in fields where !value.isFinite || !range.contains(value) {
      throw RemappingStickMappingError.invalidField(field)
    }
    guard flickHysteresis < flickThreshold else {
      throw RemappingStickMappingError.invalidField("flick_hysteresis")
    }
  }

  /// Profile document keys of a stick mapping.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case source
    case mode
    case tuning
    case aimDegreesPerSecond
    case pointerPointsPerDegree
    case flickDurationMs
    case flickThreshold
    case flickHysteresis
    case pointerRadiusPoints
    case scrollDegreesPerLine
    case scrollAxis
    case rotationDirection
    case steeringDegreesAtFullScale
    case steeringReturnDegreesPerSecond
    case steeringOutput
    case passthrough
  }

  /// Decodes a stick mapping from a profile document.
  ///
  /// Omitted fields take the initializer defaults.
  /// - Throws: `DecodingError` for an unknown key or a bad value, or the error of ``validate()``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      source: try values.decode(RemappingStickSource.self, forKey: .source),
      mode: try values.decodeIfPresent(RemappingStickMode.self, forKey: .mode) ?? .aim,
      tuning: try values.decodeIfPresent(RemappingStickTuning.self, forKey: .tuning) ?? .default,
      aimDegreesPerSecond: try values.decodeIfPresent(Double.self, forKey: .aimDegreesPerSecond)
        ?? 360,
      pointerPointsPerDegree: try values.decodeIfPresent(
        Double.self,
        forKey: .pointerPointsPerDegree
      ) ?? 1,
      flickDurationMs: try values.decodeIfPresent(Double.self, forKey: .flickDurationMs) ?? 100,
      flickThreshold: try values.decodeIfPresent(Double.self, forKey: .flickThreshold) ?? 0.9,
      flickHysteresis: try values.decodeIfPresent(Double.self, forKey: .flickHysteresis) ?? 0.1,
      pointerRadiusPoints: try values.decodeIfPresent(Double.self, forKey: .pointerRadiusPoints)
        ?? 128,
      scrollDegreesPerLine: try values.decodeIfPresent(Double.self, forKey: .scrollDegreesPerLine)
        ?? 15,
      scrollAxis: try values.decodeIfPresent(RemappingStickScrollAxis.self, forKey: .scrollAxis)
        ?? .vertical,
      rotationDirection: try values.decodeIfPresent(
        RemappingStickRotationDirection.self,
        forKey: .rotationDirection
      ) ?? .clockwise,
      steeringDegreesAtFullScale: try values.decodeIfPresent(
        Double.self,
        forKey: .steeringDegreesAtFullScale
      ) ?? 360,
      steeringReturnDegreesPerSecond: try values.decodeIfPresent(
        Double.self,
        forKey: .steeringReturnDegreesPerSecond
      ) ?? 360,
      steeringOutput: try values.decodeIfPresent(
        RemappingStickSteeringOutput.self,
        forKey: .steeringOutput
      ) ?? .leftStickX,
      passthrough: try values.decodeIfPresent(Bool.self, forKey: .passthrough) ?? false
    )
    try validate()
  }
}

/// Error for an invalid stick mapping.
public enum RemappingStickMappingError: Error, Equatable, Sendable {
  /// A field is not finite or is out of range; the payload names it.
  case invalidField(String)
}
