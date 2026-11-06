import OpenJoystickDriverKit

/// The gyro output as the motion sheet edits it, with the numbers as text.
struct ProfileGyroDraft {
  /// The trackball settings.
  var trackball: ProfileTrackballDraft
  /// Where the gyro output goes.
  var mode: RemappingGyroOutputMode
  /// When the gyro output is active.
  var activationMode: RemappingGyroActivationMode
  /// Whether the activation source stops acting as itself while it activates the gyro output.
  var consumesActivationSource: Bool
  /// The control that activates the gyro output; ignored when the activation mode is Always.
  var activationSource: RemappingSource
  /// The pointer points per degree, as typed.
  var pointerPointsPerDegree: String
  /// The degrees per second that reach a full stick deflection, as typed.
  var fullStickDegreesPerSecond: String

  /// Creates the draft from the profile's gyro output; a missing activation source reads as the
  /// south button.
  init(_ output: RemappingGyroOutput) {
    mode = output.mode
    trackball = ProfileTrackballDraft(output.trackball)
    consumesActivationSource = output.consumesActivationSource
    activationMode = output.activationMode
    activationSource = output.activationSource ?? .button(.south)
    pointerPointsPerDegree = String(output.pointerPointsPerDegree)
    fullStickDegreesPerSecond = String(output.fullStickDegreesPerSecond)
  }

  /// Returns the gyro output that the draft describes.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The gyro output that the draft describes.
  /// - Throws: ``RemappingGyroOutputError`` when a number cannot be read, and the error of the
  ///   output's validation when its values are out of range.
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
      trackball: trackball.validatedSettings(decimalSeparator: decimalSeparator)
    )
    try output.validate()
    return output
  }
}
