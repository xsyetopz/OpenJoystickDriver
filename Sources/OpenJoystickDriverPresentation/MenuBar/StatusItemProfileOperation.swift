#if canImport(AppKit) && canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit

  /// A profile change the status menu and the Profile menu can start.
  enum StatusItemProfileOperation: Equatable {
    /// Activates the profile, optionally although it produces no output.
    case activate(profileID: UUID, allowEmpty: Bool)
    /// Deactivates the profile.
    case deactivate(profileID: UUID)

    /// The activation of the profile, or nil when the person declines.
    ///
    /// A profile that produces no output is activated only after `confirmEmpty` returns true, as
    /// `ojd profile activate` requires `--allow-empty` for it. A profile the library does not hold
    /// is activated without the allowance, so the service decides.
    static func activation(
      of profileID: UUID,
      in profiles: [RemappingProfile],
      confirmEmpty: (RemappingProfile) -> Bool
    ) -> Self? {
      guard let profile = profiles.first(where: { $0.id == profileID }), profile.producesNoOutput
      else { return .activate(profileID: profileID, allowEmpty: false) }
      return confirmEmpty(profile) ? .activate(profileID: profileID, allowEmpty: true) : nil
    }

    /// The mutation request that tracks the operation.
    var request: RuntimeMutationRequest {
      switch self {
      case .activate(let profileID, _):
        return RuntimeMutationRequest(operation: .activate(profileID: profileID))
      case .deactivate(let profileID):
        return RuntimeMutationRequest(operation: .deactivate(profileID: profileID))
      }
    }

    /// Runs the operation on the window's shared library under the editor's mutation tracking.
    ///
    /// Returns nil, without running it, when the editor holds a mutation.
    @MainActor
    func perform(on window: any MenuProfileMutating) async -> MenuProfileMutationOutcome? {
      let request = self.request
      return await window.performMenuProfileMutation(request) { library in
        switch self {
        case .activate(let profileID, let allowEmpty):
          return await library.activateRemappingProfile(
            id: profileID,
            allowEmpty: allowEmpty,
            request: request
          )
        case .deactivate(let profileID):
          return await library.deactivateRemappingProfile(profileID: profileID, request: request)
        }
      }
    }
  }

#endif
