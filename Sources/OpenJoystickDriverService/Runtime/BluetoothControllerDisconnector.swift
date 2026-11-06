import Foundation
import IOBluetooth
import OpenJoystickDriverKit

/// Disconnects a wireless controller through IOBluetooth within a time limit.
final class BluetoothControllerDisconnector: WirelessControllerDisconnecting, Sendable {
  /// What closing a Bluetooth connection reported.
  struct CloseResult: Sendable, Equatable {
    /// The status of the close call.
    let status: IOReturn
    /// Whether the device is still connected.
    let isConnected: Bool
  }

  /// Closes the connection of an address within a timeout in nanoseconds.
  private let closeConnection: @Sendable (String, UInt64) -> CloseResult

  /// Creates a disconnector that closes connections with `closeConnection`; by default the closing
  /// call of IOBluetooth, which waits for the device to disconnect.
  init(
    closeConnection: @escaping @Sendable (String, UInt64) -> CloseResult = { address, timeout in
      guard let device = IOBluetoothDevice(addressString: address) else {
        return CloseResult(status: kIOReturnNotFound, isConnected: false)
      }
      let status = device.closeConnection()
      guard status == kIOReturnSuccess else {
        return CloseResult(status: status, isConnected: device.isConnected())
      }
      let deadline = DispatchTime.now().uptimeNanoseconds &+ timeout
      while device.isConnected(), DispatchTime.now().uptimeNanoseconds < deadline {
        Thread.sleep(forTimeInterval: 0.02)
      }
      return CloseResult(status: status, isConnected: device.isConnected())
    }
  ) { self.closeConnection = closeConnection }

  /// Disconnects the controller at `address` and reports how it ended.
  ///
  /// The outcome is `timedOut` when the close takes longer than `timeoutNanoseconds`.
  func disconnect(
    address: String,
    timeoutNanoseconds: UInt64
  ) async -> WirelessControllerDisconnectOutcome {
    let outcomes = AsyncStream<WirelessControllerDisconnectOutcome> { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let result = self.closeConnection(address, timeoutNanoseconds)
        let outcome: WirelessControllerDisconnectOutcome
        if result.status != kIOReturnSuccess {
          outcome = .failed(result.status)
        } else if result.isConnected {
          outcome = .stillConnected
        } else {
          outcome = .disconnected
        }
        continuation.yield(outcome)
        continuation.finish()
      }
      // A GCD timer, like the close above, so the timeout does not wait for a cooperative thread.
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + .nanoseconds(Int(clamping: timeoutNanoseconds))
      ) {
        continuation.yield(.timedOut)
        continuation.finish()
      }
    }
    for await outcome in outcomes { return outcome }
    return .failed(kIOReturnError)
  }
}
