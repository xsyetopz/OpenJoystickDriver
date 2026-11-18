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
    /// A profile that produces no output, launches actions or needs a permission that is missing
    /// is activated only after `confirm` returns true for its confirmation, as the profile editor
    /// asks. `ojd profile activate` requires `--allow-empty` and `--confirm-actions` for them. A
    /// profile the library does not hold is activated without the allowance, so the service
    /// decides.
    static func activation(
      of profileID: UUID,
      in profiles: [RemappingProfile],
      postEventAccess: RemappingPostEventAccessState?,
      confirm: (ProfileEditorConfirmation) -> Bool
    ) -> Self? {
      guard let profile = profiles.first(where: { $0.id == profileID }),
        let needed = ProfileEditorConfirmation.activation(
          of: profile,
          postEventAccess: postEventAccess
        )
      else { return .activate(profileID: profileID, allowEmpty: false) }
      guard confirm(needed) else { return nil }
      if case .activateEmpty = needed { return .activate(profileID: profileID, allowEmpty: true) }
      return .activate(profileID: profileID, allowEmpty: false)
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
      let pending = self.request
      return await window.performMenuProfileMutation(pending) { library in
        switch self {
        case .activate(let profileID, let allowEmpty):
          return await library.activateRemappingProfile(
            id: profileID,
            allowEmpty: allowEmpty,
            request: pending
          )
        case .deactivate(let profileID):
          return await library.deactivateRemappingProfile(profileID: profileID, request: pending)
        }
      }
    }
  }

#endif
