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
  /// Starts sending one input report and calls `completion` once with the outcome, without
  /// waiting for the send.
  ///
  /// - Returns: A closure that asks the send to stop; a send may ignore it.
  func startSend(
    _ report: [UInt8],
    completion: @escaping @Sendable (Result<Void, any Error>) -> Void
  ) -> @Sendable () -> Void
  /// Takes the device away from the host.
  func close()
  /// Returns once the native device is gone. Backends without async teardown return at once.
  func waitUntilClosed() async
}

/// A virtual device whose native send blocks the calling thread until the host takes the report.
///
/// The report sender calls ``sendBlocking(_:)`` on its own serial queue instead of
/// ``VirtualDeviceBackend/startSend(_:completion:)``, so a report costs no extra thread wake.
package protocol BlockingVirtualDeviceBackend: VirtualDeviceBackend {
  /// Sends one input report and returns once the host took it.
  ///
  /// - Throws: The backend's error when the host cannot take the report.
  func sendBlocking(_ report: [UInt8]) throws
}

extension VirtualDeviceBackend {
  /// Yields once and returns, for a backend with no async teardown.
  package func waitUntilClosed() async { await Task.yield() }

  /// Runs ``send(_:)`` in an unstructured task, so a send that ignores cancellation never holds
  /// the caller; the returned closure cancels that task.
  package func startSend(
    _ report: [UInt8],
    completion: @escaping @Sendable (Result<Void, any Error>) -> Void
  ) -> @Sendable () -> Void {
    let task = Task.detached { [self] in
      do {
        try await send(report)
        completion(.success(()))
      } catch { completion(.failure(error)) }
    }
    return { task.cancel() }
  }
}

/// Creates the native virtual HID device for one controller.
///
/// The host platform implements it.
package protocol VirtualHIDDevicePublisher: Sendable {
  /// Creates the unpublished device that `profile` and `format` describe for `identifier`, with
  /// the serial number and LocationID of `identity`.
  /// Throws when the host refuses to create it.
  func createDevice(
    for identifier: LogicalControllerID,
    identity: VirtualDeviceIdentity,
    profile: VirtualDeviceProfile,
    format: any VirtualGamepadReportFormat
  ) throws -> any VirtualDeviceBackend
}
