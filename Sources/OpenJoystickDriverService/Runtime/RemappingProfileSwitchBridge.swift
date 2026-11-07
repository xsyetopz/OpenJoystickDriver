import Foundation
import OpenJoystickDriverKit

/// Carries a `ProfileSwitch` of the engine to the activation path of the service.
final class RemappingProfileSwitchBridge: RemappingProfileSwitching, Sendable {
  /// A weak reference to the server.
  private struct WeakServer {
    /// The server whose activation path runs the switch.
    weak var server: ApplicationServiceServer?
  }

  /// The profile library that names the candidates.
  private let library: RemappingProfileLibrary
  /// The server, once attached.
  private let attached = Locked(WeakServer())

  /// Creates a bridge that resolves targets in `library`.
  init(library: RemappingProfileLibrary) { self.library = library }

  /// Attaches the server that activates the profile.
  func attach(_ server: ApplicationServiceServer) { attached.withLock { $0.server = server } }

  /// Activates the profile that `target` names, as `ojd profile activate` does.
  ///
  /// `Next` and `Previous` walk the profiles of the same model and scope as `current`.
  /// - Throws: ``RemappingProfileLibraryError`` when the library, the target or the activation
  ///   fails.
  func switchProfile(
    _ target: RemappingProfileTarget,
    from current: UUID,
    for identifier: LogicalControllerID
  ) async throws {
    guard let server = attached.withLock({ $0.server }) else { return }
    let all = try await library.profiles()
    guard let origin = all.first(where: { $0.id == current }) else { return }
    let sameModel = all.filter {
      $0.device.vendorID == origin.device.vendorID && $0.device.productID == origin.device.productID
    }
    var candidates = sameModel
    if case .profile = target {
    } else {
      candidates = sameModel.filter { $0.applicationScope == origin.applicationScope }
    }
    guard let next = target.resolve(from: current, among: candidates) else { return }
    _ = try await server.activateRemappingProfile(id: next.id, allowEmpty: false)
  }
}
