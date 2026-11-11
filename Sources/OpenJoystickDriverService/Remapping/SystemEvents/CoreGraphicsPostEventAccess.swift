import CoreGraphics
public import OpenJoystickDriverKit

/// Probes and requests the CoreGraphics post-event permission.
protocol CoreGraphicsPostEventAccessProbing: Sendable {
  /// Tells whether post-event access is granted.
  func preflight() -> Bool
  /// Asks macOS for post-event access and tells whether it is granted.
  @discardableResult
  func request() -> Bool
}

/// The probe that calls CoreGraphics.
private struct PlatformPostEventAccessProbe: CoreGraphicsPostEventAccessProbing {
  /// Tells whether post-event access is granted.
  func preflight() -> Bool { CGPreflightPostEventAccess() }

  /// Asks macOS for post-event access.
  @discardableResult
  func request() -> Bool { CGRequestPostEventAccess() }
}

/// Reads and requests the CoreGraphics permission used for keyboard and pointer injection.
///
/// This is deliberately separate from the IOHID post-event permission used to
/// create a virtual output controller.
public struct CoreGraphicsPostEventAccess: Sendable {
  /// The probe of the permission.
  private let probe: any CoreGraphicsPostEventAccessProbing

  /// Creates the access with the CoreGraphics probe.
  public init() { probe = PlatformPostEventAccessProbe() }

  /// Creates the access with `probe`.
  init(probe: any CoreGraphicsPostEventAccessProbing) { self.probe = probe }

  /// Returns whether post-event access is granted.
  public func currentState() -> RemappingPostEventAccessState {
    probe.preflight() ? .granted : .notAuthorized
  }

  /// Requests access and then reads the authoritative state back from preflight.
  ///
  /// The return value from `CGRequestPostEventAccess` is intentionally ignored;
  /// it is not accepted as evidence that event posting is authorized.
  @discardableResult
  public func requestAccess() -> RemappingPostEventAccessState {
    let initialState = currentState()
    guard initialState != .granted else { return initialState }
    _ = probe.request()
    return currentState()
  }
}
