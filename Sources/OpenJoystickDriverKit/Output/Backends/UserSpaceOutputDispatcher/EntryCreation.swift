import Foundation

extension UserSpaceOutputDispatcher {
  /// Creates the device for `identifier` with `identity`, then publishes it with the host's report handler
  /// attached.
  ///
  /// A dispatcher closed in between releases the device without publishing it.
  internal func createEntry(for identifier: LogicalControllerID,
    identity: VirtualDeviceIdentity
  ) async throws -> Entry {
    guard lifecycle.isOpen else { throw CancellationError() }
    let backend = try await backendFactory(identifier, identity)
    guard lifecycle.isOpen else {
      backend.close()
      throw CancellationError()
    }
    let inputReportState = UserSpaceInputReportState(format: format)
    let entry = Entry(
      backend: backend,
      inputReportState: inputReportState,
      frameQueueCapacity: VirtualGamepadReportMapping.frameQueueCapacity(for: identifier)
    )
    backend.activate(
      hostReports: hostReportHandler(
        identifier: identifier,
        input: inputReportState,
        sender: entry.sender
      )
    )
    print("[UserSpaceOutputDispatcher] Created virtual device for \(identifier)")
    return entry
  }

  /// The handler that answers the host's report requests for the device of `identifier`.
  internal func hostReportHandler(
    identifier: LogicalControllerID,
    input: UserSpaceInputReportState,
    sender: UserSpaceReportSender
  ) -> UserSpaceHostReportHandler {
    let isOpen: @Sendable () -> Bool = { [lifecycle] in lifecycle.isOpen }
    return UserSpaceHostReportHandler(
      identifier: identifier,
      input: input,
      sender: sender,
      isOpen: isOpen,
      onOutput: onOutputCommand
    ) { [weak self] status in self?.registryLock.withLock { self?._lastRumbleStatus = status } }
  }
}
