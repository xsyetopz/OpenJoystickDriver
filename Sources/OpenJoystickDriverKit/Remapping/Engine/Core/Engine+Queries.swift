public import Foundation

extension RemappingEventEngine {
  /// Whether any output needs a future tick.
  ///
  /// Held keys and pointer buttons alone need none. A faulted engine reports `false`, because
  /// fail-closed handling clears all mapping state.
  public func hasScheduledOutput() -> Bool { state.hasScheduledOutput }

  /// Returns whether a `Pause` has the controller pass through unmapped.
  public func isPaused(_ identifier: LogicalControllerID) -> Bool {
    state.devices[identifier]?.isPaused == true
  }

  /// Returns the motion calibration status of a controller, or `nil` when it has no mapping
  /// session.
  public func motionCalibrationStatus(
    for identifier: LogicalControllerID
  ) -> RemappingMotionCalibrationStatus? { state.motionCalibrationStatus(for: identifier) }

  /// Returns the identifier of the current mapping session of a controller, or `nil` without one.
  ///
  /// A profile replacement or a release ends a session and its identifier.
  public func motionSessionIdentifier(for identifier: LogicalControllerID) -> UUID? {
    state.devices[identifier]?.sessionID
  }

  /// Returns the earliest forward-only deadline required by scheduled output, or `nil` when none
  /// is.
  ///
  /// Turbo deadlines are exact phase boundaries. Continuous destinations use the caller-owned
  /// cadence because their platform scaling and delivery rate are adapter policy. Arithmetic
  /// saturates at `UInt64.max`.
  /// - Parameters:
  ///   - uptimeNanoseconds: The current forward-only uptime in nanoseconds.
  ///   - continuousIntervalNanoseconds: Interval between ticks of continuous output.
  /// - Returns: The earliest deadline in forward-only nanoseconds, or `nil` when no output is
  ///   scheduled.
  public func nextScheduledTick(
    after uptimeNanoseconds: UInt64,
    continuousIntervalNanoseconds: UInt64
  ) -> UInt64? {
    state.nextScheduledTick(
      after: uptimeNanoseconds,
      continuousIntervalNanoseconds: continuousIntervalNanoseconds
    )
  }
}
