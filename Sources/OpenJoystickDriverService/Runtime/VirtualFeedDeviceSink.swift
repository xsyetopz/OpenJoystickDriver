import Foundation
import OpenJoystickDriverKit

/// The virtual device of one feed as the sink of the feed's frames.
final class VirtualFeedDeviceSink: OutputSink {
  /// Marks the frames as delivered to a virtual device.
  let destination = OutputDestination.virtualDevice
  /// The device that takes the frames.
  private let device: any VirtualFeedDevice

  /// Creates a sink for `device`.
  init(_ device: any VirtualFeedDevice) { self.device = device }

  /// Sends the gamepad state of `frame` to the device.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)`` for a frame that is not a gamepad state, or
  ///   the failure of the device.
  func consume(
    _ frame: StreamFrame,
    onDelivered: @Sendable () -> Void
  ) async throws {
    guard case .gamepad(let state, let identifier) = frame else {
      throw StreamBoundaryError.unsupported(destination)
    }
    try await device.send(state, for: identifier)
    onDelivered()
  }
}
