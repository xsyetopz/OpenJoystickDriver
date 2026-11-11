import Foundation

/// The virtual-device path: every ``OutputDispatcher`` is an ``OutputSink`` for controller frames,
/// and for gamepad frames when it is also a ``RemappingGamepadSink``.
extension OutputDispatcher {
  /// The virtual device.
  public var destination: OutputDestination { .virtualDevice }

  /// Passes the frame to the dispatcher.
  ///
  /// - Throws: ``StreamBoundaryError/unsupported(_:)`` for a frame the dispatcher does not take, or
  ///   the error of the dispatcher.
  @preconcurrency
  public func consume(
    _ frame: StreamFrame,
    onDelivered: @escaping @Sendable () -> Void
  ) async throws {
    switch frame {
    case .controller(let event, let identifier):
      try await dispatchPublishing(
        event,
        from: identifier,
        onPublished: onDelivered
      )
    case .gamepad(let state, let identifier):
      guard let sink = self as? any RemappingGamepadSink else {
        throw StreamBoundaryError.unsupported(destination)
      }
      try await sink.send(state, for: identifier)
      onDelivered()
    case .activation(let identifier):
      await activateOutput(for: identifier)
      onDelivered()
    case .observed, .feed:
      throw StreamBoundaryError.unsupported(destination)
    }
  }
}
