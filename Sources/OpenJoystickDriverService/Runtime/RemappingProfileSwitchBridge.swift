import Foundation
import OpenJoystickDriverKit

/// Carries a `ProfileSwitch` of the engine to the activation path of the service.
final class RemappingProfileSwitchBridge: RemappingProfileSwitching, Sendable {
  /// A weak reference to the server.
  private struct WeakServer {
    /// The server whose activation path runs the switch.
    weak var server: (any AutomationService & AnyObject)?
  }

  /// The profile library that names the candidates.
  private let library: RemappingProfileLibrary
  /// The server, once attached.
  private let attached = Locked(WeakServer())
  /// Writes one line to the service log, which the Activity area and `ojd log` show.
  private let report: @Sendable (String) -> Void

  /// Creates a bridge that resolves targets in `library` and reports to `report`.
  init(
    library: RemappingProfileLibrary,
    report: @escaping @Sendable (String) -> Void = { print($0) }
  ) {
    self.library = library
    self.report = report
  }

  /// Attaches the server that activates the profile.
  func attach(_ server: any AutomationService & AnyObject) {
    attached.withLock { $0.server = server }
  }

  /// Activates the profile that `target` names, as `ojd profile activate` does, and logs the old
  /// and new profile names, or the failure.
  ///
  /// `Next` and `Previous` walk the profiles of the same model and scope as `current`.
  func switchProfile(
    _ target: RemappingProfileTarget,
    from current: UUID,
    for identifier: LogicalControllerID
  ) async {
    do {
      try await activate(target, from: current)
    } catch {
      report("[ProfileSwitch] Switch from \(current.uuidString) failed: \(error)")
    }
  }

  /// Activates the profile that `target` names among the profiles of the same model as `current`.
  private func activate(_ target: RemappingProfileTarget, from current: UUID) async throws {
    guard let server = attached.withLock({ $0.server }) else { return }
    let all = try await library.profiles()
    guard let origin = all.first(where: { $0.id == current }) else {
      throw RemappingProfileLibraryError.profileNotFound(current)
    }
    var candidates = all.filter {
      $0.device.vendorID == origin.device.vendorID && $0.device.productID == origin.device.productID
    }
    if case .profile = target {
    } else {
      candidates = candidates.filter { $0.applicationScope == origin.applicationScope }
    }
    guard let next = target.resolve(from: current, among: candidates) else {
      throw RemappingProfileSwitchError.noTarget(target)
    }
    _ = try await server.activateRemappingProfile(id: next.id, allowEmpty: false)
    report("[ProfileSwitch] Profile \"\(origin.name)\" -> \"\(next.name)\"")
  }
}

/// A `ProfileSwitch` that names no profile to activate.
enum RemappingProfileSwitchError: Error, Equatable {
  /// `target` resolves to no profile of the controller's model and scope.
  case noTarget(RemappingProfileTarget)
}
