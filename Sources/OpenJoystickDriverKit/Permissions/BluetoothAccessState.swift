import Foundation

/// The state of the Bluetooth access that the service needs to connect Switch 2 controllers.
public enum BluetoothAccessState: String, Codable, Sendable, Equatable {
  /// The user has not been asked.
  case notAsked
  /// The user allowed Bluetooth.
  case granted
  /// The user denied Bluetooth.
  case denied
  /// A policy of the Mac restricts Bluetooth, and the user cannot change that.
  case restricted
  /// The service has no Bluetooth access to ask for.
  case unavailable

  /// Whether the user can still act on it: ask for it, or allow it in System Settings.
  public var needsStep: Bool { self == .notAsked || self == .denied }
}
