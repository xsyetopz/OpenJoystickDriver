import Foundation

/// The interval between permission checks while polling, in nanoseconds.
private let permissionPollNanoseconds: UInt64 = 1_000_000_000
// TCC needs a short run-loop turn to register the application after the
// Input Monitoring request.  Asking for Accessibility immediately afterwards
// can make macOS skip adding the app to the Input Monitoring list altogether.
/// The pause after the Input Monitoring request, in nanoseconds.
private let inputReadRegistrationDelayNanoseconds: UInt64 = 600_000_000

/// Manages the macOS HID permissions used by OpenJoystickDriver.
public actor PermissionManager {
  /// A permission that OJD requests.
  public enum Requirement: String, Codable, Sendable, Equatable {
    /// Input Monitoring, which reads the physical controllers.
    case inputRead
    /// Accessibility, which publishes the virtual controller output.
    case inputInject
  }

  /// The state of one permission.
  public enum AccessState: String, Codable, CaseIterable, Sendable, Equatable,
    CustomStringConvertible
  {
    /// The permission is granted.
    case granted = "Granted"
    /// The permission is denied.
    case denied = "Denied"
    /// The state of the permission is not known.
    case unknown = "Unknown"

    /// The raw value.
    public var description: String { rawValue }

    /// A short bracketed text for the state.
    public var label: String {
      switch self {
      case .granted: return "[OK]"
      case .denied: return "[DENIED]"
      case .unknown: return "[UNKNOWN]"
      }
    }
  }

  /// Current permission states for physical input and virtual HID publication.
  public struct Snapshot: Codable, Sendable, Equatable {
    /// The state of Input Monitoring.
    public let inputRead: AccessState
    /// The state of Accessibility.
    public let inputInject: AccessState

    /// Creates a snapshot from the two states.
    public init(inputRead: AccessState, inputInject: AccessState) {
      self.inputRead = inputRead
      self.inputInject = inputInject
    }

    /// Whether both permissions are granted.
    public var isReady: Bool { inputRead == .granted && inputInject == .granted }
  }

  /// The last observed state of Input Monitoring.
  public private(set) var inputReadState: AccessState = .unknown
  /// The last observed state of Accessibility.
  public private(set) var inputInjectState: AccessState = .unknown
  /// The last observed state of the post-event permission.
  private(set) var postEventState: RemappingPostEventAccessState
  /// The task that polls while polling runs.
  private(set) var pollingTask: Task<Void, Never>?
  /// The system that reads and requests access.
  private let system: any AccessControlSystem

  /// Reads and requests access through `system`.
  package init(system: any AccessControlSystem) {
    self.system = system
    postEventState = system.postEventAccessState()
  }

  /// Reads the current state of both permissions.
  public func checkAccess() -> Snapshot {
    Snapshot(
      inputRead: system.inputReadAccessState(),
      inputInject: system.inputInjectAccessState()
    )
  }

  /// Reads both permissions, records them and announces a change.
  @discardableResult
  public func refreshAccessState() -> Snapshot {
    let snapshot = checkAccess()
    record(snapshot, postEvent: system.postEventAccessState())
    return snapshot
  }

  /// Stores the observed permission states and announces one status change when any differs.
  func record(_ snapshot: Snapshot, postEvent: RemappingPostEventAccessState) {
    let readChanged = updateState(
      name: "Input read",
      previous: inputReadState,
      current: snapshot.inputRead
    )
    let injectChanged = updateState(
      name: "Input inject",
      previous: inputInjectState,
      current: snapshot.inputInject
    )
    inputReadState = snapshot.inputRead
    inputInjectState = snapshot.inputInject
    let postEventChanged = postEvent != postEventState
    postEventState = postEvent
    if readChanged || injectChanged || postEventChanged {
      NotificationCenter.postServiceStatusChanged(from: self)
    }
  }

  /// Requests every HID permission that is not already granted.
  ///
  /// Input Monitoring is deliberately requested before Accessibility. macOS
  /// registers the caller in the Input Monitoring list asynchronously; a
  /// short delay lets that registration complete before the second request.
  /// The system's request results are deliberately ignored. The
  /// authoritative post-request state is the system's access state.
  @discardableResult
  public func requestRequiredAccess() async -> Snapshot {
    var snapshot = checkAccess()
    if snapshot.inputRead != .granted {
      await requestInputReadOnMainActor()
      try? await Task.sleep(nanoseconds: inputReadRegistrationDelayNanoseconds)
      snapshot = checkAccess()
    }
    if snapshot.inputInject != .granted {
      await requestInputInjectOnMainActor()
    }
    return refreshAccessState()
  }

  /// Requests one permission from the row that owns that permission.
  ///
  /// The request result is never treated as a grant; the returned snapshot is
  /// read back through the system's access state.
  @discardableResult
  public func requestAccess(_ requirement: Requirement) async -> Snapshot {
    let snapshot = checkAccess()
    switch requirement {
    case .inputRead where snapshot.inputRead != .granted:
      await requestInputReadOnMainActor()
      try? await Task.sleep(nanoseconds: inputReadRegistrationDelayNanoseconds)
    case .inputInject where snapshot.inputInject != .granted:
      await requestInputInjectOnMainActor()
    default: break
    }
    return refreshAccessState()
  }

  /// TCC request calls are initiated on the app's main actor.
  ///
  ///  Besides matching AppKit's user-initiated permission flow, this gives macOS a live run loop
  /// for registering the bundle before the settings deep link is opened.
  private func requestInputReadOnMainActor() async {
    let access = system
    await MainActor.run { access.requestInputReadAccess() }
  }

  /// Requests Accessibility on the main actor.
  private func requestInputInjectOnMainActor() async {
    let access = system
    await MainActor.run { access.requestInputInjectAccess() }
  }

  /// Starts to read the permissions every second; a running poll is replaced.
  public func startPolling() {
    pollingTask?.cancel()
    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: permissionPollNanoseconds)
        guard let self else { break }
        await refreshAccessState()
      }
    }
  }

  /// Stops polling.
  public func stopPolling() {
    pollingTask?.cancel()
    pollingTask = nil
  }

  /// Logs a change of one permission and returns whether it changed.
  private func updateState(name: String, previous: AccessState, current: AccessState) -> Bool {
    guard previous != current else { return false }
    print("[PermissionManager] \(name) state changed: \(previous) -> \(current)")
    return true
  }
}

