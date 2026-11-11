import Foundation

/// The session state of a connected controller.
public enum ControllerSessionState: String, Codable, Equatable, Sendable {
  /// The session publishes the controller's input.
  case active = "Active"
  /// The user suspended the session, so the pipeline does not publish the controller's input.
  case suspended = "Suspended"
}

/// Why a suspend or resume request changed nothing.
public enum ControllerSessionMutationFailure: String, Codable, Equatable, Sendable {
  /// The reference names no connected controller, or its pipeline could not change state.
  case notFound = "not-found"
  /// The session is already suspended.
  case alreadySuspended = "already-suspended"
  /// The session is already active.
  case alreadyActive = "already-active"
}

/// The outcome of suspending a controller's session.
public struct ControllerSuspendResult: Codable, Equatable, Sendable {
  /// The session state after the request.
  public let state: ControllerSessionState
  /// Why the request changed nothing; nil on success.
  public let failure: ControllerSessionMutationFailure?

  /// Creates a result from the session state and the failure, if any.
  public init(state: ControllerSessionState, failure: ControllerSessionMutationFailure? = nil) {
    self.state = state
    self.failure = failure
  }

  /// Whether the controller is suspended and no failure occurred.
  public var succeeded: Bool { state == .suspended && failure == nil }

}

/// The outcome of resuming a controller's session.
public struct ControllerResumeResult: Codable, Equatable, Sendable {
  /// The session state after the request.
  public let state: ControllerSessionState
  /// Why the request changed nothing; nil on success.
  public let failure: ControllerSessionMutationFailure?

  /// Creates a result from the session state and the failure, if any.
  public init(state: ControllerSessionState, failure: ControllerSessionMutationFailure? = nil) {
    self.state = state
    self.failure = failure
  }

  /// Whether the controller is active and no failure occurred.
  public var succeeded: Bool { state == .active && failure == nil }
}

/// Why a request to disconnect a wireless controller left it connected.
public enum WirelessControllerDisconnectFailure: String, Codable, Equatable, Sendable {
  /// The reference names no connected controller, or its session could not be suspended.
  case notFound = "not-found"
  /// The controller's link is not Bluetooth.
  case notBluetooth = "not-bluetooth"
  /// The controller links over Bluetooth LE, which has no supported disconnect path.
  case bluetoothLEUnsupported = "bluetooth-le-unsupported"
  /// The controller has no Bluetooth address or no HID routing address.
  case missingAddress = "missing-address"
  /// The disconnect did not complete: no disconnector is available, a stage failed, or Bluetooth
  /// still reported the controller connected.
  case disconnectFailed = "disconnect-failed"
  /// Bluetooth did not confirm the disconnection before the timeout.
  case timedOut = "timed-out"
}

/// The step of a wireless disconnect that failed.
public enum WirelessControllerDisconnectStage: String, Codable, Equatable, Sendable {
  /// Releasing OJD's HID input claim on the controller.
  case releaseHIDClaim = "release-hid-claim"
  /// Closing the Bluetooth connection.
  case closeBluetoothConnection = "close-bluetooth-connection"
  /// Waiting for Bluetooth to confirm the disconnection.
  case confirmBluetoothDisconnection = "confirm-bluetooth-disconnection"
  /// Reacquiring the HID input claim after a failed disconnect.
  case restoreHIDClaim = "restore-hid-claim"
  /// Resuming the controller session after a failed disconnect.
  case restoreControllerSession = "restore-controller-session"
}

/// The outcome of disconnecting a wireless controller.
public struct WirelessControllerDisconnectResult: Codable, Equatable, Sendable {
  /// The session state after the request.
  public let state: ControllerSessionState
  /// Why the controller stayed connected; nil on success.
  public let failure: WirelessControllerDisconnectFailure?
  /// The step that failed; nil when no step failed.
  public let failedStage: WirelessControllerDisconnectStage?
  /// The code of the Bluetooth stack for a rejected close; nil otherwise.
  public let systemCode: Int32?
  /// The failure as text.
  public let detail: String?
  /// What the user can do to restore the controller's input; nil when nothing failed.
  public let recovery: String?

  /// Creates a result from the session state and the failure details, which default to nil.
  public init(
    state: ControllerSessionState,
    failure: WirelessControllerDisconnectFailure? = nil,
    failedStage: WirelessControllerDisconnectStage? = nil,
    systemCode: Int32? = nil,
    detail: String? = nil,
    recovery: String? = nil
  ) {
    self.state = state
    self.failure = failure
    self.failedStage = failedStage
    self.systemCode = systemCode
    self.detail = detail
    self.recovery = recovery
  }

  /// Whether the disconnect finished without a failure.
  public var succeeded: Bool { failure == nil }
}
