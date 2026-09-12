/// Selects one runtime controller; an omitted command reads calibration status.
public struct ApplicationServiceMotionCalibrationArguments: Codable, Sendable {
  public let runtimeIdentifier: String
  public let command: RemappingMotionCalibrationCommand?

  public init(
    runtimeIdentifier: String, command: RemappingMotionCalibrationCommand? = nil
  ) {
    self.runtimeIdentifier = runtimeIdentifier
    self.command = command
  }

  private enum CodingKeys: String, CodingKey {
    case runtimeIdentifier = "runtime_identifier"
    case command
  }
}
