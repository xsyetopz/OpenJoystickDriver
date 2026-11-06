import Foundation

/// Stable identifiers for virtual controller output backends.
public enum VirtualControllerBackendID: String, CaseIterable, Sendable {
  /// The user-space HID backend, which publishes an `IOHIDUserDevice`.
  case userSpaceHID
  /// The user-space HID backend with the `apple-gamecontroller` identity.
  case gameControllerHID
}

/// Static capability description used by diagnostics and backend acceptance loops.
public struct VirtualControllerBackendCapabilities: Equatable, Sendable {
  /// Whether the published controller is visible system-wide.
  public let isSystemWide: Bool
  /// Whether the backend can serve several physical controllers.
  public let supportsMultiplePhysicalControllers: Bool
  /// Whether the backend needs an entitlement.
  public let requiresEntitlement: Bool
  /// Whether the backend is available.
  public let isImplemented: Bool
  /// Whether this backend publishes a controller that games and other consumers can open.
  public let publishesConsumerGamepad: Bool
  /// A note for diagnostics.
  public let notes: String

  /// Creates a capability description from its fields.
  public init(
    isSystemWide: Bool,
    supportsMultiplePhysicalControllers: Bool,
    requiresEntitlement: Bool,
    isImplemented: Bool,
    publishesConsumerGamepad: Bool = true,
    notes: String
  ) {
    self.isSystemWide = isSystemWide
    self.supportsMultiplePhysicalControllers = supportsMultiplePhysicalControllers
    self.requiresEntitlement = requiresEntitlement
    self.isImplemented = isImplemented
    self.publishesConsumerGamepad = publishesConsumerGamepad
    self.notes = notes
  }
}

/// Runtime status for one virtual controller backend.
public struct VirtualControllerBackendStatus: Equatable, Sendable {
  /// The backend the status is about.
  public let id: VirtualControllerBackendID
  /// Whether the backend is running.
  public let isRunning: Bool
  /// The backend's own status text.
  public let detail: String

  /// Creates a status from its fields.
  public init(id: VirtualControllerBackendID, isRunning: Bool, detail: String) {
    self.id = id
    self.isRunning = isRunning
    self.detail = detail
  }
}

/// Output backend contract for publishing normalized controller state to macOS consumers.
public protocol VirtualControllerBackend: OutputDispatcher {
  /// Which backend this is.
  var backendID: VirtualControllerBackendID { get }
  /// What the backend can do.
  var capabilities: VirtualControllerBackendCapabilities { get }

  /// Starts the backend and returns its status.
  @discardableResult
  func startBackend() async -> VirtualControllerBackendStatus
  /// Stops the backend.
  func stopBackend() async
  /// The backend's current status.
  func backendStatus() -> VirtualControllerBackendStatus
}

/// The capabilities of the backends that the Kit lists.
public enum VirtualControllerBackendCatalog {
  /// The capabilities of the ``VirtualControllerBackendID/gameControllerHID`` backend.
  public static let gameControllerHIDCapabilities = VirtualControllerBackendCapabilities(
    isSystemWide: true,
    supportsMultiplePhysicalControllers: true,
    requiresEntitlement: true,
    isImplemented: true,
    notes: "Apple GameController.framework support uses the user-space HID "
      + "backend with the apple-gamecontroller identity."
  )
}

extension UserSpaceOutputDispatcher: VirtualControllerBackend {
  /// The user-space HID backend.
  public var backendID: VirtualControllerBackendID { .userSpaceHID }

  /// What the user-space HID backend can do.
  public var capabilities: VirtualControllerBackendCapabilities {
    VirtualControllerBackendCapabilities(
      isSystemWide: true,
      supportsMultiplePhysicalControllers: true,
      requiresEntitlement: true,
      isImplemented: true,
      notes: "IOKit IOHIDUserDevice output on every supported macOS."
    )
  }

  /// Starts the backend and returns its status.
  public func startBackend() -> VirtualControllerBackendStatus {
    VirtualControllerBackendStatus(id: backendID, isRunning: true, detail: status.wireValue)
  }

  /// Closes the dispatcher.
  public func stopBackend() async { await close() }

  /// The current status of the backend.
  public func backendStatus() -> VirtualControllerBackendStatus {
    VirtualControllerBackendStatus(
      id: backendID,
      isRunning: status != .off,
      detail: status.wireValue
    )
  }
}
