import Foundation

public enum RemappingStickSource: String, Codable, CaseIterable, Hashable, Sendable {
  case left
  case right
}

public enum RemappingStickMode: String, Codable, CaseIterable, Hashable, Sendable {
  case aim
  case flick
  case flickOnly = "flick_only"
  case rotateOnly = "rotate_only"
  case pointerArea = "pointer_area"
  case pointerRing = "pointer_ring"
  case scrollWheel = "scroll_wheel"
  case steering
}

public enum RemappingStickScrollAxis: String, Codable, CaseIterable, Hashable, Sendable {
  case horizontal
  case vertical
}

public enum RemappingStickRotationDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case clockwise
  case counterclockwise

  var multiplier: Double { self == .clockwise ? -1 : 1 }
}

public enum RemappingStickSteeringOutput: String, Codable, CaseIterable, Hashable, Sendable {
  case leftStickX = "left_stick_x"
  case rightStickX = "right_stick_x"

  var axis: RemappingAxis {
    switch self {
    case .leftStickX: .leftStickX
    case .rightStickX: .rightStickX
    }
  }
}

/// Angular stick output, calibrated separately from logical screen-point conversion.
public struct RemappingStickMapping: Codable, Equatable, Hashable, Sendable {
  public let source: RemappingStickSource
  public let mode: RemappingStickMode
  public let tuning: RemappingStickTuning
  public let aimDegreesPerSecond: Double
  public let pointerPointsPerDegree: Double
  public let flickDurationMs: Double
  public let flickThreshold: Double
  public let flickHysteresis: Double
  /// Pointer displacement from the activation anchor, in logical screen points.
  public let pointerRadiusPoints: Double
  /// Angular stick travel that emits one logical scroll line.
  public let scrollDegreesPerLine: Double
  public let scrollAxis: RemappingStickScrollAxis
  public let rotationDirection: RemappingStickRotationDirection
  /// Accumulated wheel rotation that represents full virtual steering output.
  public let steeringDegreesAtFullScale: Double
  /// Automatic return speed while the stick is not fully deflected.
  public let steeringReturnDegreesPerSecond: Double
  public let steeringOutput: RemappingStickSteeringOutput
  /// Keeps the physical stick axes in passthrough output in addition to this mapping.
  public let passthrough: Bool

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

  public func validate() throws {
    try tuning.validate()
    let fields: [(String, Double, ClosedRange<Double>)] = [
      ("aim_degrees_per_second", aimDegreesPerSecond, 0...10_000),
      ("pointer_points_per_degree", pointerPointsPerDegree, 0...1000),
      ("flick_duration_ms", flickDurationMs, 0...10_000),
      ("flick_threshold", flickThreshold, 0.1...1),
      ("flick_hysteresis", flickHysteresis, 0...0.5),
      ("pointer_radius_points", pointerRadiusPoints, 1...10_000),
      ("scroll_degrees_per_line", scrollDegreesPerLine, 1...360),
      ("steering_degrees_at_full_scale", steeringDegreesAtFullScale, 45...1440),
      ("steering_return_degrees_per_second", steeringReturnDegreesPerSecond, 0...10_000)
    ]
    for (field, value, range) in fields where !value.isFinite || !range.contains(value) {
      throw RemappingStickMappingError.invalidField(field)
    }
    guard flickHysteresis < flickThreshold else {
      throw RemappingStickMappingError.invalidField("flick_hysteresis")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case source, mode, tuning
    case aimDegreesPerSecond = "aim_degrees_per_second"
    case pointerPointsPerDegree = "pointer_points_per_degree"
    case flickDurationMs = "flick_duration_ms"
    case flickThreshold = "flick_threshold"
    case flickHysteresis = "flick_hysteresis"
    case pointerRadiusPoints = "pointer_radius_points"
    case scrollDegreesPerLine = "scroll_degrees_per_line"
    case scrollAxis = "scroll_axis"
    case rotationDirection = "rotation_direction"
    case steeringDegreesAtFullScale = "steering_degrees_at_full_scale"
    case steeringReturnDegreesPerSecond = "steering_return_degrees_per_second"
    case steeringOutput = "steering_output"
    case passthrough
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      source: try values.decode(RemappingStickSource.self, forKey: .source),
      mode: try values.decodeIfPresent(RemappingStickMode.self, forKey: .mode) ?? .aim,
      tuning: try values.decodeIfPresent(RemappingStickTuning.self, forKey: .tuning) ?? .default,
      aimDegreesPerSecond: try values.decodeIfPresent(Double.self, forKey: .aimDegreesPerSecond)
        ?? 360,
      pointerPointsPerDegree: try values.decodeIfPresent(
        Double.self, forKey: .pointerPointsPerDegree
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
        RemappingStickRotationDirection.self, forKey: .rotationDirection
      ) ?? .clockwise,
      steeringDegreesAtFullScale: try values.decodeIfPresent(
        Double.self, forKey: .steeringDegreesAtFullScale
      ) ?? 360,
      steeringReturnDegreesPerSecond: try values.decodeIfPresent(
        Double.self, forKey: .steeringReturnDegreesPerSecond
      ) ?? 360,
      steeringOutput: try values.decodeIfPresent(
        RemappingStickSteeringOutput.self, forKey: .steeringOutput
      ) ?? .leftStickX,
      passthrough: try values.decodeIfPresent(Bool.self, forKey: .passthrough) ?? false
    )
    try validate()
  }
}

public enum RemappingStickMappingError: Error, Equatable, Sendable {
  case invalidField(String)
}
