/// Command for manual gyro bias collection.
public enum RemappingMotionCalibrationCommand: String, Codable, CaseIterable, Sendable {
  /// Starts (`start`), pauses (`pause`) or resets (`reset`) collection.
  ///
  /// Reset also discards the bias offset and the other motion estimates.
  case start, pause, reset
}

/// Motion calibration state of a controller.
public struct RemappingMotionCalibrationStatus: Codable, Equatable, Sendable {
  /// Whether a processed motion sample is available as a baseline.
  public let hasMotionBaseline: Bool
  /// Whether manual bias collection runs.
  public let isCollecting: Bool
  /// Gyro bias offset that is removed from readings, in degrees per second.
  public let offsetDegreesPerSecond: ControllerMotionVector
}

/// Why a motion calibration request cannot run.
public enum RemappingMotionCalibrationError: Error, Equatable, Sendable {
  /// The controller is not known to the engine.
  case controllerUnavailable
  /// No processed motion sample exists, which starting a collection needs as a baseline.
  case motionUnavailable
}

/// Reason the service refused a motion calibration request for a connected controller.
///
/// Each case has its own stable error code. ``RemappingMotionCalibrationError/motionUnavailable``
/// covers a controller that reports no motion data.
public enum RemappingMotionCalibrationRefusal: Error, Equatable, Sendable {
  /// The Joy-Con pair profile takes its gyro from another controller, or from none.
  case gyroNotSelected
  /// No eligible remapping profile is active for the controller, so no motion is processed.
  case profileInactive
  /// The controller's remapping session or route changed while the request ran.
  case sessionChanged
}

extension RemappingEngineState {
  /// Returns the calibration status of a controller, or `nil` when the engine does not know it.
  func motionCalibrationStatus(
    for identifier: LogicalControllerID
  ) -> RemappingMotionCalibrationStatus? {
    guard let motion = devices[identifier]?.motion else { return nil }
    return RemappingMotionCalibrationStatus(
      hasMotionBaseline: motion.motion.latest != nil,
      isCollecting: motion.motion.isManuallyCalibrating,
      offsetDegreesPerSecond: motion.motion.calibrationOffset
    )
  }

  /// Applies a calibration command to a controller and returns the resulting status.
  /// - Throws: ``RemappingMotionCalibrationError/controllerUnavailable`` for an unknown controller.
  ///   ``RemappingMotionCalibrationError/motionUnavailable`` when a start request has no baseline.
  mutating func calibrateMotion(
    _ command: RemappingMotionCalibrationCommand,
    for identifier: LogicalControllerID
  ) throws -> RemappingMotionCalibrationStatus {
    guard var device = devices[identifier] else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    switch command {
    case .start:
      guard device.motion.motion.startCalibration() else {
        throw RemappingMotionCalibrationError.motionUnavailable
      }
    case .pause: device.motion.motion.pauseCalibration()
    case .reset: device.motion.motion.resetCalibration()
    }
    devices[identifier] = device
    return RemappingMotionCalibrationStatus(
      hasMotionBaseline: device.motion.motion.latest != nil,
      isCollecting: device.motion.motion.isManuallyCalibrating,
      offsetDegreesPerSecond: device.motion.motion.calibrationOffset
    )
  }
}
