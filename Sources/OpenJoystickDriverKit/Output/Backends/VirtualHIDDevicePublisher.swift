import Foundation

/// One native virtual HID device that the user-space dispatcher feeds.
package protocol VirtualDeviceBackend: AnyObject, Sendable {
  /// Starts answering the host's get and set report requests through `hostReports`, then
  /// publishes the device. Called once, before the first ``send(_:)``.
  func activate(hostReports: UserSpaceHostReportHandler)
  /// Sends one input report to the host.
  ///
  /// - Throws: The backend's error when the host cannot take the report.
  func send(_ report: [UInt8]) async throws
  /// Takes the device away from the host.
  func close()
  /// Returns once the native device is gone. Backends without async teardown return at once.
  func waitUntilClosed() async
}

extension VirtualDeviceBackend {
  /// Yields once and returns, for a backend with no async teardown.
  package func waitUntilClosed() async { await Task.yield() }
}

/// Creates the native virtual HID device for one controller.
///
/// The host platform implements it.
package protocol VirtualHIDDevicePublisher: Sendable {
  /// Creates the unpublished device that `profile` and `format` describe for `identifier`.
  /// Throws when the host refuses to create it.
  func createDevice(
    for identifier: LogicalControllerID,
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat
  ) throws -> any VirtualDeviceBackend
}
