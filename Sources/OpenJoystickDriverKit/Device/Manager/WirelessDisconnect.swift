import Foundation

/// What the host's Bluetooth stack reports for a request to disconnect a wireless controller.
public enum WirelessControllerDisconnectOutcome: Sendable, Equatable {
  /// The host closed the link and confirmed the disconnection.
  case disconnected
  /// The host rejected the disconnect with a status code of its Bluetooth stack.
  case failed(Int32)
  /// The host reported the controller still connected after the close.
  case stillConnected
  /// The host did not confirm the disconnection before the timeout.
  case timedOut
}

/// Disconnects a wireless controller at the host's Bluetooth stack.
public protocol WirelessControllerDisconnecting: Sendable {
  /// Disconnects the controller at `address` and waits up to `timeoutNanoseconds` for the host to
  /// confirm it.
  func disconnect(
    address: String,
    timeoutNanoseconds: UInt64
  ) async -> WirelessControllerDisconnectOutcome
}
