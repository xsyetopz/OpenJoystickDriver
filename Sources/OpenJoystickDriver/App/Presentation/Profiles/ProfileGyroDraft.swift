import OpenJoystickDriverKit

struct ProfileGyroDraft {
  var trackball: ProfileTrackballDraft
  var mode: RemappingGyroOutputMode
  var activationMode: RemappingGyroActivationMode
  var consumesActivationSource: Bool
  var activationSource: RemappingSource
  var pointerPointsPerDegree: String
  var fullStickDegreesPerSecond: String
  var virtualMotion: Bool

  init(_ output: RemappingGyroOutput) {
    mode = output.mode
    trackball = ProfileTrackballDraft(output.trackball)
    consumesActivationSource = output.consumesActivationSource
    activationMode = output.activationMode
    activationSource = output.activationSource ?? .button(.south)
    pointerPointsPerDegree = String(output.pointerPointsPerDegree)
    fullStickDegreesPerSecond = String(output.fullStickDegreesPerSecond)
    virtualMotion = output.virtualMotion
  }

  func validatedOutput(decimalSeparator: String = ".") throws -> RemappingGyroOutput {
    guard
      let pointer = ProfileMotionDraft.numericValue(
        pointerPointsPerDegree,
        decimalSeparator: decimalSeparator
      )
    else { throw RemappingGyroOutputError.invalidField("pointer_points_per_degree") }
    guard
      let stick = ProfileMotionDraft.numericValue(
        fullStickDegreesPerSecond,
        decimalSeparator: decimalSeparator
      )
    else { throw RemappingGyroOutputError.invalidField("full_stick_degrees_per_second") }
    let output = try RemappingGyroOutput(
      mode: mode,
      pointerPointsPerDegree: pointer,
      fullStickDegreesPerSecond: stick,
      activationMode: activationMode,
      activationSource: activationMode == .always ? nil : activationSource,
      consumesActivationSource: consumesActivationSource,
      trackball: trackball.validatedSettings(decimalSeparator: decimalSeparator),
      virtualMotion: virtualMotion
    )
    try output.validate()
    return output
  }
}
