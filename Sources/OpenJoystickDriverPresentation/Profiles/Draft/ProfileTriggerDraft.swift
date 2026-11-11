import OpenJoystickDriverKit

/// One trigger mapping as the trigger sheet edits it, with the numbers as text.
struct ProfileTriggerDraft {
  /// The trigger.
  let source: RemappingTriggerSource
  /// Whether the trigger has a mapping.
  var enabled: Bool
  /// How the two stages of the trigger combine.
  var mode: RemappingDualStageTriggerMode
  /// The soft pull threshold.
  var softThreshold: String
  /// The full pull threshold.
  var fullThreshold: String
  /// The hysteresis.
  var hysteresis: String
  /// The skip window in milliseconds.
  var skipWindowMs: String
  /// Whether the trigger keeps acting as itself.
  var passthrough: Bool

  /// Creates the draft of `source` from its mapping, or the defaults when it has none.
  init(source: RemappingTriggerSource, mapping: RemappingTriggerMapping?) {
    self.source = source
    enabled = mapping != nil
    let value = mapping ?? RemappingTriggerMapping(source: source)
    mode = value.mode
    softThreshold = String(value.softThreshold)
    fullThreshold = String(value.fullThreshold)
    hysteresis = String(value.hysteresis)
    skipWindowMs = String(value.skipWindowMs)
    passthrough = value.passthrough
  }

  /// Returns the mapping that the draft describes, or nil when the trigger has none.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The mapping that the draft describes, or nil when the trigger has none.
  /// - Throws: ``RemappingTriggerMappingError`` when a number cannot be read, and the error of the
  ///   mapping's validation when its values are out of range.
  func validatedMapping(decimalSeparator: String = ".") throws -> RemappingTriggerMapping? {
    guard enabled else { return nil }
    func number(_ raw: String, _ field: String) throws -> Double {
      guard let value = ProfileMotionDraft.numericValue(raw, decimalSeparator: decimalSeparator)
      else { throw RemappingTriggerMappingError.invalidField(field) }
      return value
    }
    let mapping = try RemappingTriggerMapping(
      source: source,
      mode: mode,
      softThreshold: number(softThreshold, "soft_threshold"),
      fullThreshold: number(fullThreshold, "full_threshold"),
      hysteresis: number(hysteresis, "hysteresis"),
      skipWindowMs: number(skipWindowMs, "skip_window_ms"),
      passthrough: passthrough
    )
    try mapping.validate()
    return mapping
  }
}
