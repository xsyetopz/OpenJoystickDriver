/// The arguments of a motion calibration request.
///
/// Names one connected controller; an omitted command reads the calibration status.
public struct ApplicationServiceMotionCalibrationArguments: Codable, Sendable {
  /// The controller to calibrate.
  public let controller: ControllerReference
  /// The calibration command; nil reads the status.
  public let command: RemappingMotionCalibrationCommand?

  /// Creates the arguments from a controller and an optional command.
  public init(controller: ControllerReference, command: RemappingMotionCalibrationCommand? = nil) {
    self.controller = controller
    self.command = command
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `controller` key.
    case controller
    /// The `command` key.
    case command
  }
}
