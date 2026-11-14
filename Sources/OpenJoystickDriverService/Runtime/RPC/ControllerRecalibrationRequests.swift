import Foundation
public import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// How long a step reads raw input, and the time between two reads.
  private static let sampleCount = 40
  private static let sampleIntervalNanoseconds: UInt64 = 50_000_000

  /// Runs the recalibration `arguments` names on the controller they name.
  ///
  /// A step reads raw input for about two seconds and stores what it measured in the model's user
  /// record; the gyro step stores the mean angular velocity and stores nothing for a controller
  /// with no gyro. `reset` removes the stored values and clears the gyro bias estimate.
  public func recalibrateController(
    _ arguments: ControllerRecalibrationArguments
  ) async -> ControllerRecalibrationResult {
    guard let identifier = await deviceManager.connectedIdentifier(for: arguments.controller)
    else {
      return ControllerRecalibrationResult(
        action: arguments.action,
        failure: .controllerUnavailable
      )
    }
    var samples: [ControllerState] = []
    var gyro: [ControllerMotionVector] = []
    if arguments.action.step != nil {
      for _ in 0..<Self.sampleCount {
        if let state = await deviceManager.rawControllerState(for: identifier) {
          samples.append(state)
        }
        if let rate = await deviceManager.rawAngularVelocity(for: identifier) { gyro.append(rate) }
        try? await Task.sleep(nanoseconds: Self.sampleIntervalNanoseconds)
      }
    }
    var gyroOffsetCleared = false
    if arguments.action == .reset {
      let status = await remappingRequests.motionCalibration(
        ApplicationServiceMotionCalibrationArguments(
          controller: arguments.controller,
          command: .reset
        )
      )
      if case .success = status { gyroOffsetCleared = true }
    }
    let result = Self.recalibrate(
      arguments.action,
      model: identifier.model,
      samples: samples,
      gyro: gyro,
      stored: DeviceCatalog.current.withLock { $0.calibration(of: identifier.model) },
      gyroOffsetCleared: gyroOffsetCleared
    )
    if result.failure == nil { NotificationCenter.postServiceStatusChanged(from: self) }
    return result
  }

  /// Writes what `action` measures from `samples` and `gyro`, or removes the stored values for
  /// `reset`, in the user record of `model` in `directory`; `stored` gives the centres and rests a
  /// later step measures from.
  static func recalibrate(
    _ action: ControllerRecalibrationAction,
    model: ControllerModelID,
    samples: [ControllerState],
    gyro: [ControllerMotionVector] = [],
    stored: ControllerCalibration,
    gyroOffsetCleared: Bool = false,
    directory: URL = ControllerRecordSet.userDirectory
  ) -> ControllerRecalibrationResult {
    func write(_ key: ControllerTuning.Key, _ value: Double?) -> ControllerTuningResult {
      setControllerTuning(
        vendorID: Int(model.vendorID),
        productID: Int(model.productID),
        key: key,
        value: value,
        directory: directory
      )
    }
    func failed(_ result: ControllerTuningResult) -> ControllerRecalibrationResult {
      ControllerRecalibrationResult(
        action: action,
        gyroOffsetCleared: gyroOffsetCleared,
        failure: result.failure.map {
          switch $0 {
          case .noRecord: .noRecord
          case .persistenceFailed: .persistenceFailed
          case .invalidRecord, .notSet, .invalidRequest: .invalidRecord
          }
        },
        detail: result.detail
      )
    }
    guard let step = action.step else {
      var cleared: [ControllerTuning.Key] = []
      for key in ControllerCalibration.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        let result = write(key, nil)
        switch result.failure {
        case nil: cleared.append(key)
        case .notSet: continue
        default: return failed(result)
        }
      }
      return ControllerRecalibrationResult(
        action: action,
        cleared: cleared,
        gyroOffsetCleared: gyroOffsetCleared
      )
    }
    let outcome = ControllerCalibration.capture(step, samples: samples, gyro: gyro, stored: stored)
    for (key, value) in outcome.values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      let result = write(key, value)
      if result.failure != nil { return failed(result) }
    }
    return ControllerRecalibrationResult(
      action: action,
      stored: ControllerCalibration(values: outcome.values),
      unmoved: outcome.unmoved
    )
  }
}
