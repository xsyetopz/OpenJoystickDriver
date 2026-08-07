import Foundation

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
