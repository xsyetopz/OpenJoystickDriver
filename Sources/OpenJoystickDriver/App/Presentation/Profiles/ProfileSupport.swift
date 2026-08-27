#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileListButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
      configuration.label.foregroundColor(Color.primary).background(
        RoundedRectangle(cornerRadius: 6).fill(
          selected ? Color(NSColor.selectedControlColor).opacity(0.42) : Color.clear
        )
      ).opacity(configuration.isPressed ? 0.72 : 1)
    }
  }

  /// A destructive action that keeps the native semantic role on systems that support it while
  /// retaining a visibly destructive fallback for the macOS 10.15 deployment target.
  struct OJDDestructiveButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
      self.action = action
      self.label = label
    }

    @ViewBuilder var body: some View {
      if #available(macOS 12.0, *) {
        Button(role: .destructive, action: action, label: label).foregroundColor(
          Color(NSColor.systemRed)
        )
      } else {
        Button(action: action, label: label).foregroundColor(Color(NSColor.systemRed))
      }
    }
  }

  extension View {
    /// SwiftUI's tooltip modifier was introduced after the app's minimum deployment target.
    @ViewBuilder func ojdHelp(_ message: String) -> some View {
      if #available(macOS 11.0, *) { help(message) } else { self }
    }
  }

  struct ProfileActionErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
      HStack(alignment: .top, spacing: 10) {
        OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
          Color(NSColor.systemRed)
        )
        VStack(alignment: .leading, spacing: 4) {
          Text(
            OJDLocalized.string(
              "profiles.actionNeedsAttention",
              fallback: "Profile action needs attention"
            )
          ).font(.headline)
          Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        Spacer(minLength: 0)
        Button(OJDLocalized.string("common.dismiss", fallback: "Dismiss"), action: dismiss)
      }.padding(12).background(Color(NSColor.controlBackgroundColor)).ojdAccessibilityLabel(
        OJDLocalized.string("profiles.actionErrorTitle", fallback: "Profile action error")
      ).ojdAccessibilityValue(message)
    }
  }

  enum ProfileSaveStatus: Equatable {
    case unsaved
    case saving
    case saved
    case error

    var label: String {
      switch self {
      case .unsaved: return OJDLocalized.string("profiles.unsaved", fallback: "Unsaved changes")
      case .saving: return OJDLocalized.string("profiles.saving", fallback: "Saving...")
      case .saved: return OJDLocalized.string("profiles.saved", fallback: "Saved")
      case .error: return OJDLocalized.string("profiles.saveFailed", fallback: "Save failed")
      }
    }

    var accessibilityValue: String { label }

    var color: Color {
      switch self {
      case .unsaved, .saving: return Color(NSColor.secondaryLabelColor)
      case .saved: return Color(NSColor.systemGreen)
      case .error: return Color(NSColor.systemRed)
      }
    }
  }

  enum ProfileEditorAction: Equatable, Sendable {
    case select(UUID)
    case importProfile(RemappingProfile)

    var profileID: UUID {
      switch self {
      case .select(let profileID): return profileID
      case .importProfile(let profile): return profile.id
      }
    }
  }

  enum ProfileEditorTransition: Equatable, Sendable {
    case perform(ProfileEditorAction)
    case confirmDiscard
    case blocked
  }

  enum ProfileEditorMutationCompletion: Equatable, Sendable {
    case none
    case select(UUID)
    case refreshEditor

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

  enum ProfileEditorMutationStart: Equatable, Sendable {
    case acquired
    case alreadyOwned
    case rejected
  }

  enum ProfileEditorMutationReconciliation: Equatable, Sendable {
    case acquired
    case retained
    case replaced
    case rejected

    var isAccepted: Bool {
      switch self {
      case .acquired, .retained, .replaced: return true
      case .rejected: return false
      }
    }
  }

  enum ProfileEditorMutationFinish: Equatable, Sendable {
    case ignored
    case released(shouldRefreshEditor: Bool)

    var didRelease: Bool {
      if case .released = self { return true }
      return false
    }

    var shouldRefreshEditor: Bool {
      if case .released(let shouldRefreshEditor) = self { return shouldRefreshEditor }
      return false
    }
  }

  enum ProfileEditorSaveResolution: Equatable, Sendable {
    case ignored
    case succeeded
    case conflict
    case failed(String)
  }

  struct ProfileEditorSaveState: Equatable, Sendable {
    private(set) var operation: RuntimeMutationOperation?
    private(set) var mutationID: UUID?

    var isInFlight: Bool { operation != nil && mutationID != nil }

    mutating func begin(_ request: RuntimeMutationRequest) -> Bool {
      guard case .update = request.operation, !isInFlight else { return false }
      operation = request.operation
      mutationID = request.id
      return true
    }

    mutating func cancel() {
      operation = nil
      mutationID = nil
    }

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

  struct ProfileEditorTransitionState: Equatable, Sendable {
    private(set) var isDirty = false
    private(set) var pendingAction: ProfileEditorAction?
    private(set) var activeMutationRequest: RuntimeMutationRequest?
    private(set) var activeRuntimeMutationID: UUID?
    private var restoreDirtyAfterMutationFailure = false

    var activeMutationOperation: RuntimeMutationOperation? { activeMutationRequest?.operation }
    var isEditingBlocked: Bool { activeMutationRequest != nil }

    mutating func setDirty(_ dirty: Bool) {
      isDirty = dirty
      if !dirty { pendingAction = nil }
    }

    mutating func request(_ action: ProfileEditorAction) -> ProfileEditorTransition {
      guard !isEditingBlocked else { return .blocked }
      guard isDirty else { return .perform(action) }
      pendingAction = action
      return .confirmDiscard
    }

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

    mutating func cancelPendingAction() {
      pendingAction = nil
      restoreDirtyAfterMutationFailure = false
    }

    @discardableResult mutating func beginMutation(
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

    func ownsMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeMutationRequest == request else { return false }
      return activeRuntimeMutationID == nil || activeRuntimeMutationID == request.id
    }

    mutating func bindRuntimeMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeMutationRequest == request else { return false }
      if let activeRuntimeMutationID, activeRuntimeMutationID != request.id { return false }
      activeRuntimeMutationID = request.id
      return true
    }

    mutating func reconcileRuntimeMutation(_ request: RuntimeMutationRequest)
      -> ProfileEditorMutationReconciliation
    {
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

    @discardableResult mutating func finishMutationIfOwned(
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

    @discardableResult mutating func finishMutation(
      _ request: RuntimeMutationRequest,
      succeeded: Bool = true
    ) -> Bool { finishMutationIfOwned(request, succeeded: succeeded).shouldRefreshEditor }
  }

#endif
