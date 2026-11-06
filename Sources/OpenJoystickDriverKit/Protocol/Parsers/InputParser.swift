import Foundation

/// Whether a receiver-backed controller has a logical controller connected.
///
/// A receiver reports logical controller connect and disconnect independently of the HID device
/// that carries the reports.
public enum ControllerInputConnectionState: Sendable, Equatable {
  /// A logical controller is connected.
  case connected
  /// No logical controller is connected.
  case disconnected
}

/// How current a controller's input reports are.
public enum ControllerInputHealthState: String, Codable, Sendable {
  /// Reports arrive and advance.
  case healthy = "Healthy"
  /// Reports have stopped arriving or advancing.
  case stale = "Stale"
  /// The controls must return to neutral first.
  case waitingForNeutral = "WaitingForNeutral"
}

/// Why a controller's input is not healthy.
public enum ControllerInputHealthFailureReason: String, Codable, CaseIterable, Sendable {
  /// No input report arrived.
  case missingReports = "MissingReports"
  /// Reports arrive, but their freshness does not advance.
  case freshnessNotAdvancing = "FreshnessNotAdvancing"
  /// No input since the session started from a controller that sends none until its home button
  /// is pressed (``InputStartAction/pressGuide``).
  case guideNotPressed = "GuideNotPressed"
}

/// What the user does before a controller sends its first input report; the family's protocol
/// description names it (`inputStart`).
public enum InputStartAction: String, Sendable {
  /// Press the home button: the PS button of a USB DualShock 3.
  case pressGuide = "PressGuide"
}

/// A controller's input report health, for diagnostics.
public struct ControllerInputHealth: Codable, Sendable {
  /// The health state.
  public let state: ControllerInputHealthState
  /// The wire format of the latest input report; nil until one arrives.
  public let reportFormat: String?
  /// The age of the latest input report in nanoseconds; nil until one arrives.
  public let lastReportAgeNanoseconds: UInt64?
  /// Why the input is not healthy; nil when it is.
  public let failureReason: ControllerInputHealthFailureReason?
  /// How many times input recovered during the session.
  public let recoveryCount: Int

  /// Creates the health of a controller's input.
  public init(
    state: ControllerInputHealthState,
    reportFormat: String? = nil,
    lastReportAgeNanoseconds: UInt64? = nil,
    failureReason: ControllerInputHealthFailureReason? = nil,
    recoveryCount: Int = 0
  ) {
    self.state = state
    self.reportFormat = reportFormat
    self.lastReportAgeNanoseconds = lastReportAgeNanoseconds
    self.failureReason = failureReason
    self.recoveryCount = recoveryCount
  }
}
