/// Calibrated physical motion forwarded to a compatible virtual controller report.
public struct RemappingVirtualMotionState: Equatable, Sendable {
  public let gyroscopeDegreesPerSecond: ControllerMotionVector
  public let accelerationG: ControllerMotionVector
  public let deltaNanoseconds: UInt64

  public init(
    gyroscopeDegreesPerSecond: ControllerMotionVector,
    accelerationG: ControllerMotionVector,
    deltaNanoseconds: UInt64
  ) {
    self.gyroscopeDegreesPerSecond = gyroscopeDegreesPerSecond
    self.accelerationG = accelerationG
    self.deltaNanoseconds = deltaNanoseconds
  }
}
