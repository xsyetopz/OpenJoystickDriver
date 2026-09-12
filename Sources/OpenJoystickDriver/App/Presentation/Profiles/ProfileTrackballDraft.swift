import OpenJoystickDriverKit

struct ProfileTrackballDraft {
  var enabled: Bool
  var source: RemappingSource
  var axes: RemappingGyroTrackballAxes
  var decay: String
  var consumesSource: Bool

  init(_ settings: RemappingGyroTrackball?) {
    enabled = settings != nil
    source = settings?.source ?? .button(.east)
    axes = settings?.axes ?? .both
    decay = String(settings?.decayHalvingsPerSecond ?? 1)
    consumesSource = settings?.consumesSource ?? true
  }

  func validatedSettings(decimalSeparator: String) throws -> RemappingGyroTrackball? {
    guard enabled else { return nil }
    guard let value = ProfileMotionDraft.numericValue(decay, decimalSeparator: decimalSeparator)
    else { throw RemappingGyroOutputError.invalidField("trackball.decay_halvings_per_second") }
    let settings = RemappingGyroTrackball(
      source: source, axes: axes, decayHalvingsPerSecond: value, consumesSource: consumesSource
    )
    try settings.validate()
    return settings
  }
}
