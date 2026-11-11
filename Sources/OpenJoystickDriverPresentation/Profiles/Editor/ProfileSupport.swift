#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The banner that says a profile action needs attention, with a Dismiss button.
  struct ProfileActionErrorBanner: View {
    /// The reason.
    let message: String
    /// Dismisses the banner.
    let dismiss: () -> Void

    /// The banner.
    var body: some View {
      HStack(alignment: .top, spacing: OJDSpacing.medium) {
        OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
          Color(NSColor.systemRed)
        ).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
          Text(
            OJDLocalized.string(
              "ui.profiles.actionNeedsAttention"
            )
          ).font(.headline)
          Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        Spacer(minLength: 0)
        Button(OJDLocalized.string("action.dismiss"), action: dismiss)
      }.padding(12).background(Color(NSColor.controlBackgroundColor))
        .accessibilityElement(children: .contain).ojdAccessibilityLabel(
          OJDLocalized.string("ui.profiles.actionErrorTitle")
        ).ojdAccessibilityValue(message)
    }
  }

  /// Where the editor's save is.
  enum ProfileSaveStatus: Equatable {
    /// The draft differs from the stored profile.
    case unsaved
    /// A save runs.
    case saving
    /// The draft equals the stored profile.
    case saved
    /// The latest save failed.
    case error

    /// The text of the status.
    var label: String {
      switch self {
      case .unsaved: return OJDLocalized.string("ui.profiles.unsaved")
      case .saving: return OJDLocalized.string("ui.profiles.saving")
      case .saved: return OJDLocalized.string("ui.profiles.saved")
      case .error: return OJDLocalized.string("ui.profiles.saveFailed")
      }
    }

    /// The status as VoiceOver reads it.
    var accessibilityValue: String { label }

    /// The color of the status.
    var color: Color { Color(semanticState.presentation.tone.color) }

    /// The semantic state that gives the status its look.
    var semanticState: SemanticState {
      switch self {
      case .unsaved: return .dirty
      case .saving: return .loading
      case .saved: return .saved
      case .error: return .failure
      }
    }
  }

  /// What the editor was asked to do with the profile list.
  enum ProfileEditorAction: Equatable, Sendable {
    /// Select the profile.
    case select(UUID)
    /// Import the profile.
    case importProfile(RemappingProfile)

    /// The identifier of the profile the action concerns.
    var profileID: UUID {
      switch self {
      case .select(let profileID): return profileID
      case .importProfile(let profile): return profile.id
      }
    }
  }

  /// What happens when an editor action is requested.
  enum ProfileEditorTransition: Equatable, Sendable {
    /// The action runs.
    case perform(ProfileEditorAction)
    /// The edits must be confirmed to be discarded first.
    case confirmDiscard
    /// A change blocks the action.
    case blocked
  }

  /// What the editor does when a change ends.
  enum ProfileEditorMutationCompletion: Equatable, Sendable {
    /// Nothing.
    case none
    /// Select the profile.
    case select(UUID)
    /// Refresh the editor from the stored profile.
    case refreshEditor

    /// Returns what to do when `operation` ends.
    ///
    /// - Parameters:
    ///   - operation: The change that ended.
    ///   - selectedProfileID: The profile the editor shows, or nil.
    ///   - shouldRefreshEditor: Whether the editor has no unsaved edits to keep.
    /// - Returns: What to do when `operation` ends.
    static func action(
      for operation: RuntimeMutationOperation,
      selectedProfileID: UUID?,
      shouldRefreshEditor: Bool
    ) -> Self {
      switch operation {
      case .create(let profileID): return .select(profileID)
      case .importProfile(let profileID):
        if selectedProfileID == profileID, shouldRefreshEditor { return .refreshEditor }
        if selectedProfileID != profileID { return .select(profileID) }
        return .none
      default: return .none
      }
    }
  }

  /// Whether the editor took ownership of a change.
  enum ProfileEditorMutationStart: Equatable, Sendable {
    /// The editor took it.
    case acquired
    /// The editor already owned it.
    case alreadyOwned
    /// Another change is in flight.
    case rejected
  }

  /// How the editor settled a change that the service reported.
  enum ProfileEditorMutationReconciliation: Equatable, Sendable {
    /// The editor took it.
    case acquired
    /// The editor kept the one it owned.
    case retained
    /// The service's request replaced the editor's request of the same operation.
    case replaced
    /// Another change is in flight.
    case rejected

    /// Whether the change belongs to the editor.
    var isAccepted: Bool {
      switch self {
      case .acquired, .retained, .replaced: return true
      case .rejected: return false
      }
    }
  }

  /// What the editor does when it finishes a change.
  enum ProfileEditorMutationFinish: Equatable, Sendable {
    /// The change did not belong to the editor.
    case ignored
    /// The editor released the change; the value says whether to refresh the editor.
    case released(shouldRefreshEditor: Bool)

    /// Whether the editor released the change.
    var didRelease: Bool {
      if case .released = self { return true }
      return false
    }

    /// Whether the editor should refresh from the stored profile.
    var shouldRefreshEditor: Bool {
      if case .released(let shouldRefreshEditor) = self { return shouldRefreshEditor }
      return false
    }
  }

  /// How a save request ended.
  enum ProfileEditorSaveResolution: Equatable, Sendable {
    /// The result does not belong to the save.
    case ignored
    /// The save succeeded.
    case succeeded
    /// The stored profile changed elsewhere.
    case conflict
    /// The save failed; the value is the message.
    case failed(String)
  }

  /// The save request that is in flight.
  struct ProfileEditorSaveState: Equatable, Sendable {
    /// The operation of the request, or nil.
    private(set) var operation: RuntimeMutationOperation?
    /// The identifier of the request, or nil.
    private(set) var mutationID: UUID?

    /// Whether a save runs.
    var isInFlight: Bool { operation != nil && mutationID != nil }

    /// Starts tracking `request`.
    ///
    /// Returns false unless it is an update and no save runs.
    mutating func begin(_ request: RuntimeMutationRequest) -> Bool {
      guard case .update = request.operation, !isInFlight else { return false }
      operation = request.operation
      mutationID = request.id
      return true
    }

    /// Stops tracking the save.
    mutating func cancel() {
      operation = nil
      mutationID = nil
    }

    /// Settles the save with `result`.
    ///
    /// A result of another request is ignored; otherwise the save ends.
    mutating func resolve(_ result: RuntimeMutationResult) -> ProfileEditorSaveResolution {
      guard isInFlight, operation == result.operation, mutationID == result.id else {
        return .ignored
      }
      cancel()
      switch result {
      case .succeeded: return .succeeded
      case .conflict: return .conflict
      case .failed(_, _, let message), .rejected(_, _, let message): return .failed(message)
      }
    }
  }

  /// The editor's dirty state, the action waiting for confirmation and the change it owns.
  struct ProfileEditorTransitionState: Equatable, Sendable {
    /// Whether the editor holds unsaved edits.
    private(set) var isDirty = false
    /// The action that waits for the person to confirm discarding the edits.
    private(set) var pendingAction: ProfileEditorAction?
    /// The change the editor owns, or nil.
    private(set) var activeMutationRequest: RuntimeMutationRequest?
    /// The identifier of the service's change that the editor bound to its request, or nil.
    private(set) var activeRuntimeMutationID: UUID?
    /// Whether a failed import brings the unsaved edits back.
    private var restoreDirtyAfterMutationFailure = false

    /// The operation of the change the editor owns, or nil.
    var activeMutationOperation: RuntimeMutationOperation? { activeMutationRequest?.operation }
    /// Whether a change blocks editing.
    var isEditingBlocked: Bool { activeMutationRequest != nil }

    /// Sets whether the editor holds unsaved edits; clean edits drop the waiting action.
    mutating func setDirty(_ dirty: Bool) {
      isDirty = dirty
      if !dirty { pendingAction = nil }
    }

    /// Requests `action`.
    ///
    /// It runs at once when the edits are clean, waits for confirmation when they are not, and is
    /// blocked while a change runs.
    mutating func request(_ action: ProfileEditorAction) -> ProfileEditorTransition {
      guard !isEditingBlocked else { return .blocked }
      guard isDirty else { return .perform(action) }
      pendingAction = action
      return .confirmDiscard
    }

    /// Takes the action that waited for confirmation and drops the unsaved edits.
    ///
    /// Returns nil when no action waits.
    mutating func discardPendingAction() -> ProfileEditorAction? {
      guard let pendingAction else { return nil }
      self.pendingAction = nil
      let wasDirty = isDirty
      if case .importProfile = pendingAction {
        restoreDirtyAfterMutationFailure = wasDirty
      } else {
        restoreDirtyAfterMutationFailure = false
      }
      isDirty = false
      return pendingAction
    }

    /// Drops the action that waited for confirmation.
    mutating func cancelPendingAction() {
      pendingAction = nil
      restoreDirtyAfterMutationFailure = false
    }

    /// Takes ownership of `request`.
    ///
    /// - Parameters:
    ///   - request: The change to start.
    ///   - restoresDirtyOnFailure: Whether a failure brings the unsaved edits back.
    /// - Returns: Whether the editor took it, owned it already, or must reject it.
    @discardableResult
    mutating func beginMutation(
      _ request: RuntimeMutationRequest,
      restoresDirtyOnFailure: Bool = false
    ) -> ProfileEditorMutationStart {
      if let activeMutationRequest {
        guard activeMutationRequest == request else { return .rejected }
        restoreDirtyAfterMutationFailure =
          restoreDirtyAfterMutationFailure || restoresDirtyOnFailure
        return .alreadyOwned
      }
      activeMutationRequest = request
      restoreDirtyAfterMutationFailure = restoreDirtyAfterMutationFailure || restoresDirtyOnFailure
      activeRuntimeMutationID = nil
      return .acquired
    }

    /// Returns whether the editor owns `request`.
    func ownsMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeMutationRequest == request else { return false }
      return activeRuntimeMutationID == nil || activeRuntimeMutationID == request.id
    }

    /// Binds the service's change identifier to the request the editor owns.
    ///
    /// Returns false when the editor owns another request or another identifier.
    mutating func bindRuntimeMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeMutationRequest == request else { return false }
      if let activeRuntimeMutationID, activeRuntimeMutationID != request.id { return false }
      activeRuntimeMutationID = request.id
      return true
    }

    /// Settles a change that the service reported against the one the editor owns.
    mutating func reconcileRuntimeMutation(
      _ request: RuntimeMutationRequest
    ) -> ProfileEditorMutationReconciliation {
      if activeMutationRequest == nil {
        guard beginMutation(request) == .acquired else { return .rejected }
        guard bindRuntimeMutation(request) else { return .rejected }
        return .acquired
      }
      if activeMutationRequest == request {
        guard bindRuntimeMutation(request) else { return .rejected }
        return .retained
      }
      guard activeMutationRequest?.operation == request.operation, activeRuntimeMutationID == nil
      else { return .rejected }
      activeMutationRequest = request
      guard bindRuntimeMutation(request) else { return .rejected }
      return .replaced
    }

    /// Releases the change if the editor owns it.
    ///
    /// A failure brings the unsaved edits back when the import asked for it.
    ///
    /// - Parameters:
    ///   - request: The change that ended.
    ///   - succeeded: Whether it succeeded.
    /// - Returns: Ignored when the editor does not own the change, else released, which says
    ///   whether the editor refreshes.
    @discardableResult
    mutating func finishMutationIfOwned(
      _ request: RuntimeMutationRequest,
      succeeded: Bool = true
    ) -> ProfileEditorMutationFinish {
      guard ownsMutation(request) else { return .ignored }
      activeMutationRequest = nil
      activeRuntimeMutationID = nil
      if !succeeded, restoreDirtyAfterMutationFailure { isDirty = true }
      restoreDirtyAfterMutationFailure = false
      return .released(shouldRefreshEditor: succeeded && !isDirty)
    }

    /// Releases the change if the editor owns it.
    ///
    /// Returns whether the editor should refresh.
    @discardableResult
    mutating func finishMutation(_ request: RuntimeMutationRequest, succeeded: Bool = true) -> Bool
    { finishMutationIfOwned(request, succeeded: succeeded).shouldRefreshEditor }
  }

#endif
