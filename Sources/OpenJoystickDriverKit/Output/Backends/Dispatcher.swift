import Foundation

/// Takes parsed controller events and sends them to an output target.
///
/// Implement this inward-owned port to decide what happens when controller state changes.
/// Production adapters live in their owning transport targets; the kit provides
/// ``LoggingOutputDispatcher`` for diagnostics.
public protocol OutputDispatcher: AnyObject, Sendable {
  /// When `true`, all report/event output is suppressed (e.g. during developer
  /// packet capture). Implementations should invalidate any cached state on change.
  var suppressOutput: Bool { get set }

  /// Receives a batch of events from one controller and writes them to the output.
  ///
  /// Called by ``DevicePipeline`` every time the parser produces new events.
  /// - Parameters:
  ///   - events: The controller events to process.
  ///   - identifier: Which controller the events came from.
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async
}
