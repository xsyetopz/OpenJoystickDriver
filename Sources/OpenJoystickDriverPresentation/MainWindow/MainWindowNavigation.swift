#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit

  /// Saves and restores the area that the main window shows.
  protocol MainWindowAreaPersistence {
    /// Returns the saved area, or nil when none is saved.
    func loadArea() -> MainWindowArea?
    /// Saves `area` as the area to show next.
    func saveArea(_ area: MainWindowArea)
  }

  /// Remembers the selected area between launches in user defaults.
  ///
  /// It is window state, not a setting.
  struct UserDefaultsMainWindowAreaPersistence: MainWindowAreaPersistence {
    /// The user defaults key of the saved area.
    static let key = "OpenJoystickDriver.mainWindow.lastArea"

    /// The user defaults that hold the saved area.
    let defaults: UserDefaults

    /// Creates the store on `defaults`.
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Returns the saved area, or nil when none is saved or its name is unknown.
    func loadArea() -> MainWindowArea? {
      guard let rawValue = defaults.string(forKey: Self.key) else { return nil }
      return MainWindowArea(rawValue: rawValue)
    }

    /// Saves `area` under ``key``.
    func saveArea(_ area: MainWindowArea) { defaults.set(area.rawValue, forKey: Self.key) }
  }

  /// The selected area of the main window.
  ///
  /// Leaving Profiles with unsaved editor changes asks first, and no area switch happens while a
  /// profile editor mutation is running.
  @MainActor
  final class MainWindowNavigationModel: ObservableObject {
    /// The area that the window shows.
    @Published
    private(set) var selectedArea: MainWindowArea
    /// The area that waits for the answer to the discard question.
    @Published
    private(set) var pendingArea: MainWindowArea?
    /// Counts the discards of editor changes, so the Profiles editor reloads its profile.
    @Published
    private(set) var discardGeneration = 0
    /// Whether the discard question is shown.
    @Published
    var isDiscardConfirmationPresented = false
    /// Set when `perform(in:_:)` is refused for a running profile editor mutation; the window
    /// shows the reason until dismissed.
    @Published
    var isMutationRefusalPresented = false

    /// Where the selected area is saved.
    private let persistence: any MainWindowAreaPersistence
    /// Whether the Profiles editor holds changes that are not saved.
    private var profilesEditorIsDirty = false
    /// The profile mutation that the editor or a menu is running, if any.
    private var activeProfilesEditorMutation: RuntimeMutationRequest?
    /// Whether the running mutation was matched to a runtime mutation.
    private var activeProfilesEditorMutationIsRuntimeBound = false
    /// The action that waits for the answer to the discard question.
    private var pendingAction: (@MainActor () -> Void)?

    /// Creates the model on the saved area, or Controllers when none is saved.
    init(persistence: any MainWindowAreaPersistence = UserDefaultsMainWindowAreaPersistence()) {
      self.persistence = persistence
      selectedArea = persistence.loadArea() ?? .controllers
    }

    /// Asks to show `area`.
    ///
    /// Returns true when the area is selected on return.
    ///
    /// Returns false when a profile editor mutation is running, or when unsaved editor changes
    /// need an answer to the discard question first.
    @discardableResult
    func requestArea(_ area: MainWindowArea) -> Bool {
      guard area != selectedArea else { return true }
      guard activeProfilesEditorMutation == nil else { return false }
      guard profilesEditorIsDirty else {
        selectAcceptedArea(area)
        return true
      }
      pendingAction = nil
      pendingArea = area
      isDiscardConfirmationPresented = true
      return false
    }

    /// Shows `area` and runs `action` there.
    ///
    /// When the discard question is open the action waits for the answer: it runs once the area is
    /// selected by a discard and is dropped on cancel. It is refused with a visible message while a
    /// profile editor mutation is running.
    @discardableResult
    func perform(in area: MainWindowArea, _ action: @escaping @MainActor () -> Void) -> Bool {
      guard activeProfilesEditorMutation == nil else {
        isMutationRefusalPresented = true
        return false
      }
      if requestArea(area) {
        action()
        return true
      }
      pendingAction = action
      return false
    }

    /// Records whether the Profiles editor holds unsaved changes.
    func setProfilesEditorDirty(_ dirty: Bool) { profilesEditorIsDirty = dirty }

    /// Starts tracking `request` as the editor's mutation and cancels any waiting area switch.
    ///
    /// Returns false when another mutation is tracked.
    @discardableResult
    func beginProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == nil else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = false
      cancelPendingArea()
      return true
    }

    /// Runs `body` as a menu-started profile mutation under the editor's mutation tracking.
    ///
    /// Returns nil, without running `body`, when the editor holds a mutation.
    func trackMenuProfileMutation<Result>(
      _ request: RuntimeMutationRequest,
      _ body: () async -> Result
    ) async -> Result? {
      guard beginProfilesEditorMutation(request) else { return nil }
      let result = await body()
      finishProfilesEditorMutation(request)
      return result
    }

    /// Whether `request` is the mutation that the editor tracks.
    func ownsProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      activeProfilesEditorMutation == request
    }

    /// Stops tracking `request`.
    ///
    /// Returns false when it is not the tracked mutation.
    @discardableResult
    func finishProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == request else { return false }
      activeProfilesEditorMutation = nil
      activeProfilesEditorMutationIsRuntimeBound = false
      return true
    }

    /// Adopts the runtime mutation `request` as the tracked mutation, unless a different one is
    /// tracked.
    ///
    /// Returns true when `request` is tracked on return. A tracked mutation of the same operation
    /// that is not yet matched to a runtime mutation is replaced.
    @discardableResult
    func reconcileProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard
        activeProfilesEditorMutation == nil || activeProfilesEditorMutation == request
          || (activeProfilesEditorMutation?.operation == request.operation
            && !activeProfilesEditorMutationIsRuntimeBound)
      else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = true
      cancelPendingArea()
      return true
    }

    /// Discards the editor changes, selects the waiting area and runs the action that waits.
    func discardPendingArea() {
      guard let pendingArea else {
        cancelPendingArea()
        return
      }
      profilesEditorIsDirty = false
      discardGeneration &+= 1
      self.pendingArea = nil
      isDiscardConfirmationPresented = false
      selectAcceptedArea(pendingArea)
      let action = pendingAction
      pendingAction = nil
      action?()
    }

    /// Drops the waiting area and action and closes the discard question.
    func cancelPendingArea() {
      pendingAction = nil
      pendingArea = nil
      isDiscardConfirmationPresented = false
    }

    /// Selects `area` and saves it.
    private func selectAcceptedArea(_ area: MainWindowArea) {
      selectedArea = area
      persistence.saveArea(area)
    }
  }

#endif
