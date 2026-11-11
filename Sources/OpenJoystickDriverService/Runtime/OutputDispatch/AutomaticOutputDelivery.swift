import OpenJoystickDriverKit

/// What one automatic dispatch publishes through the backend it leased.
enum AutomaticOutputDelivery: Sendable {
  /// An input event of the controller.
  case input(ControllerEvent)
  /// The activation of the controller's output.
  case activation
  /// A gamepad state from the remapping engine.
  case remapped(RemappingGamepadState)

  /// Publishes the delivery through `backend` for `identifier`; `onPublished` runs for an input
  /// event once it has been published.
  ///
  /// - Throws: ``RemappingEventEngineError/sinkUnavailable`` when a remapped state meets a backend
  ///   that takes none, or the failure of the backend.
  func publish(
    through backend: any VirtualOutputDispatching,
    for identifier: LogicalControllerID,
    onPublished: @escaping @Sendable () -> Void = {}
  ) async throws {
    switch self {
    case .remapped(let state):
      guard let sink = backend as? any RemappingGamepadSink else {
        throw RemappingEventEngineError.sinkUnavailable
      }
      try await sink.send(state, for: identifier)
    case .input(let event):
      try await backend.dispatchPublishing(
        event,
        from: identifier,
        onPublished: onPublished
      )
    case .activation: try await backend.activateOutputReportingFailure(for: identifier)
    }
  }
}
