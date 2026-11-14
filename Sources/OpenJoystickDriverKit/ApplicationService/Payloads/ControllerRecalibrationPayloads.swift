import Foundation

/// What `recalibrateController` does: a calibration step, or a reset of the stored calibration.
public enum ControllerRecalibrationAction: String, Codable, CaseIterable, Sendable {
  /// Sticks and triggers released: stores the stick centres and the trigger rests.
  case rest = "Rest"
  /// Each stick moved through its full circle: stores the stick ranges.
  case circle = "Circle"
  /// Each trigger pressed fully: stores the trigger ends.
  case triggers = "Triggers"
  /// Removes the stored centres, ranges, and trigger ends, and clears the gyro offset.
  case reset = "Reset"

  /// The action that runs `step`.
  public init(_ step: ControllerCalibration.Step) {
    switch step {
    case .rest: self = .rest
    case .circle: self = .circle
    case .triggers: self = .triggers
    }
  }

  /// The step this action measures; nil for `reset`.
  public var step: ControllerCalibration.Step? {
    switch self {
    case .rest: .rest
    case .circle: .circle
    case .triggers: .triggers
    case .reset: nil
    }
  }
}

/// Arguments of `recalibrateController`: the controller and the action to run on it.
public struct ControllerRecalibrationArguments: Codable, Sendable {
  /// The controller the action runs on.
  public let controller: ControllerReference
  /// The action to run.
  public let action: ControllerRecalibrationAction

  /// Creates the arguments from a controller and an action.
  public init(controller: ControllerReference, action: ControllerRecalibrationAction) {
    self.controller = controller
    self.action = action
  }
}

/// Why a `recalibrateController` request changed nothing.
public enum ControllerRecalibrationFailure: String, Codable, Equatable, Sendable {
  /// No connected controller, or more than one, matches the reference.
  case controllerUnavailable
  /// No record of the controller's model exists, so there is nowhere to store the calibration.
  case noRecord
  /// The user record, or the record with the calibration set, is invalid.
  case invalidRecord
  /// The user record cannot be written.
  case persistenceFailed
}

/// Result of `recalibrateController`.
public struct ControllerRecalibrationResult: Codable, Equatable, Sendable {
  /// The action the request ran.
  public let action: ControllerRecalibrationAction
  /// The values the step stored; empty for `reset`.
  public let stored: ControllerCalibration
  /// The keys `reset` removed from the user record.
  public let cleared: [ControllerTuning.Key]
  /// The controls that did not move enough to measure, whose stored values stay.
  public let unmoved: [Control]
  /// Whether `reset` cleared the gyro offset; false for a controller with no active gyro profile.
  public let gyroOffsetCleared: Bool
  /// Why the request stored nothing; nil when it succeeded.
  public let failure: ControllerRecalibrationFailure?
  /// The problem text of `invalidRecord` or `persistenceFailed`.
  public let detail: String?

  /// Creates the result from its values.
  public init(
    action: ControllerRecalibrationAction,
    stored: ControllerCalibration = .none,
    cleared: [ControllerTuning.Key] = [],
    unmoved: [Control] = [],
    gyroOffsetCleared: Bool = false,
    failure: ControllerRecalibrationFailure? = nil,
    detail: String? = nil
  ) {
    self.action = action
    self.stored = stored
    self.cleared = cleared
    self.unmoved = unmoved
    self.gyroOffsetCleared = gyroOffsetCleared
    self.failure = failure
    self.detail = detail
  }
}
