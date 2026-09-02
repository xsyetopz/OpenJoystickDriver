import Foundation

/// Common interface for Compatibility virtual HID outputs.
public protocol CompatibilityUserSpaceOutputDispatching: OutputDispatcher {
  /// Human-readable backend status for UI/CLI reporting.
  var status: String { get }
  /// Most recent app-originated rumble report summary, or `"none"`.
  var lastRumbleStatus: String { get }
  /// Tears down any user-space virtual HID devices owned by this output.
  func setOutputSuppressed(_ suppressed: Bool) async
  func close() async
}

/// Optional output-dispatcher hook for controller lifecycle events.
///
/// `DevicePipeline` calls this when a physical controller pipeline stops so output backends
/// can tear down any per-controller virtual devices.
public protocol ControllerLifecycleListener: AnyObject, Sendable {
  func controllerDidStop(_ identifier: DeviceIdentifier) async
}

public extension CompatibilityUserSpaceOutputDispatching {
  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
}

/// Takes parsed controller events and sends them to an output target.
///
/// Implement this inward-owned port to decide what happens when controller state changes.
/// Production adapters live in their owning transport targets; the kit provides
/// ``LoggingOutputDispatcher`` for diagnostics.
public protocol OutputDispatcher: AnyObject, Sendable {
  /// When `true`, all report/event output is suppressed (e.g. during developer
  /// packet capture). Implementations should invalidate any cached state on change.
  var suppressOutput: Bool { get set }
  func setOutputSuppressed(_ suppressed: Bool) async

  /// Receives a batch of events from one controller and writes them to the output.
  ///
  /// Called by ``DevicePipeline`` every time the parser produces new events.
  /// - Parameters:
  ///   - events: The controller events to process.
  ///   - identifier: Which controller the events came from.
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async
}

public extension OutputDispatcher {
  func setOutputSuppressed(_ suppressed: Bool) { suppressOutput = suppressed }
}

/// OutputDispatcher that logs controller events to debug output.
///
/// Used for hardware validation and testing. Production output uses a transport adapter.
public final class LoggingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  // Suppression is ignored because this dispatcher is only for development.
  /// Accepted but ignored; this dispatcher always logs.
  public var suppressOutput = false

  /// Creates a new LoggingOutputDispatcher.
  public init() {}

  /// Prints each event to standard output.
  public func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    for event in events {
      print("[Output] " + "\(identifier.vendorID):\(identifier.productID)" + " -> \(event)")
    }
  }
}
