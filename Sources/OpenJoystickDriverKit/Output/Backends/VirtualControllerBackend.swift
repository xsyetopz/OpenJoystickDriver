import Foundation

/// Stable identifiers for virtual controller output backends.
public enum VirtualControllerBackendID: String, CaseIterable, Sendable {
  case driverKitHID
  case userSpaceHID
  case gameControllerHID
}

/// Static capability description used by diagnostics and backend acceptance loops.
public struct VirtualControllerBackendCapabilities: Equatable, Sendable {
  public let isSystemWide: Bool
  public let supportsMultiplePhysicalControllers: Bool
  public let requiresEntitlement: Bool
  public let isImplemented: Bool
  /// Whether this backend publishes a controller that games and other consumers can open.
  public let publishesConsumerGamepad: Bool
  public let notes: String

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
  public let id: VirtualControllerBackendID
  public let isRunning: Bool
  public let detail: String

  public init(id: VirtualControllerBackendID, isRunning: Bool, detail: String) {
    self.id = id
    self.isRunning = isRunning
    self.detail = detail
  }
}

/// Output backend contract for publishing normalized controller state to macOS consumers.
public protocol VirtualControllerBackend: OutputDispatcher {
  var backendID: VirtualControllerBackendID { get }
  var capabilities: VirtualControllerBackendCapabilities { get }

  @discardableResult func startBackend() async -> VirtualControllerBackendStatus
  func stopBackend() async
  func backendStatus() -> VirtualControllerBackendStatus
}

public enum VirtualControllerBackendCatalog {
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
  public var backendID: VirtualControllerBackendID { .userSpaceHID }

  public var capabilities: VirtualControllerBackendCapabilities {
    VirtualControllerBackendCapabilities(
      isSystemWide: true,
      supportsMultiplePhysicalControllers: true,
      requiresEntitlement: true,
      isImplemented: true,
      notes: "IOHIDUserDevice compatibility output path."
    )
  }

  public func startBackend() -> VirtualControllerBackendStatus {
    VirtualControllerBackendStatus(id: backendID, isRunning: true, detail: status)
  }

  public func stopBackend() { close() }

  public func backendStatus() -> VirtualControllerBackendStatus {
    VirtualControllerBackendStatus(id: backendID, isRunning: status != "off", detail: status)
  }
}
