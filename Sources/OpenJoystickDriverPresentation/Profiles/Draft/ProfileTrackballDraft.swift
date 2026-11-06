import OpenJoystickDriverKit

/// The gyro trackball as the motion sheet edits it.
struct ProfileTrackballDraft {
  /// Whether the trackball is on.
  var enabled: Bool
  /// The control that drives the trackball.
  var source: RemappingSource
  /// The axes the trackball follows.
  var axes: RemappingGyroTrackballAxes
  /// The decay in halvings per second, as typed.
  var decay: String
  /// Whether the source stops acting as itself while it drives the trackball.
  var consumesSource: Bool

  /// Creates the draft from the profile's trackball settings, or the defaults when it has none.
  init(_ settings: RemappingGyroTrackball?) {
    enabled = settings != nil
    source = settings?.source ?? .button(.east)
    axes = settings?.axes ?? .both
    decay = String(settings?.decayHalvingsPerSecond ?? 1)
    consumesSource = settings?.consumesSource ?? true
  }

  /// Returns the trackball settings that the draft describes, or nil when it is off.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the number.
  /// - Returns: The trackball settings that the draft describes, or nil when it is off.
  /// - Throws: ``RemappingGyroOutputError`` when the decay cannot be read, and the error of the
  ///   settings' validation when they are out of range.
  func validatedSettings(decimalSeparator: String) throws -> RemappingGyroTrackball? {
    guard enabled else { return nil }
    guard let value = ProfileMotionDraft.numericValue(decay, decimalSeparator: decimalSeparator)
    else { throw RemappingGyroOutputError.invalidField("trackball.decay_halvings_per_second") }
    let settings = RemappingGyroTrackball(
      source: source,
      axes: axes,
      decayHalvingsPerSecond: value,
      consumesSource: consumesSource
    )
    try settings.validate()
    return settings
  }
}
