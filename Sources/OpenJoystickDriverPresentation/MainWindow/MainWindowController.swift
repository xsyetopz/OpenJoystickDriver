#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  /// The size limits of the main window and its three columns.
  enum MainWindowSizingPolicy {
    /// The minimum and maximum width of the sidebar.
    static let sidebarWidth = (minimum: CGFloat(170), maximum: CGFloat(260))
    /// The minimum and maximum width of the content list column.
    static let listWidth = (minimum: CGFloat(200), maximum: CGFloat(320))
    /// The minimum width of the detail column.
    static let minimumDetailWidth: CGFloat = 420
    /// The content size of a new main window.
    static let defaultContentSize = NSSize(width: 1_040, height: 700)
    /// The smallest content height that the window allows.
    static let minimumContentHeight: CGFloat = 560

    /// Returns the smallest content width that fits the columns that show: the sum of their
    /// minimum widths.
    static func minimumContentWidth(showsSidebar: Bool, showsList: Bool) -> CGFloat {
      (showsSidebar ? sidebarWidth.minimum : 0) + (showsList ? listWidth.minimum : 0)
        + minimumDetailWidth
    }

    /// Returns the smallest content size that fits the columns that show.
    static func minimumContentSize(showsSidebar: Bool, showsList: Bool) -> NSSize {
      NSSize(
        width: minimumContentWidth(showsSidebar: showsSidebar, showsList: showsList),
        height: minimumContentHeight
      )
    }

    /// Returns the smallest frame size of `window` whose content area is
    /// ``minimumContentSize(showsSidebar:showsList:)``.
    @MainActor
    static func minimumFrameSize(
      for window: NSWindow,
      showsSidebar: Bool,
      showsList: Bool
    )
      -> NSSize
    {
      let content = minimumContentSize(showsSidebar: showsSidebar, showsList: showsList)
      return window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
    }
  }

  /// The main window: a sidebar, a content list column and a detail column, with a toolbar.
  ///
  /// Closing the window hides it, which keeps the selected area, the screens' state and the window
  /// geometry.
  @MainActor
  final class MainWindowController: NSWindowController, NSWindowDelegate, MainWindowPresenting,
    MenuProfileMutating
  {
    /// Decides which area is selected and guards switches away from a profile editor with edits.
    let navigation: MainWindowNavigationModel
    /// The models of every area's screen.
    let screens: MainWindowScreens
    /// Reports to the app whether the window is visible.
    private let visibilityChanged: @MainActor (Bool) -> Void
    /// The split view that holds the sidebar, the list column and the detail column.
    private let splitViewController = NSSplitViewController()
    /// The content list column, collapsed for an area without a list.
    private let listItem: NSSplitViewItem
    /// The sidebar column, collapsed by the sidebar toggle.
    private let sidebarItem: NSSplitViewItem
    /// Re-applies the window minimum when the sidebar collapses or returns.
    private var sidebarObservation: AnyCancellable?
    /// Keeps the window title and the toolbar in step with the selected area.
    private var areaObservation: AnyCancellable?
    /// Re-validates the toolbar items when any state that enables them changes.
    private var toolbarEnablementObservation: AnyCancellable?
    /// Updates the toolbar actions and log following when Activity switches its view.
    private var activityModeObservation: AnyCancellable?
    /// Keeps the window subtitle in step with the service status.
    private var summaryObservation: AnyCancellable?
    /// Whether a resize is being corrected, so that the correction does not repeat.
    private var isEnforcingMinimumSize = false

    /// Creates the main window with its screens, split view and toolbar.
    ///
    /// The window restores its saved frame, or centers when there is none.
    /// - Parameters:
    ///   - runtime: The runtime state that every area reads.
    ///   - supportReport: The support report and log export model.
    ///   - restartApplication: Restarts the app, for the Access area.
    ///   - openInputTest: Opens the Input Test window for a controller.
    ///   - visibilityChanged: Called with true when the window is shown and false when it is
    ///     hidden.
    ///   - persistence: Where the selected area is saved between launches.
    init(
      runtime: RuntimeViewModel,
      supportReport: SupportReportModel,
      restartApplication: @escaping @MainActor () -> Void,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void,
      visibilityChanged: @escaping @MainActor (Bool) -> Void,
      persistence: any MainWindowAreaPersistence = UserDefaultsMainWindowAreaPersistence()
    ) {
      self.visibilityChanged = visibilityChanged
      let navigationModel = MainWindowNavigationModel(persistence: persistence)
      self.navigation = navigationModel
      screens = MainWindowScreens(
        runtime: runtime,
        supportReport: supportReport,
        controllers: ControllersViewModel(runtime: runtime),
        library: ProfileLibraryModel(runtime: runtime),
        profiles: ProfilesViewModel(),
        activity: ActivityModel(
          log: ActivityLogModel(),
          diagnostics: ActivityDiagnosticsModel {
            await ActivityDiagnosticsChecks.run(gateway: supportReport.gateway)
          }
        ) { fix in
          switch fix {
          case .requestInputRead:
            PermissionAccessActions.requestControllerAccess(
              viewModel: runtime,
              requirement: .inputRead
            )
          case .requestInputInject:
            PermissionAccessActions.requestControllerAccess(
              viewModel: runtime,
              requirement: .inputInject
            )
          case .approveDriver:
            if !SystemExtensionApproval.openSystemSettings() {
              return OJDLocalized.string("platform.macos.ui.setup.openSystemSettingsFailed")
            }
          case .showLibrary: _ = navigationModel.requestArea(.library)
          }
          return nil
        },
        errorCodeExplainer: ErrorCodeExplainerModel(),
        whatsNew: WhatsNewModel(),
        libraryArea: LibraryViewModel(),
        access: AccessViewModel(),
        restartApplication: restartApplication,
        openInputTest: openInputTest
      )

      let sidebar = NSSplitViewItem(
        sidebarWithViewController: NSHostingController(
          rootView: MainWindowSidebar(navigation: navigationModel)
        )
      )
      self.sidebarItem = sidebar
      sidebar.canCollapse = true
      sidebar.minimumThickness = MainWindowSizingPolicy.sidebarWidth.minimum
      sidebar.maximumThickness = MainWindowSizingPolicy.sidebarWidth.maximum
      let list = NSSplitViewItem(
        contentListWithViewController: NSHostingController(
          rootView: MainWindowListRoot(
            navigation: navigationModel,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens
          )
        )
      )
      list.minimumThickness = MainWindowSizingPolicy.listWidth.minimum
      list.maximumThickness = MainWindowSizingPolicy.listWidth.maximum
      list.isCollapsed = !navigationModel.selectedArea.hasListColumn
      self.listItem = list
      let detailItem = NSSplitViewItem(
        viewController: NSHostingController(
          rootView: MainWindowRoot(
            navigation: navigationModel,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens
          )
        )
      )
      detailItem.minimumThickness = MainWindowSizingPolicy.minimumDetailWidth
      splitViewController.addSplitViewItem(sidebar)
      splitViewController.addSplitViewItem(list)
      splitViewController.addSplitViewItem(detailItem)

      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: MainWindowSizingPolicy.defaultContentSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.contentViewController = splitViewController
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      installSizingPolicy(on: window)

      sidebarObservation = sidebar.publisher(for: \.isCollapsed).dropFirst().sink {
        [weak self, weak window] _ in
        guard let self, let window else { return }
        applyMinimumSize(to: window)
      }
      areaObservation = navigationModel.$selectedArea.sink { [weak self] area in
        self?.reflect(area: area)
      }
      toolbarEnablementObservation = Publishers.MergeMany(
        runtime.scopedRefreshInFlightPublisher.map { _ in () }.eraseToAnyPublisher(),
        runtime.$remappingState.map { _ in () }.eraseToAnyPublisher(),
        screens.library.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.libraryArea.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.profiles.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.access.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.activity.log.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.activity.diagnostics.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        navigationModel.objectWillChange.map { _ in () }.eraseToAnyPublisher()
      ).receive(on: DispatchQueue.main).sink { [weak self] in
        self?.window?.toolbar?.validateVisibleItems()
      }
      activityModeObservation = screens.activity.$mode.receive(on: DispatchQueue.main).sink {
        [weak self] _ in
        guard let self else { return }
        showToolbarActions(of: navigationModel.selectedArea)
        updateLogFollowing(area: navigationModel.selectedArea)
      }
      summaryObservation = runtime.$statusState.sink { [weak window] status in
        window?.subtitle = MainWindowSummary.text(for: navigationModel.selectedArea, status: status)
      }
    }

    /// Unavailable, because the window controller is created in code only.
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: MainWindowPresenting

    /// Shows the main window, on `area` when it is not nil.
    func showMainWindow(area: MainWindowArea?) {
      if let area { navigation.requestArea(area) }
      present()
      screens.whatsNew.presentIfNeeded()
    }

    /// Shows Access and has its permission rows scroll to the permission.
    func showAccess(permission: AccessPermissionRow.Kind) {
      screens.access.focusedPermission = permission
      showMainWindow(area: .access)
    }

    /// Shows Controllers with the controller selected.
    func showController(id: String) {
      guard navigation.requestArea(.controllers) else {
        present()
        return
      }
      screens.controllers.select(sessionToken: id)
      present()
    }

    /// Shows the main window with the Explain Error Code sheet open.
    func showErrorCodeExplainer() {
      present()
      screens.errorCodeExplainer.isPresented = true
    }

    /// The session token of the selected controller, or nil when none is selected.
    var selectedControllerID: String? {
      screens.controllers.selectedDevice?.sessionToken.rawValue
    }

    /// The area the window shows.
    var selectedArea: MainWindowArea { navigation.selectedArea }

    /// Shows the Input Test window for the controller, after selecting it in Controllers.
    func showInputTest(controllerID: String) {
      guard navigation.requestArea(.controllers) else {
        present()
        return
      }
      showController(id: controllerID)
      guard
        let device = screens.controllers.devices.first(where: {
          $0.sessionToken.rawValue == controllerID
        })
      else { return }
      screens.openInputTest(device)
    }

    // MARK: Profile mutations from menus

    /// Runs a profile mutation of the status or main menu on the shared library under the
    /// Profiles editor's mutation tracking.
    ///
    /// Returns nil, without running `mutation`, when the editor holds a mutation.
    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome? {
      let library = screens.library
      return await navigation.trackMenuProfileMutation(request) {
        let result = await mutation(library)
        return MenuProfileMutationOutcome(result: result, lastError: library.lastError)
      }
    }

    /// Shows Profiles and asks for a profile file to import.
    func importProfile() {
      present()
      navigation.perform(in: .profiles) { [weak self] in
        self?.screens.profiles.chooseProfileToImport()
      }
    }

    /// Shows Profiles and asks where to save the selected profile.
    func exportProfile() {
      present()
      navigation.perform(in: .profiles) { [weak self] in
        guard let self, let profile = selectedProfile else { return }
        screens.profiles.exportProfile(profile)
      }
    }

    /// Whether a saved profile is selected in the Profiles screen.
    var hasSelectedProfile: Bool { selectedProfile != nil }

    /// The selected profile, or nil while the runtime is unavailable, a damaged entry is selected
    /// or nothing is selected.
    private var selectedProfile: RemappingProfile? {
      guard case .available(let snapshot) = screens.runtime.remappingState,
        screens.profiles.selectedRecoveryIssueID == nil,
        let selectedID = screens.profiles.selectedProfileID
      else { return nil }
      return snapshot.profiles.first { $0.id == selectedID }
    }

    /// Shows Library and asks for a record file or mod folder to install.
    func installRecordOrMod() {
      present()
      navigation.perform(in: .library) { [weak self] in
        guard let url = LibraryFilePicker.chooseRecordOrModFolder() else { return }
        self?.screens.libraryArea.beginInstall(from: url)
      }
    }

    // MARK: Window

    /// Sizes the window, shows it in front and activates the app.
    private func present() {
      guard let window else { return }
      applyMinimumSize(to: window)
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
      visibilityChanged(true)
      AppForeground.show(window)
      updateLogFollowing(area: navigation.selectedArea)
    }

    /// Hides the window instead of closing it and returns false.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
      // Hiding keeps the selected area, the screens' state and the window geometry.
      sender.orderOut(nil)
      updateLogFollowing(area: navigation.selectedArea)
      visibilityChanged(false)
      return false
    }

    /// Keeps the window from being resized below its minimum frame size.
    func windowWillResize(_ sender: NSWindow, toFrameSize frameSize: NSSize) -> NSSize {
      WindowFramePolicy.fittingSize(frameSize, minimumSize: minimumFrameSize(for: sender))
    }

    /// The smallest frame of `window` that fits the sidebar and list column while they show.
    private func minimumFrameSize(for window: NSWindow) -> NSSize {
      MainWindowSizingPolicy.minimumFrameSize(
        for: window,
        showsSidebar: !sidebarItem.isCollapsed,
        showsList: !listItem.isCollapsed
      )
    }

    /// Sets the window's minimum sizes from the columns that show, and grows the window when it is
    /// smaller than that.
    private func applyMinimumSize(to window: NSWindow) {
      window.contentMinSize = MainWindowSizingPolicy.minimumContentSize(
        showsSidebar: !sidebarItem.isCollapsed,
        showsList: !listItem.isCollapsed
      )
      window.minSize = minimumFrameSize(for: window)
      let fittedFrame = WindowFramePolicy.fittingFrame(window.frame, minimumSize: window.minSize)
      guard fittedFrame.size != window.frame.size else { return }
      isEnforcingMinimumSize = true
      window.setFrame(fittedFrame, display: true)
      isEnforcingMinimumSize = false
    }

    /// Stops following the logs while the window is miniaturized.
    func windowDidMiniaturize(_: Notification) {
      updateLogFollowing(area: navigation.selectedArea)
    }

    /// Resumes following the logs when the window returns from the Dock.
    func windowDidDeminiaturize(_: Notification) {
      updateLogFollowing(area: navigation.selectedArea)
    }

    /// Grows the window back to its minimum frame size after a resize that made it smaller.
    func windowDidResize(_ notification: Notification) {
      guard !isEnforcingMinimumSize, let window = notification.object as? NSWindow else { return }
      applyMinimumSize(to: window)
    }

    /// Moves the window inside the visible frame of its new screen.
    func windowDidChangeScreen(_: Notification) {
      guard let window else { return }
      WindowFramePolicy.clamp(window, minimumSize: minimumFrameSize(for: window))
    }

    /// Applies the minimum sizes, restores the saved frame and keeps the window on screen.
    private func installSizingPolicy(on window: NSWindow) {
      applyMinimumSize(to: window)
      window.setContentSize(MainWindowSizingPolicy.defaultContentSize)
      let autosaveName = "MainWindowGeometry"
      let restoredFrame = window.setFrameUsingName(autosaveName)
      window.setFrameAutosaveName(autosaveName)
      if !restoredFrame { window.center() }
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
    }

    /// Gives the window its unified toolbar, with no user customization.
    private func configureToolbar(for window: NSWindow) {
      let toolbar = NSToolbar(identifier: MainWindowToolbarLayout.toolbar)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconOnly
      window.toolbar = toolbar
      if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
    }

    /// Collapses or shows the list column and updates the toolbar, log following, title and
    /// subtitle for `area`.
    private func reflect(area: MainWindowArea) {
      listItem.isCollapsed = !area.hasListColumn
      if let window { applyMinimumSize(to: window) }
      showToolbarActions(of: area)
      updateLogFollowing(area: area)
      window?.title = area.title
      window?.subtitle = MainWindowSummary.text(for: area, status: screens.runtime.statusState)
    }
  }

  extension MainWindowController {
    /// Replaces the toolbar's area actions with those of `area`.
    func showToolbarActions(of area: MainWindowArea) {
      guard let toolbar = window?.toolbar else { return }
      let fixedCount = MainWindowToolbarLayout.fixedItems.count
      while toolbar.items.count > fixedCount { toolbar.removeItem(at: toolbar.items.count - 1) }
      let actions = area.toolbarActions(activityMode: screens.activity.mode)
      for (offset, action) in actions.enumerated() {
        toolbar.insertItem(withItemIdentifier: action.identifier, at: fixedCount + offset)
      }
    }

    /// Runs the action of the clicked toolbar item when it is enabled.
    @objc
    func performToolbarAction(_ sender: NSToolbarItem) {
      guard let action = MainWindowToolbarAction(identifier: sender.itemIdentifier) else { return }
      perform(action)
    }

    /// The toolbar actions that the selected area shows and that are enabled; the main menu enables
    /// its commands for them.
    var enabledToolbarActions: Set<MainWindowToolbarAction> {
      Set(
        navigation.selectedArea.toolbarActions(activityMode: screens.activity.mode).filter(
          isEnabled
        )
      )
    }

    /// The toolbar actions that the selected area shows and that are disabled; the commands that
    /// work from any area wait for them.
    var disabledToolbarActions: Set<MainWindowToolbarAction> {
      Set(
        navigation.selectedArea.toolbarActions(activityMode: screens.activity.mode).filter {
          !isEnabled($0)
        }
      )
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
      switch action {
      case .newProfile: screens.profiles.beginCreatingProfile()
      case .importProfile: screens.profiles.chooseProfileToImport()
      case .validateProfileFile: screens.profiles.validateProfileFile()
      case .duplicateProfile: screens.profiles.duplicatingProfile = selectedProfile
      case .convertProfile:
        if let selectedProfile { screens.profiles.beginConverting(selectedProfile) }
      case .exportProfile:
        if let selectedProfile { screens.profiles.exportProfile(selectedProfile) }
      case .deleteProfile:
        if let selectedProfile { screens.profiles.activeAlert = .delete(selectedProfile.id) }
      case .installLibraryItem: installRecordOrMod()
      case .grantProgram:
        if let url = AccessFilePicker.chooseProgram() {
          screens.access.requestGrant(programAt: url)
        }
      case .createToken: screens.access.requestTokenForm()
      case .validateLibraryItem:
        if let url = LibraryFilePicker.chooseRecordOrModFolder() {
          screens.libraryArea.validate(at: url)
        }
      case .testLibraryRecord:
        if let capture = LibraryFilePicker.chooseCapture(),
          let expectation = LibraryFilePicker.chooseExpectation()
        {
          screens.libraryArea.testSelectedRecord(capture: capture, expectation: expectation)
        }
      case .removeLibraryItem: screens.libraryArea.requestRemoveSelection()
      case .searchLibrary: break
      case .copyActivityLog: screens.activity.log.copyVisible()
      case .saveActivityLog: saveActivityLog()
      case .showActivityLogInFinder: showActivityLogInFinder()
      case .runDiagnostics: Task { await screens.activity.diagnostics.run() }
      case .activityMode, .activityFilter, .activitySearch:
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

  extension MainWindowController: NSToolbarDelegate {
    /// Returns the fixed items and every area action.
    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.allowedItems
    }

    /// Returns the fixed items and the actions of the selected area.
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
      MainWindowToolbarLayout.items(
        for: navigation.selectedArea,
        activityMode: screens.activity.mode
      )
    }

    /// Returns no identifiers, because no toolbar item stays selected.
    func toolbarSelectableItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
      []
    }

    /// Returns the toolbar item for `itemIdentifier`: the sidebar separator or an area action.
    func toolbar(
      _: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
      if itemIdentifier == .sidebarTrackingSeparator {
        return NSTrackingSeparatorToolbarItem(
          identifier: itemIdentifier,
          splitView: splitViewController.splitView,
          dividerIndex: 0
        )
      }
      guard let action = MainWindowToolbarAction(identifier: itemIdentifier) else { return nil }
      if let item = makeActivityControlItem(for: action) { return item }
      let item = MainWindowToolbarLayout.makeItem(for: action)
      if let search = item as? NSSearchToolbarItem {
        search.searchField.stringValue = screens.libraryArea.searchText
        search.searchField.target = self
        search.searchField.action = #selector(librarySearchChanged(_:))
        return search
      }
      item.target = self
      item.action = #selector(performToolbarAction(_:))
      return item
    }
  }

#endif
