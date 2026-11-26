#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension MainWindowController {
    /// Runs the action of the clicked toolbar item when it is enabled.
    @objc
    func performToolbarAction(_ sender: NSToolbarItem) {
      guard let action = MainWindowToolbarAction(identifier: sender.itemIdentifier) else { return }
      perform(action)
    }

    /// The menu-run actions that the selected area offers and that are enabled; the main menu
    /// enables its commands for them.
    var enabledToolbarActions: Set<MainWindowToolbarAction> {
      Set(shownCommandActions.filter(isEnabled))
    }

    /// The menu-run actions that the selected area offers and that are disabled; the commands that
    /// work from any area wait for them.
    var disabledToolbarActions: Set<MainWindowToolbarAction> {
      Set(shownCommandActions.filter { !isEnabled($0) })
    }

    /// The search field of the list in view, or nil when the area has none or the toolbar is
    /// hidden.
    var searchFieldInView: NSSearchField? { searchItemInView?.searchField }

    private var searchItemInView: NSSearchToolbarItem? {
      guard let action = navigation.selectedArea.searchAction(activityMode: screens.activity.mode),
        let toolbar = window?.toolbar, toolbar.isVisible
      else { return nil }
      return toolbar.items.first { $0.itemIdentifier == action.identifier } as? NSSearchToolbarItem
    }

    /// Moves the keyboard focus to the search field of the list in view.
    func focusSearchField() {
      // A collapsed search item is a button whose field is not in the window, so
      // `makeFirstResponder` on the field does nothing; the item must expand it.
      searchItemInView?.beginSearchInteraction()
    }

    /// Runs `action` when its toolbar item is enabled.
    func perform(_ action: MainWindowToolbarAction) {
      guard isEnabled(action) else { return }
      // The area's alerts and sheets hang off the area view, which the setup steps replace.
      navigation.dismissSetupSteps()
      switch action {
      case .newProfile: screens.profiles.beginCreatingProfile()
      case .importProfile: screens.profiles.chooseProfileToImport()
      case .validateProfileFile: screens.profiles.validateProfileFile()
      case .duplicateProfile: screens.profiles.duplicatingProfile = selectedProfile
      case .convertProfile: convertSelectedProfile()
      case .exportProfile: exportSelectedProfile()
      case .deleteProfile: deleteSelectedProfile()
      case .installLibraryItem: installRecordOrMod()
      case .grantProgram: grantProgramAccess()
      case .createToken: screens.access.requestTokenForm()
      case .validateLibraryItem: validateLibraryFolder()
      case .testLibraryRecord: testSelectedLibraryRecord()
      case .removeLibraryItem: screens.libraryArea.requestRemoveSelection()
      case .copyActivityLog: screens.activity.log.copyVisible()
      case .saveActivityLog: saveActivityLog()
      case .showActivityLogInFinder: showActivityLogInFinder()
      case .runDiagnostics: Task { await screens.activity.diagnostics.run() }
      case .activityMode, .activityFilter, .activitySearch, .searchLibrary:
        preconditionFailure("\(action) has its own control action")
      }
    }

    /// Filters the Library list by the text in the toolbar search field.
    @objc
    func librarySearchChanged(_ sender: NSSearchField) {
      screens.libraryArea.searchText = sender.stringValue
    }

    /// Whether the toolbar item for `action` is enabled in the current state.
    func isEnabled(_ action: MainWindowToolbarAction) -> Bool {
      switch action {
      case .newProfile, .importProfile, .validateProfileFile, .duplicateProfile, .convertProfile,
        .exportProfile, .deleteProfile:
        return action.isEnabled(profile: profileToolbarState)
      case .installLibraryItem, .validateLibraryItem, .searchLibrary, .saveActivityLog,
        .showActivityLogInFinder, .activityMode, .activityFilter, .activitySearch:
        return true
      case .grantProgram, .createToken: return screens.access.status != nil && !screens.access.busy
      case .testLibraryRecord: return screens.libraryArea.canTestSelection
      case .removeLibraryItem: return screens.libraryArea.canRemoveSelection
      case .copyActivityLog: return !screens.activity.log.rows.isEmpty
      case .runDiagnostics: return !screens.activity.diagnostics.isRunning
      }
    }

    /// The Profiles toolbar's view of the selection, blocking and unsaved edits.
    private var profileToolbarState: ProfileToolbarState {
      ProfileToolbarState(
        hasSelection: selectedProfile != nil,
        isBlocked: screens.profiles.isActionBlocked(
          library: screens.library,
          runtime: screens.runtime
        ),
        hasUnsavedChanges: screens.profiles.editorTransition.isDirty
      )
    }
  }

  extension MainWindowController: NSToolbarItemValidation {
    /// Enables the toolbar item for its action, and explains in its tooltip why a profile action
    /// waits for unsaved edits.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
      guard let action = MainWindowToolbarAction(identifier: item.itemIdentifier) else {
        return true
      }
      if action.needsSavedProfile {
        item.toolTip =
          profileToolbarState.hasUnsavedChanges
          ? OJDLocalized.string("ui.profiles.saveFirst")
          : OJDLocalized.string(action.descriptionKey)
      }
      return isEnabled(action)
    }
  }

#endif
