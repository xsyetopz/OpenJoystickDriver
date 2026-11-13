import Foundation

/// Physical trigger that feeds a ``RemappingTriggerMapping``.
public enum RemappingTriggerSource: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left trigger.
  case left = "Left"
  /// The right trigger.
  case right = "Right"

  /// Analog axis that the trigger reports.
  var axis: RemappingAxis {
    switch self {
    case .left: .leftTrigger
    case .right: .rightTrigger
    }
  }
}

/// Pull depth of a dual-stage trigger.
public enum RemappingTriggerStage: String, Codable, CaseIterable, Hashable, Sendable {
  /// The light first pull.
  case soft = "Soft"
  /// The full pull.
  case full = "Full"
}

/// Determines how a full pull interacts with the soft-pull stage.
public enum RemappingDualStageTriggerMode: String, Codable, CaseIterable, Hashable, Sendable {
  /// Soft and full stages may remain active together.
  case simultaneous = "Simultaneous"
  /// Full pull replaces soft pull without buffering.
  case exclusive = "Exclusive"
  /// Buffer soft pull; a quick full pull selects only full, otherwise full is ignored.
  case preferFull = "PreferFull"
  /// Buffer soft pull; a late full pull joins soft pull.
  case preferFullCombined = "PreferFullCombined"
  /// Emit soft immediately, but replace it when a quick full pull arrives.
  case responsivePreferFull = "ResponsivePreferFull"
  /// Emit soft immediately; a quick full pull replaces it and a late full pull joins it.
  case responsivePreferFullCombined = "ResponsivePreferFullCombined"

  /// Whether a soft pull waits for ``RemappingTriggerMapping/skipWindowMs`` before it settles.
  public var buffersSoftPull: Bool {
    switch self {
    case .preferFull, .preferFullCombined, .responsivePreferFull, .responsivePreferFullCombined:
      true
    case .simultaneous, .exclusive: false
    }
  }

  /// Whether the soft stage is active while it waits for a possible quick full pull.
  var emitsSoftWhileBuffered: Bool {
    self == .responsivePreferFull || self == .responsivePreferFullCombined
  }

  /// Whether a full pull that arrives after the skip window is active together with the soft stage.
  var permitsLateFullPull: Bool {
    self == .preferFullCombined || self == .responsivePreferFullCombined
  }
}

/// Soft and full stages of one physical trigger, each usable as a binding source.
public struct RemappingTriggerMapping: Codable, Equatable, Hashable, Sendable {
  /// Physical trigger that this mapping reads.
  public let source: RemappingTriggerSource
  /// How the full pull interacts with the soft pull.
  public let mode: RemappingDualStageTriggerMode
  /// Trigger value at which the soft stage activates, from 0 to 1.
  public let softThreshold: Double
  /// Trigger value at which the full stage activates, from 0 to 1.
  public let fullThreshold: Double
  /// Margin below a threshold that keeps a stage active until the trigger falls under it.
  public let hysteresis: Double
  /// Time after the soft pull in which a full pull counts as quick, in milliseconds.
  public let skipWindowMs: Double
  /// Keeps the physical trigger axis in passthrough output in addition to this mapping.
  public let passthrough: Bool

  /// Creates a trigger mapping.
  ///
  /// Defaults match the values a profile document gets when it omits a field. The initializer does
  /// not validate; call ``validate()``.
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

  /// Checks every field against its allowed range.
  ///
  /// Each field must be finite and inside its range, ``softThreshold`` must be below
  /// ``fullThreshold`` and ``hysteresis`` below ``softThreshold``.
  /// - Throws: ``RemappingTriggerMappingError/invalidField(_:)`` with the snake_case field name, or
  ///   `"thresholds"` for an inconsistent ordering.
  public func validate() throws {
    let fields: [(String, Double, ClosedRange<Double>)] = [
      ("soft_threshold", softThreshold, 0.01...0.95), ("full_threshold", fullThreshold, 0.05...1),
      ("hysteresis", hysteresis, 0...0.25), ("skip_window_ms", skipWindowMs, 1...1000),
    ]
    for (field, value, range) in fields where !value.isFinite || !range.contains(value) {
      throw RemappingTriggerMappingError.invalidField(field)
    }
    guard softThreshold < fullThreshold, hysteresis < softThreshold else {
      throw RemappingTriggerMappingError.invalidField("thresholds")
    }
  }

  /// Profile document keys of a trigger mapping.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case source
    case mode
    case hysteresis
    case passthrough
    case softThreshold
    case fullThreshold
    case skipWindowMs
  }

  /// Decodes a trigger mapping from a profile document.
  ///
  /// Omitted fields take the initializer defaults.
  /// - Throws: `DecodingError` for an unknown key or a bad value, or the error of ``validate()``.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
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

/// Error for an invalid trigger mapping.
public enum RemappingTriggerMappingError: Error, Equatable, Sendable {
  /// A field is not finite, is out of range or breaks the threshold order; the payload names it.
  case invalidField(String)
}
