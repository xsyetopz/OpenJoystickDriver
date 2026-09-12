import Foundation

public enum RemappingTriggerSource: String, Codable, CaseIterable, Hashable, Sendable {
  case left
  case right

  var axis: RemappingAxis {
    switch self {
    case .left: .leftTrigger
    case .right: .rightTrigger
    }
  }
}

public enum RemappingTriggerStage: String, Codable, CaseIterable, Hashable, Sendable {
  case soft
  case full
}

/// Determines how a full pull interacts with the soft-pull stage.
public enum RemappingDualStageTriggerMode: String, Codable, CaseIterable, Hashable, Sendable {
  /// Soft and full stages may remain active together.
  case simultaneous
  /// Full pull replaces soft pull without buffering.
  case exclusive
  /// Buffer soft pull; a quick full pull selects only full, otherwise full is ignored.
  case preferFull = "prefer_full"
  /// Buffer soft pull; a late full pull joins soft pull.
  case preferFullCombined = "prefer_full_combined"
  /// Emit soft immediately, but replace it when a quick full pull arrives.
  case responsivePreferFull = "responsive_prefer_full"
  /// Emit soft immediately; a quick full pull replaces it and a late full pull joins it.
  case responsivePreferFullCombined = "responsive_prefer_full_combined"

  public var buffersSoftPull: Bool {
    switch self {
    case .preferFull, .preferFullCombined, .responsivePreferFull,
      .responsivePreferFullCombined: true
    case .simultaneous, .exclusive: false
    }
  }

  var emitsSoftWhileBuffered: Bool {
    self == .responsivePreferFull || self == .responsivePreferFullCombined
  }

  var permitsLateFullPull: Bool {
    self == .preferFullCombined || self == .responsivePreferFullCombined
  }
}

public struct RemappingTriggerMapping: Codable, Equatable, Hashable, Sendable {
  public let source: RemappingTriggerSource
  public let mode: RemappingDualStageTriggerMode
  public let softThreshold: Double
  public let fullThreshold: Double
  public let hysteresis: Double
  public let skipWindowMs: Double
  public let passthrough: Bool

  public init(
    source: RemappingTriggerSource,
    mode: RemappingDualStageTriggerMode = .simultaneous,
    softThreshold: Double = 0.1,
    fullThreshold: Double = 0.95,
    hysteresis: Double = 0.05,
    skipWindowMs: Double = 150,
    passthrough: Bool = false
  ) {
    self.source = source
    self.mode = mode
    self.softThreshold = softThreshold
    self.fullThreshold = fullThreshold
    self.hysteresis = hysteresis
    self.skipWindowMs = skipWindowMs
    self.passthrough = passthrough
  }

  public func validate() throws {
    let fields: [(String, Double, ClosedRange<Double>)] = [
      ("soft_threshold", softThreshold, 0.01...0.95),
      ("full_threshold", fullThreshold, 0.05...1),
      ("hysteresis", hysteresis, 0...0.25),
      ("skip_window_ms", skipWindowMs, 1...1000),
    ]
    for (field, value, range) in fields where !value.isFinite || !range.contains(value) {
      throw RemappingTriggerMappingError.invalidField(field)
    }
    guard softThreshold < fullThreshold, hysteresis < softThreshold else {
      throw RemappingTriggerMappingError.invalidField("thresholds")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case source, mode, hysteresis, passthrough
    case softThreshold = "soft_threshold"
    case fullThreshold = "full_threshold"
    case skipWindowMs = "skip_window_ms"
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      source: try values.decode(RemappingTriggerSource.self, forKey: .source),
      mode: try values.decodeIfPresent(RemappingDualStageTriggerMode.self, forKey: .mode)
        ?? .simultaneous,
      softThreshold: try values.decodeIfPresent(Double.self, forKey: .softThreshold) ?? 0.1,
      fullThreshold: try values.decodeIfPresent(Double.self, forKey: .fullThreshold) ?? 0.95,
      hysteresis: try values.decodeIfPresent(Double.self, forKey: .hysteresis) ?? 0.05,
      skipWindowMs: try values.decodeIfPresent(Double.self, forKey: .skipWindowMs) ?? 150,
      passthrough: try values.decodeIfPresent(Bool.self, forKey: .passthrough) ?? false
    )
    try validate()
  }
}

public enum RemappingTriggerMappingError: Error, Equatable, Sendable {
  case invalidField(String)
}
