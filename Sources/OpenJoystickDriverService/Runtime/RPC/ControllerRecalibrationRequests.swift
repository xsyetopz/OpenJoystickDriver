import Foundation
public import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Runs the recalibration `arguments` names on the controller they name.
  ///
  /// A step reads raw input for about two seconds and stores what it measured in the `unit` patch
  /// of the controller's port key, or in the model's user record for a controller with no port
  /// key; the gyro step stores the mean angular velocity and stores nothing for a controller with
  /// no gyro. `reset` removes the unit's stored values and the model's, and clears the gyro bias
  /// estimate.
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
      for _ in 0..<ControllerRecalibrationAction.sampleCount {
        if let state = await deviceManager.rawControllerState(for: identifier) {
          samples.append(state)
        }
        if let rate = await deviceManager.rawAngularVelocity(for: identifier) { gyro.append(rate) }
        try? await Task.sleep(nanoseconds: ControllerRecalibrationAction.sampleIntervalNanoseconds)
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
    let unit = ControllerPortKey.of(identifier, installationKey: installationKey)
    let result = Self.recalibrate(
      arguments.action,
      model: identifier.model,
      unit: unit,
      samples: samples,
      gyro: gyro,
      stored: DeviceCatalog.current.withLock { $0.calibration(of: identifier.model, unit: unit) },
      gyroOffsetCleared: gyroOffsetCleared
    )
    if result.failure == nil { NotificationCenter.postServiceStatusChanged(from: self) }
    return result
  }

  /// Writes what `action` measures from `samples` and `gyro` in the `unit` patch of `model` in
  /// `directory`, or in the model's user record when `unit` is nil; `stored` gives the centres and
  /// rests a later step measures from.
  ///
  /// `reset` removes the stored values of the unit and of the model, because a value the model
  /// stores applies to every unit of it.
  static func recalibrate(
    _ action: ControllerRecalibrationAction,
    model: ControllerModelID,
    unit: ControllerPortKey? = nil,
    samples: [ControllerState],
    gyro: [ControllerMotionVector] = [],
    stored: ControllerCalibration,
    gyroOffsetCleared: Bool = false,
    directory: URL = ControllerRecordSet.userDirectory
  ) -> ControllerRecalibrationResult {
    func write(
      _ key: ControllerTuning.Key,
      _ value: Double?,
      to target: ControllerRecordWriter.Target? = nil
    ) -> ControllerTuningResult {
      let unitTarget = unit.map { ControllerRecordWriter.Target.unit(model, $0) }
      return setControllerTuning(
        target ?? unitTarget ?? .model(model),
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
      let targets: [ControllerRecordWriter.Target] =
        [.model(model)] + (unit.map { [.unit(model, $0)] } ?? [])
      for key in ControllerCalibration.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        var removed = false
        for target in targets {
          let result = write(key, nil, to: target)
          switch result.failure {
          case nil: removed = true
          case .notSet: continue
          default: return failed(result)
          }
        }
        if removed { cleared.append(key) }
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
