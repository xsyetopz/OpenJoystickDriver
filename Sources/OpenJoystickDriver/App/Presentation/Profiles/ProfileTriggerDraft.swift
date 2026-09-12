import OpenJoystickDriverKit

struct ProfileTriggerDraft {
  let source: RemappingTriggerSource
  var enabled: Bool
  var mode: RemappingDualStageTriggerMode
  var softThreshold: String
  var fullThreshold: String
  var hysteresis: String
  var skipWindowMs: String
  var passthrough: Bool

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
