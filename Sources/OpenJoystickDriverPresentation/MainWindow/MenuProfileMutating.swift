#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit

  /// The result of a profile mutation started from a menu.
  struct MenuProfileMutationOutcome {
    /// The mutation's result.
    let result: RuntimeMutationResult
    /// The library's error text, shown for a conflict.
    let lastError: String?
  }

  /// Runs menu-started profile mutations under the Profiles editor's mutation tracking, and the
  /// main menu commands that carry a toolbar action or Find.
  @MainActor
  protocol MenuProfileMutating: MainWindowPresenting {
    /// The toolbar actions that the selected area shows and that are enabled.
    var enabledToolbarActions: Set<MainWindowToolbarAction> { get }
    /// The toolbar actions that the selected area shows and that are disabled.
    var disabledToolbarActions: Set<MainWindowToolbarAction> { get }
    /// The search field of the list in view, or nil when there is none.
    var searchFieldInView: NSSearchField? { get }
    /// Runs `action` when its toolbar item is enabled.
    func perform(_ action: MainWindowToolbarAction)
    /// Moves the keyboard focus to the search field of the list in view.
    func focusSearchField()
    /// Opens the Access area scrolled to the row of the permission.
    func showAccess(permission: AccessPermissionRow.Kind)

    /// Runs `mutation` for `request` and returns its outcome.
    ///
    /// Returns nil, without running `mutation`, when the editor holds a mutation.
    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome?
  }

#endif
