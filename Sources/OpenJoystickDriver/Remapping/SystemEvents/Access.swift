import CoreGraphics
import OpenJoystickDriverKit

protocol CoreGraphicsPostEventAccessProbing: Sendable {
  func preflight() -> Bool
  @discardableResult func request() -> Bool
}

private struct PlatformPostEventAccessProbe: CoreGraphicsPostEventAccessProbing {
  func preflight() -> Bool { CGPreflightPostEventAccess() }

  @discardableResult func request() -> Bool { CGRequestPostEventAccess() }
}

/// Reads and requests the CoreGraphics permission used for keyboard and pointer injection.
///
/// This is deliberately separate from the IOHID post-event permission used to
/// create a compatibility virtual controller.
public struct CoreGraphicsPostEventAccess: Sendable {
  private let probe: any CoreGraphicsPostEventAccessProbing

  public init() { probe = PlatformPostEventAccessProbe() }

  init(probe: any CoreGraphicsPostEventAccessProbing) { self.probe = probe }

  public func currentState() -> RemappingPostEventAccessState {
    probe.preflight() ? .granted : .notAuthorized
  }

  /// Requests access and then reads the authoritative state back from preflight.
  ///
  /// The return value from `CGRequestPostEventAccess` is intentionally ignored;
  /// it is not accepted as evidence that event posting is now authorized.
  @discardableResult public func requestAccess() -> RemappingPostEventAccessState {
    let initialState = currentState()
    guard initialState != .granted else { return initialState }
    _ = probe.request()
    return currentState()
  }
}