/// One permission that OJD lists for the user.
public struct OJDPermissionRequirement: Sendable, Equatable {
  /// The name of the permission.
  public let name: String
  /// The component that holds the permission.
  public let owner: String
  /// What the permission is for.
  public let purpose: String
  /// Whether OJD requests the permission.
  public let requested: Bool

  /// Creates a requirement from its parts.
  public init(name: String, owner: String, purpose: String, requested: Bool) {
    self.name = name
    self.owner = owner
    self.purpose = purpose
    self.requested = requested
  }

  /// Input Monitoring, held by the app.
  public static let inputRead = Self(
    name: "Input read",
    owner: "OpenJoystickDriver app",
    purpose: "Read input from physical controllers",
    requested: true
  )
  /// Accessibility, held by the app.
  public static let inputInject = Self(
    name: "Input inject",
    owner: "OpenJoystickDriver app",
    purpose: "Publish virtual controller output",
    requested: true
  )
  /// Raw USB access through an entitlement, held by the app; not a privacy permission.
  public static let usbTransport = Self(
    name: "USB transport",
    owner: "OpenJoystickDriver app",
    purpose: "Own entitlement-restricted raw USB interfaces; not a privacy permission",
    requested: true
  )

  /// Posting keyboard, pointer and scroll events, held by the service.
  public static let postEvent = Self(
    name: "Post event",
    owner: "OpenJoystickDriver service",
    purpose: "Send remapped keyboard, pointer, and scroll events",
    requested: true
  )

  /// Every requirement, in the order OJD lists them.
  public static let inventory = [inputRead, inputInject, usbTransport, postEvent]
}
